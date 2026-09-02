// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/store/ProofManagerStorage.sol";
import "../src/ProofManagerV1.sol";
import "../src/interfaces/IProofManager.sol";
import "./ProofManagerHarness.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    INativeTokenVault
} from "era-contracts/l1-contracts/contracts/bridge/ntv/INativeTokenVault.sol";
import {
    IL2AssetRouter
} from "era-contracts/l1-contracts/contracts/bridge/asset-router/IL2AssetRouter.sol";
import {
    DataEncoding
} from "era-contracts/l1-contracts/contracts/common/libraries/DataEncoding.sol";
import {
    L2_NATIVE_TOKEN_VAULT_ADDR,
    L2_ASSET_ROUTER_ADDR
} from "era-contracts/l1-contracts/contracts/common/L2ContractAddresses.sol";

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
    address submitter = makeAddr("submitter");
    address fermah = makeAddr("fermah");
    address lagrange = makeAddr("lagrange");
    address externalAddr = makeAddr("externalAddr");
    address otherProvingNetwork = makeAddr("otherProvingNetwork");

    bytes32 owner_role = 0x00;
    bytes32 submitter_role = keccak256("SUBMITTER_ROLE");

    function setUp() public virtual {
        ProofManagerV1Harness impl = new ProofManagerV1Harness();

        ProxyAdmin admin = new ProxyAdmin(owner);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(admin), "");

        proofManager = ProofManagerV1Harness(address(proxy));
        vm.prank(owner);

        proofManager.initialize(fermah, lagrange, address(usdc), submitter, owner);
        proofManager.initializeV2();

        usdc.mint(address(proofManager), 50_000_000);
    }

    /*//////////////////////////////////////////
                1. Initialization
    //////////////////////////////////////////*/

    /// @dev Happy path for initialization.
    function testInit() public view {
        assertEq(proofManager.hasRole(owner_role, owner), true, "invalid owner");
        assertEq(proofManager.hasRole(submitter_role, submitter), true, "invalid submitter");

        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Fermah,
            IProofManager.ProvingNetworkInfo({
                addr: fermah, status: IProofManager.ProvingNetworkStatus.Active, owedReward: 0
            })
        );
        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Lagrange,
            IProofManager.ProvingNetworkInfo({
                addr: lagrange, status: IProofManager.ProvingNetworkStatus.Active, owedReward: 0
            })
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

        ProofManagerV1 impl = new ProofManagerV1();
        ProxyAdmin admin = new ProxyAdmin(owner);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(admin), "");

        ProofManagerV1 _proofManager = ProofManagerV1(address(proxy));
        vm.prank(owner);

        _proofManager.initialize(fermah, lagrange, address(this), submitter, owner);
    }

    /// @dev Do not allow zero address for admin.
    function testInitFailsWithZeroAdminAddress() public {
        ProofManagerV1 impl = new ProofManagerV1();
        ProxyAdmin admin = new ProxyAdmin(owner);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(admin), "");

        ProofManagerV1 _proofManager = ProofManagerV1(address(proxy));
        vm.prank(owner);

        vm.expectRevert(abi.encodeWithSelector(IProofManager.AddressCannotBeZero.selector, "admin"));

        _proofManager.initialize(fermah, lagrange, address(usdc), submitter, address(0));
    }

    /// @dev Do not allow zero address for submitter.
    function testInitFailsWithZeroSubmitterAddress() public {
        ProofManagerV1 impl = new ProofManagerV1();
        ProxyAdmin admin = new ProxyAdmin(owner);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(admin), "");

        ProofManagerV1 _proofManager = ProofManagerV1(address(proxy));
        vm.prank(owner);

        vm.expectRevert(
            abi.encodeWithSelector(IProofManager.AddressCannotBeZero.selector, "submitter")
        );

        _proofManager.initialize(fermah, lagrange, address(usdc), address(0), owner);
    }

    /// @dev Do not allow zero address for proving networks.
    function testInitFailsWithZeroProvingNetworkAddress() public {
        ProofManagerV1 impl = new ProofManagerV1();
        ProxyAdmin admin = new ProxyAdmin(owner);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(admin), "");

        ProofManagerV1 _proofManager = ProofManagerV1(address(proxy));

        vm.expectRevert(
            abi.encodeWithSelector(IProofManager.AddressCannotBeZero.selector, "fermah")
        );

        vm.prank(owner);
        _proofManager.initialize(address(0), lagrange, address(usdc), submitter, owner);

        vm.expectRevert(
            abi.encodeWithSelector(IProofManager.AddressCannotBeZero.selector, "lagrange")
        );

        vm.prank(owner);
        _proofManager.initialize(fermah, address(0), address(usdc), submitter, owner);
    }

    /// @dev Do not allow zero address for USDC contract.
    function testInitFailsWithZeroUSDCAddress() public {
        ProofManagerV1 impl = new ProofManagerV1();
        ProxyAdmin admin = new ProxyAdmin(owner);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(admin), "");

        ProofManagerV1 _proofManager = ProofManagerV1(address(proxy));
        vm.prank(owner);

        vm.expectRevert(abi.encodeWithSelector(IProofManager.AddressCannotBeZero.selector, "usdc"));

        _proofManager.initialize(fermah, lagrange, address(0), submitter, owner);
    }

    /*//////////////////////////////////////////
            1.II. V2 Upgrade
    //////////////////////////////////////////*/

    /// @dev initializeV2 seeds maxReward with the previously hard-coded value (5 USDC) and emits the event.
    function testInitializeV2_seedsMaxReward() public {
        ProofManagerV1Harness impl = new ProofManagerV1Harness();
        ProxyAdmin admin = new ProxyAdmin(owner);
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(admin), "");
        ProofManagerV1Harness _proofManager = ProofManagerV1Harness(address(proxy));

        vm.prank(owner);
        _proofManager.initialize(fermah, lagrange, address(usdc), submitter, owner);

        vm.expectEmit(false, false, false, true);
        emit IProofManager.MaxRewardUpdated(5_000_000);

        _proofManager.initializeV2();

        assertEq(_proofManager.getMaxReward(), 5_000_000, "maxReward should be seeded to 5 USDC");
    }

    /// @dev initializeV2 is guarded by reinitializer(2) and cannot be called more than once.
    function testInitializeV2_cannotBeCalledTwice() public {
        // proofManager in setUp already had initializeV2 called once.
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        proofManager.initializeV2();
    }

    /*//////////////////////////////////////////
            1.III. V3 Recovery Migration
    //////////////////////////////////////////*/

    // The V2 upgrade introduced the `heapObligations` counter but left it at zero on
    // proxies that already had in-flight requests in the heap, which caused
    // `_purge_expired_requests` and the refused/proven branches to underflow with
    // `Panic(0x11)` once any pre-existing entry got touched. The tests below cover
    // `initializeV3`, the one-shot recovery routine that walks the live heap and
    // rebuilds `heapObligations` so those code paths become safe again.

    /// @dev Storage slot of the `heapObligations` field (slot index 8 per
    ///      `forge inspect ProofManagerV1 storage-layout`). Used by the tests below
    ///      to simulate the bug state on otherwise-correctly-tracked harness storage.
    bytes32 private constant HEAP_OBLIGATIONS_SLOT = bytes32(uint256(8));

    /// @dev With a populated heap, V3 must reconstruct `heapObligations` as the sum
    ///      of `maxReward` over every entry currently in the heap. We populate the
    ///      heap normally (so the harness tracks the correct value), then clobber the
    ///      slot to zero to simulate the post-V2 bug, and finally assert that V3
    ///      restores the value to what it was before clobbering.
    function testInitializeV3_backfillsHeapObligations() public {
        // Populate the heap with three requests of distinct maxRewards. Use distinct
        // values so a wrong-attribution implementation (e.g. counting the same entry
        // multiple times) would surface as a mismatched total. Set Fermah as the
        // preferred network so every round-robin slot maps to an active provider —
        // without this the third submission would be refused and would never enter
        // the heap, making the expected sum smaller than intended.
        vm.prank(owner);
        proofManager.updatePreferredProvingNetwork(IProofManager.ProvingNetwork.Fermah);

        uint256[3] memory rewards = [uint256(4_000_000), 3_000_000, 2_500_000];
        uint256 expected = 0;
        for (uint256 i = 0; i < rewards.length; i++) {
            vm.prank(submitter);
            proofManager.submitProofRequest(
                IProofManager.ProofRequestIdentifier(1, i + 1),
                IProofManager.ProofRequestParams({
                    proofInputsUrl: "https://console.google.com/buckets/...",
                    protocolMajor: 0,
                    protocolMinor: 27,
                    protocolPatch: 0,
                    timeoutAfter: 3600,
                    maxReward: rewards[i]
                })
            );
            expected += rewards[i];
        }
        assertEq(
            proofManager.getHeapObligations(),
            expected,
            "sanity: harness should track obligations correctly before clobbering"
        );

        // Simulate the post-V2 bug: counter zeroed out while the heap still holds entries.
        vm.store(address(proofManager), HEAP_OBLIGATIONS_SLOT, bytes32(uint256(0)));
        assertEq(proofManager.getHeapObligations(), 0, "clobber must take effect");

        proofManager.initializeV3();

        assertEq(
            proofManager.getHeapObligations(),
            expected,
            "V3 must rebuild heapObligations as sum of in-flight maxRewards"
        );
    }

    /// @dev End-to-end: in the bugged state, `submitProofRequest` reverts with
    ///      `Panic(0x11)` once a pre-existing heap entry has expired and the purge
    ///      loop tries to subtract from a zero counter. After running V3 the same
    ///      submission succeeds, confirming the recovery actually unbricks the
    ///      contract rather than just reshuffling internal state.
    function testInitializeV3_unbricksSubmitAfterExpiry() public {
        submitDefaultProofRequest(1, 1);

        // Reproduce the bug: counter at zero while the heap still holds the entry above.
        vm.store(address(proofManager), HEAP_OBLIGATIONS_SLOT, bytes32(uint256(0)));

        // ACK_TIMEOUT is 2 minutes; warping past it means the entry is expired and the
        // next `submitProofRequest` will hit `_purge_expired_requests`.
        vm.warp(block.timestamp + 3 minutes);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(submitter);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 2), defaultProofRequestParams()
        );

        // Recovery: rebuild the counter, then the same submission should now succeed.
        proofManager.initializeV3();

        vm.prank(submitter);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 2), defaultProofRequestParams()
        );
    }

    /// @dev V3 only counts entries that are *currently* in the heap. Requests that
    ///      have left the heap (proven, refused, expired-and-purged) must not be
    ///      double-counted, otherwise the rebuilt value would over-state obligations
    ///      and reduce capacity for new submissions.
    function testInitializeV3_excludesEntriesAlreadyRemovedFromHeap() public {
        // (1, 1): submit then prove — leaves the heap.
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);
        vm.prank(fermah);
        proofManager.submitProof(
            IProofManager.ProofRequestIdentifier(1, 1), bytes("proof"), 4_000_000
        );

        // (1, 2): submit and leave it pending — stays in the heap.
        submitDefaultProofRequest(1, 2);

        uint256 expected = 4_000_000; // only (1, 2) is still in the heap

        // Clobber and recover.
        vm.store(address(proofManager), HEAP_OBLIGATIONS_SLOT, bytes32(uint256(0)));
        proofManager.initializeV3();

        assertEq(
            proofManager.getHeapObligations(),
            expected,
            "V3 must skip proof requests that have already been removed from the heap"
        );
    }

    /// @dev `reinitializer(3)` must prevent replay. Re-running V3 — including via the
    ///      same admin path that legitimately invokes it during the upgrade — has to
    ///      revert, otherwise an attacker (or a misconfigured upgrade) could clobber
    ///      heapObligations after the contract has resumed normal operation.
    function testInitializeV3_cannotBeCalledTwice() public {
        proofManager.initializeV3();

        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        proofManager.initializeV3();
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
            IProofManager.ProvingNetworkInfo({
                addr: otherProvingNetwork,
                status: IProofManager.ProvingNetworkStatus.Active,
                owedReward: 0
            })
        );
    }

    /// @dev Only owner can update proving network address.
    function testNonOwnerCannotUpdateProvingNetworkAddress() public {
        vm.prank(externalAddr);
        expectAccessRevert(externalAddr, owner_role);
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
            IProofManager.ProvingNetworkInfo({
                addr: fermah, status: IProofManager.ProvingNetworkStatus.Inactive, owedReward: 0
            })
        );
    }

    /// @dev Only owner can update a proving network's status.
    function testNonOwnerCannotUpdateProvingNetworkStatus() public {
        vm.prank(externalAddr);
        expectAccessRevert(externalAddr, owner_role);
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
        vm.prank(externalAddr);
        expectAccessRevert(externalAddr, owner_role);
        proofManager.updatePreferredProvingNetwork(IProofManager.ProvingNetwork.Fermah);
    }

    /*//////////////////////////////////////////
            2.IV. Update Max Reward
    //////////////////////////////////////////*/

    /// @dev Happy path: admin raises the cap and a proof request that was previously over-limit is now accepted.
    function testUpdateMaxReward() public {
        uint256 newCap = 8_000_000;

        vm.expectEmit(false, false, false, true);
        emit IProofManager.MaxRewardUpdated(newCap);

        vm.prank(owner);
        proofManager.updateMaxReward(newCap);

        assertEq(proofManager.getMaxReward(), newCap, "maxReward should reflect the new cap");

        // A request offering more than the old 5 USDC cap is now valid.
        vm.prank(submitter);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams({
                proofInputsUrl: "https://console.google.com/buckets/...",
                protocolMajor: 0,
                protocolMinor: 27,
                protocolPatch: 0,
                timeoutAfter: 3600,
                maxReward: 7_000_000
            })
        );
    }

    /// @dev Lowering the cap blocks proof requests that exceed the new, tighter limit.
    function testUpdateMaxReward_lowerCapEnforced() public {
        uint256 newCap = 2_000_000;

        vm.prank(owner);
        proofManager.updateMaxReward(newCap);

        // defaultProofRequestParams uses 4e6 which is now over the new cap.
        vm.expectRevert(abi.encodeWithSelector(IProofManager.MaxRewardOutOfBounds.selector));
        vm.prank(submitter);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1), defaultProofRequestParams()
        );
    }

    /// @dev Non-admin cannot change the max reward cap.
    function testUpdateMaxReward_nonOwnerReverts() public {
        vm.prank(externalAddr);
        expectAccessRevert(externalAddr, owner_role);
        proofManager.updateMaxReward(1_000_000);
    }

    /// @dev Setting maxReward to zero is rejected to prevent locking pre-funded USDC in the contract.
    function testUpdateMaxReward_cannotSetToZero() public {
        vm.expectRevert(abi.encodeWithSelector(IProofManager.MaxRewardOutOfBounds.selector));
        vm.prank(owner);
        proofManager.updateMaxReward(0);
    }

    /// @dev Lowering maxReward while the heap holds high-reward proofs must not cause insolvency.
    ///
    /// Sequence:
    ///   1. Fill the heap with proofs at 4 USDC each until the 5 USDC cap leaves no room.
    ///   2. Lower the cap to 1 USDC — this widens the available capacity.
    ///   3. Submit additional proofs at 1 USDC each until the heap is full again.
    ///   4. Assert that the total heap obligations never exceed the contract's USDC balance.
    function testUpdateMaxReward_lowerCapDoesNotUnderfund() public {
        // setUp mints 50 USDC (50_000_000) into the contract and sets maxReward = 5 USDC.
        // With per-proof rewards of 4 USDC, the capacity check (balance - heapObligations >= maxReward)
        // allows at most 12 proofs before the remaining free balance drops below the 5 USDC cap.
        vm.startPrank(submitter);
        for (uint256 i = 0; i < 12; i++) {
            proofManager.submitProofRequest(
                IProofManager.ProofRequestIdentifier(1, uint256(i + 1)),
                IProofManager.ProofRequestParams({
                    proofInputsUrl: "https://console.google.com/buckets/...",
                    protocolMajor: 0,
                    protocolMinor: 27,
                    protocolPatch: 0,
                    timeoutAfter: 3600,
                    maxReward: 4_000_000
                })
            );
        }
        vm.stopPrank();

        // Lower the cap from 5 USDC to 1 USDC. The free balance (50M - 48M = 2M) now satisfies
        // the new cap, so two more 1 USDC proofs can be accepted.
        vm.prank(owner);
        proofManager.updateMaxReward(1_000_000);

        vm.startPrank(submitter);
        for (uint256 i = 0; i < 2; i++) {
            proofManager.submitProofRequest(
                IProofManager.ProofRequestIdentifier(1, uint256(13 + i)),
                IProofManager.ProofRequestParams({
                    proofInputsUrl: "https://console.google.com/buckets/...",
                    protocolMajor: 0,
                    protocolMinor: 27,
                    protocolPatch: 0,
                    timeoutAfter: 3600,
                    maxReward: 1_000_000
                })
            );
        }
        vm.stopPrank();

        uint256 heapObligations = proofManager.getHeapObligations();
        uint256 balance = usdc.balanceOf(address(proofManager));

        assertLe(heapObligations, balance, "heap obligations must not exceed contract balance");
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
            4e6,
            0
        );

        vm.prank(submitter);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1), defaultProofRequestParams()
        );
        assertProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequest({
                proofInputsUrl: "https://console.google.com/buckets/...",
                protocolMajor: 0,
                protocolMinor: 27,
                protocolPatch: 0,
                submittedAt: block.timestamp,
                timeoutAfter: 3600,
                maxReward: 4e6,
                status: IProofManager.ProofRequestStatus.PendingAcknowledgement,
                assignedTo: IProofManager.ProvingNetwork.Fermah,
                requestedReward: 0,
                proof: bytes(""),
                requestId: 0
            })
        );
    }

    /// @dev Only submitter can submit a proof request.
    function testNonOwnerCannotSubmitProof() public {
        expectAccessRevert(externalAddr, submitter_role);
        vm.prank(externalAddr);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1), defaultProofRequestParams()
        );
    }

    /// @dev A proof request for a specific chain/batch can be submitted only once.
    function testCannotSubmitDuplicateProof() public {
        submitDefaultProofRequest(1, 1);
        vm.expectRevert(abi.encodeWithSelector(IProofManager.DuplicatedProofRequest.selector, 1, 1));
        submitDefaultProofRequest(1, 1);
    }

    /// @dev No proof can be generated in 0 seconds.
    function testCannotSubmitProofRequestWithZeroTimeout() public {
        vm.expectRevert(
            abi.encodeWithSelector(IProofManager.InvalidProofRequestTimeout.selector, 0)
        );
        vm.prank(submitter);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams({
                proofInputsUrl: "https://console.google.com/buckets/...",
                protocolMajor: 0,
                protocolMinor: 27,
                protocolPatch: 0,
                timeoutAfter: 0,
                maxReward: 4e6
            })
        );
    }

    /// @dev Cannot submit proof request with max reward out of bounds(0, 5_000_000)
    function testCannotSubmitProofRequestWithMaxRewardOutOfBounds() public {
        vm.expectRevert(abi.encodeWithSelector(IProofManager.MaxRewardOutOfBounds.selector));
        vm.prank(submitter);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams({
                proofInputsUrl: "https://console.google.com/buckets/...",
                protocolMajor: 0,
                protocolMinor: 27,
                protocolPatch: 0,
                timeoutAfter: 3600,
                maxReward: 5_000_001
            })
        );

        vm.expectRevert(abi.encodeWithSelector(IProofManager.MaxRewardOutOfBounds.selector));
        vm.prank(submitter);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams({
                proofInputsUrl: "https://console.google.com/buckets/...",
                protocolMajor: 0,
                protocolMinor: 27,
                protocolPatch: 0,
                timeoutAfter: 3600,
                maxReward: 0
            })
        );
    }

    function testPurgeNotAcknowledgedRequestsOnSubmit() public {
        submitDefaultProofRequest(1, 1);

        IProofManager.ProofRequestIdentifier memory id =
            IProofManager.ProofRequestIdentifier({ chainId: 1, blockNumber: 1 });

        {
            (IProofManager.ProofRequest memory rBefore) = proofManager.proofRequest(id);
            assertEq(
                uint8(rBefore.status),
                uint8(IProofManager.ProofRequestStatus.PendingAcknowledgement)
            );
        }

        vm.warp(block.timestamp + 3 minutes);

        submitDefaultProofRequest(1, 2);

        {
            (IProofManager.ProofRequest memory rAfter) = proofManager.proofRequest(id);
            assertEq(uint8(rAfter.status), uint8(IProofManager.ProofRequestStatus.Unacknowledged));
        }
    }

    function testPurgeAcknowledgedRequestsOnSubmit() public {
        submitDefaultProofRequest(1, 1);
        vm.prank(fermah);

        IProofManager.ProofRequestIdentifier memory id =
            IProofManager.ProofRequestIdentifier({ chainId: 1, blockNumber: 1 });

        proofManager.acknowledgeProofRequest(id, true);

        vm.warp(block.timestamp + 3 hours);
        submitDefaultProofRequest(1, 2);

        {
            (IProofManager.ProofRequest memory rAfter) = proofManager.proofRequest(id);
            assertEq(uint8(rAfter.status), uint8(IProofManager.ProofRequestStatus.TimedOut));
        }
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
                IProofManager.ProofRequest({
                    proofInputsUrl: "https://console.google.com/buckets/...",
                    protocolMajor: 0,
                    protocolMinor: 27,
                    protocolPatch: 0,
                    submittedAt: block.timestamp,
                    timeoutAfter: 3600,
                    maxReward: 4e6,
                    status: outputs[i].status,
                    assignedTo: outputs[i].network,
                    requestedReward: 0,
                    proof: bytes(""),
                    requestId: i
                })
            );
        }
        vm.stopPrank();
    }

    /// @dev Proof should not be empty.
    function testProofShouldBeNotEmpty() public {
        submitDefaultProofRequest(1, 1);

        vm.prank(fermah);
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);

        vm.prank(fermah);
        vm.expectRevert(abi.encodeWithSelector(IProofManager.EmptyProof.selector));
        proofManager.submitProof(IProofManager.ProofRequestIdentifier(1, 1), bytes(""), 1e6);
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
        vm.prank(submitter);
        proofManager.submitProofValidationResult(IProofManager.ProofRequestIdentifier(1, 1), true);
        assertProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequest({
                proofInputsUrl: "https://console.google.com/buckets/...",
                protocolMajor: 0,
                protocolMinor: 27,
                protocolPatch: 0,
                submittedAt: block.timestamp,
                timeoutAfter: 3600,
                maxReward: 4e6,
                status: IProofManager.ProofRequestStatus.Validated,
                assignedTo: IProofManager.ProvingNetwork.Fermah,
                requestedReward: 0,
                proof: bytes(""),
                requestId: 0
            })
        );
    }

    /// @dev Only submitter can submit proof validation result.
    function testNonOwnerCannotSubmitProofValidationResult() public {
        submitDefaultProofRequest(1, 1);
        proofManager.forceSetProofRequestStatus(
            IProofManager.ProofRequestIdentifier(1, 1), IProofManager.ProofRequestStatus.Proven
        );
        vm.prank(externalAddr);
        expectAccessRevert(externalAddr, submitter_role);
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
        vm.prank(submitter);
        proofManager.submitProofValidationResult(IProofManager.ProofRequestIdentifier(1, 1), true);
    }

    /// @dev Submitting proof validation result marks requests due for reward.
    function testUpdateProofRequestStatusAsValidatedForPayment() public {
        for (uint256 i = 0; i < 8; ++i) {
            uint256 reward = (i + 1) * 1e5;
            vm.prank(submitter);
            proofManager.submitProofRequest(
                IProofManager.ProofRequestIdentifier(1, i),
                IProofManager.ProofRequestParams({
                    proofInputsUrl: "https://console.google.com/buckets/...",
                    protocolMajor: 0,
                    protocolMinor: 27,
                    protocolPatch: 0,
                    timeoutAfter: 3600,
                    maxReward: reward
                })
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
                vm.prank(submitter);
                proofManager.submitProofValidationResult(
                    IProofManager.ProofRequestIdentifier(1, i), true
                );
            }
        }

        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Fermah,
            IProofManager.ProvingNetworkInfo({
                addr: fermah, status: IProofManager.ProvingNetworkStatus.Active, owedReward: 6e5
            })
        );
        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Lagrange,
            IProofManager.ProvingNetworkInfo({
                addr: lagrange, status: IProofManager.ProvingNetworkStatus.Active, owedReward: 8e5
            })
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
        vm.prank(submitter);
        proofManager.submitProofValidationResult(IProofManager.ProofRequestIdentifier(1, 1), false);
        assertProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequest({
                proofInputsUrl: "https://console.google.com/buckets/...",
                protocolMajor: 0,
                protocolMinor: 27,
                protocolPatch: 0,
                submittedAt: block.timestamp,
                timeoutAfter: 3600,
                maxReward: 4e6,
                status: IProofManager.ProofRequestStatus.ValidationFailed,
                assignedTo: IProofManager.ProvingNetwork.Fermah,
                requestedReward: 0,
                proof: bytes(""),
                requestId: 0
            })
        );
        assertProvingNetworkInfo(
            IProofManager.ProvingNetwork.Fermah,
            IProofManager.ProvingNetworkInfo(IProofManager.ProvingNetworkStatus.Active, fermah, 0)
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
                IProofManager.OnlyProvingNetworkAssigneeAllowed.selector, lagrange
            )
        );
        proofManager.acknowledgeProofRequest(IProofManager.ProofRequestIdentifier(1, 1), true);
    }

    /// @dev Cannot acknowledge a proof request that doesn't exist.
    function testCannotAcknowledgeUnexistingProofRequest() public {
        vm.prank(fermah);
        vm.expectRevert(
            abi.encodeWithSelector(IProofManager.OnlyProvingNetworkAssigneeAllowed.selector, fermah)
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
            1, 1, bytes("such proof much wow"), IProofManager.ProvingNetwork.Fermah, 3e6
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
            1, 1, bytes("such proof much wow"), IProofManager.ProvingNetwork.Fermah, 4e6
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
                IProofManager.OnlyProvingNetworkAssigneeAllowed.selector, lagrange
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
            abi.encodeWithSelector(IProofManager.OnlyProvingNetworkAssigneeAllowed.selector, fermah)
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

    /// @dev Reverts if there's nothing to pay.
    function testClaimRewardRevertsWhenNothingToPay() public {
        vm.prank(fermah);
        vm.expectRevert(abi.encodeWithSelector(IProofManager.NoPaymentDue.selector));
        proofManager.claimReward();
    }

    /// @dev Happy path: the caller is paid what its own network is owed, nothing more.
    function testClaimRewardPaysOnlyCallersNetwork() public {
        accrueReward(1, 1, IProofManager.ProvingNetwork.Fermah, fermah, 3e6);
        accrueReward(1, 2, IProofManager.ProvingNetwork.Lagrange, lagrange, 2e6);

        bytes32 assetId = mockBridge();

        vm.expectCall(
            L2_ASSET_ROUTER_ADDR,
            abi.encodeCall(
                IL2AssetRouter.withdraw,
                (assetId, DataEncoding.encodeBridgeBurnData(3e6, fermah, address(usdc)))
            )
        );
        vm.expectEmit(true, false, false, true);
        emit IProofManager.RewardClaimed(IProofManager.ProvingNetwork.Fermah, 3e6);

        vm.prank(fermah);
        proofManager.claimReward();

        assertEq(
            proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Fermah).owedReward,
            0,
            "Fermah should have been paid"
        );
        assertEq(
            proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Lagrange).owedReward,
            2e6,
            "Lagrange reward should be untouched"
        );
    }

    /// @dev When one address is registered for both networks, a single claim settles both.
    ///     Otherwise the rewards of whichever network loses the tie-break stay stuck forever.
    function testClaimRewardPaysBothNetworksWhenAddressIsShared() public {
        accrueReward(1, 1, IProofManager.ProvingNetwork.Fermah, fermah, 3e6);
        accrueReward(1, 2, IProofManager.ProvingNetwork.Lagrange, lagrange, 2e6);

        vm.prank(owner);
        proofManager.updateProvingNetworkAddress(IProofManager.ProvingNetwork.Lagrange, fermah);

        bytes32 assetId = mockBridge();

        vm.expectCall(
            L2_ASSET_ROUTER_ADDR,
            abi.encodeCall(
                IL2AssetRouter.withdraw,
                (assetId, DataEncoding.encodeBridgeBurnData(5e6, fermah, address(usdc)))
            )
        );
        vm.expectEmit(true, false, false, true);
        emit IProofManager.RewardClaimed(IProofManager.ProvingNetwork.Fermah, 3e6);
        vm.expectEmit(true, false, false, true);
        emit IProofManager.RewardClaimed(IProofManager.ProvingNetwork.Lagrange, 2e6);

        vm.prank(fermah);
        proofManager.claimReward();

        assertEq(
            proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Fermah).owedReward,
            0,
            "Fermah should have been paid"
        );
        assertEq(
            proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Lagrange).owedReward,
            0,
            "Lagrange should have been paid as well"
        );
    }

    /// @dev A shared address that is only owed on the second network still gets paid.
    function testClaimRewardPaysSharedAddressOwedOnlyByLagrange() public {
        // Burn the first slot of the round robin (which always goes to Fermah) so that the
        // request below is assigned to Lagrange and Fermah is owed nothing.
        submitDefaultProofRequest(1, 1);
        accrueReward(1, 2, IProofManager.ProvingNetwork.Lagrange, lagrange, 2e6);

        vm.prank(owner);
        proofManager.updateProvingNetworkAddress(IProofManager.ProvingNetwork.Lagrange, fermah);

        bytes32 assetId = mockBridge();

        vm.expectCall(
            L2_ASSET_ROUTER_ADDR,
            abi.encodeCall(
                IL2AssetRouter.withdraw,
                (assetId, DataEncoding.encodeBridgeBurnData(2e6, fermah, address(usdc)))
            )
        );

        vm.prank(fermah);
        proofManager.claimReward();

        assertEq(
            proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Lagrange).owedReward,
            0,
            "Lagrange should have been paid"
        );
    }

    function testRequestRejectedIfNoFundsAvailable() public {
        // The round-robin assigns: Fermah, Lagrange, None (refused), None (refused), repeat.
        // So 2 of every 4 requests are refused and never enter the heap.
        //
        // Capacity is now tracked via `heapObligations` (sum of per-request maxReward in the heap)
        // rather than heap.size() × globalMaxReward. Each request uses maxReward=4e6; the global
        // cap is 5e6; balance is 50e6.
        //
        // The contract accepts one more request while free = balance - heapObligations >= globalMaxReward.
        // With 12 items in the heap: free = 50e6 - 12×4e6 = 2e6 < 5e6 → rejected.
        // The 12th in-flight item is added at i=21; the rejection is triggered at i=22 (refused,
        // but the capacity check runs before assignment and still fails).
        for (uint256 i = 0; i < 22; i++) {
            submitDefaultProofRequest(1, i + 1);
        }

        vm.expectRevert(abi.encodeWithSelector(IProofManager.NoFundsAvailable.selector));

        submitDefaultProofRequest(1, 23);
    }

    /*//////////////////////////////////////////
                    5. Getters
    //////////////////////////////////////////*/

    /// @dev Test proofRequest getter sets the right status after timeouts.
    function testProofRequestStatusIsSetOnTimeouts() public {
        vm.prank(submitter);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams({
                proofInputsUrl: "https://console.google.com/buckets/...",
                protocolMajor: 0,
                protocolMinor: 27,
                protocolPatch: 0,
                timeoutAfter: 3600,
                maxReward: 4e6
            })
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
        assertEq(
            proofRequest.requestId,
            expectedProofRequest.requestId,
            "Request ID should be set correctly"
        );
    }

    /*//////////////////////////////////////////
                    Helpers
    //////////////////////////////////////////*/

    /// @dev Submits a default proof request to the proof manager.
    /// @dev Drives a proof request through the full flow so that `network` ends up owed
    ///     `requestedReward`. `provingNetworkAddr` must be the address currently registered
    ///     for `network`, and the round robin must be about to assign the request to it.
    function accrueReward(
        uint256 chainId,
        uint256 blockNumber,
        IProofManager.ProvingNetwork network,
        address provingNetworkAddr,
        uint256 requestedReward
    ) private {
        IProofManager.ProofRequestIdentifier memory id =
            IProofManager.ProofRequestIdentifier({ chainId: chainId, blockNumber: blockNumber });

        submitDefaultProofRequest(chainId, blockNumber);
        assertEq(
            uint8(proofManager.proofRequest(id).assignedTo),
            uint8(network),
            "request was not assigned to the expected network"
        );

        vm.prank(provingNetworkAddr);
        proofManager.acknowledgeProofRequest(id, true);
        vm.prank(provingNetworkAddr);
        proofManager.submitProof(id, bytes("such proof much wow"), requestedReward);
        vm.prank(submitter);
        proofManager.submitProofValidationResult(id, true);
    }

    /// @dev Mocks the L2 bridge contracts that `claimReward` withdraws through.
    function mockBridge() private returns (bytes32 assetId) {
        assetId = keccak256("usdc-asset-id");
        vm.mockCall(
            L2_NATIVE_TOKEN_VAULT_ADDR,
            abi.encodeCall(INativeTokenVault.assetId, (address(usdc))),
            abi.encode(assetId)
        );
        vm.mockCall(
            L2_ASSET_ROUTER_ADDR,
            abi.encodeWithSelector(IL2AssetRouter.withdraw.selector),
            abi.encode(bytes32(0))
        );
    }

    function submitDefaultProofRequest(uint256 chainId, uint256 blockNumber) private {
        IProofManager.ProofRequestIdentifier memory id =
            IProofManager.ProofRequestIdentifier({ chainId: chainId, blockNumber: blockNumber });
        vm.prank(submitter);
        proofManager.submitProofRequest(id, defaultProofRequestParams());
    }

    /// @dev Default Proof Request Params for testing.
    function defaultProofRequestParams()
        private
        pure
        returns (IProofManager.ProofRequestParams memory)
    {
        return IProofManager.ProofRequestParams({
            proofInputsUrl: "https://console.google.com/buckets/...",
            protocolMajor: 0,
            protocolMinor: 27,
            protocolPatch: 0,
            timeoutAfter: 3600,
            maxReward: 4e6
        });
    }

    /*//////////////////////////////////////////
            Admin Token Withdrawal
    //////////////////////////////////////////*/

    function test_withdraw_partialAmount() public {
        uint256 initialBalance = usdc.balanceOf(address(proofManager));
        uint256 withdrawAmount = 10_000_000; // 10 USDC

        vm.expectEmit(true, true, false, true);
        emit IProofManager.FundsWithdrawn(address(usdc), owner, withdrawAmount);

        vm.prank(owner);
        proofManager.withdraw(address(usdc), withdrawAmount);

        assertEq(usdc.balanceOf(owner), withdrawAmount, "owner should receive withdrawn amount");
        assertEq(
            usdc.balanceOf(address(proofManager)),
            initialBalance - withdrawAmount,
            "contract balance should decrease"
        );
    }

    function test_withdraw_fullBalance() public {
        uint256 fullBalance = usdc.balanceOf(address(proofManager));

        vm.prank(owner);
        proofManager.withdraw(address(usdc), fullBalance);

        assertEq(usdc.balanceOf(address(proofManager)), 0, "contract should be empty");
        assertEq(usdc.balanceOf(owner), fullBalance, "owner should have full balance");
    }

    function test_withdraw_revertsIfNotAdmin() public {
        expectAccessRevert(externalAddr, owner_role);
        vm.prank(externalAddr);
        proofManager.withdraw(address(usdc), 1_000_000);
    }

    function test_withdraw_revertsIfAmountExceedsBalance() public {
        uint256 balance = usdc.balanceOf(address(proofManager));

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(owner);
        proofManager.withdraw(address(usdc), balance + 1);
    }

    /// @dev Expects default revert for ownable contract.
    function expectAccessRevert(address caller, bytes32 neededRole) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                caller,
                neededRole
            )
        );
    }
}
