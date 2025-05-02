// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "../Base.t.sol";

contract RequestManagerTest is Base {
    /*////////////////////////
            Helpers
    ////////////////////////*/

    /// @dev Helper DTO for testing proof assignment logic.
    struct SubmitProofExpected {
        ProofManagerStorage.ProvingNetwork network;
        ProofManagerStorage.ProofRequestStatus status;
    }

    /*////////////////////////////////////
            Submit Proof Request
    ////////////////////////////////////*/

    /// @dev Happy path for submitting a proof request.
    function testSubmitProofRequest() public {
        vm.expectEmit(true, true, false, true);
        emit ProofManagerStorage.ProofRequestSubmitted(
            1,
            1,
            ProofManagerStorage.ProvingNetwork.Fermah,
            ProofManagerStorage.ProofRequestStatus.Ready
        );

        proofManager.submitProofRequest(
            ProofManagerStorage.ProofRequestIdentifier(1, 1),
            ProofManagerStorage.ProofRequestParams(
                "https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6
            )
        );
        assertProofRequest(
            ProofManagerStorage.ProofRequestIdentifier(1, 1),
            ProofManagerStorage.ProofRequest(
                "https://console.google.com/buckets/...",
                0,
                27,
                0,
                block.timestamp,
                3600,
                4e6,
                ProofManagerStorage.ProofRequestStatus.Ready,
                ProofManagerStorage.ProvingNetwork.Fermah,
                0,
                bytes("")
            )
        );
    }

    /// @dev Only owner can submit a proof request.
    function testNonOwnerCannotSubmitProof() public {
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        submitDefaultProofRequest(1, 1);
    }

    /// @dev A proof request for a specific chain/batch can be submitted only once.
    function testCannotSubmitDuplicateProof() public {
        submitDefaultProofRequest(1, 1);
        vm.expectRevert("duplicated proof request");
        submitDefaultProofRequest(1, 1);
    }

    /// @dev No proof can be generated in 0 seconds.
    function testCannotSubmitProofWithZeroTimeout() public {
        vm.expectRevert("proof generation timeout must be bigger than 0");
        proofManager.submitProofRequest(
            ProofManagerStorage.ProofRequestIdentifier(1, 1),
            ProofManagerStorage.ProofRequestParams(
                "https://console.google.com/buckets/...", 0, 27, 0, 0, 4e6
            )
        );
    }

    /// @dev If the request is higher than withdrawal limit, then withdraw is blocked.
    function testCannotSubmitProofWithMaxRewardHigherThanWithdrawalLimit() public {
        vm.expectRevert("max reward is higher than maximum withdraw limit");
        proofManager.submitProofRequest(
            ProofManagerStorage.ProofRequestIdentifier(1, 1),
            ProofManagerStorage.ProofRequestParams(
                "https://console.google.com/buckets/...", 0, 27, 0, 3600, 25_000e6 + 1
            )
        );
    }

    /// @dev Happy path for proof assignment logic.
    function testSubmitProofAssignmentLogic() public {
        SubmitProofExpected[8] memory outputs = [
            // request 0, fermah inactive, lagrange active, preferred none
            SubmitProofExpected(
                ProofManagerStorage.ProvingNetwork.Fermah,
                ProofManagerStorage.ProofRequestStatus.Refused
            ),
            // request 1, fermah inactive, lagrange active, preferred none
            SubmitProofExpected(
                ProofManagerStorage.ProvingNetwork.Lagrange,
                ProofManagerStorage.ProofRequestStatus.Ready
            ),
            // request 2, fermah inactive, lagrange active, preferred none
            SubmitProofExpected(
                ProofManagerStorage.ProvingNetwork.None, ProofManagerStorage.ProofRequestStatus.Refused
            ),
            // request 3, fermah inactive, lagrange active, preferred fermah
            SubmitProofExpected(
                ProofManagerStorage.ProvingNetwork.Fermah,
                ProofManagerStorage.ProofRequestStatus.Refused
            ),
            // request 4, fermah active, lagrange active, preferred fermah
            SubmitProofExpected(
                ProofManagerStorage.ProvingNetwork.Fermah, ProofManagerStorage.ProofRequestStatus.Ready
            ),
            // request 5, fermah active, lagrange active, preferred fermah
            SubmitProofExpected(
                ProofManagerStorage.ProvingNetwork.Lagrange,
                ProofManagerStorage.ProofRequestStatus.Ready
            ),
            // request 6, fermah active, lagrange active, preferred fermah
            SubmitProofExpected(
                ProofManagerStorage.ProvingNetwork.Fermah, ProofManagerStorage.ProofRequestStatus.Ready
            ),
            // request 7, fermah active, lagrange active, preferred lagrange
            SubmitProofExpected(
                ProofManagerStorage.ProvingNetwork.Lagrange,
                ProofManagerStorage.ProofRequestStatus.Ready
            )
        ];

        proofManager.markNetwork(
            ProofManagerStorage.ProvingNetwork.Fermah,
            ProofManagerStorage.ProvingNetworkStatus.Inactive
        );

        for (uint256 i = 0; i < 3; ++i) {
            submitDefaultProofRequest(1, i);
        }

        proofManager.setPreferredNetwork(ProofManagerStorage.ProvingNetwork.Fermah);

        submitDefaultProofRequest(1, 3);

        proofManager.markNetwork(
            ProofManagerStorage.ProvingNetwork.Fermah,
            ProofManagerStorage.ProvingNetworkStatus.Active
        );

        for (uint256 i = 4; i < 7; ++i) {
            submitDefaultProofRequest(1, i);
        }

        proofManager.setPreferredNetwork(ProofManagerStorage.ProvingNetwork.Lagrange);

        submitDefaultProofRequest(1, 7);

        for (uint256 i = 0; i < 8; ++i) {
            assertProofRequest(
                ProofManagerStorage.ProofRequestIdentifier(1, i),
                ProofManagerStorage.ProofRequest(
                    "https://console.google.com/buckets/...",
                    0,
                    27,
                    0,
                    block.timestamp,
                    3600,
                    4e6,
                    outputs[i].status,
                    outputs[i].network,
                    0,
                    bytes("")
                )
            );
        }
    }

    /*////////////////////////
            Mark Proof
    ////////////////////////*/

    /// @dev Happy path for marking a proof.
    function testMarkProof() public {
        submitDefaultProofRequest(1, 1);

        proofManager.forceSetProofRequestStatus(
            ProofManagerStorage.ProofRequestIdentifier(1, 1),
            ProofManagerStorage.ProofRequestStatus.Proven
        );

        vm.expectEmit(true, true, false, true);
        emit ProofManagerStorage.ProofStatusChanged(
            1, 1, ProofManagerStorage.ProofRequestStatus.Validated
        );
        proofManager.markProof(
            ProofManagerStorage.ProofRequestIdentifier(1, 1),
            ProofManagerStorage.ProofRequestStatus.Validated
        );
        assertProofRequest(
            ProofManagerStorage.ProofRequestIdentifier(1, 1),
            ProofManagerStorage.ProofRequest(
                "https://console.google.com/buckets/...",
                0,
                27,
                0,
                block.timestamp,
                3600,
                4e6,
                ProofManagerStorage.ProofRequestStatus.Validated,
                ProofManagerStorage.ProvingNetwork.Fermah,
                0,
                bytes("")
            )
        );
    }

    /// @dev Only owner can mark a proof.
    function testNonOwnerCannotMarkProof() public {
        submitDefaultProofRequest(1, 1);
        proofManager.forceSetProofRequestStatus(
            ProofManagerStorage.ProofRequestIdentifier(1, 1),
            ProofManagerStorage.ProofRequestStatus.Proven
        );
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.markProof(
            ProofManagerStorage.ProofRequestIdentifier(1, 1),
            ProofManagerStorage.ProofRequestStatus.Validated
        );
    }

    /// @dev Proof Manager respects it's transition access control.
    function testIllegalTransitionReverts() public {
        submitDefaultProofRequest(1, 1);

        vm.expectRevert("transition not allowed for request manager");
        proofManager.markProof(
            ProofManagerStorage.ProofRequestIdentifier(1, 1),
            ProofManagerStorage.ProofRequestStatus.Committed
        );
    }

    /// @dev Moving proofs to validated makes them due for payment.
    function testMarkProofAsValidatedForPayment() public {
        for (uint256 i = 0; i < 8; ++i) {
            uint256 price = (i + 1) * 1e6;
            // submit request
            proofManager.submitProofRequest(
                ProofManagerStorage.ProofRequestIdentifier(1, i),
                ProofManagerStorage.ProofRequestParams(
                    "https://console.google.com/buckets/...", 0, 27, 0, 3600, price
                )
            );
            // pretend it's been committed
            proofManager.forceSetProofRequestStatus(
                ProofManagerStorage.ProofRequestIdentifier(1, i),
                ProofManagerStorage.ProofRequestStatus.Committed
            );

            if (i % 4 < 2) {
                if (i % 4 == 0) {
                    vm.prank(fermah);
                } else {
                    vm.prank(lagrange);
                }
                // this can't be pretended, as we need to set the price
                proofManager.submitProof(
                    ProofManagerStorage.ProofRequestIdentifier(1, i),
                    bytes("such proof much wow"),
                    price
                );
                // mark it as validated
                proofManager.markProof(
                    ProofManagerStorage.ProofRequestIdentifier(1, i),
                    ProofManagerStorage.ProofRequestStatus.Validated
                );
            }
        }

        ProofManagerStorage.ProofRequestIdentifier[] memory identifiers =
            new ProofManagerStorage.ProofRequestIdentifier[](2);
        identifiers[0] = ProofManagerStorage.ProofRequestIdentifier(1, 0);
        identifiers[1] = ProofManagerStorage.ProofRequestIdentifier(1, 4);
        assertProvingNetworkInfo(
            ProofManagerStorage.ProvingNetwork.Fermah,
            ProofManagerStorage.ProvingNetworkInfo(
                fermah, ProofManagerStorage.ProvingNetworkStatus.Active, identifiers, 6e6
            )
        );
        identifiers = new ProofManagerStorage.ProofRequestIdentifier[](2);
        identifiers[0] = ProofManagerStorage.ProofRequestIdentifier(1, 1);
        identifiers[1] = ProofManagerStorage.ProofRequestIdentifier(1, 5);
        assertProvingNetworkInfo(
            ProofManagerStorage.ProvingNetwork.Lagrange,
            ProofManagerStorage.ProvingNetworkInfo(
                lagrange, ProofManagerStorage.ProvingNetworkStatus.Active, identifiers, 8e6
            )
        );
    }
}
