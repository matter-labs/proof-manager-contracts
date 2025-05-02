// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "../store/ProofManagerStorage.sol";

/// @author Matter Labs
/// @notice This library contains transition logic for proof request status lifecycle
library Transitions {
    /*
                +--> [refuse]
                |
    [ready] -------+--> [unack]
                |
                +--> [commit] --> [timed out]
                            |
                            +--> [proven] --> [failed]
                                            |
                                            +--> [validated] --> [paid]
    */
    /// @dev This function checks if the transition from one status to another is allowed according to the spec.
    ///     NOTE: Implementation serves as documentation on the state machine.
    /// @param from The current status of the proof request.
    /// @param to The new status of the proof request after transition.
    /// @return True if the transition is allowed, false otherwise.
    function isAllowed(
        ProofManagerStorage.ProofRequestStatus from,
        ProofManagerStorage.ProofRequestStatus to
    ) internal pure returns (bool) {
        if (from == ProofManagerStorage.ProofRequestStatus.Ready) {
            return (
                to == ProofManagerStorage.ProofRequestStatus.Committed
                    || to == ProofManagerStorage.ProofRequestStatus.Refused
                    || to == ProofManagerStorage.ProofRequestStatus.Unacknowledged
            );
        }
        if (from == ProofManagerStorage.ProofRequestStatus.Committed) {
            return (
                to == ProofManagerStorage.ProofRequestStatus.Proven
                    || to == ProofManagerStorage.ProofRequestStatus.TimedOut
            );
        }
        if (from == ProofManagerStorage.ProofRequestStatus.Proven) {
            return (
                to == ProofManagerStorage.ProofRequestStatus.Validated
                    || to == ProofManagerStorage.ProofRequestStatus.ValidationFailed
            );
        }
        if (from == ProofManagerStorage.ProofRequestStatus.Validated) {
            return (to == ProofManagerStorage.ProofRequestStatus.Paid);
        }
        return false;
    }

    /*
                +--> [refuse]
                |        x
    [ready] -------+--> [unack]
        x       |
                +--> [commit] --> [timed out]
                         x  |
                            +--> [proven] --> [failed]
                                     x      |
                                            +--> [validated] --> [paid]
                                                                    x
    */
    /// @dev Request Manager can do even less transitions (due to access control).
    ///     NOTE: No similar function exists for Proving Networks (handled manually), but could be introduced in the future.
    /// @param from The current status of the proof request.
    /// @param to The new status of the proof request after transition.
    /// @return True if the transition is allowed, false otherwise.
    function isRequestManagerAllowed(
        ProofManagerStorage.ProofRequestStatus from,
        ProofManagerStorage.ProofRequestStatus to
    ) internal pure returns (bool) {
        require(isAllowed(from, to), "invalid transition");
        return to == ProofManagerStorage.ProofRequestStatus.Unacknowledged
            || to == ProofManagerStorage.ProofRequestStatus.TimedOut
            || to == ProofManagerStorage.ProofRequestStatus.ValidationFailed
            || to == ProofManagerStorage.ProofRequestStatus.Validated;
    }
}
