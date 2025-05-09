// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "./store/ProofManagerStorage.sol";
import { Transitions } from "./lib/Transitions.sol";
import "./interfaces/IProofManager.sol";

import { OwnableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @author Matter Labs
/// @notice Entry point for Proof Manager.
contract ProofManagerV1 is IProofManager, Initializable, OwnableUpgradeable, ProofManagerStorage {
    using Transitions for ProofRequestStatus;

    IERC20 public USDC;

    /// @dev Constructor. Sets up the contract.
    function initialize(address fermah, address lagrange, address usdc, address _owner)
        external
        initializer
    {
        require(_owner != address(0), "owner cannot be zero");
        __Ownable_init(_owner);
        require(
            fermah != address(0) && lagrange != address(0), "proving network address cannot be zero"
        );
        require(usdc != address(0), "usdc contract address cannot be zero");

        USDC = IERC20(usdc);

        initializeProvingNetwork(ProvingNetwork.Fermah, fermah);
        initializeProvingNetwork(ProvingNetwork.Lagrange, lagrange);

        _preferredProvingNetwork = ProvingNetwork.None;
        emit PreferredProvingNetworkSet(ProvingNetwork.None);
        _requestCounter = 0;
    }

    /*////////////////////////
            Helpers
    ////////////////////////*/

    /// @dev Initializes a proving network. Used in the constructor.
    function initializeProvingNetwork(ProvingNetwork provingNetwork, address addr) private {
        ProvingNetworkInfo storage info = _provingNetworks[provingNetwork];
        info.addr = addr;
        info.status = ProvingNetworkStatus.Active;
        delete info.unclaimedProofs;
        info.paymentDue = 0;

        emit ProvingNetworkAddressChanged(provingNetwork, addr);
        emit ProvingNetworkStatusChanged(provingNetwork, ProvingNetworkStatus.Active);
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

    /// @dev Getter for Preferred Proving Network.
    function preferredNetwork() external view returns (ProvingNetwork) {
        return _preferredProvingNetwork;
    }

    /////// NetworkAdmin functions ///////

    /*////////////////////////
            Modifiers
    ////////////////////////*/

    /// @dev None is an escape hatch (lack of Option<>) and should not be used in public API.
    modifier provingNetworkNotNone(ProvingNetwork provingNetwork) {
        require(provingNetwork != ProvingNetwork.None, "proving network cannot be None");
        _;
    }

    /*////////////////////////
            Public API
    ////////////////////////*/

    /// @dev Useful for key rotation or key compromise.
    function updateProvingNetworkAddress(ProvingNetwork provingNetwork, address addr)
        external
        onlyOwner
        provingNetworkNotNone(provingNetwork)
    {
        require(addr != address(0), "cannot unset proving network address");
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
        _preferredProvingNetwork = provingNetwork;
        emit PreferredProvingNetworkSet(provingNetwork);
    }

    ///////// Proving Network Actions /////////

    /*////////////////////////
            Modifiers
    ////////////////////////*/

    /// @dev You need to be a proving network to call this function.
    modifier onlyProvingNetwork() {
        require(
            msg.sender == _provingNetworks[ProvingNetwork.Fermah].addr
                || msg.sender == _provingNetworks[ProvingNetwork.Lagrange].addr,
            "only proving network"
        );
        _;
    }

    /// @dev You need the proof request to be assigned to you to call this function.
    modifier onlyAssignee(ProofRequestIdentifier calldata id) {
        require(
            msg.sender
                == _provingNetworks[_proofRequests[id.chainId][id.blockNumber].assignedTo].addr,
            "only proving network assignee"
        );
        _;
    }

    /*////////////////////////
            Public API
    ////////////////////////*/

    /// @dev Acknowledges a proof request. The proving network can either commit to prove or refuse (due to price, availability, etc).
    function acknowledgeProofRequest(ProofRequestIdentifier calldata id, bool accept)
        external
        onlyAssignee(id)
    {
        // NOTE: Checking if the proof request exists is not necessary. By default, a proof request that doesn't exist is assigned to ProvingNetwork None.
        //      As such, onlyAssignee(id) will fail.
        ProofRequest storage _proofRequest = _proofRequests[id.chainId][id.blockNumber];
        require(
            _proofRequest.status == ProofRequestStatus.Ready,
            "cannot acknowledge proof request that is not ready"
        );
        require(
            block.timestamp <= _proofRequest.submittedAt + ACK_TIMEOUT,
            "proof request passed acknowledgement deadline"
        );

        _proofRequest.status = accept ? ProofRequestStatus.Committed : ProofRequestStatus.Refused;

        emit ProofStatusChanged(id.chainId, id.blockNumber, _proofRequest.status);
    }

    /// @dev Submit proof for proof request.
    function submitProof(
        ProofRequestIdentifier calldata id,
        bytes calldata proof,
        uint256 provingNetworkPrice
    ) external onlyAssignee(id) {
        ProofRequest storage _proofRequest = _proofRequests[id.chainId][id.blockNumber];
        require(
            _proofRequest.status == ProofRequestStatus.Committed,
            "cannot submit proof for non committed proof request"
        );
        require(
            block.timestamp <= _proofRequest.submittedAt + _proofRequest.timeoutAfter,
            "proof request passed proving deadline"
        );

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
        require(payableAmount > 0, "no payment due");

        if (payableAmount > WITHDRAW_LIMIT) {
            payableAmount = WITHDRAW_LIMIT;
        }

        uint256 paid = 0;
        uint256 i = 0;

        while (i < info.unclaimedProofs.length && paid < payableAmount) {
            ProofRequestIdentifier memory id = info.unclaimedProofs[i];

            ProofRequest storage _proofRequest = _proofRequests[id.chainId][id.blockNumber];

            uint256 price = _proofRequest.provingNetworkPrice;
            if (paid + price > payableAmount) break;

            _proofRequest.status = ProofRequestStatus.Paid;
            paid += price;

            // swap and pop to reduce gas utilization
            info.unclaimedProofs[i] = info.unclaimedProofs[info.unclaimedProofs.length - 1];
            info.unclaimedProofs.pop();
        }

        info.paymentDue -= paid;
        // sanity check, "should never happen"
        require(paid > 0, "paid==0");

        require(USDC.transfer(msg.sender, paid), "USDC transfer fail");
        emit PaymentWithdrawn(provingNetwork, paid);
    }

    /////////// Proving Network Actions ///////////

    /*////////////////////////
            Helpers
    ////////////////////////*/

    /// @dev Computes the next assignee based on current state. Does not change state!
    ///    NOTE: Assigment is 25%, 25% and 50%.
    function _nextAssignee() internal view returns (ProvingNetwork to) {
        uint256 mod = _requestCounter % 4;
        if (mod == 0) return ProvingNetwork.Fermah;
        if (mod == 1) return ProvingNetwork.Lagrange;
        return _preferredProvingNetwork;
    }

    /*////////////////////////
            Public API
    ////////////////////////*/

    /// @dev Submits a proof request. The proof is assigned to the next proving network in round robin.
    function submitProofRequest(
        ProofRequestIdentifier calldata id,
        ProofRequestParams calldata params
    ) external onlyOwner {
        require(
            _proofRequests[id.chainId][id.blockNumber].submittedAt == 0, "duplicated proof request"
        );
        require(params.timeoutAfter > 0, "proof generation timeout must be bigger than 0");

        require(
            params.maxReward <= WITHDRAW_LIMIT, "max reward is higher than maximum withdraw limit"
        );

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
        require(
            _proofRequest.status.isRequestManagerAllowed(status),
            "transition not allowed for request manager"
        );
        _proofRequest.status = status;
        emit ProofStatusChanged(id.chainId, id.blockNumber, status);

        if (status == ProofRequestStatus.Validated) {
            ProvingNetworkInfo storage _provingNetworkInfo =
                _provingNetworks[_proofRequest.assignedTo];

            _provingNetworkInfo.unclaimedProofs.push(id);
            _provingNetworkInfo.paymentDue += _proofRequest.provingNetworkPrice;
        }
    }
}
