// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "../interfaces/IProofManager.sol";

/// @author Matter Labs
/// @notice This library contains transition logic for proof request status lifecycle
library Transitions {
    /*
                +--> [Refused]
                |
    [Ready] ----+-----> [Unacknowledged]
                |
                +--> [Committed] --> [TimedOut]
                                |
                                +--> [Proven] --> [ValidationFailed]
                                            |
                                            +--> [Validated] --> [Paid]
    */
    /// @dev This function checks if the transition from one status to another is allowed according to the spec.
    ///     NOTE: Implementation serves as documentation on the state machine.
    /// @param from The current status of the proof request.
    /// @param to The new status of the proof request after transition.
    /// @return True if the transition is allowed, false otherwise.
    function isAllowed(IProofManager.ProofRequestStatus from, IProofManager.ProofRequestStatus to)
        internal
        pure
        returns (bool)
    {
        if (from == IProofManager.ProofRequestStatus.Ready) {
            return (
                to == IProofManager.ProofRequestStatus.Committed
                    || to == IProofManager.ProofRequestStatus.Refused
                    || to == IProofManager.ProofRequestStatus.Unacknowledged
            );
        }
        if (from == IProofManager.ProofRequestStatus.Committed) {
            return (
                to == IProofManager.ProofRequestStatus.Proven
                    || to == IProofManager.ProofRequestStatus.TimedOut
            );
        }
        if (from == IProofManager.ProofRequestStatus.Proven) {
            return (
                to == IProofManager.ProofRequestStatus.Validated
                    || to == IProofManager.ProofRequestStatus.ValidationFailed
            );
        }
        if (from == IProofManager.ProofRequestStatus.Validated) {
            return (to == IProofManager.ProofRequestStatus.Paid);
        }
        return false;
    }

    /*
                +--> [Refused]
                |
    [Ready] ----+-----> [Unacknowledged]
       x        |              x
                +--> [Committed] --> [TimedOut]
                                |        x
                                +--> [Proven] --> [ValidationFailed]
                                            |            x
                                            +--> [Validated] --> [Paid]
                                                      x
    */
    /// @dev Request Manager can do even less transitions (due to access control).
    ///     NOTE: No similar function exists for Proving Networks (handled manually), but could be introduced in the future.
    /// @param from The current status of the proof request.
    /// @param to The new status of the proof request after transition.
    /// @return True if the transition is allowed, false otherwise.
    function isRequestManagerAllowed(
        IProofManager.ProofRequestStatus from,
        IProofManager.ProofRequestStatus to
    ) internal pure returns (bool) {
        if (!isAllowed(from, to)) revert IProofManager.TransitionNotAllowed(from, to);
        return to == IProofManager.ProofRequestStatus.Unacknowledged
            || to == IProofManager.ProofRequestStatus.TimedOut
            || to == IProofManager.ProofRequestStatus.ValidationFailed
            || to == IProofManager.ProofRequestStatus.Validated;
    }
}
