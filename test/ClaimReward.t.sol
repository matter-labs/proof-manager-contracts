// // SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/store/ProofManagerStorage.sol";
import "../src/ProofManagerV1.sol";
import "../src/interfaces/IProofManager.sol";
import "./ProofManagerHarness.sol";
import {
    L2_NATIVE_TOKEN_VAULT_ADDR,
    L2_ASSET_ROUTER_ADDR,
    L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR
} from "era-contracts/l1-contracts/contracts/common/L2ContractAddresses.sol";

import { INativeTokenVault } from
    "era-contracts/l1-contracts/contracts/bridge/ntv/INativeTokenVault.sol";

/// @dev Test contract for the ProofManagerV1 contract.
contract ProofManagerV1Test is Test {
    /// @dev Helper DTO for testing proof assignment logic.
    struct SubmitProofExpected {
        IProofManager.ProvingNetwork network;
        IProofManager.ProofRequestStatus status;
    }

    /// @dev ProofManager, but with a few functions that override invariants.
    ProofManagerV1Harness proofManager;
    MockUsdc usdc;

    address owner = makeAddr("owner");
    address fermah = makeAddr("fermah");
    address lagrange = makeAddr("lagrange");
    address nonOwner = makeAddr("nonOwner");
    address otherProvingNetwork = makeAddr("otherProvingNetwork");

    function setUp() public virtual {
        proofManager = new ProofManagerV1Harness();
        usdc = new MockUsdc("Mock USDC", "USDC", 6);
        proofManager.initialize(fermah, lagrange, address(usdc), owner);
        usdc.mint(address(proofManager), 1_000e6);
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

    function testAssetRouter() public {
        vm.prank(address(proofManager));
        usdc.approve(L2_NATIVE_TOKEN_VAULT_ADDR, 100);

        // Basically we want all L2->L1 transactions to pass
        vm.mockCall(
            address(L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR),
            abi.encodeWithSignature("sendToL1(bytes)"),
            abi.encode(bytes32(uint256(1)))
        );

        bytes32 assetId = DataEncoding.encodeNTVAssetId(block.chainid, address(usdc));

        IL2AssetRouter(L2_ASSET_ROUTER_ADDR).withdraw(
            assetId, DataEncoding.encodeBridgeBurnData(100, address(1), address(usdc))
        );
    }

    /// @dev Happy path for claim reward, typical expected usage.
    ///     NOTE: Can be treated as an "end to end" test.
    function testClaimReward() public {
        vm.prank(owner);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1),
            IProofManager.ProofRequestParams({
                proofInputsUrl: "https://console.google.com/buckets/...",
                protocolMajor: 0,
                protocolMinor: 27,
                protocolPatch: 0,
                timeoutAfter: 3600,
                maxReward: 100e6
            })
        );
        vm.prank(owner);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 2),
            IProofManager.ProofRequestParams({
                proofInputsUrl: "https://console.google.com/buckets/...",
                protocolMajor: 0,
                protocolMinor: 27,
                protocolPatch: 0,
                timeoutAfter: 3600,
                maxReward: 250e6
            })
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

        // here we want to emulate process of withdrawing USDC from L2 to L1
        vm.prank(address(proofManager));
        usdc.approve(L2_NATIVE_TOKEN_VAULT_ADDR, 250e6);

        vm.prank(fermah);
        vm.mockCall(
            address(L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR),
            abi.encodeWithSignature("sendToL1(bytes)"),
            abi.encode(bytes32(uint256(1)))
        );
        vm.expectEmit(true, true, false, true);
        emit IProofManager.RewardClaimed(IProofManager.ProvingNetwork.Fermah, 125e6);
        proofManager.claimReward();

        info = proofManager.provingNetworkInfo(IProofManager.ProvingNetwork.Fermah);
        assertEq(info.owedReward, 0);
    }

    /// @dev Ensures only proving network can call claim reward.
    function testOnlyProvingNetworkCanClaimReward() public {
        vm.prank(owner);
        proofManager.submitProofRequest(
            IProofManager.ProofRequestIdentifier(1, 1), defaultProofRequestParams()
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
            IProofManager.ProofRequestParams({
                proofInputsUrl: "https://console.google.com/buckets/...",
                protocolMajor: 0,
                protocolMinor: 27,
                protocolPatch: 0,
                timeoutAfter: 3600,
                maxReward: 1_005e6
            })
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
            IProofManager.ProofRequestParams({
                proofInputsUrl: "https://console.google.com/buckets/...",
                protocolMajor: 0,
                protocolMinor: 27,
                protocolPatch: 0,
                timeoutAfter: 3600,
                maxReward: 4e6
            })
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
}
