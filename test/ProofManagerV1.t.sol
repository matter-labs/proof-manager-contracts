// // SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { ProvingNetworkInfo, ProofRequest } from "../src/store/ProofManagerStorage.sol";
import { ProofManagerV1 } from "../src/ProofManagerV1.sol";
import {
    PreferredProvingNetworkSet,
    ProvingNetworkStatusChanged,
    ProvingNetworkAddressChanged,
    ProofRequestSubmitted,
    ProofStatusChanged,
    PaymentWithdrawn,
    ProvingNetwork,
    ProofRequestIdentifier,
    ProofRequestParams,
    ProofRequestStatus,
    ProvingNetworkStatus
} from "../src/interfaces/IProofManager.sol";
import { ProofManagerHarness, MockUSDC } from "./harness/ProofManagerHarness.sol";

/// @dev Test contract for the ProofManagerV1 contract.
contract ProofManagerV1Test is Test {
    /// @dev Helper DTO for testing proof assignment logic.
    struct SubmitProofExpected {
        ProvingNetwork network;
        ProofRequestStatus status;
    }

    /// @dev ProofManager, but with a few functions that override invariants.
    ProofManagerHarness proofManager;
    MockUSDC usdc = new MockUSDC();

    address owner = makeAddr("owner");
    address fermah = makeAddr("fermah");
    address lagrange = makeAddr("lagrange");
    address nonOwner = makeAddr("nonOwner");
    address otherProvingNetwork = makeAddr("otherProvingNetwork");

    function setUp() public virtual {
        proofManager = new ProofManagerHarness();
        proofManager.initialize(fermah, lagrange, address(usdc), owner);
        usdc.mint(address(proofManager), 1_000_000e6);
    }

    /*//////////////////////////////////////////
                1. Initialization
    //////////////////////////////////////////*/

    /// @dev Happy path for constructor.
    function testInit() public view {
        assertEq(proofManager.owner(), owner, "owner must be contract deployer");

        assertProvingNetworkInfo(
            ProvingNetwork.Fermah,
            ProvingNetworkInfo(
                fermah, ProvingNetworkStatus.Active, new ProofRequestIdentifier[](0), 0
            )
        );
        assertProvingNetworkInfo(
            ProvingNetwork.Lagrange,
            ProvingNetworkInfo(
                lagrange, ProvingNetworkStatus.Active, new ProofRequestIdentifier[](0), 0
            )
        );

        assertEq(
            uint8(proofManager.preferredNetwork()),
            uint8(ProvingNetwork.None),
            "preferred network should be None"
        );
    }

    /// @dev Happy path for constructor, checking events.
    function testInitEmitsEvents() public {
        vm.expectEmit(true, true, false, false);
        emit ProvingNetworkAddressChanged(ProvingNetwork.Fermah, fermah);
        vm.expectEmit(true, true, false, false);
        emit ProvingNetworkStatusChanged(ProvingNetwork.Fermah, ProvingNetworkStatus.Active);
        vm.expectEmit(true, true, false, false);
        emit ProvingNetworkAddressChanged(ProvingNetwork.Lagrange, lagrange);
        vm.expectEmit(true, true, false, false);
        emit ProvingNetworkStatusChanged(ProvingNetwork.Lagrange, ProvingNetworkStatus.Active);

        vm.expectEmit(true, false, false, false);
        emit PreferredProvingNetworkSet(ProvingNetwork.None);
        ProofManagerV1 _proofManager = new ProofManagerV1();
        _proofManager.initialize(fermah, lagrange, address(this), owner);
    }

    /// @dev Do not allow zero address for proving networks.
    function testInitFailsWithZeroProvingNetworkAddress() public {
        ProofManagerV1 _proofManager = new ProofManagerV1();
        vm.expectRevert("proving network address cannot be zero");
        _proofManager.initialize(address(0), lagrange, address(this), owner);

        _proofManager = new ProofManagerV1();
        vm.expectRevert("proving network address cannot be zero");
        _proofManager.initialize(fermah, address(0), address(this), owner);
    }

    /// @dev Do not allow zero address for USDC contract.
    function testInitFailsWithZeroUSDCAddress() public {
        ProofManagerV1 _proofManager = new ProofManagerV1();
        vm.expectRevert("usdc contract address cannot be zero");

        _proofManager.initialize(fermah, lagrange, address(0), owner);
    }

    /*//////////////////////////////////////////
        2. Proving Network Management
    //////////////////////////////////////////*/

    /*//////////////////////////////////////////
        2.I. Change Proving Network Address
    //////////////////////////////////////////*/

    /// @dev Happy path for updating a proving network address.
    function testUpdateProvingNetworkAddress() public {
        vm.expectEmit(true, true, false, true);
        emit ProvingNetworkAddressChanged(ProvingNetwork.Fermah, otherProvingNetwork);
        vm.prank(owner);
        proofManager.updateProvingNetworkAddress(ProvingNetwork.Fermah, otherProvingNetwork);
        assertProvingNetworkInfo(
            ProvingNetwork.Fermah,
            ProvingNetworkInfo(
                otherProvingNetwork, ProvingNetworkStatus.Active, new ProofRequestIdentifier[](0), 0
            )
        );
    }

    /// @dev Only owner can update proving network address.
    function testNonOwnerCannotUpdateProvingNetworkAddress() public {
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.updateProvingNetworkAddress(ProvingNetwork.Fermah, otherProvingNetwork);
    }

    /// @dev Proving Network None is not a real network. As such, you can't add an address to it.
    function testCannotUpdateProvingNetworkAddressForNone() public {
        vm.expectRevert("proving network cannot be None");
        vm.prank(owner);
        proofManager.updateProvingNetworkAddress(ProvingNetwork.None, otherProvingNetwork);
    }

    /// @dev You can't set a proving network address to zero. This is a safety check.
    function testCannotUpdateProvingNetworkAddressToZero() public {
        vm.expectRevert("cannot unset proving network address");
        vm.prank(owner);
        proofManager.updateProvingNetworkAddress(ProvingNetwork.Fermah, address(0));
    }

    /*//////////////////////////////////////////
        2.II. Update Proving Network Status
    //////////////////////////////////////////*/

    /// @dev Happy path for updating a proving network's status.
    function testUpdateProvingNetworkStatus() public {
        vm.expectEmit(true, true, false, true);
        emit ProvingNetworkStatusChanged(ProvingNetwork.Fermah, ProvingNetworkStatus.Inactive);
        vm.prank(owner);
        proofManager.updateProvingNetworkStatus(
            ProvingNetwork.Fermah, ProvingNetworkStatus.Inactive
        );
        assertProvingNetworkInfo(
            ProvingNetwork.Fermah,
            ProvingNetworkInfo(
                fermah, ProvingNetworkStatus.Inactive, new ProofRequestIdentifier[](0), 0
            )
        );
    }

    /// @dev Only owner can update a proving network's status.
    function testNonOwnerCannotUpdateProvingNetworkStatus() public {
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.updateProvingNetworkStatus(
            ProvingNetwork.Fermah, ProvingNetworkStatus.Inactive
        );
    }

    /// @dev Proving Network None is not a real network. As such, you can't update its status.
    function testCannotUpdateProvingNetworkStatusForNone() public {
        vm.expectRevert("proving network cannot be None");
        vm.prank(owner);
        proofManager.updateProvingNetworkStatus(ProvingNetwork.None, ProvingNetworkStatus.Inactive);
    }

    /*//////////////////////////////////////////
        2.III. Update Preferred Proving Network
    //////////////////////////////////////////*/

    /// @dev Happy path for updating the preferred proving network.
    function testUpdatePreferredProvingNetwork() public {
        assertEq(
            uint8(proofManager.preferredNetwork()),
            uint8(ProvingNetwork.None),
            "preferred network should be None"
        );

        vm.expectEmit(true, true, false, true);
        emit PreferredProvingNetworkSet(ProvingNetwork.Fermah);
        vm.prank(owner);
        proofManager.updatePreferredProvingNetwork(ProvingNetwork.Fermah);
        assertEq(
            uint8(proofManager.preferredNetwork()),
            uint8(ProvingNetwork.Fermah),
            "preferred network should be Fermah"
        );
    }

    /// @dev Only owner can update the preferred proving network.
    function testNonOwnerCannotUpdatePreferredProvingNetwork() public {
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.updatePreferredProvingNetwork(ProvingNetwork.Fermah);
    }

    /*//////////////////////////////////////////
            3. Proof Request Management
    //////////////////////////////////////////*/

    /*//////////////////////////////////////////
            3.I Submit Proof Request
    //////////////////////////////////////////*/

    /// @dev Happy path for submitting a proof request.
    function testSubmitProofRequest() public {
        vm.expectEmit(true, true, false, true);
        emit ProofRequestSubmitted(
            1,
            1,
            ProvingNetwork.Fermah,
            "https://console.google.com/buckets/...",
            0,
            27,
            0,
            3600,
            4e6
        );

        vm.prank(owner);
        proofManager.submitProofRequest(
            ProofRequestIdentifier(1, 1),
            ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6)
        );
        assertProofRequest(
            ProofRequestIdentifier(1, 1),
            ProofRequest(
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
        expectOwnableRevert(nonOwner);
        vm.prank(nonOwner);
        proofManager.submitProofRequest(
            ProofRequestIdentifier(1, 1),
            ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6)
        );
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
        vm.prank(owner);
        proofManager.submitProofRequest(
            ProofRequestIdentifier(1, 1),
            ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 0, 4e6)
        );
    }

    /// @dev If the request is higher than withdrawal limit, then withdraw is blocked.
    function testCannotSubmitProofWithMaxRewardHigherThanWithdrawalLimit() public {
        vm.expectRevert("max reward is higher than maximum withdraw limit");
        vm.prank(owner);
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

        vm.prank(owner);
        proofManager.updateProvingNetworkStatus(
            ProvingNetwork.Fermah, ProvingNetworkStatus.Inactive
        );

        for (uint256 i = 0; i < 3; ++i) {
            submitDefaultProofRequest(1, i);
        }

        vm.prank(owner);
        proofManager.updatePreferredProvingNetwork(ProvingNetwork.Fermah);

        submitDefaultProofRequest(1, 3);

        vm.prank(owner);
        proofManager.updateProvingNetworkStatus(ProvingNetwork.Fermah, ProvingNetworkStatus.Active);

        for (uint256 i = 4; i < 7; ++i) {
            submitDefaultProofRequest(1, i);
        }

        vm.prank(owner);
        proofManager.updatePreferredProvingNetwork(ProvingNetwork.Lagrange);

        submitDefaultProofRequest(1, 7);

        for (uint256 i = 0; i < 8; ++i) {
            assertProofRequest(
                ProofRequestIdentifier(1, i),
                ProofRequest(
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
        vm.stopPrank();
    }

    /*//////////////////////////////////////////
        3.II Update Proof Request Status
    //////////////////////////////////////////*/

    /// @dev Happy path for updating proof request status.
    function testUpdateProofRequestStatus() public {
        submitDefaultProofRequest(1, 1);

        proofManager.forceSetProofRequestStatus(
            ProofRequestIdentifier(1, 1), ProofRequestStatus.Proven
        );

        vm.expectEmit(true, true, false, true);
        emit ProofStatusChanged(1, 1, ProofRequestStatus.Validated);
        vm.prank(owner);
        proofManager.updateProofRequestStatus(
            ProofRequestIdentifier(1, 1), ProofRequestStatus.Validated
        );
        assertProofRequest(
            ProofRequestIdentifier(1, 1),
            ProofRequest(
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

    /// @dev Only owner can update proof request status.
    function testNonOwnerCannotUpdateProofRequestStatus() public {
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
        vm.prank(owner);
        proofManager.updateProofRequestStatus(
            ProofRequestIdentifier(1, 1), ProofRequestStatus.Committed
        );
    }

    /// @dev Moving proofs to validated makes them due for payment.
    function testUpdateProofRequestStatusAsValidatedForPayment() public {
        for (uint256 i = 0; i < 8; ++i) {
            uint256 price = (i + 1) * 1e6;
            // submit request
            vm.prank(owner);
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
                vm.prank(owner);
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
            ProvingNetworkInfo(fermah, ProvingNetworkStatus.Active, identifiers, 6e6)
        );
        identifiers = new ProofRequestIdentifier[](2);
        identifiers[0] = ProofRequestIdentifier(1, 1);
        identifiers[1] = ProofRequestIdentifier(1, 5);
        assertProvingNetworkInfo(
            ProvingNetwork.Lagrange,
            ProvingNetworkInfo(lagrange, ProvingNetworkStatus.Active, identifiers, 8e6)
        );
    }

    /*//////////////////////////////////////////
            4. Proving Network Interactions
    //////////////////////////////////////////*/

    /*//////////////////////////////////////////
            4.I. Acknowledge Proof Request
    //////////////////////////////////////////*/

    /// @dev Happy path for commiting to a proof request.
    function testAcknowledgeProofRequestCommitted() public {
        submitDefaultProofRequest(1, 1);

        vm.prank(fermah);

        vm.expectEmit(true, true, false, true);
        emit ProofStatusChanged(1, 1, ProofRequestStatus.Committed);
        proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, 1), true);

        ProofRequest memory proofRequest = proofManager.proofRequest(1, 1);
        assertEq(uint8(proofRequest.status), uint8(ProofRequestStatus.Committed));
    }

    /// @dev Happy path for refusing a proof request.
    function testAcknowledgeProofRequestRefused() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);

        vm.expectEmit(true, true, false, true);
        emit ProofStatusChanged(1, 1, ProofRequestStatus.Refused);
        proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, 1), false);

        ProofRequest memory proofRequest = proofManager.proofRequest(1, 1);
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

    /*//////////////////////////////////////////
                4.II. Submit Proof
    //////////////////////////////////////////*/

    /// @dev Happy path for submitting a proof.
    function testSubmitProof() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(ProofRequestIdentifier(1, 1), true);

        vm.expectEmit(true, true, false, true);
        emit ProofStatusChanged(1, 1, ProofRequestStatus.Proven);
        vm.prank(fermah);
        proofManager.submitProof(ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6);

        ProofRequest memory proofRequest = proofManager.proofRequest(1, 1);
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

        ProofRequest memory proofRequest = proofManager.proofRequest(1, 1);
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

    /*//////////////////////////////////////////
                4.III. Withdraw
    //////////////////////////////////////////*/

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

        ProvingNetworkInfo memory info = proofManager.provingNetworkInfo(ProvingNetwork.Fermah);
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

        ProvingNetworkInfo memory info = proofManager.provingNetworkInfo(ProvingNetwork.Fermah);
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

        ProvingNetworkInfo memory info = proofManager.provingNetworkInfo(ProvingNetwork.Fermah);
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

    /*////////////////////////
            Assertions
    ////////////////////////*/

    /// @dev Asserts that set proving network info matches expected one.
    function assertProvingNetworkInfo(
        ProvingNetwork network,
        ProvingNetworkInfo memory expectedInfo
    ) private view {
        ProvingNetworkInfo memory info = proofManager.provingNetworkInfo(network);

        assertEq(info.addr, expectedInfo.addr, "Proving network address should be set correctly");
        assertEq(
            uint8(info.status),
            uint8(expectedInfo.status),
            "Proving network status should be set correctly"
        );
        assertEq(
            abi.encode(info.unclaimedProofs),
            abi.encode(expectedInfo.unclaimedProofs),
            "Proving network should have the same unclaimed proofs"
        );
        assertEq(
            info.paymentDue,
            expectedInfo.paymentDue,
            "Proving network payment due should be set correctly"
        );
    }

    /// @dev Asserts that set proof request matches expected one.
    function assertProofRequest(
        ProofRequestIdentifier memory id,
        ProofRequest memory expectedProofRequest
    ) private view {
        ProofRequest memory proofRequest = proofManager.proofRequest(id.chainId, id.blockNumber);
        assertEq(
            proofRequest.proofInputsUrl,
            expectedProofRequest.proofInputsUrl,
            "Proof inputs URL should be set correctly"
        );
        assertEq(
            proofRequest.protocolMajor,
            expectedProofRequest.protocolMajor,
            "Protocol major version should be set correctly"
        );
        assertEq(
            proofRequest.protocolMinor,
            expectedProofRequest.protocolMinor,
            "Protocol minor version should be set correctly"
        );
        assertEq(
            proofRequest.protocolPatch,
            expectedProofRequest.protocolPatch,
            "Protocol patch version should be set correctly"
        );
        assertEq(
            proofRequest.submittedAt,
            expectedProofRequest.submittedAt,
            "Submitted at timestamp should be set correctly"
        );
        assertEq(
            proofRequest.timeoutAfter,
            expectedProofRequest.timeoutAfter,
            "Deadline should be set correctly"
        );
        assertEq(
            proofRequest.maxReward,
            expectedProofRequest.maxReward,
            "Max reward should be set correctly"
        );
        assertEq(
            uint8(proofRequest.status),
            uint8(expectedProofRequest.status),
            "Proof request status should be set correctly"
        );
        assertEq(
            uint8(proofRequest.assignedTo),
            uint8(expectedProofRequest.assignedTo),
            "Assigned proving network should be set correctly"
        );
        assertEq(
            proofRequest.provingNetworkPrice,
            expectedProofRequest.provingNetworkPrice,
            "Proving network price should be set correctly"
        );
        assertEq(proofRequest.proof, expectedProofRequest.proof, "Proof should be set correctly");
    }

    /*/////////////////////
            Helpers
    /////////////////////*/

    /// @dev Submits a default proof request to the proof manager.
    function submitDefaultProofRequest(uint256 chainId, uint256 blockNumber) private {
        ProofRequestIdentifier memory id =
            ProofRequestIdentifier({ chainId: chainId, blockNumber: blockNumber });
        vm.prank(owner);
        proofManager.submitProofRequest(
            id, ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6)
        );
    }

    /// @dev Expects default revert for ownable contract.
    function expectOwnableRevert(address expectedCaller) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")), expectedCaller
            )
        );
    }
}
