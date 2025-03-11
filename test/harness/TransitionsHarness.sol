// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "../../src/store/ProofManagerStorage.sol";
import "../../src/lib/Transitions.sol";

/// @dev Test‑only wrapper.
contract TransitionsHarness {
    function requestManagerAllowed(
        ProofManagerStorage.ProofRequestStatus from,
        ProofManagerStorage.ProofRequestStatus to
    ) external pure returns (bool) {
        // turns this library call in a real EVM message call
        return Transitions.isRequestManagerAllowed(from, to);
    }
}
