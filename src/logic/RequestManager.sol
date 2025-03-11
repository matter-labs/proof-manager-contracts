// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "../store/ProofManagerStorage.sol";
import "../lib/Transitions.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @author Matter Labs
/// @notice This contract is used for proof request management.
abstract contract RequestManager is ProofManagerStorage, Ownable {
    using Transitions for ProofRequestStatus;

    /*////////////////////////
            Helpers
    ////////////////////////*/

    /// @dev Computes the next assignee based on current state. Does not change state!
    ///    NOTE: Assigment is 25%, 25% and 50%.
    function _nextAssignee() internal view returns (ProvingNetwork to) {
        uint256 mod = _requestCounter % 4;
        if (mod == 0) return ProvingNetwork.Fermah;
        if (mod == 1) return ProvingNetwork.Lagrange;
        return _preferredNetwork;
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
            _proofRequests[id.chainId][id.blockNumber].submittedAt == 0,
            "duplicated proof request"
        );
        require(
            params.timeoutAfter > 0,
            "proof generation timeout must be bigger than 0"
        );

        require(
            params.maxReward <= WITHDRAW_LIMIT,
            "max reward is higher than maximum withdraw limit"
        );

        ProvingNetwork assignedTo = _nextAssignee();
        bool refused = (assignedTo == ProvingNetwork.None) ||
            _provingNetworks[assignedTo].status ==
            ProvingNetworkStatus.Inactive;

        ProofRequestStatus status = refused
            ? ProofRequestStatus.Refused
            : ProofRequestStatus.Ready;

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
            status
        );

        _requestCounter += 1;
    }

    /// @dev Changes proof request's status. Used for timeout scenarios (unacknowledged/timed out) or validation from L1 (validated/validation failed).
    ///     NOTE: When a proof request is marked as validated, the proof will be due for payment to the proving network that proved it.
    function markProof(
        ProofRequestIdentifier calldata id,
        ProofRequestStatus status
    ) external onlyOwner {
        ProofRequest storage proofRequest = _proofRequests[id.chainId][
            id.blockNumber
        ];
        require(
            proofRequest.status.isRequestManagerAllowed(status),
            "transition not allowed for request manager"
        );
        proofRequest.status = status;
        emit ProofStatusChanged(id.chainId, id.blockNumber, status);

        if (status == ProofRequestStatus.Validated) {
            ProvingNetworkInfo storage provingNetworkInfo = _provingNetworks[
                proofRequest.assignedTo
            ];

            provingNetworkInfo.unclaimedProofs.push(id);
            provingNetworkInfo.paymentDue += proofRequest.provingNetworkPrice;
        }
    }
}
