// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";

import "../harness/TransitionsHarness.sol";

contract TransitionsTest is Test {
    using Transitions for ProofRequestStatus;

    /// @dev Ensures that all transitions possible are covered.
    function testIsAllowedMatrix() public pure {
        for (uint8 i = 0; i < 9; i++) {
            for (uint8 j = 0; j < 9; j++) {
                ProofRequestStatus from = ProofRequestStatus(i);
                ProofRequestStatus to = ProofRequestStatus(j);

                bool expected = false;

                // Ready to {Committed, Refused, Unacknowledged}
                if (
                    from == ProofRequestStatus.Ready
                        && (
                            to == ProofRequestStatus.Committed || to == ProofRequestStatus.Refused
                                || to == ProofRequestStatus.Unacknowledged
                        )
                ) {
                    expected = true;
                }
                // Committed to {Proven, TimedOut}
                else if (
                    from == ProofRequestStatus.Committed
                        && (to == ProofRequestStatus.Proven || to == ProofRequestStatus.TimedOut)
                ) {
                    expected = true;
                }
                // Proven to {Validated, ValidationFailed}
                else if (
                    from == ProofRequestStatus.Proven
                        && (
                            to == ProofRequestStatus.Validated
                                || to == ProofRequestStatus.ValidationFailed
                        )
                ) {
                    expected = true;
                }
                // Validated to {Paid}
                else if (from == ProofRequestStatus.Validated && to == ProofRequestStatus.Paid) {
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
                ProofRequestStatus from = ProofRequestStatus(i);
                ProofRequestStatus to = ProofRequestStatus(j);

                // general transition
                bool allowed = from.isAllowed(to);

                // request manager transition -- note we don't need to check from state, as it's been checked in `isAllowed` above
                bool expected = (
                    to == ProofRequestStatus.Unacknowledged || to == ProofRequestStatus.TimedOut
                        || to == ProofRequestStatus.ValidationFailed
                        || to == ProofRequestStatus.Validated
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
                    vm.expectRevert("invalid transition");
                    harness.requestManagerAllowed(from, to);
                }
            }
        }
    }
}
