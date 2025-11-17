// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./store/ProofManagerStorage.sol";
import { MinHeapLib } from "./store/MinHeapLib.sol";
import "./interfaces/IProofManager.sol";

import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    DataEncoding
} from "era-contracts/l1-contracts/contracts/common/libraries/DataEncoding.sol";
import {
    INativeTokenVault
} from "era-contracts/l1-contracts/contracts/bridge/ntv/INativeTokenVault.sol";
import {
    IL2AssetRouter
} from "era-contracts/l1-contracts/contracts/bridge/asset-router/IL2AssetRouter.sol";
import {
    L2_NATIVE_TOKEN_VAULT_ADDR,
    L2_ASSET_ROUTER_ADDR
} from "era-contracts/l1-contracts/contracts/common/L2ContractAddresses.sol";

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @notice Entry point for Proof Manager.
contract ProofManagerV1 is
    IProofManager,
    Initializable,
    AccessControlUpgradeable,
    ProofManagerStorage
{
    using MinHeapLib for MinHeapLib.Heap;

    bytes32 public constant SUBMITTER_ROLE = keccak256("SUBMITTER_ROLE");

    /*//////////////////////////////////////////
                    Constants
    //////////////////////////////////////////*/

    /// @dev Hard-coded constant on Proof Request acknowledgement timeout time.
    ///     Proving Networks have 2 minutes to commit to proving a proof request once posted on chain.
    ///     Minimizes the proving downtime in case of communication failure.
    uint256 private constant ACK_TIMEOUT = 2 minutes;

    /// @dev Hard-coded constant on maximum timeout after.
    ///     Proving Networks have max 3 hours(can be less) to submit a proof once committed.
    ///     This is to prevent Submitter to send requests that will be almost never expired.
    uint256 private constant MAX_TIMEOUT_AFTER = 3 hours;

    /// @dev Hard-coded constant on maximum reward amount.
    ///      Constant limits maximum reward that can be provided for a single proof request.
    ///      Safe capacity for the reward is 5 USDC per proof, although the actual value is lower.
    uint256 private constant MAX_REWARD = 5_000_000;

    /*//////////////////////////////////////////
                    Modifiers
    //////////////////////////////////////////*/

    /// @dev You need to be a proving network to call this function.
    modifier onlyProvingNetwork() {
        if (
            msg.sender != _provingNetworks[ProvingNetwork.Fermah].addr
                && msg.sender != _provingNetworks[ProvingNetwork.Lagrange].addr
        ) revert OnlyProvingNetworkAllowed(msg.sender);
        _;
    }

    /// @dev You need the proof request to be assigned to you to call this function.
    modifier onlyAssignee(ProofRequestIdentifier calldata id) {
        if (
            _provingNetworks[_proofRequests[id.chainId][id.blockNumber].assignedTo].addr
                != msg.sender
        ) revert OnlyProvingNetworkAssigneeAllowed(msg.sender);
        _;
    }

    /// @dev You need to have a proving network that is not None to call this function.
    ///     None is an escape hatch (lack of Option<>) and should not be used in public API.
    modifier provingNetworkNotNone(ProvingNetwork provingNetwork) {
        if (provingNetwork == ProvingNetwork.None) revert ProvingNetworkCannotBeNone();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    // /*//////////////////////////////////////////
    //                 Initialization
    // //////////////////////////////////////////*/

    function initialize(
        address fermah,
        address lagrange,
        address _usdc,
        address _submitter,
        address _admin
    ) external initializer {
        if (_submitter == address(0)) revert AddressCannotBeZero("submitter");
        if (_admin == address(0)) revert AddressCannotBeZero("admin");
        if (fermah == address(0)) revert AddressCannotBeZero("fermah");
        if (lagrange == address(0)) revert AddressCannotBeZero("lagrange");
        if (_usdc == address(0)) revert AddressCannotBeZero("usdc");

        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SUBMITTER_ROLE, _submitter);

        usdc = IERC20(_usdc);

        _initializeProvingNetwork(ProvingNetwork.Fermah, fermah);
        _initializeProvingNetwork(ProvingNetwork.Lagrange, lagrange);

        _updatePreferredProvingNetwork(ProvingNetwork.None);

        // NOTE: _requestCounter is set to 0 by default.
    }

    /*////////////////////////
            Getters
    ////////////////////////*/

    /// @dev Computed Unacknowledged and TimedOut status on the fly. The state is not persisted on chain.
    function proofRequest(ProofRequestIdentifier calldata id)
        external
        view
        returns (ProofRequest memory)
    {
        ProofRequest memory _proofRequest = _proofRequests[id.chainId][id.blockNumber];
        if (_proofRequest.status == ProofRequestStatus.PendingAcknowledgement) {
            if (block.timestamp > _proofRequest.submittedAt + ACK_TIMEOUT) {
                _proofRequest.status = ProofRequestStatus.Unacknowledged;
            }
        } else if (_proofRequest.status == ProofRequestStatus.Committed) {
            if (block.timestamp > _proofRequest.submittedAt + _proofRequest.timeoutAfter) {
                _proofRequest.status = ProofRequestStatus.TimedOut;
            }
        }
        return _proofRequest;
    }

    /// @dev Getter for Proving Network Info.
    function provingNetworkInfo(ProvingNetwork provingNetwork)
        external
        view
        returns (ProvingNetworkInfo memory)
    {
        return _provingNetworks[provingNetwork];
    }

    /*//////////////////////////////////////////
            Proving Network Management
    //////////////////////////////////////////*/

    /// @inheritdoc IProofManager
    function updateProvingNetworkAddress(ProvingNetwork provingNetwork, address addr)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        provingNetworkNotNone(provingNetwork)
    {
        if (addr == address(0)) revert AddressCannotBeZero("proving network");
        _updateProvingNetworkAddress(provingNetwork, addr);
    }

    /// @inheritdoc IProofManager
    function updateProvingNetworkStatus(ProvingNetwork provingNetwork, ProvingNetworkStatus status)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        provingNetworkNotNone(provingNetwork)
    {
        _provingNetworks[provingNetwork].status = status;
        emit ProvingNetworkStatusUpdated(provingNetwork, status);
    }

    /// @inheritdoc IProofManager
    function updatePreferredProvingNetwork(ProvingNetwork provingNetwork)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _updatePreferredProvingNetwork(provingNetwork);
    }

    /*//////////////////////////////////////////
            Proof Request Management
    //////////////////////////////////////////*/

    /// @inheritdoc IProofManager
    function submitProofRequest(
        ProofRequestIdentifier calldata id,
        ProofRequestParams calldata params
    ) external onlyRole(SUBMITTER_ROLE) {
        if (_proofRequests[id.chainId][id.blockNumber].submittedAt != 0) {
            revert DuplicatedProofRequest(id.chainId, id.blockNumber);
        }
        if (params.timeoutAfter <= ACK_TIMEOUT || params.timeoutAfter > MAX_TIMEOUT_AFTER) {
            revert InvalidProofRequestTimeout();
        }
        if (params.maxReward == 0 || params.maxReward > MAX_REWARD) {
            revert MaxRewardOutOfBounds();
        }

        _purge_expired_requests();

        if (!_can_accept_request()) {
            revert NoFundsAvailable();
        }

        ProvingNetwork assignedTo = _nextAssignee();
        bool refused = (assignedTo == ProvingNetwork.None)
            || _provingNetworks[assignedTo].status == ProvingNetworkStatus.Inactive;

        ProofRequestStatus status =
            refused ? ProofRequestStatus.Refused : ProofRequestStatus.PendingAcknowledgement;

        _heap.addProofRequest(block.timestamp + ACK_TIMEOUT, id);

        _proofRequests[id.chainId][id.blockNumber] = ProofRequest({
            proofInputsUrl: params.proofInputsUrl,
            protocolMajor: params.protocolMajor,
            protocolMinor: params.protocolMinor,
            protocolPatch: params.protocolPatch,
            submittedAt: block.timestamp,
            timeoutAfter: params.timeoutAfter,
            maxReward: params.maxReward,
            status: status,
            assignedTo: assignedTo,
            requestedReward: 0,
            proof: bytes(""),
            requestId: _requestCounter
        });

        emit ProofRequestSubmitted(
            id.chainId,
            id.blockNumber,
            assignedTo,
            params.proofInputsUrl,
            params.protocolMajor,
            params.protocolMinor,
            params.protocolPatch,
            params.timeoutAfter,
            params.maxReward,
            _requestCounter
        );

        // overflow is not a problem here, the number of proofs is unfathomably large (we'd need some ~10**66 proofs per second for 100 years straight for overflow to happen)
        _requestCounter += 1;
    }

    /// @inheritdoc IProofManager
    function submitProofValidationResult(ProofRequestIdentifier calldata id, bool isProofValid)
        external
        onlyRole(SUBMITTER_ROLE)
    {
        ProofRequest storage _proofRequest = _proofRequests[id.chainId][id.blockNumber];
        if (_proofRequest.status != ProofRequestStatus.Proven) {
            revert ProofRequestIsNotProven(_proofRequest.status);
        }
        if (isProofValid) {
            _proofRequest.status = ProofRequestStatus.Validated;
            ProvingNetworkInfo storage _provingNetworkInfo =
                _provingNetworks[_proofRequest.assignedTo];
            // overflow is not a problem here, the contract would have to pay billion of trillions of current world GDP before it would happen
            _provingNetworkInfo.owedReward += _proofRequest.requestedReward;
        } else {
            _proofRequest.status = ProofRequestStatus.ValidationFailed;
        }

        _heap.removeAt(id);
        unstableReward -= _proofRequest.requestedReward;

        emit ProofValidationResult(
            id.chainId, id.blockNumber, isProofValid, _proofRequest.assignedTo
        );
    }

    /*//////////////////////////////////////////
            Proving Network Interactions
    //////////////////////////////////////////*/

    /// @inheritdoc IProofManager
    function acknowledgeProofRequest(ProofRequestIdentifier calldata id, bool accepted)
        external
        onlyAssignee(id)
    {
        // NOTE: Checking if the proof request exists is not necessary. By default, a proof request that doesn't exist is assigned to ProvingNetwork None.
        //      As such, onlyAssignee(id) will fail.
        ProofRequest storage _proofRequest = _proofRequests[id.chainId][id.blockNumber];

        if (_proofRequest.status != ProofRequestStatus.PendingAcknowledgement) {
            revert ProofRequestIsNotPendingAcknowledgement(_proofRequest.status);
        }
        if (block.timestamp > _proofRequest.submittedAt + ACK_TIMEOUT) {
            revert ProofRequestAcknowledgementDeadlinePassed();
        }

        _heap.replaceAt(id, _proofRequest.submittedAt + _proofRequest.timeoutAfter);

        _proofRequest.status = accepted ? ProofRequestStatus.Committed : ProofRequestStatus.Refused;

        emit ProofRequestAcknowledged(
            id.chainId, id.blockNumber, accepted, _proofRequest.assignedTo
        );
    }

    /// @inheritdoc IProofManager
    function submitProof(
        ProofRequestIdentifier calldata id,
        bytes calldata proof,
        uint256 requestedReward
    ) external onlyAssignee(id) {
        ProofRequest storage _proofRequest = _proofRequests[id.chainId][id.blockNumber];
        if (_proofRequest.status != ProofRequestStatus.Committed) {
            revert ProofRequestIsNotCommitted(_proofRequest.status);
        }
        if (block.timestamp > _proofRequest.submittedAt + _proofRequest.timeoutAfter) {
            revert ProofRequestProvingDeadlinePassed();
        }
        if (proof.length == 0) revert EmptyProof();

        _proofRequest.status = ProofRequestStatus.Proven;
        _proofRequest.proof = proof;
        _proofRequest.requestedReward =
            requestedReward <= _proofRequest.maxReward ? requestedReward : _proofRequest.maxReward;

        _heap.removeAt(id);
        unstableReward += _proofRequest.requestedReward;

        emit ProofRequestProven(id.chainId, id.blockNumber, proof, _proofRequest.assignedTo);
    }

    /// @inheritdoc IProofManager
    function claimReward() external onlyProvingNetwork {
        ProvingNetwork provingNetwork = msg.sender == _provingNetworks[ProvingNetwork.Fermah].addr
            ? ProvingNetwork.Fermah
            : ProvingNetwork.Lagrange;

        ProvingNetworkInfo storage info = _provingNetworks[provingNetwork];
        uint256 toPay = info.owedReward;

        if (toPay == 0) revert NoPaymentDue();

        uint256 balance = usdc.balanceOf(address(this));

        if (toPay > balance) revert NotEnoughUsdcFunds(balance, toPay);
        info.owedReward = 0;

        bytes32 assetId = INativeTokenVault(L2_NATIVE_TOKEN_VAULT_ADDR).assetId(address(usdc));

        IL2AssetRouter(L2_ASSET_ROUTER_ADDR)
            .withdraw(assetId, DataEncoding.encodeBridgeBurnData(toPay, info.addr, address(usdc)));

        emit RewardClaimed(provingNetwork, toPay);
    }

    // /*////////////////////////
    //         Helpers
    // ////////////////////////*/

    /// @dev Initializes a proving network's state. Used at initialization time.
    function _initializeProvingNetwork(ProvingNetwork provingNetwork, address addr) private {
        // NOTE: owedReward is set to 0 by default.
        // NOTE2: status is set to Active by default, but event still needs to be emitted.;
        _updateProvingNetworkAddress(provingNetwork, addr);
        emit ProvingNetworkStatusUpdated(provingNetwork, ProvingNetworkStatus.Active);
    }

    /// @dev Computes the next assignee based on current state. Does not change state!
    ///    NOTE: Distribution is 25%, 25% and 50%.
    function _nextAssignee() private view returns (ProvingNetwork to) {
        uint256 mod = _requestCounter % 4;
        if (mod == 0) return ProvingNetwork.Fermah;
        if (mod == 1) return ProvingNetwork.Lagrange;
        return preferredProvingNetwork;
    }

    function _updateProvingNetworkAddress(ProvingNetwork provingNetwork, address addr) private {
        _provingNetworks[provingNetwork].addr = addr;
        emit ProvingNetworkAddressUpdated(provingNetwork, addr);
    }

    function _updatePreferredProvingNetwork(ProvingNetwork provingNetwork) private {
        preferredProvingNetwork = provingNetwork;
        emit PreferredProvingNetworkUpdated(provingNetwork);
    }

    /// @dev Computes the total amount of potential in-flight requests.
    function _can_accept_request() private view returns (bool) {
        return (usdc.balanceOf(address(this))
                    - _provingNetworks[ProvingNetwork.Fermah].owedReward
                    - _provingNetworks[ProvingNetwork.Lagrange].owedReward
                    - unstableReward) / MAX_REWARD - _heap.size() > 0;
    }

    function _purge_expired_requests() private {
        while (!_heap.isEmpty() && _heap.peek().key < block.timestamp) {
            MinHeapLib.Node memory node = _heap.extractMin();
            ProofRequest storage _proofRequest = _proofRequests[
                node.proofRequestIdentifier.chainId
            ][node.proofRequestIdentifier.blockNumber];

            if (_proofRequest.status == ProofRequestStatus.PendingAcknowledgement) {
                _proofRequest.status = ProofRequestStatus.Unacknowledged;
            } else if (_proofRequest.status == ProofRequestStatus.Committed) {
                _proofRequest.status = ProofRequestStatus.TimedOut;
            }
        }
    }
}
