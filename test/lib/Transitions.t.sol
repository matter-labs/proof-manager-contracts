// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";

import "../../src/interfaces/IProofManager.sol";
import { Transitions } from "../../src/lib/Transitions.sol";
import { TransitionsHarness } from "../harness/TransitionsHarness.sol";
import "../../src/ProofManagerV1.sol";

/// @dev Test contract for the Transitions library.
contract TransitionsTest is Test {
    using Transitions for IProofManager.ProofRequestStatus;

    /// @dev Ensures that all transitions possible are covered.
    function testIsAllowedMatrix() public pure {
        for (uint8 i = 0; i < 9; i++) {
            for (uint8 j = 0; j < 9; j++) {
                IProofManager.ProofRequestStatus from = IProofManager.ProofRequestStatus(i);
                IProofManager.ProofRequestStatus to = IProofManager.ProofRequestStatus(j);

                bool expected = false;

                // Ready to {Committed, Refused, Unacknowledged}
                if (
                    from == IProofManager.ProofRequestStatus.Ready
                        && (
                            to == IProofManager.ProofRequestStatus.Committed || to == IProofManager.ProofRequestStatus.Refused
                                || to == IProofManager.ProofRequestStatus.Unacknowledged
                        )
                ) {
                    expected = true;
                }
                // Committed to {Proven, TimedOut}
                else if (
                    from == IProofManager.ProofRequestStatus.Committed
                        && (to == IProofManager.ProofRequestStatus.Proven || to == IProofManager.ProofRequestStatus.TimedOut)
                ) {
                    expected = true;
                }
                // Proven to {Validated, ValidationFailed}
                else if (
                    from == IProofManager.ProofRequestStatus.Proven
                        && (
                            to == IProofManager.ProofRequestStatus.Validated
                                || to == IProofManager.ProofRequestStatus.ValidationFailed
                        )
                ) {
                    expected = true;
                }
                // Validated to {Paid}
                else if (from == IProofManager.ProofRequestStatus.Validated && to == IProofManager.ProofRequestStatus.Paid) {
                    expected = true;
                }

                bool actual = from.isAllowed(to);
                assertEq(
                    actual,
                    expected,
                    string(
                        abi.encodePacked(
                            "isAllowed(",
                            vm.toString(i),
                            ", ",
                            vm.toString(j),
                            ") = ",
                            vm.toString(actual),
                            " expected ",
                            vm.toString(expected)
                        )
                    )
                );
            }
        }
    }

    /// @dev Ensures that RequestManager can do a subset of transitions (the ones access control allows for).
    function testRequestManagerAllowedOrRevertMatrix() public {
        TransitionsHarness harness = new TransitionsHarness();
        for (uint8 i = 0; i < 9; i++) {
            for (uint8 j = 0; j < 9; j++) {
                IProofManager.ProofRequestStatus from = IProofManager.ProofRequestStatus(i);
                IProofManager.ProofRequestStatus to = IProofManager.ProofRequestStatus(j);

                // general transition
                bool allowed = from.isAllowed(to);

                // request manager transition -- note we don't need to check from state, as it's been checked in `isAllowed` above
                bool expected = (
                    to == IProofManager.ProofRequestStatus.Unacknowledged || to == IProofManager.ProofRequestStatus.TimedOut
                        || to == IProofManager.ProofRequestStatus.ValidationFailed
                        || to == IProofManager.ProofRequestStatus.Validated
                );

                if (allowed) {
                    // if good transition, it's either allowed or not

                    bool actual = from.isRequestManagerAllowed(to);
                    assertEq(
                        actual,
                        expected,
                        string(
                            abi.encodePacked(
                                "isRequestManagerAllowed(",
                                vm.toString(i),
                                ", ",
                                vm.toString(j),
                                ") = ",
                                vm.toString(actual),
                                " expected ",
                                vm.toString(expected)
                            )
                        )
                    );
                } else {
                    // otherwise it is a guaranteed revert
                    vm.expectRevert(abi.encodeWithSelector(IProofManager.TransitionNotAllowed.selector, from, to));
                    harness.requestManagerAllowed(from, to);
                }
            }
        }
    }
}
