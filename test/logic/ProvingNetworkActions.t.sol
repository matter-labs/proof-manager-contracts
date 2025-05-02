pragma solidity ^0.8.29;

import "../Base.t.sol";

contract ProverActionsTest is Base {
    /*////////////////////////////////////
            Acknowledge Proof Request
    ////////////////////////////////////*/

    /// @dev Happy path for commiting to a proof request.
    function testAcknowledgeProofRequestCommitted() public {
        submitDefaultProofRequest(1, 1);

        vm.prank(fermah);

        vm.expectEmit(true, true, false, true);
        emit ProofStatusChanged(1, 1, ProofRequestStatus.Committed);
        proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, 1), true);

        ProofManagerStorage.ProofRequest memory proofRequest = proofManager.proofRequest(1, 1);
        assertEq(uint8(proofRequest.status), uint8(ProofRequestStatus.Committed));
    }

    /// @dev Happy path for refusing a proof request.
    function testAcknowledgeProofRequestRefused() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);

        vm.expectEmit(true, true, false, true);
        emit ProofStatusChanged(1, 1, ProofRequestStatus.Refused);
        proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, 1), false);

        ProofManagerStorage.ProofRequest memory proofRequest = proofManager.proofRequest(1, 1);
        assertEq(uint8(proofRequest.status), uint8(ProofRequestStatus.Refused));
    }

    /// @dev Cannot acknowledge someone else's proof request.
    function testCannotAcknowledgeProofRequestThatIsAssignedToSomeoneElse() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(lagrange);
        vm.expectRevert("only proving network assignee");
        proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, 1), true);
    }

    /// @dev Cannot acknowledge a proof request that doesn't exist.
    function testCannotAcknowledgeUnexistingProofRequest() public {
        vm.prank(fermah);
        vm.expectRevert("only proving network assignee");
        proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, 1), true);
    }

    /// @dev Cannot acknowledge a proof request that is in any state but Ready.
    function testCannotAcknowledgeProofRequestThatIsNotReady() public {
        submitDefaultProofRequest(1, 1);
        for (uint256 i = 1; i < 9; i++) {
            proofManager.forceSetProofRequestStatus(
                ProofRequestIdentifier(1, 1), ProofRequestStatus(i)
            );
            vm.prank(fermah);
            vm.expectRevert("cannot acknowledge proof request that is not ready");
            proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, 1), true);
        }
    }

    /// @dev Cannot acknowledge a proof request that is past the acknowledgement deadline.
    function testCannotAcknowledgeTimedOutProofRequest() public {
        submitDefaultProofRequest(1, 1);
        vm.warp(block.timestamp + 2 minutes + 1);
        vm.prank(fermah);
        vm.expectRevert("proof request passed acknowledgement deadline");
        proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, 1), true);
    }

    /*///////////////////////////
            Submit Proof
    ///////////////////////////*/

    /// @dev Happy path for submitting a proof.
    function testSubmitProof() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, 1), true);

        vm.expectEmit(true, true, false, true);
        emit ProofStatusChanged(1, 1, ProofRequestStatus.Proven);
        vm.prank(fermah);
        proofManager.submitProof(ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6);

        ProofManagerStorage.ProofRequest memory proofRequest = proofManager.proofRequest(1, 1);
        assertEq(uint8(proofRequest.status), uint8(ProofRequestStatus.Proven));
        assertEq(proofRequest.proof, bytes("such proof much wow"));
        assertEq(proofRequest.provingNetworkPrice, 3e6);
    }

    /// @dev Proof price is always min(sequencer price, proving network price)
    function testSubmitProofPriceCannotBeHigherThanMaxReward() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, 1), true);

        vm.expectEmit(true, true, false, true);
        emit ProofStatusChanged(1, 1, ProofRequestStatus.Proven);
        vm.prank(fermah);
        proofManager.submitProof(ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 5e6);

        ProofManagerStorage.ProofRequest memory proofRequest = proofManager.proofRequest(1, 1);
        assertEq(uint8(proofRequest.status), uint8(ProofRequestStatus.Proven));
        assertEq(proofRequest.proof, bytes("such proof much wow"));
        assertEq(proofRequest.provingNetworkPrice, 4e6);
    }

    /// @dev Cannot submit proof for a request that is assigned to someone else.
    function testCannotSubmitProofForProofRequestThatIsAssignedToSomeoneElse() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(lagrange);
        vm.expectRevert("only proving network assignee");
        proofManager.submitProof(ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6);
    }

    /// @dev Cannot submit proof for a request that doesn't exist.
    function testCannontSubmitProofForUnexistentProofRequest() public {
        vm.prank(fermah);
        vm.expectRevert("only proving network assignee");
        proofManager.submitProof(ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6);
    }

    /// @dev Cannot submit proof for a request that is not in the Committed state.
    function testCannotSubmitProofForUncommitedProofRequest() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);
        vm.expectRevert("cannot submit proof for non committed proof request");
        proofManager.submitProof(ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6);
    }

    /// @dev Cannot submit proof for a request that is past the proving deadline.
    function testCannotSubmitProofForTimedOutProofRequest() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, 1), true);
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(fermah);
        vm.expectRevert("proof request passed proving deadline");
        proofManager.submitProof(ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6);
    }

    /*////////////////////////
            Withdraw
    ////////////////////////*/

    /// @dev Happy path for withdrawing payment, very typical expected usage.
    ///     NOTE: Can be treated as an "end to end" test.
    function testWithdrawWithinLimit() public {
        vm.prank(owner);
        proofManager.submitProofRequest(
            ProofRequestIdentifier(1, 1),
            ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, 100e6)
        );
        vm.prank(owner);
        proofManager.submitProofRequest(
            ProofRequestIdentifier(1, 2),
            ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, 250e6)
        );
        vm.prank(owner);
        proofManager.forceSetProofRequestAssignee(
            ProofRequestIdentifier(1, 2), ProvingNetwork.Fermah
        );

        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, 1), true);
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, 2), true);

        vm.prank(fermah);
        proofManager.submitProof(ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 50e6);

        vm.prank(fermah);
        proofManager.submitProof(ProofRequestIdentifier(1, 2), bytes("such proof much wow"), 75e6);

        vm.prank(owner);
        proofManager.updateProofRequestStatus(
            ProofRequestIdentifier(1, 1), ProofRequestStatus.Validated
        );
        vm.prank(owner);
        proofManager.updateProofRequestStatus(
            ProofRequestIdentifier(1, 2), ProofRequestStatus.Validated
        );

        assertEq(usdc.balanceOf(fermah), 0);

        ProofManagerStorage.ProvingNetworkInfo memory info =
            proofManager.provingNetworkInfo(ProvingNetwork.Fermah);
        assertEq(info.unclaimedProofs.length, 2);
        assertEq(info.paymentDue, 125e6);

        vm.expectEmit(true, true, false, true);
        emit PaymentWithdrawn(ProvingNetwork.Fermah, 125e6);

        vm.prank(fermah);
        proofManager.withdraw();

        assertEq(usdc.balanceOf(fermah), 125e6);

        info = proofManager.provingNetworkInfo(ProvingNetwork.Fermah);
        assertEq(info.unclaimedProofs.length, 0);
        assertEq(info.paymentDue, 0);
    }

    /// @dev Checks what happens when the price is exactly limit at withdrawal. 1 extra proof remaining.
    ///     NOTE: Can be treated as an "end to end" test.
    function testWithdrawAndExactlyLimitCanBeWithdrawn() public {
        vm.prank(owner);
        proofManager.updatePreferredProvingNetwork(ProvingNetwork.Fermah);
        uint256 pricePerProof = 6_250e6;
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(owner);
            proofManager.submitProofRequest(
                ProofRequestIdentifier(1, i),
                ProofRequestParams(
                    "https://console.google.com/buckets/...", 0, 27, 0, 3600, pricePerProof
                )
            );
            proofManager.forceSetProofRequestAssignee(
                ProofRequestIdentifier(1, i), ProvingNetwork.Fermah
            );

            vm.prank(fermah);
            proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, i), true);
            vm.prank(fermah);
            proofManager.submitProof(
                ProofRequestIdentifier(1, i), bytes("such proof much wow"), pricePerProof
            );
            vm.prank(owner);
            proofManager.updateProofRequestStatus(
                ProofRequestIdentifier(1, i), ProofRequestStatus.Validated
            );
        }

        assertEq(usdc.balanceOf(fermah), 0);

        ProofManagerStorage.ProvingNetworkInfo memory info =
            proofManager.provingNetworkInfo(ProvingNetwork.Fermah);
        assertEq(info.unclaimedProofs.length, 5);
        assertEq(info.paymentDue, pricePerProof * 5);

        vm.expectEmit(true, true, false, true);
        emit PaymentWithdrawn(ProvingNetwork.Fermah, pricePerProof * 4);

        vm.prank(fermah);
        proofManager.withdraw();

        assertEq(usdc.balanceOf(fermah), pricePerProof * 4);

        info = proofManager.provingNetworkInfo(ProvingNetwork.Fermah);

        assertEq(info.unclaimedProofs.length, 1);
        assertEq(info.paymentDue, pricePerProof);

        vm.expectEmit(true, true, false, true);
        emit PaymentWithdrawn(ProvingNetwork.Fermah, pricePerProof);

        vm.prank(fermah);
        proofManager.withdraw();

        assertEq(usdc.balanceOf(fermah), pricePerProof * 5);

        info = proofManager.provingNetworkInfo(ProvingNetwork.Fermah);
        assertEq(info.unclaimedProofs.length, 0);
        assertEq(info.paymentDue, 0);
    }

    /// @dev Ensures that if the next proof is more expensive than limit, it breaks. 2 extra proofs remaining.
    function testWithdrawAndNeedsBreakDueToWithdrawLimit() public {
        vm.prank(owner);
        proofManager.updatePreferredProvingNetwork(ProvingNetwork.Fermah);
        uint256 pricePerProof = 7_000e6;
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(owner);
            proofManager.submitProofRequest(
                ProofRequestIdentifier(1, i),
                ProofRequestParams(
                    "https://console.google.com/buckets/...", 0, 27, 0, 3600, pricePerProof
                )
            );
            proofManager.forceSetProofRequestAssignee(
                ProofRequestIdentifier(1, i), ProvingNetwork.Fermah
            );

            vm.prank(fermah);
            proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, i), true);
            vm.prank(fermah);
            proofManager.submitProof(
                ProofRequestIdentifier(1, i), bytes("such proof much wow"), pricePerProof
            );
            vm.prank(owner);
            proofManager.updateProofRequestStatus(
                ProofRequestIdentifier(1, i), ProofRequestStatus.Validated
            );
        }

        assertEq(usdc.balanceOf(fermah), 0);

        ProofManagerStorage.ProvingNetworkInfo memory info =
            proofManager.provingNetworkInfo(ProvingNetwork.Fermah);
        assertEq(info.unclaimedProofs.length, 5);
        assertEq(info.paymentDue, pricePerProof * 5);

        vm.expectEmit(true, true, false, true);
        emit PaymentWithdrawn(ProvingNetwork.Fermah, pricePerProof * 3);

        vm.prank(fermah);
        proofManager.withdraw();

        assertEq(usdc.balanceOf(fermah), pricePerProof * 3);

        info = proofManager.provingNetworkInfo(ProvingNetwork.Fermah);

        assertEq(info.unclaimedProofs.length, 2);
        assertEq(info.paymentDue, pricePerProof * 2);

        vm.expectEmit(true, true, false, true);
        emit PaymentWithdrawn(ProvingNetwork.Fermah, pricePerProof * 2);

        vm.prank(fermah);
        proofManager.withdraw();

        assertEq(usdc.balanceOf(fermah), pricePerProof * 5);

        info = proofManager.provingNetworkInfo(ProvingNetwork.Fermah);
        assertEq(info.unclaimedProofs.length, 0);
        assertEq(info.paymentDue, 0);
    }

    /// @dev Ensures only proving network can call withdraw.
    function testOnlyProvingNetworkCanWithdraw() public {
        vm.prank(owner);
        proofManager.submitProofRequest(
            ProofRequestIdentifier(1, 1),
            ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6)
        );
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, 1), true);
        vm.prank(fermah);
        proofManager.submitProof(ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6);
        vm.prank(owner);
        proofManager.updateProofRequestStatus(
            ProofRequestIdentifier(1, 1), ProofRequestStatus.Validated
        );
        vm.expectRevert("only proving network");
        proofManager.withdraw();
    }

    /// @dev Reverts if there's nothing to pay.
    function testWithdrawRevertsWhenNothingToPay() public {
        vm.prank(fermah);
        vm.expectRevert("no payment due");
        proofManager.withdraw();
    }
}
