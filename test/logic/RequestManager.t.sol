// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "../Base.t.sol";

contract RequestManagerTest is Base {
    /*////////////////////////
            Helpers
    ////////////////////////*/

    /// @dev Helper DTO for testing proof assignment logic.
    struct SubmitProofExpected {
        ProvingNetwork network;
        ProofRequestStatus status;
    }

    /*////////////////////////////////////
            Submit Proof Request
    ////////////////////////////////////*/

    /// @dev Happy path for submitting a proof request.
    function testSubmitProofRequest() public {
        vm.expectEmit(true, true, false, true);
        emit ProofRequestSubmitted(1, 1, ProvingNetwork.Fermah, ProofRequestStatus.Ready);

        proofManager.submitProofRequest(
            ProofRequestIdentifier(1, 1),
            ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6)
        );
        assertProofRequest(
            ProofRequestIdentifier(1, 1),
            ProofManagerStorage.ProofRequest(
                "https://console.google.com/buckets/...",
                0,
                27,
                0,
                block.timestamp,
                3600,
                4e6,
                ProofRequestStatus.Ready,
                ProvingNetwork.Fermah,
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
            ProofRequestIdentifier(1, 1),
            ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 0, 4e6)
        );
    }

    /// @dev If the request is higher than withdrawal limit, then withdraw is blocked.
    function testCannotSubmitProofWithMaxRewardHigherThanWithdrawalLimit() public {
        vm.expectRevert("max reward is higher than maximum withdraw limit");
        proofManager.submitProofRequest(
            ProofRequestIdentifier(1, 1),
            ProofRequestParams(
                "https://console.google.com/buckets/...", 0, 27, 0, 3600, 25_000e6 + 1
            )
        );
    }

    /// @dev Happy path for proof assignment logic.
    function testSubmitProofAssignmentLogic() public {
        SubmitProofExpected[8] memory outputs = [
            // request 0, fermah inactive, lagrange active, preferred none
            SubmitProofExpected(ProvingNetwork.Fermah, ProofRequestStatus.Refused),
            // request 1, fermah inactive, lagrange active, preferred none
            SubmitProofExpected(ProvingNetwork.Lagrange, ProofRequestStatus.Ready),
            // request 2, fermah inactive, lagrange active, preferred none
            SubmitProofExpected(ProvingNetwork.None, ProofRequestStatus.Refused),
            // request 3, fermah inactive, lagrange active, preferred fermah
            SubmitProofExpected(ProvingNetwork.Fermah, ProofRequestStatus.Refused),
            // request 4, fermah active, lagrange active, preferred fermah
            SubmitProofExpected(ProvingNetwork.Fermah, ProofRequestStatus.Ready),
            // request 5, fermah active, lagrange active, preferred fermah
            SubmitProofExpected(ProvingNetwork.Lagrange, ProofRequestStatus.Ready),
            // request 6, fermah active, lagrange active, preferred fermah
            SubmitProofExpected(ProvingNetwork.Fermah, ProofRequestStatus.Ready),
            // request 7, fermah active, lagrange active, preferred lagrange
            SubmitProofExpected(ProvingNetwork.Lagrange, ProofRequestStatus.Ready)
        ];

        proofManager.updateProvingNetworkStatus(
            ProvingNetwork.Fermah, ProvingNetworkStatus.Inactive
        );

        for (uint256 i = 0; i < 3; ++i) {
            submitDefaultProofRequest(1, i);
        }

        proofManager.updatePreferredProvingNetwork(ProvingNetwork.Fermah);

        submitDefaultProofRequest(1, 3);

        proofManager.updateProvingNetworkStatus(ProvingNetwork.Fermah, ProvingNetworkStatus.Active);

        for (uint256 i = 4; i < 7; ++i) {
            submitDefaultProofRequest(1, i);
        }

        proofManager.updatePreferredProvingNetwork(ProvingNetwork.Lagrange);

        submitDefaultProofRequest(1, 7);

        for (uint256 i = 0; i < 8; ++i) {
            assertProofRequest(
                ProofRequestIdentifier(1, i),
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
            ProofRequestIdentifier(1, 1), ProofRequestStatus.Proven
        );

        vm.expectEmit(true, true, false, true);
        emit ProofStatusChanged(1, 1, ProofRequestStatus.Validated);
        proofManager.updateProofRequestStatus(
            ProofRequestIdentifier(1, 1), ProofRequestStatus.Validated
        );
        assertProofRequest(
            ProofRequestIdentifier(1, 1),
            ProofManagerStorage.ProofRequest(
                "https://console.google.com/buckets/...",
                0,
                27,
                0,
                block.timestamp,
                3600,
                4e6,
                ProofRequestStatus.Validated,
                ProvingNetwork.Fermah,
                0,
                bytes("")
            )
        );
    }

    /// @dev Only owner can mark a proof.
    function testNonOwnerCannotMarkProof() public {
        submitDefaultProofRequest(1, 1);
        proofManager.forceSetProofRequestStatus(
            ProofRequestIdentifier(1, 1), ProofRequestStatus.Proven
        );
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.updateProofRequestStatus(
            ProofRequestIdentifier(1, 1), ProofRequestStatus.Validated
        );
    }

    /// @dev Proof Manager respects it's transition access control.
    function testIllegalTransitionReverts() public {
        submitDefaultProofRequest(1, 1);

        vm.expectRevert("transition not allowed for request manager");
        proofManager.updateProofRequestStatus(
            ProofRequestIdentifier(1, 1), ProofRequestStatus.Committed
        );
    }

    /// @dev Moving proofs to validated makes them due for payment.
    function testMarkProofAsValidatedForPayment() public {
        for (uint256 i = 0; i < 8; ++i) {
            uint256 price = (i + 1) * 1e6;
            // submit request
            proofManager.submitProofRequest(
                ProofRequestIdentifier(1, i),
                ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, price)
            );
            // pretend it's been committed
            proofManager.forceSetProofRequestStatus(
                ProofRequestIdentifier(1, i), ProofRequestStatus.Committed
            );

            if (i % 4 < 2) {
                if (i % 4 == 0) {
                    vm.prank(fermah);
                } else {
                    vm.prank(lagrange);
                }
                // this can't be pretended, as we need to set the price
                proofManager.submitProof(
                    ProofRequestIdentifier(1, i), bytes("such proof much wow"), price
                );
                // mark it as validated
                proofManager.updateProofRequestStatus(
                    ProofRequestIdentifier(1, i), ProofRequestStatus.Validated
                );
            }
        }

        ProofRequestIdentifier[] memory identifiers = new ProofRequestIdentifier[](2);
        identifiers[0] = ProofRequestIdentifier(1, 0);
        identifiers[1] = ProofRequestIdentifier(1, 4);
        assertProvingNetworkInfo(
            ProvingNetwork.Fermah,
            ProofManagerStorage.ProvingNetworkInfo(
                fermah, ProvingNetworkStatus.Active, identifiers, 6e6
            )
        );
        identifiers = new ProofRequestIdentifier[](2);
        identifiers[0] = ProofRequestIdentifier(1, 1);
        identifiers[1] = ProofRequestIdentifier(1, 5);
        assertProvingNetworkInfo(
            ProvingNetwork.Lagrange,
            ProofManagerStorage.ProvingNetworkInfo(
                lagrange, ProvingNetworkStatus.Active, identifiers, 8e6
            )
        );
    }
}
