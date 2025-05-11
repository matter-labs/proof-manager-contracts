// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "../../src/interfaces/IProofManager.sol";
import { Transitions } from "../../src/lib/Transitions.sol";

/// @dev Test‑only wrapper to materialize library call.
contract TransitionsHarness {
    function requestManagerAllowed(
        IProofManager.ProofRequestStatus from,
        IProofManager.ProofRequestStatus to
    ) external pure returns (bool) {
        // turns this library call in a real EVM message call
        return Transitions.isRequestManagerAllowed(from, to);
    }
}
