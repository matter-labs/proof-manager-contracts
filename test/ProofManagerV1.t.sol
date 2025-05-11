// // SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import "../src/store/ProofManagerStorage.sol";
import "../src/ProofManagerV1.sol";
import "../src/interfaces/IProofManager.sol";
import { ProofManagerHarness, MockUSDC } from "./harness/ProofManagerHarness.sol";

/// @dev Test contract for the ProofManagerV1 contract.
contract ProofManagerV1Test is Test {
    /// @dev Helper DTO for testing proof assignment logic.
    struct SubmitProofExpected {
        IProofManager.ProvingNetwork network;
        IProofManager.ProofRequestStatus status;
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
            IProofManager.ProvingNetwork.Fermah,
            IProofManager.ProvingNetworkInfo(
                fermah,
                IProofManager.ProvingNetworkStatus.Active,
                new IProofManager.ProofRequestIdentifier[](0),
                0
            )
        );
        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Lagrange,
            IProofManager.ProvingNetworkInfo(
                lagrange,
                IProofManager.ProvingNetworkStatus.Active,
                new IProofManager.ProofRequestIdentifier[](0),
                0
            )
        );

        assertEq(
            uint8(proofManager.preferredProvingNetwork()),
            uint8(IProofManager.ProvingNetwork.None),
            "preferred network should be None"
        );
    }

    /// @dev Happy path for constructor, checking events.
    function testInitEmitsEvents() public {
        vm.expectEmit(true, true, false, false);
        emit IProofManager.ProvingNetworkAddressChanged(IProofManager.ProvingNetwork.Fermah, fermah);
        vm.expectEmit(true, true, false, false);
        emit IProofManager.ProvingNetworkStatusChanged(
            IProofManager.ProvingNetwork.Fermah, IProofManager.ProvingNetworkStatus.Active
        );
        vm.expectEmit(true, true, false, false);
        emit IProofManager.ProvingNetworkAddressChanged(
            IProofManager.ProvingNetwork.Lagrange, lagrange
        );
        vm.expectEmit(true, true, false, false);
        emit IProofManager.ProvingNetworkStatusChanged(
            IProofManager.ProvingNetwork.Lagrange, IProofManager.ProvingNetworkStatus.Active
        );

        vm.expectEmit(true, false, false, false);
        emit IProofManager.PreferredProvingNetworkSet(IProofManager.ProvingNetwork.None);
        ProofManagerV1 _proofManager = new ProofManagerV1();
        _proofManager.initialize(fermah, lagrange, address(this), owner);
    }

    /// @dev Do not allow zero address for proving networks.
    function testInitFailsWithZeroProvingNetworkAddress() public {
        ProofManagerV1 _proofManager = new ProofManagerV1();
        vm.expectRevert(abi.encodeWithSelector(IProofManager.AddressCannotBeZero.selector, "fermah"));
        _proofManager.initialize(address(0), lagrange, address(this), owner);

        _proofManager = new ProofManagerV1();
        vm.expectRevert(abi.encodeWithSelector(IProofManager.AddressCannotBeZero.selector, "lagrange"));
        _proofManager.initialize(fermah, address(0), address(this), owner);
    }

    /// @dev Do not allow zero address for USDC contract.
    function testInitFailsWithZeroUSDCAddress() public {
        ProofManagerV1 _proofManager = new ProofManagerV1();
        vm.expectRevert(abi.encodeWithSelector(IProofManager.AddressCannotBeZero.selector, "usdc"));

        _proofManager.initialize(fermah, lagrange, address(0), owner);
    }

    /// @dev Do not allow zero address for owner.
    function testInitFailsWithZeroOwnerAddress() public {
        ProofManagerV1 _proofManager = new ProofManagerV1();
        vm.expectRevert(abi.encodeWithSelector(IProofManager.AddressCannotBeZero.selector, "owner"));

        _proofManager.initialize(fermah, lagrange, address(this), address(0));
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
        emit IProofManager.ProvingNetworkAddressChanged(
            IProofManager.ProvingNetwork.Fermah, otherProvingNetwork
        );
        vm.prank(owner);
        proofManager.updateProvingNetworkAddress(
            IProofManager.ProvingNetwork.Fermah, otherProvingNetwork
        );
        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Fermah,
            IProofManager.ProvingNetworkInfo(
                otherProvingNetwork,
                IProofManager.ProvingNetworkStatus.Active,
                new IProofManager.ProofRequestIdentifier[](0),
                0
            )
        );
    }

    /// @dev Only owner can update proving network address.
    function testNonOwnerCannotUpdateProvingNetworkAddress() public {
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.updateProvingNetworkAddress(IProofManager.ProvingNetwork.Fermah, otherProvingNetwork);
    }

    /// @dev Proving Network None is not a real network. As such, you can't add an address to it.
    function testCannotUpdateProvingNetworkAddressForNone() public {
        vm.expectRevert(IProofManager.ProvingNetworkCannotBeNone.selector);
        vm.prank(owner);
        proofManager.updateProvingNetworkAddress(IProofManager.ProvingNetwork.None, otherProvingNetwork);
    }

    /// @dev You can't set a proving network address to zero. This is a safety check.
    function testCannotUpdateProvingNetworkAddressToZero() public {
        vm.expectRevert(abi.encodeWithSelector(IProofManager.AddressCannotBeZero.selector, "proving network"));
        vm.prank(owner);
        proofManager.updateProvingNetworkAddress(IProofManager.ProvingNetwork.Fermah, address(0));
    }

    /*//////////////////////////////////////////
        2.II. Update Proving Network Status
    //////////////////////////////////////////*/

    /// @dev Happy path for updating a proving network's status.
    function testUpdateProvingNetworkStatus() public {
        vm.expectEmit(true, true, false, true);
        emit IProofManager.ProvingNetworkStatusChanged(
            IProofManager.ProvingNetwork.Fermah, IProofManager.ProvingNetworkStatus.Inactive
        );
        vm.prank(owner);
        proofManager.updateProvingNetworkStatus(
            IProofManager.ProvingNetwork.Fermah, IProofManager.ProvingNetworkStatus.Inactive
        );
        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Fermah,
            IProofManager.ProvingNetworkInfo(
                fermah,
                IProofManager.ProvingNetworkStatus.Inactive,
                new IProofManager.ProofRequestIdentifier[](0),
                0
            )
        );
    }

    /// @dev Only owner can update a proving network's status.
    function testNonOwnerCannotUpdateProvingNetworkStatus() public {
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.updateProvingNetworkStatus(
            IProofManager.ProvingNetwork.Fermah, IProofManager.ProvingNetworkStatus.Inactive
        );
    }

    /// @dev Proving Network None is not a real network. As such, you can't update its status.
    function testCannotUpdateProvingNetworkStatusForNone() public {
        vm.expectRevert(IProofManager.ProvingNetworkCannotBeNone.selector);
        vm.prank(owner);
        proofManager.updateProvingNetworkStatus(IProofManager.ProvingNetwork.None, IProofManager.ProvingNetworkStatus.Inactive);
    }

    /*//////////////////////////////////////////
        2.III. Update Preferred Proving Network
    //////////////////////////////////////////*/

    /// @dev Happy path for updating the preferred proving network.
    function testUpdatePreferredProvingNetwork() public {
        assertEq(
            uint8(proofManager.preferredProvingNetwork()),
            uint8(IProofManager.ProvingNetwork.None),
            "preferred network should be None"
        );

        vm.expectEmit(true, true, false, true);
        emit IProofManager.PreferredProvingNetworkSet(IProofManager.ProvingNetwork.Fermah);
        vm.prank(owner);
        proofManager.updatePreferredProvingNetwork(IProofManager.ProvingNetwork.Fermah);
        assertEq(
            uint8(proofManager.preferredProvingNetwork()),
            uint8(IProofManager.ProvingNetwork.Fermah),
            "preferred network should be Fermah"
        );
    }

    /// @dev Only owner can update the preferred proving network.
    function testNonOwnerCannotUpdatePreferredProvingNetwork() public {
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.updatePreferredProvingNetwork(IProofManager.ProvingNetwork.Fermah);
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
        emit IProofManager.ProofRequestSubmitted(
            1,
            1,
            IProofManager.ProvingNetwork.Fermah,
            "https://console.google.com/buckets/...",
            0,
            27,
            0,
            3600,
            4e6
        );

        vm.prank(owner);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6)
        );
        assertProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequest(
                "https://console.google.com/buckets/...",
                0,
                27,
                0,
                block.timestamp,
                3600,
                4e6,
                IProofManager.ProofRequestStatus.Ready,
                IProofManager.ProvingNetwork.Fermah,
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
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6)
        );
    }

    /// @dev A proof request for a specific chain/batch can be submitted only once.
    function testCannotSubmitDuplicateProof() public {
        submitDefaultProofRequest(1, 1);
        vm.expectRevert(abi.encodeWithSelector(IProofManager.DuplicatedProofRequest.selector, 1, 1));
        submitDefaultProofRequest(1, 1);
    }

    /// @dev No proof can be generated in 0 seconds.
    function testCannotSubmitProofWithZeroTimeout() public {
        vm.expectRevert(abi.encodeWithSelector(IProofManager.InvalidProofRequestTimeout.selector, 0));
        vm.prank(owner);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 0, 4e6)
        );
    }

    /// @dev If the request is higher than withdrawal limit, then withdraw is blocked.
    function testCannotSubmitProofWithMaxRewardHigherThanWithdrawalLimit() public {
        vm.expectRevert(abi.encodeWithSelector(IProofManager.RewardBiggerThanLimit.selector, 25_000e6 + 1));
        vm.prank(owner);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams(
                "https://console.google.com/buckets/...", 0, 27, 0, 3600, 25_000e6 + 1
            )
        );
    }

    /// @dev Happy path for proof assignment logic.
    function testSubmitProofAssignmentLogic() public {
        SubmitProofExpected[8] memory outputs = [
            // request 0, fermah inactive, lagrange active, preferred none
            SubmitProofExpected(IProofManager.ProvingNetwork.Fermah, IProofManager.ProofRequestStatus.Refused),
            // request 1, fermah inactive, lagrange active, preferred none
            SubmitProofExpected(IProofManager.ProvingNetwork.Lagrange, IProofManager.ProofRequestStatus.Ready),
            // request 2, fermah inactive, lagrange active, preferred none
            SubmitProofExpected(IProofManager.ProvingNetwork.None, IProofManager.ProofRequestStatus.Refused),
            // request 3, fermah inactive, lagrange active, preferred fermah
            SubmitProofExpected(IProofManager.ProvingNetwork.Fermah, IProofManager.ProofRequestStatus.Refused),
            // request 4, fermah active, lagrange active, preferred fermah
            SubmitProofExpected(IProofManager.ProvingNetwork.Fermah, IProofManager.ProofRequestStatus.Ready),
            // request 5, fermah active, lagrange active, preferred fermah
            SubmitProofExpected(IProofManager.ProvingNetwork.Lagrange, IProofManager.ProofRequestStatus.Ready),
            // request 6, fermah active, lagrange active, preferred fermah
            SubmitProofExpected(IProofManager.ProvingNetwork.Fermah, IProofManager.ProofRequestStatus.Ready),
            // request 7, fermah active, lagrange active, preferred lagrange
            SubmitProofExpected(IProofManager.ProvingNetwork.Lagrange, IProofManager.ProofRequestStatus.Ready)
        ];

        vm.prank(owner);
        proofManager.updateProvingNetworkStatus(
            IProofManager.ProvingNetwork.Fermah, IProofManager.ProvingNetworkStatus.Inactive
        );

        for (uint256 i = 0; i < 3; ++i) {
            submitDefaultProofRequest(1, i);
        }

        vm.prank(owner);
        proofManager.updatePreferredProvingNetwork(IProofManager.ProvingNetwork.Fermah);

        submitDefaultProofRequest(1, 3);

        vm.prank(owner);
        proofManager.updateProvingNetworkStatus(IProofManager.ProvingNetwork.Fermah, IProofManager.ProvingNetworkStatus.Active);

        for (uint256 i = 4; i < 7; ++i) {
            submitDefaultProofRequest(1, i);
        }

        vm.prank(owner);
        proofManager.updatePreferredProvingNetwork(IProofManager.ProvingNetwork.Lagrange);

        submitDefaultProofRequest(1, 7);

        for (uint256 i = 0; i < 8; ++i) {
            assertProofRequest(
                IProofManager.ProofRequestIdentifier(1, i),
                IProofManager.ProofRequest(
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
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.Proven
        );

        vm.expectEmit(true, true, false, true);
        emit IProofManager.ProofStatusChanged(1, 1, IProofManager.ProofRequestStatus.Validated);
        vm.prank(owner);
        proofManager.updateProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.Validated
        );
        assertProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequest(
                "https://console.google.com/buckets/...",
                0,
                27,
                0,
                block.timestamp,
                3600,
                4e6,
                IProofManager.ProofRequestStatus.Validated,
                IProofManager.ProvingNetwork.Fermah,
                0,
                bytes("")
            )
        );
    }

    /// @dev Only owner can update proof request status.
    function testNonOwnerCannotUpdateProofRequestStatus() public {
        submitDefaultProofRequest(1, 1);
        proofManager.forceSetProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.Proven
        );
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.updateProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.Validated
        );
    }

    /// @dev Proof Manager respects it's transition access control.
    function testIllegalTransitionReverts() public {
        submitDefaultProofRequest(1, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IProofManager.TransitionNotAllowedForProofRequestManager.selector,
                IProofManager.ProofRequestStatus.Ready,
                IProofManager.ProofRequestStatus.Committed
            )
        );
        vm.prank(owner);
        proofManager.updateProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.Committed
        );
    }

    /// @dev Moving proofs to validated makes them due for payment.
    function testUpdateProofRequestStatusAsValidatedForPayment() public {
        for (uint256 i = 0; i < 8; ++i) {
            uint256 price = (i + 1) * 1e6;
            // submit request
            vm.prank(owner);
            proofManager.submitProofRequest(
                IProofManager.ProofRequestIdentifier(1, i),
                IProofManager.ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, price)
            );
            // pretend it's been committed
            proofManager.forceSetProofRequestStatus(
                IProofManager.ProofRequestIdentifier(1, i), IProofManager.ProofRequestStatus.Committed
            );

            if (i % 4 < 2) {
                if (i % 4 == 0) {
                    vm.prank(fermah);
                } else {
                    vm.prank(lagrange);
                }
                // this can't be pretended, as we need to set the price
                proofManager.submitProof(
                    IProofManager.ProofRequestIdentifier(1, i), bytes("such proof much wow"), price
                );

                // mark it as validated
                vm.prank(owner);
                proofManager.updateProofRequestStatus(
                    IProofManager.ProofRequestIdentifier(1, i), IProofManager.ProofRequestStatus.Validated
                );
            }
        }

        IProofManager.ProofRequestIdentifier[] memory identifiers =
            new IProofManager.ProofRequestIdentifier[](2);
        identifiers[0] = IProofManager.ProofRequestIdentifier(1, 0);
        identifiers[1] = IProofManager.ProofRequestIdentifier(1, 4);
        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Fermah,
            IProofManager.ProvingNetworkInfo(
                fermah, IProofManager.ProvingNetworkStatus.Active, identifiers, 6e6
            )
        );
        identifiers = new IProofManager.ProofRequestIdentifier[](2);
        identifiers[0] = IProofManager.ProofRequestIdentifier(1, 1);
        identifiers[1] = IProofManager.ProofRequestIdentifier(1, 5);
        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Lagrange,
            IProofManager.ProvingNetworkInfo(
                lagrange, IProofManager.ProvingNetworkStatus.Active, identifiers, 8e6
            )
        );
    }

    /// @dev Update proof request status to unacked/timedout does not work before deadline, but does after.
    function testUpdateProofRequestStatusToUnackedOrTimedout() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IProofManager.ProofRequestDidNotReachDeadline.selector));
        vm.warp(block.timestamp + 2 minutes);
        proofManager.updateProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.Unacknowledged
        );

        vm.prank(owner);
        vm.warp(block.timestamp + 1 minutes);
        proofManager.updateProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.Unacknowledged
        );

        proofManager.forceSetProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.Committed
        );

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IProofManager.ProofRequestDidNotReachDeadline.selector));
        // first timeblock is at T0. Then 2 minutes pass, then 1 more minute; default proof request has 1h deadline, (1h - 3m = 57m max)
        vm.warp(block.timestamp + 57 minutes);
        proofManager.updateProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.TimedOut
        );

        vm.prank(owner);
        vm.warp(block.timestamp + 1 minutes);
        proofManager.updateProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.TimedOut
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
        emit IProofManager.ProofStatusChanged(1, 1, IProofManager.ProofRequestStatus.Committed);
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);

        IProofManager.ProofRequest memory proofRequest = proofManager.proofRequest(1, 1);
        assertEq(uint8(proofRequest.status), uint8(IProofManager.ProofRequestStatus.Committed));
    }

    /// @dev Happy path for refusing a proof request.
    function testAcknowledgeProofRequestRefused() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);

        vm.expectEmit(true, true, false, true);
        emit IProofManager.ProofStatusChanged(1, 1, IProofManager.ProofRequestStatus.Refused);
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), false);

        IProofManager.ProofRequest memory proofRequest = proofManager.proofRequest(1, 1);
        assertEq(uint8(proofRequest.status), uint8(IProofManager.ProofRequestStatus.Refused));
    }

    /// @dev Cannot acknowledge someone else's proof request.
    function testCannotAcknowledgeProofRequestThatIsAssignedToSomeoneElse() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(lagrange);
        vm.expectRevert(
            abi.encodeWithSelector(IProofManager.OnlyProvingNetworkAssigneedAllowed.selector, lagrange)
        );
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);
    }

    /// @dev Cannot acknowledge a proof request that doesn't exist.
    function testCannotAcknowledgeUnexistingProofRequest() public {
        vm.prank(fermah);
        vm.expectRevert(abi.encodeWithSelector(IProofManager.OnlyProvingNetworkAssigneedAllowed.selector, fermah));
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);
    }

    /// @dev Cannot acknowledge a proof request that is in any state but Ready.
    function testCannotAcknowledgeProofRequestThatIsNotReady() public {
        submitDefaultProofRequest(1, 1);
        for (uint256 i = 1; i < 9; i++) {
            proofManager.forceSetProofRequestStatus(
                IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus(i)
            );
            vm.prank(fermah);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IProofManager.TransitionNotAllowedForProvingNetwork.selector,
                    IProofManager.ProofRequestStatus(i),
                    IProofManager.ProofRequestStatus.Committed
                )
            );
            proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);
        }
    }

    /// @dev Cannot acknowledge a proof request that is past the acknowledgement deadline.
    function testCannotAcknowledgeTimedOutProofRequest() public {
        submitDefaultProofRequest(1, 1);
        vm.warp(block.timestamp + 2 minutes + 1);
        vm.prank(fermah);
        vm.expectRevert(
            abi.encodeWithSelector(IProofManager.ProofRequestAcknowledgementDeadlinePassed.selector, 1, 1)
        );
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);
    }

    /*//////////////////////////////////////////
                4.II. Submit Proof
    //////////////////////////////////////////*/

    /// @dev Happy path for submitting a proof.
    function testSubmitProof() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);

        vm.expectEmit(true, true, false, true);
        emit IProofManager.ProofStatusChanged(1, 1, IProofManager.ProofRequestStatus.Proven);
        vm.prank(fermah);
        proofManager.submitProof(IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6);

        IProofManager.ProofRequest memory proofRequest = proofManager.proofRequest(1, 1);
        assertEq(uint8(proofRequest.status), uint8(IProofManager.ProofRequestStatus.Proven));
        assertEq(proofRequest.proof, bytes("such proof much wow"));
        assertEq(proofRequest.provingNetworkPrice, 3e6);
    }

    /// @dev Proof price is always min(sequencer price, proving network price)
    function testSubmitProofPriceCannotBeHigherThanMaxReward() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);

        vm.expectEmit(true, true, false, true);
        emit IProofManager.ProofStatusChanged(1, 1, IProofManager.ProofRequestStatus.Proven);
        vm.prank(fermah);
        proofManager.submitProof(
            IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 5e6
        );

        IProofManager.ProofRequest memory proofRequest = proofManager.proofRequest(1, 1);
        assertEq(uint8(proofRequest.status), uint8(IProofManager.ProofRequestStatus.Proven));
        assertEq(proofRequest.proof, bytes("such proof much wow"));
        assertEq(proofRequest.provingNetworkPrice, 4e6);
    }

    /// @dev Cannot submit proof for a request that is assigned to someone else.
    function testCannotSubmitProofForProofRequestThatIsAssignedToSomeoneElse() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(lagrange);
        vm.expectRevert(
            abi.encodeWithSelector(IProofManager.OnlyProvingNetworkAssigneedAllowed.selector, lagrange)
        );
        proofManager.submitProof(IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6);
    }

    /// @dev Cannot submit proof for a request that doesn't exist.
    function testCannontSubmitProofForUnexistentProofRequest() public {
        vm.prank(fermah);
        vm.expectRevert(abi.encodeWithSelector(IProofManager.OnlyProvingNetworkAssigneedAllowed.selector, fermah));
        proofManager.submitProof(IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6);
    }

    /// @dev Cannot submit proof for a request that is not in the Committed state.
    function testCannotSubmitProofForUncommitedProofRequest() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);
        vm.expectRevert(
            abi.encodeWithSelector(
                IProofManager.TransitionNotAllowedForProvingNetwork.selector,
                IProofManager.ProofRequestStatus.Ready,
                IProofManager.ProofRequestStatus.Proven
            )
        );
        proofManager.submitProof(IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6);
    }

    /// @dev Cannot submit proof for a request that is past the proving deadline.
    function testCannotSubmitProofForTimedOutProofRequest() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(fermah);
        vm.expectRevert(abi.encodeWithSelector(IProofManager.ProofRequestProvingDeadlinePassed.selector, 1, 1));
        proofManager.submitProof(IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6);
    }

    /*//////////////////////////////////////////
                4.III. Withdraw
    //////////////////////////////////////////*/

    /// @dev Happy path for withdrawing payment, very typical expected usage.
    ///     NOTE: Can be treated as an "end to end" test.
    function testWithdrawWithinLimit() public {
        vm.prank(owner);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, 100e6)
        );
        vm.prank(owner);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 2),
            IProofManager.ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, 250e6)
        );
        vm.prank(owner);
        proofManager.forceSetProofRequestAssignee(
            IProofManager.ProofRequestIdentifier(1, 2), IProofManager.ProvingNetwork.Fermah
        );

        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 2), true);

        vm.prank(fermah);
        proofManager.submitProof(IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 50e6);

        vm.prank(fermah);
        proofManager.submitProof(IProofManager.ProofRequestIdentifier(1, 2), bytes("such proof much wow"), 75e6);

        vm.prank(owner);
        proofManager.updateProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.Validated
        );
        vm.prank(owner);
        proofManager.updateProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 2), IProofManager.ProofRequestStatus.Validated
        );

        assertEq(usdc.balanceOf(fermah), 0);

        IProofManager.ProvingNetworkInfo memory info = proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Fermah);
        assertEq(info.unclaimedProofs.length, 2);
        assertEq(info.paymentDue, 125e6);

        for (uint256 i = 2; i > 0; i--) {
            vm.expectEmit(true, true, false, true);
            emit IProofManager.ProofStatusChanged(1, i, IProofManager.ProofRequestStatus.Paid);
        }
        vm.expectEmit(true, true, false, true);
        emit IProofManager.PaymentWithdrawn(IProofManager.ProvingNetwork.Fermah, 125e6);

        vm.prank(fermah);
        proofManager.withdraw();

        assertEq(usdc.balanceOf(fermah), 125e6);

        info = proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Fermah);
        assertEq(info.unclaimedProofs.length, 0);
        assertEq(info.paymentDue, 0);
    }

    /// @dev Checks what happens when the price is exactly limit at withdrawal. 1 extra proof remaining.
    ///     NOTE: Can be treated as an "end to end" test.
    function testWithdrawAndExactlyLimitCanBeWithdrawn() public {
        vm.prank(owner);
        proofManager.updatePreferredProvingNetwork(IProofManager.ProvingNetwork.Fermah);
        uint256 pricePerProof = 6_250e6;
        for (uint256 i = 1; i <= 5; i++) {
            vm.prank(owner);
            proofManager.submitProofRequest(
                IProofManager.ProofRequestIdentifier(1, i),
                IProofManager.ProofRequestParams(
                    "https://console.google.com/buckets/...", 0, 27, 0, 3600, pricePerProof
                )
            );
            proofManager.forceSetProofRequestAssignee(
                IProofManager.ProofRequestIdentifier(1, i), IProofManager.ProvingNetwork.Fermah
            );

            vm.prank(fermah);
            proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, i), true);
            vm.prank(fermah);
            proofManager.submitProof(
                IProofManager.ProofRequestIdentifier(1, i), bytes("such proof much wow"), pricePerProof
            );
            vm.prank(owner);
            proofManager.updateProofRequestStatus(
                IProofManager.ProofRequestIdentifier(1, i), IProofManager.ProofRequestStatus.Validated
            );
        }

        assertEq(usdc.balanceOf(fermah), 0);

        IProofManager.ProvingNetworkInfo memory info = proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Fermah);
        assertEq(info.unclaimedProofs.length, 5);
        assertEq(info.paymentDue, pricePerProof * 5);

        for (uint256 i = 5; i >= 2; i--) {
            vm.expectEmit(true, true, false, true);
            emit IProofManager.ProofStatusChanged(1, i, IProofManager.ProofRequestStatus.Paid);
        }
        vm.expectEmit(true, true, false, true);
        emit IProofManager.PaymentWithdrawn(IProofManager.ProvingNetwork.Fermah, pricePerProof * 4);

        vm.prank(fermah);
        proofManager.withdraw();

        assertEq(usdc.balanceOf(fermah), pricePerProof * 4);

        info = proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Fermah);

        assertEq(info.unclaimedProofs.length, 1);
        assertEq(info.paymentDue, pricePerProof);

        vm.expectEmit(true, true, false, true);
        emit IProofManager.ProofStatusChanged(1, 1, IProofManager.ProofRequestStatus.Paid);
        vm.expectEmit(true, true, false, true);
        emit IProofManager.PaymentWithdrawn(IProofManager.ProvingNetwork.Fermah, pricePerProof);

        vm.prank(fermah);
        proofManager.withdraw();

        assertEq(usdc.balanceOf(fermah), pricePerProof * 5);

        info = proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Fermah);
        assertEq(info.unclaimedProofs.length, 0);
        assertEq(info.paymentDue, 0);
    }

    /// @dev Ensures that if the next proof is more expensive than limit, it breaks. 2 extra proofs remaining.
    function testWithdrawAndNeedsBreakDueToWithdrawLimit() public {
        vm.prank(owner);
        proofManager.updatePreferredProvingNetwork(IProofManager.ProvingNetwork.Fermah);
        uint256 pricePerProof = 7_000e6;
        for (uint256 i = 1; i <= 5; i++) {
            vm.prank(owner);
            proofManager.submitProofRequest(
                IProofManager.ProofRequestIdentifier(1, i),
                IProofManager.ProofRequestParams(
                    "https://console.google.com/buckets/...", 0, 27, 0, 3600, pricePerProof
                )
            );
            proofManager.forceSetProofRequestAssignee(
                IProofManager.ProofRequestIdentifier(1, i), IProofManager.ProvingNetwork.Fermah
            );

            vm.prank(fermah);
            proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, i), true);
            vm.prank(fermah);
            proofManager.submitProof(
                IProofManager.ProofRequestIdentifier(1, i), bytes("such proof much wow"), pricePerProof
            );
            vm.prank(owner);
            proofManager.updateProofRequestStatus(
                IProofManager.ProofRequestIdentifier(1, i), IProofManager.ProofRequestStatus.Validated
            );
        }

        assertEq(usdc.balanceOf(fermah), 0);

        IProofManager.ProvingNetworkInfo memory info = proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Fermah);
        assertEq(info.unclaimedProofs.length, 5);
        assertEq(info.paymentDue, pricePerProof * 5);

        for (uint256 i = 5; i >= 3; i--) {
            vm.expectEmit(true, true, false, true);
            emit IProofManager.ProofStatusChanged(1, i, IProofManager.ProofRequestStatus.Paid);
        }
        vm.expectEmit(true, true, false, true);
        emit IProofManager.PaymentWithdrawn(IProofManager.ProvingNetwork.Fermah, pricePerProof * 3);

        vm.prank(fermah);
        proofManager.withdraw();

        assertEq(usdc.balanceOf(fermah), pricePerProof * 3);

        info = proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Fermah);

        assertEq(info.unclaimedProofs.length, 2);
        assertEq(info.paymentDue, pricePerProof * 2);

        for (uint256 i = 2; i >= 1; i--) {
            vm.expectEmit(true, true, false, true);
            emit IProofManager.ProofStatusChanged(1, i, IProofManager.ProofRequestStatus.Paid);
        }
        vm.expectEmit(true, true, false, true);
        emit IProofManager.PaymentWithdrawn(IProofManager.ProvingNetwork.Fermah, pricePerProof * 2);

        vm.prank(fermah);
        proofManager.withdraw();

        assertEq(usdc.balanceOf(fermah), pricePerProof * 5);

        info = proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Fermah);
        assertEq(info.unclaimedProofs.length, 0);
        assertEq(info.paymentDue, 0);
    }

    /// @dev Ensures only proving network can call withdraw.
    function testOnlyProvingNetworkCanWithdraw() public {
        vm.prank(owner);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6)
        );
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);
        vm.prank(fermah);
        proofManager.submitProof(IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6);
        vm.prank(owner);
        proofManager.updateProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.Validated
        );
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IProofManager.OnlyProvingNetworkAllowed.selector, owner));
        proofManager.withdraw();
    }

    /// @dev Reverts if there's nothing to pay.
    function testWithdrawRevertsWhenNothingToPay() public {
        vm.prank(fermah);
        vm.expectRevert(abi.encodeWithSelector(IProofManager.NoPaymentDue.selector));
        proofManager.withdraw();
    }

    /*////////////////////////
            Assertions
    ////////////////////////*/

    /// @dev Asserts that set proving network info matches expected one.
    function assertProvingNetworkInfo(
        IProofManager.ProvingNetwork network,
        IProofManager.ProvingNetworkInfo memory expectedInfo
    ) private view {
        IProofManager.ProvingNetworkInfo memory info = proofManager.provingNetworkInfo(network);

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
        IProofManager.ProofRequestIdentifier memory id,
        IProofManager.ProofRequest memory expectedProofRequest
    ) private view {
        IProofManager.ProofRequest memory proofRequest =
            proofManager.proofRequest(id.chainId, id.blockNumber);
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
        IProofManager.ProofRequestIdentifier memory id =
            IProofManager.ProofRequestIdentifier({ chainId: chainId, blockNumber: blockNumber });
        vm.prank(owner);
        proofManager.submitProofRequest(
            id, IProofManager.ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6)
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
