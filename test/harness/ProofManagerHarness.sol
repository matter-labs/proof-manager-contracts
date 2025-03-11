// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "../../src/ProofManager.sol";

/// @dev Test‑only wrapper that exposes internal fields/allows specific transitions to simplify code.
contract ProofManagerHarness is ProofManager {
    constructor(
        address fermah,
        address lagrange,
        address usdc
    ) ProofManager(fermah, lagrange, usdc) {}

    /*////////////////////////
            Helpers
    ////////////////////////*/

    /// @dev Changes status of a proof request, regardless of state machine.
    function forceSetProofRequestStatus(
        ProofManagerStorage.ProofRequestIdentifier memory id,
        ProofManagerStorage.ProofRequestStatus status
    ) external {
        _proofRequests[id.chainId][id.blockNumber].status = status;
    }

    /// @dev Changes assignee of proof request, regardless of round robin.
    function forceSetProofRequestAssignee(
        ProofManagerStorage.ProofRequestIdentifier memory id,
        ProofManagerStorage.ProvingNetwork assignee
    ) external {
        _proofRequests[id.chainId][id.blockNumber].assignedTo = assignee;
    }
}
