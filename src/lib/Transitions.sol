// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import { ProofRequestStatus } from "../interfaces/IProofManager.sol";

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
    function isAllowed(ProofRequestStatus from, ProofRequestStatus to)
        internal
        pure
        returns (bool)
    {
        if (from == ProofRequestStatus.Ready) {
            return (
                to == ProofRequestStatus.Committed || to == ProofRequestStatus.Refused
                    || to == ProofRequestStatus.Unacknowledged
            );
        }
        if (from == ProofRequestStatus.Committed) {
            return (to == ProofRequestStatus.Proven || to == ProofRequestStatus.TimedOut);
        }
        if (from == ProofRequestStatus.Proven) {
            return (to == ProofRequestStatus.Validated || to == ProofRequestStatus.ValidationFailed);
        }
        if (from == ProofRequestStatus.Validated) {
            return (to == ProofRequestStatus.Paid);
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
    function isRequestManagerAllowed(ProofRequestStatus from, ProofRequestStatus to)
        internal
        pure
        returns (bool)
    {
        require(isAllowed(from, to), "invalid transition");
        return to == ProofRequestStatus.Unacknowledged || to == ProofRequestStatus.TimedOut
            || to == ProofRequestStatus.ValidationFailed || to == ProofRequestStatus.Validated;
    }
}
