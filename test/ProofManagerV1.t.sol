// // SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "../src/store/ProofManagerStorage.sol";
import "../src/ProofManagerV1.sol";
import "../src/interfaces/IProofManager.sol";
import "./ProofManagerHarness.sol";

/// @dev Test contract for the ProofManagerV1 contract.
contract ProofManagerV1Test is Test {
    /// @dev Helper DTO for testing proof assignment logic.
    struct SubmitProofExpected {
        IProofManager.ProvingNetwork network;
        IProofManager.ProofRequestStatus status;
    }

    /// @dev ProofManager, but with a few functions that override invariants.
    ProofManagerV1Harness proofManager;
    MockUsdc usdc = new MockUsdc();

    address owner = makeAddr("owner");
    address fermah = makeAddr("fermah");
    address lagrange = makeAddr("lagrange");
    address nonOwner = makeAddr("nonOwner");
    address otherProvingNetwork = makeAddr("otherProvingNetwork");

    function setUp() public virtual {
        proofManager = new ProofManagerV1Harness();
        proofManager.initialize(fermah, lagrange, address(usdc), owner);
        usdc.mint(address(proofManager), 1_000e6);
    }

    /*//////////////////////////////////////////
                1. Initialization
    //////////////////////////////////////////*/

    /// @dev Happy path for initialization.
    function testInit() public view {
        assertEq(proofManager.owner(), owner, "invalid owner");

        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Fermah,
            IProofManager.ProvingNetworkInfo(fermah, IProofManager.ProvingNetworkStatus.Active, 0)
        );
        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Lagrange,
            IProofManager.ProvingNetworkInfo(lagrange, IProofManager.ProvingNetworkStatus.Active, 0)
        );

        assertEq(
            uint8(proofManager.preferredProvingNetwork()),
            uint8(IProofManager.ProvingNetwork.None),
            "preferred network should be None"
        );
    }

    /// @dev Happy path for initialization, checking events.
    function testInitEmitsEvents() public {
        vm.expectEmit(true, true, false, false);
        emit IProofManager.ProvingNetworkAddressUpdated(IProofManager.ProvingNetwork.Fermah, fermah);
        vm.expectEmit(true, true, false, false);
        emit IProofManager.ProvingNetworkStatusUpdated(
            IProofManager.ProvingNetwork.Fermah, IProofManager.ProvingNetworkStatus.Active
        );
        vm.expectEmit(true, true, false, false);
        emit IProofManager.ProvingNetworkAddressUpdated(
            IProofManager.ProvingNetwork.Lagrange, lagrange
        );
        vm.expectEmit(true, true, false, false);
        emit IProofManager.ProvingNetworkStatusUpdated(
            IProofManager.ProvingNetwork.Lagrange, IProofManager.ProvingNetworkStatus.Active
        );

        vm.expectEmit(true, false, false, false);
        emit IProofManager.PreferredProvingNetworkUpdated(IProofManager.ProvingNetwork.None);
        ProofManagerV1 _proofManager = new ProofManagerV1();
        _proofManager.initialize(fermah, lagrange, address(this), owner);
    }

    /// @dev Do not allow zero address for owner.
    function testInitFailsWithZeroOwnerAddress() public {
        ProofManagerV1 _proofManager = new ProofManagerV1();
        vm.expectRevert(abi.encodeWithSelector(IProofManager.AddressCannotBeZero.selector, "owner"));

        _proofManager.initialize(fermah, lagrange, address(this), address(0));
    }

    /// @dev Do not allow zero address for proving networks.
    function testInitFailsWithZeroProvingNetworkAddress() public {
        ProofManagerV1 _proofManager = new ProofManagerV1();
        vm.expectRevert(
            abi.encodeWithSelector(IProofManager.AddressCannotBeZero.selector, "fermah")
        );
        _proofManager.initialize(address(0), lagrange, address(this), owner);

        _proofManager = new ProofManagerV1();
        vm.expectRevert(
            abi.encodeWithSelector(IProofManager.AddressCannotBeZero.selector, "lagrange")
        );
        _proofManager.initialize(fermah, address(0), address(this), owner);
    }

    /// @dev Do not allow zero address for USDC contract.
    function testInitFailsWithZeroUSDCAddress() public {
        ProofManagerV1 _proofManager = new ProofManagerV1();
        vm.expectRevert(abi.encodeWithSelector(IProofManager.AddressCannotBeZero.selector, "usdc"));

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
        emit IProofManager.ProvingNetworkAddressUpdated(
            IProofManager.ProvingNetwork.Fermah, otherProvingNetwork
        );
        vm.prank(owner);
        proofManager.updateProvingNetworkAddress(
            IProofManager.ProvingNetwork.Fermah, otherProvingNetwork
        );
        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Fermah,
            IProofManager.ProvingNetworkInfo(
                otherProvingNetwork, IProofManager.ProvingNetworkStatus.Active, 0
            )
        );
    }

    /// @dev Only owner can update proving network address.
    function testNonOwnerCannotUpdateProvingNetworkAddress() public {
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.updateProvingNetworkAddress(
            IProofManager.ProvingNetwork.Fermah, otherProvingNetwork
        );
    }

    /// @dev Proving Network None is not a real network. As such, you can't add an address to it.
    function testCannotUpdateProvingNetworkAddressForNone() public {
        vm.expectRevert(IProofManager.ProvingNetworkCannotBeNone.selector);
        vm.prank(owner);
        proofManager.updateProvingNetworkAddress(
            IProofManager.ProvingNetwork.None, otherProvingNetwork
        );
    }

    /// @dev You can't set a proving network address to zero. This is a safety check.
    function testCannotUpdateProvingNetworkAddressToZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(IProofManager.AddressCannotBeZero.selector, "proving network")
        );
        vm.prank(owner);
        proofManager.updateProvingNetworkAddress(IProofManager.ProvingNetwork.Fermah, address(0));
    }

    /*//////////////////////////////////////////
        2.II. Update Proving Network Status
    //////////////////////////////////////////*/

    /// @dev Happy path for updating a proving network's status.
    function testUpdateProvingNetworkStatus() public {
        vm.expectEmit(true, true, false, true);
        emit IProofManager.ProvingNetworkStatusUpdated(
            IProofManager.ProvingNetwork.Fermah, IProofManager.ProvingNetworkStatus.Inactive
        );
        vm.prank(owner);
        proofManager.updateProvingNetworkStatus(
            IProofManager.ProvingNetwork.Fermah, IProofManager.ProvingNetworkStatus.Inactive
        );
        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Fermah,
            IProofManager.ProvingNetworkInfo(fermah, IProofManager.ProvingNetworkStatus.Inactive, 0)
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
        proofManager.updateProvingNetworkStatus(
            IProofManager.ProvingNetwork.None, IProofManager.ProvingNetworkStatus.Inactive
        );
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
        emit IProofManager.PreferredProvingNetworkUpdated(IProofManager.ProvingNetwork.Fermah);
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
            IProofManager.ProofRequestParams(
                "https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6
            )
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
                IProofManager.ProofRequestStatus.PendingAcknowledgement,
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
            IProofManager.ProofRequestParams(
                "https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6
            )
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
        vm.expectRevert(
            abi.encodeWithSelector(IProofManager.InvalidProofRequestTimeout.selector, 0)
        );
        vm.prank(owner);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams(
                "https://console.google.com/buckets/...", 0, 27, 0, 0, 4e6
            )
        );
    }

    /// @dev Happy path for proof assignment logic.
    function testSubmitProofAssignmentLogic() public {
        SubmitProofExpected[8] memory outputs = [
            // request 0, fermah inactive, lagrange active, preferred none
            SubmitProofExpected(
                IProofManager.ProvingNetwork.Fermah, IProofManager.ProofRequestStatus.Refused
            ),
            // request 1, fermah inactive, lagrange active, preferred none
            SubmitProofExpected(
                IProofManager.ProvingNetwork.Lagrange,
                IProofManager.ProofRequestStatus.PendingAcknowledgement
            ),
            // request 2, fermah inactive, lagrange active, preferred none
            SubmitProofExpected(
                IProofManager.ProvingNetwork.None, IProofManager.ProofRequestStatus.Refused
            ),
            // request 3, fermah inactive, lagrange active, preferred fermah
            SubmitProofExpected(
                IProofManager.ProvingNetwork.Fermah, IProofManager.ProofRequestStatus.Refused
            ),
            // request 4, fermah active, lagrange active, preferred fermah
            SubmitProofExpected(
                IProofManager.ProvingNetwork.Fermah,
                IProofManager.ProofRequestStatus.PendingAcknowledgement
            ),
            // request 5, fermah active, lagrange active, preferred fermah
            SubmitProofExpected(
                IProofManager.ProvingNetwork.Lagrange,
                IProofManager.ProofRequestStatus.PendingAcknowledgement
            ),
            // request 6, fermah active, lagrange active, preferred fermah
            SubmitProofExpected(
                IProofManager.ProvingNetwork.Fermah,
                IProofManager.ProofRequestStatus.PendingAcknowledgement
            ),
            // request 7, fermah active, lagrange active, preferred lagrange
            SubmitProofExpected(
                IProofManager.ProvingNetwork.Lagrange,
                IProofManager.ProofRequestStatus.PendingAcknowledgement
            )
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
        proofManager.updateProvingNetworkStatus(
            IProofManager.ProvingNetwork.Fermah, IProofManager.ProvingNetworkStatus.Active
        );

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
        3.II Submit Proof Validation Result
    //////////////////////////////////////////*/

    /// @dev Happy path for submitting proof validation result.
    function testSubmitProofValidationResult() public {
        submitDefaultProofRequest(1, 1);

        proofManager.forceSetProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.Proven
        );

        vm.expectEmit(true, true, false, true);
        emit IProofManager.ProofValidationResult(1, 1, true, IProofManager.ProvingNetwork.Fermah);
        vm.prank(owner);
        proofManager.submitProofValidationResult(IProofManager.ProofRequestIdentifier(1, 1), true);
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

    /// @dev Only owner can submit proof validation result.
    function testNonOwnerCannotSubmitProofValidationResult() public {
        submitDefaultProofRequest(1, 1);
        proofManager.forceSetProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.Proven
        );
        vm.prank(nonOwner);
        expectOwnableRevert(nonOwner);
        proofManager.submitProofValidationResult(IProofManager.ProofRequestIdentifier(1, 1), true);
    }

    /// @dev Proof Manager cannot submit proof validation result for non proven proof request.
    function testIllegalTransitionReverts() public {
        submitDefaultProofRequest(1, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IProofManager.ProofRequestIsNotProven.selector,
                IProofManager.ProofRequestStatus.PendingAcknowledgement
            )
        );
        vm.prank(owner);
        proofManager.submitProofValidationResult(IProofManager.ProofRequestIdentifier(1, 1), true);
    }

    /// @dev Submitting proof validation result marks requests due for reward.
    function testUpdateProofRequestStatusAsValidatedForPayment() public {
        for (uint256 i = 0; i < 8; ++i) {
            uint256 reward = (i + 1) * 1e6;
            vm.prank(owner);
            proofManager.submitProofRequest(
                IProofManager.ProofRequestIdentifier(1, i),
                IProofManager.ProofRequestParams(
                    "https://console.google.com/buckets/...", 0, 27, 0, 3600, reward
                )
            );
            // pretend it's been committed
            proofManager.forceSetProofRequestStatus(
                IProofManager.ProofRequestIdentifier(1, i),
                IProofManager.ProofRequestStatus.Committed
            );

            if (i % 4 < 2) {
                if (i % 4 == 0) {
                    vm.prank(fermah);
                } else {
                    vm.prank(lagrange);
                }
                // this can't be pretended, as we need to set the price
                proofManager.submitProof(
                    IProofManager.ProofRequestIdentifier(1, i), bytes("such proof much wow"), reward
                );

                // mark it as validated
                vm.prank(owner);
                proofManager.submitProofValidationResult(
                    IProofManager.ProofRequestIdentifier(1, i), true
                );
            }
        }

        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Fermah,
            IProofManager.ProvingNetworkInfo(fermah, IProofManager.ProvingNetworkStatus.Active, 6e6)
        );
        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Lagrange,
            IProofManager.ProvingNetworkInfo(
                lagrange, IProofManager.ProvingNetworkStatus.Active, 8e6
            )
        );
    }

    /// @dev Submitting proof validation result as invalid will not mark request as due for reward.
    function testSubmitProofValidationResultAsInvalidNoPayment() public {
        submitDefaultProofRequest(1, 1);

        proofManager.forceSetProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.Proven
        );

        vm.expectEmit(true, true, false, true);
        emit IProofManager.ProofValidationResult(1, 1, false, IProofManager.ProvingNetwork.Fermah);
        vm.prank(owner);
        proofManager.submitProofValidationResult(IProofManager.ProofRequestIdentifier(1, 1), false);
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
                IProofManager.ProofRequestStatus.ValidationFailed,
                IProofManager.ProvingNetwork.Fermah,
                0,
                bytes("")
            )
        );
        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Fermah,
            IProofManager.ProvingNetworkInfo(fermah, IProofManager.ProvingNetworkStatus.Active, 0)
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
        emit IProofManager.ProofRequestAcknowledged(1, 1, true, IProofManager.ProvingNetwork.Fermah);
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);

        IProofManager.ProofRequest memory proofRequest =
            proofManager.proofRequest(IProofManager.ProofRequestIdentifier(1, 1));
        assertEq(uint8(proofRequest.status), uint8(IProofManager.ProofRequestStatus.Committed));
    }

    /// @dev Happy path for refusing a proof request.
    function testAcknowledgeProofRequestRefused() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);

        vm.expectEmit(true, true, false, true);
        emit IProofManager.ProofRequestAcknowledged(
            1, 1, false, IProofManager.ProvingNetwork.Fermah
        );
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), false);

        IProofManager.ProofRequest memory proofRequest =
            proofManager.proofRequest(IProofManager.ProofRequestIdentifier(1, 1));
        assertEq(uint8(proofRequest.status), uint8(IProofManager.ProofRequestStatus.Refused));
    }

    /// @dev Cannot acknowledge someone else's proof request.
    function testCannotAcknowledgeProofRequestThatIsAssignedToSomeoneElse() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(lagrange);
        vm.expectRevert(
            abi.encodeWithSelector(
                IProofManager.OnlyProvingNetworkAssigneedAllowed.selector, lagrange
            )
        );
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);
    }

    /// @dev Cannot acknowledge a proof request that doesn't exist.
    function testCannotAcknowledgeUnexistingProofRequest() public {
        vm.prank(fermah);
        vm.expectRevert(
            abi.encodeWithSelector(
                IProofManager.OnlyProvingNetworkAssigneedAllowed.selector, fermah
            )
        );
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);
    }

    /// @dev Cannot acknowledge a proof request that is in any state but PendingAcknowledgement.
    function testCannotAcknowledgeProofRequestThatIsNotPendingAcknowledgement() public {
        submitDefaultProofRequest(1, 1);
        for (uint256 i = 1; i < 8; i++) {
            proofManager.forceSetProofRequestStatus(
                IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus(i)
            );
            vm.prank(fermah);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IProofManager.ProofRequestIsNotPendingAcknowledgement.selector,
                    IProofManager.ProofRequestStatus(i)
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
            abi.encodeWithSelector(
                IProofManager.ProofRequestAcknowledgementDeadlinePassed.selector, 1, 1
            )
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
        emit IProofManager.ProofRequestProven(
            1, 1, bytes("such proof much wow"), IProofManager.ProvingNetwork.Fermah
        );
        vm.prank(fermah);
        proofManager.submitProof(
            IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6
        );

        IProofManager.ProofRequest memory proofRequest =
            proofManager.proofRequest(IProofManager.ProofRequestIdentifier(1, 1));
        assertEq(uint8(proofRequest.status), uint8(IProofManager.ProofRequestStatus.Proven));
        assertEq(proofRequest.proof, bytes("such proof much wow"));
        assertEq(proofRequest.requestedReward, 3e6);
    }

    /// @dev Proof price is always min(sequencer price, proving network price)
    function testSubmitProofPriceCannotBeHigherThanMaxReward() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);

        vm.expectEmit(true, true, false, true);
        emit IProofManager.ProofRequestProven(
            1, 1, bytes("such proof much wow"), IProofManager.ProvingNetwork.Fermah
        );
        vm.prank(fermah);
        proofManager.submitProof(
            IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 5e6
        );

        IProofManager.ProofRequest memory proofRequest =
            proofManager.proofRequest(IProofManager.ProofRequestIdentifier(1, 1));
        assertEq(uint8(proofRequest.status), uint8(IProofManager.ProofRequestStatus.Proven));
        assertEq(proofRequest.proof, bytes("such proof much wow"));
        assertEq(proofRequest.requestedReward, 4e6);
    }

    /// @dev Cannot submit proof for a request that is assigned to someone else.
    function testCannotSubmitProofForProofRequestThatIsAssignedToSomeoneElse() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(lagrange);
        vm.expectRevert(
            abi.encodeWithSelector(
                IProofManager.OnlyProvingNetworkAssigneedAllowed.selector, lagrange
            )
        );
        proofManager.submitProof(
            IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6
        );
    }

    /// @dev Cannot submit proof for a request that doesn't exist.
    function testCannontSubmitProofForUnexistentProofRequest() public {
        vm.prank(fermah);
        vm.expectRevert(
            abi.encodeWithSelector(
                IProofManager.OnlyProvingNetworkAssigneedAllowed.selector, fermah
            )
        );
        proofManager.submitProof(
            IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6
        );
    }

    /// @dev Cannot submit proof for a request that is not in the Committed state.
    function testCannotSubmitProofForUncommitedProofRequest() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);
        vm.expectRevert(
            abi.encodeWithSelector(
                IProofManager.ProofRequestIsNotCommitted.selector,
                IProofManager.ProofRequestStatus.PendingAcknowledgement
            )
        );
        proofManager.submitProof(
            IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6
        );
    }

    /// @dev Cannot submit proof for a request that is past the proving deadline.
    function testCannotSubmitProofForTimedOutProofRequest() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(fermah);
        vm.expectRevert(
            abi.encodeWithSelector(IProofManager.ProofRequestProvingDeadlinePassed.selector, 1, 1)
        );
        proofManager.submitProof(
            IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6
        );
    }

    /*//////////////////////////////////////////
                4.III. Claim Reward
    //////////////////////////////////////////*/

    /// @dev Happy path for claim reward, typical expected usage.
    ///     NOTE: Can be treated as an "end to end" test.
    function testClaimReward() public {
        vm.prank(owner);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams(
                "https://console.google.com/buckets/...", 0, 27, 0, 3600, 100e6
            )
        );
        vm.prank(owner);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 2),
            IProofManager.ProofRequestParams(
                "https://console.google.com/buckets/...", 0, 27, 0, 3600, 250e6
            )
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
        proofManager.submitProof(
            IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 50e6
        );

        vm.prank(fermah);
        proofManager.submitProof(
            IProofManager.ProofRequestIdentifier(1, 2), bytes("such proof much wow"), 75e6
        );

        vm.prank(owner);
        proofManager.submitProofValidationResult(IProofManager.ProofRequestIdentifier(1, 1), true);
        vm.prank(owner);
        proofManager.submitProofValidationResult(IProofManager.ProofRequestIdentifier(1, 2), true);

        assertEq(usdc.balanceOf(fermah), 0);

        IProofManager.ProvingNetworkInfo memory info =
            proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Fermah);
        assertEq(info.owedReward, 125e6);

        vm.expectEmit(true, true, false, true);
        emit IProofManager.RewardClaimed(IProofManager.ProvingNetwork.Fermah, 125e6);

        vm.prank(fermah);
        proofManager.claimReward();

        assertEq(usdc.balanceOf(fermah), 125e6);

        info = proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Fermah);
        assertEq(info.owedReward, 0);
    }

    /// @dev Ensures only proving network can call claim reward.
    function testOnlyProvingNetworkCanClaimReward() public {
        vm.prank(owner);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams(
                "https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6
            )
        );
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);
        vm.prank(fermah);
        proofManager.submitProof(
            IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6
        );
        vm.prank(owner);
        proofManager.submitProofValidationResult(IProofManager.ProofRequestIdentifier(1, 1), true);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IProofManager.OnlyProvingNetworkAllowed.selector, owner)
        );
        proofManager.claimReward();
    }

    /// @dev Reverts if there's nothing to pay.
    function testClaimRewardRevertsWhenNothingToPay() public {
        vm.prank(fermah);
        vm.expectRevert(abi.encodeWithSelector(IProofManager.NoPaymentDue.selector));
        proofManager.claimReward();
    }

    /// @dev Reverts if there are not enough funds.
    function testClaimRewardRevertsIfNotEnoughFunds() public {
        vm.prank(owner);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams(
                "https://console.google.com/buckets/...", 0, 27, 0, 3600, 1_005e6
            )
        );
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);
        vm.prank(fermah);
        proofManager.submitProof(
            IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 1_001e6
        );
        vm.prank(owner);
        proofManager.submitProofValidationResult(IProofManager.ProofRequestIdentifier(1, 1), true);

        vm.expectRevert(
            abi.encodeWithSelector(IProofManager.NotEnoughUsdcFunds.selector, 1_000e6, 1_001e6)
        );
        vm.prank(fermah);
        proofManager.claimReward();
    }

    function testClaimRewardRevertsIfUSDCTransferFails() public {
        ProofManagerV1 _proofManager = new ProofManagerV1();
        BrokenUsdc brokenUsdc = new BrokenUsdc();

        _proofManager.initialize(fermah, lagrange, address(brokenUsdc), owner);
        brokenUsdc.mint(address(_proofManager), 1_000e6);

        vm.prank(owner);
        _proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams(
                "https://console.google.com/buckets/...", 0, 27, 0, 3600, 3e6
            )
        );
        vm.prank(fermah);
        _proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);
        vm.prank(fermah);
        _proofManager.submitProof(
            IProofManager.ProofRequestIdentifier(1, 1), bytes("such proof much wow"), 3e6
        );
        vm.prank(owner);
        _proofManager.submitProofValidationResult(IProofManager.ProofRequestIdentifier(1, 1), true);

        vm.expectRevert(abi.encodeWithSelector(IProofManager.UsdcTransferFailed.selector));
        vm.prank(fermah);
        _proofManager.claimReward();
    }

    /*//////////////////////////////////////////
                    5. Getters
    //////////////////////////////////////////*/

    /// @dev Test proofRequest getter sets the right status after timeouts.
    function testProofRequestStatusIsSetOnTimeouts() public {
        vm.prank(owner);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams(
                "https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6
            )
        );
        vm.warp(block.timestamp + 2 minutes + 1);
        IProofManager.ProofRequest memory proofRequest =
            proofManager.proofRequest(IProofManager.ProofRequestIdentifier(1, 1));
        assertEq(uint8(proofRequest.status), uint8(IProofManager.ProofRequestStatus.Unacknowledged));
        proofManager.forceSetProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.Committed
        );
        vm.warp(block.timestamp + 58 minutes);
        proofRequest = proofManager.proofRequest(IProofManager.ProofRequestIdentifier(1, 1));
        assertEq(uint8(proofRequest.status), uint8(IProofManager.ProofRequestStatus.TimedOut));
    }

    /*//////////////////////////////////////////
                    Assertions
    //////////////////////////////////////////*/

    /// @dev Asserts that proving network info in storage matches expected one.
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
            info.owedReward,
            expectedInfo.owedReward,
            "Proving network owedReward should be set correctly"
        );
    }

    /// @dev Asserts that proof request in storage matches expected one.
    function assertProofRequest(
        IProofManager.ProofRequestIdentifier memory id,
        IProofManager.ProofRequest memory expectedProofRequest
    ) private view {
        IProofManager.ProofRequest memory proofRequest = proofManager.proofRequest(id);
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
            proofRequest.requestedReward,
            expectedProofRequest.requestedReward,
            "Proving network requested reward should be set correctly"
        );
        assertEq(proofRequest.proof, expectedProofRequest.proof, "Proof should be set correctly");
    }

    /*//////////////////////////////////////////
                    Helpers
    //////////////////////////////////////////*/

    /// @dev Submits a default proof request to the proof manager.
    function submitDefaultProofRequest(uint256 chainId, uint256 blockNumber) private {
        IProofManager.ProofRequestIdentifier memory id =
            IProofManager.ProofRequestIdentifier({ chainId: chainId, blockNumber: blockNumber });
        vm.prank(owner);
        proofManager.submitProofRequest(
            id,
            IProofManager.ProofRequestParams(
                "https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6
            )
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
