// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "./harness/ProofManagerHarness.sol";

/// @dev Mock USDC contract implementation.
contract FakeUSDC is IERC20 {
    mapping(address => uint256) public balanceOf;
    string public constant name = "Mock USDC";
    uint8 public constant decimals = 6;

    /*////////////////////////
            Used
    ////////////////////////*/

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
    }

    function transfer(address to, uint256 amt) external returns (bool) {
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    /*/////////////////////////////////////////
            Implemented due to interface
    /////////////////////////////////////////*/

    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        balanceOf[from] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return 0;
    }

    function approve(address spender, uint256 amt) external returns (bool) {
        return true;
    }

    function totalSupply() external view returns (uint256) {
        return 0;
    }
}

/// @dev Base test contract to simplify testing.
abstract contract Base is Test {
    /// @dev ProofManager, but with a few functions that override invariants.
    ProofManagerHarness proofManager;
    FakeUSDC usdc = new FakeUSDC();

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

    /*////////////////////////
            Assertions
    ////////////////////////*/

    /// @dev Asserts that set proving network info matches expected one.
    function assertProvingNetworkInfo(
        ProvingNetwork network,
        ProofManagerStorage.ProvingNetworkInfo memory expectedInfo
    ) internal view {
        ProofManagerStorage.ProvingNetworkInfo memory info =
            proofManager.provingNetworkInfo(network);

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
        ProofManagerStorage.ProofRequest memory expectedProofRequest
    ) internal view {
        ProofManagerStorage.ProofRequest memory proofRequest =
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
    function submitDefaultProofRequest(uint256 chainId, uint256 blockNumber) internal {
        ProofRequestIdentifier memory id =
            ProofRequestIdentifier({ chainId: chainId, blockNumber: blockNumber });
        vm.prank(owner);
        proofManager.submitProofRequest(
            id, ProofRequestParams("https://console.google.com/buckets/...", 0, 27, 0, 3600, 4e6)
        );
    }

    /// @dev Expects default revert for ownable contract.
    function expectOwnableRevert(address expectedCaller) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")), expectedCaller
            )
        );
    }
}
