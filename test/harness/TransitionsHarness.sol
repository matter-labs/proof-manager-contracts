// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "../../src/interfaces/IProofManager.sol";
import "../../src/lib/Transitions.sol";

/// @dev Test‑only wrapper.
contract TransitionsHarness {
    function requestManagerAllowed(ProofRequestStatus from, ProofRequestStatus to)
        external
        pure
        returns (bool)
    {
        // turns this library call in a real EVM message call
        return Transitions.isRequestManagerAllowed(from, to);
    }
}
