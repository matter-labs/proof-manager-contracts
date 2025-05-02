// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "../../src/ProofManagerV1.sol";
import "../../src/interfaces/IProofManager.sol";

/// @dev Test‑only wrapper that exposes internal fields/allows specific transitions to simplify code.
contract ProofManagerHarness is ProofManagerV1 {
    // constructor() {
    // }

    /*////////////////////////
            Helpers
    ////////////////////////*/

    /// @dev Changes status of a proof request, regardless of state machine.
    function forceSetProofRequestStatus(ProofRequestIdentifier memory id, ProofRequestStatus status)
        external
    {
        _proofRequests[id.chainId][id.blockNumber].status = status;
    }

    /// @dev Changes assignee of proof request, regardless of round robin.
    function forceSetProofRequestAssignee(ProofRequestIdentifier memory id, ProvingNetwork assignee)
        external
    {
        _proofRequests[id.chainId][id.blockNumber].assignedTo = assignee;
    }
}
