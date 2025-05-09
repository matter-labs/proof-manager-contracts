// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "./store/ProofManagerStorage.sol";
import "./interfaces/IProofManager.sol";
import { Transitions } from "./lib/Transitions.sol";

import { OwnableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/*////////////////////////
        Errors
////////////////////////*/

/// @dev field - what was the "field" for which we tried to set a 0 address (I.E. USDC or Fermah)
error AddressCannotBeZero(string field);
error DuplicatedProofRequest(uint256 chainId, uint256 blockNumber);
error InvalidProofRequestTimeout();
error NoPaymentDue();
error OnlyProvingNetworkAllowed(address sender);
error OnlyProvingNetworkAssigneedAllowed(address sender);
error ProofRequestAcknowledgementDeadlinePassed();
error ProofRequestProvingDeadlinePassed();
error ProvingNetworkCannotBeNone();
error RewardBiggerThanLimit(uint256 reward);
error TransitionNotAllowed(ProofRequestStatus from, ProofRequestStatus to);
error TransitionNotAllowedForProofRequestManager(ProofRequestStatus from, ProofRequestStatus to);
error TransitionNotAllowedForProvingNetwork(ProofRequestStatus from, ProofRequestStatus to);
error USDCTransferFailed();

/// @author Matter Labs
/// @notice Entry point for Proof Manager.
contract ProofManagerV1 is IProofManager, Initializable, OwnableUpgradeable, ProofManagerStorage {
    using Transitions for ProofRequestStatus;

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
        ) revert OnlyProvingNetworkAssigneedAllowed(msg.sender);
        _;
    }

    /// @dev You need to have a proving network that is not None to call this function.
    ///     None is an escape hatch (lack of Option<>) and should not be used in public API.
    modifier provingNetworkNotNone(ProvingNetwork provingNetwork) {
        if (provingNetwork == ProvingNetwork.None) revert ProvingNetworkCannotBeNone();
        _;
    }

    /*//////////////////////////////////////////
                    Initialization
    //////////////////////////////////////////*/

    function initialize(address fermah, address lagrange, address usdc, address _owner)
        external
        initializer
    {
        if (_owner == address(0)) revert AddressCannotBeZero("owner");
        __Ownable_init(_owner);
        if (fermah == address(0)) revert AddressCannotBeZero("fermah");
        if (lagrange == address(0)) revert AddressCannotBeZero("lagrange");
        if (usdc == address(0)) revert AddressCannotBeZero("usdc");

        USDC = IERC20(usdc);

        _initializeProvingNetwork(ProvingNetwork.Fermah, fermah);
        _initializeProvingNetwork(ProvingNetwork.Lagrange, lagrange);

        preferredProvingNetwork = ProvingNetwork.None;
        emit PreferredProvingNetworkSet(ProvingNetwork.None);
        _requestCounter = 0;
    }

    /*////////////////////////
            Getters
    ////////////////////////*/

    /// @dev Getter for Proof Request.
    function proofRequest(uint256 chainId, uint256 blockNumber)
        external
        view
        returns (ProofRequest memory)
    {
        return _proofRequests[chainId][blockNumber];
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

    /// @dev Useful for key rotation or key compromise.
    function updateProvingNetworkAddress(ProvingNetwork provingNetwork, address addr)
        external
        onlyOwner
        provingNetworkNotNone(provingNetwork)
    {
        if (addr == address(0)) revert AddressCannotBeZero("proving network");
        _provingNetworks[provingNetwork].addr = addr;
        emit ProvingNetworkAddressChanged(provingNetwork, addr);
    }

    /// @dev Useful for Proving Network outage (Active to Inactive) or recovery (Inactive to Active).
    function updateProvingNetworkStatus(ProvingNetwork provingNetwork, ProvingNetworkStatus status)
        external
        onlyOwner
        provingNetworkNotNone(provingNetwork)
    {
        _provingNetworks[provingNetwork].status = status;
        emit ProvingNetworkStatusChanged(provingNetwork, status);
    }

    /// @dev Used once per month to direct more proofs to the network that scored best previous month.
    function updatePreferredProvingNetwork(ProvingNetwork provingNetwork) external onlyOwner {
        preferredProvingNetwork = provingNetwork;
        emit PreferredProvingNetworkSet(provingNetwork);
    }

    /*//////////////////////////////////////////
            Proof Request Management
    //////////////////////////////////////////*/

    /// @dev Submits a proof request. The proof is assigned to the next proving network in round robin.
    function submitProofRequest(
        ProofRequestIdentifier calldata id,
        ProofRequestParams calldata params
    ) external onlyOwner {
        if (_proofRequests[id.chainId][id.blockNumber].submittedAt != 0) {
            revert DuplicatedProofRequest(id.chainId, id.blockNumber);
        }
        if (params.timeoutAfter == 0) revert InvalidProofRequestTimeout();
        if (params.maxReward > WITHDRAW_LIMIT) revert RewardBiggerThanLimit(params.maxReward);

        ProvingNetwork assignedTo = _nextAssignee();
        bool refused = (assignedTo == ProvingNetwork.None)
            || _provingNetworks[assignedTo].status == ProvingNetworkStatus.Inactive;

        ProofRequestStatus status = refused ? ProofRequestStatus.Refused : ProofRequestStatus.Ready;

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
            provingNetworkPrice: 0,
            proof: bytes("")
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
            params.maxReward
        );

        _requestCounter += 1;
    }

    /// @dev Changes proof request's status. Used for timeout scenarios (unacknowledged/timed out) or validation from L1 (validated/validation failed).
    ///     NOTE: When a proof request is marked as validated, the proof will be due for payment to the proving network that proved it.
    function updateProofRequestStatus(ProofRequestIdentifier calldata id, ProofRequestStatus status)
        external
        onlyOwner
    {
        ProofRequest storage _proofRequest = _proofRequests[id.chainId][id.blockNumber];
        if (!_proofRequest.status.isRequestManagerAllowed(status)) {
            revert TransitionNotAllowedForProofRequestManager(_proofRequest.status, status);
        }
        _proofRequest.status = status;
        emit ProofStatusChanged(id.chainId, id.blockNumber, status);

        if (status == ProofRequestStatus.Validated) {
            ProvingNetworkInfo storage _provingNetworkInfo =
                _provingNetworks[_proofRequest.assignedTo];

            _provingNetworkInfo.unclaimedProofs.push(id);
            _provingNetworkInfo.paymentDue += _proofRequest.provingNetworkPrice;
        }
    }

    /*//////////////////////////////////////////
            Proving Network Interactions
    //////////////////////////////////////////*/

    /// @dev Acknowledges a proof request. The proving network can either commit to prove or refuse (due to price, availability, etc).
    function acknowledgeProofRequest(ProofRequestIdentifier calldata id, bool accept)
        external
        onlyAssignee(id)
    {
        // NOTE: Checking if the proof request exists is not necessary. By default, a proof request that doesn't exist is assigned to ProvingNetwork None.
        //      As such, onlyAssignee(id) will fail.
        ProofRequest storage _proofRequest = _proofRequests[id.chainId][id.blockNumber];
        ProofRequestStatus status =
            accept ? ProofRequestStatus.Committed : ProofRequestStatus.Refused;

        if (_proofRequest.status != ProofRequestStatus.Ready) {
            revert TransitionNotAllowedForProvingNetwork(_proofRequest.status, status);
        }
        if (block.timestamp > _proofRequest.submittedAt + ACK_TIMEOUT) {
            revert ProofRequestAcknowledgementDeadlinePassed();
        }

        _proofRequest.status = status;

        emit ProofStatusChanged(id.chainId, id.blockNumber, _proofRequest.status);
    }

    /// @dev Submit proof for proof request.
    function submitProof(
        ProofRequestIdentifier calldata id,
        bytes calldata proof,
        uint256 provingNetworkPrice
    ) external onlyAssignee(id) {
        ProofRequest storage _proofRequest = _proofRequests[id.chainId][id.blockNumber];
        if (_proofRequest.status != ProofRequestStatus.Committed) {
            revert TransitionNotAllowedForProvingNetwork(
                _proofRequest.status, ProofRequestStatus.Proven
            );
        }
        if (block.timestamp > _proofRequest.submittedAt + _proofRequest.timeoutAfter) {
            revert ProofRequestProvingDeadlinePassed();
        }

        _proofRequest.status = ProofRequestStatus.Proven;
        _proofRequest.proof = proof;
        _proofRequest.provingNetworkPrice = provingNetworkPrice <= _proofRequest.maxReward
            ? provingNetworkPrice
            : _proofRequest.maxReward;

        emit ProofStatusChanged(id.chainId, id.blockNumber, _proofRequest.status);
    }

    /// @dev Withdraws payment for already validated proofs, up to WITHDRAW_LIMIT.
    ///     NOTE: Successive calls can be made if you reached the limit.
    function withdraw() external onlyProvingNetwork {
        ProvingNetwork provingNetwork = msg.sender == _provingNetworks[ProvingNetwork.Fermah].addr
            ? ProvingNetwork.Fermah
            : ProvingNetwork.Lagrange;

        ProvingNetworkInfo storage info = _provingNetworks[provingNetwork];
        uint256 payableAmount = info.paymentDue;
        if (payableAmount == 0) revert NoPaymentDue();

        if (payableAmount > WITHDRAW_LIMIT) {
            payableAmount = WITHDRAW_LIMIT;
        }

        uint256 paid = 0;

        while (info.unclaimedProofs.length > 0 && paid < payableAmount) {
            uint256 last_index = info.unclaimedProofs.length - 1;
            ProofRequestIdentifier memory id = info.unclaimedProofs[last_index];

            ProofRequest storage _proofRequest = _proofRequests[id.chainId][id.blockNumber];

            uint256 price = _proofRequest.provingNetworkPrice;
            if (paid + price > payableAmount) break;

            _proofRequest.status = ProofRequestStatus.Paid;
            paid += price;

            info.unclaimedProofs.pop();
            emit ProofStatusChanged(id.chainId, id.blockNumber, _proofRequest.status);
        }

        info.paymentDue -= paid;
        // sanity check, "should never happen"
        require(paid > 0, "paid==0");

        if (!USDC.transfer(msg.sender, paid)) revert USDCTransferFailed();

        emit PaymentWithdrawn(provingNetwork, paid);
    }

    /*////////////////////////
            Helpers
    ////////////////////////*/

    /// @dev Initializes a proving network. Used in the constructor.
    function _initializeProvingNetwork(ProvingNetwork provingNetwork, address addr) private {
        ProvingNetworkInfo storage info = _provingNetworks[provingNetwork];
        info.addr = addr;
        info.status = ProvingNetworkStatus.Active;
        delete info.unclaimedProofs;
        info.paymentDue = 0;

        emit ProvingNetworkAddressChanged(provingNetwork, addr);
        emit ProvingNetworkStatusChanged(provingNetwork, ProvingNetworkStatus.Active);
    }

    /// @dev Computes the next assignee based on current state. Does not change state!
    ///    NOTE: Assigment is 25%, 25% and 50%.
    function _nextAssignee() private view returns (ProvingNetwork to) {
        uint256 mod = _requestCounter % 4;
        if (mod == 0) return ProvingNetwork.Fermah;
        if (mod == 1) return ProvingNetwork.Lagrange;
        return preferredProvingNetwork;
    }
}
