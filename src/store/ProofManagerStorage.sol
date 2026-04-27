// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/IProofManager.sol";

import { MinHeapLib } from "./MinHeapLib.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @author Matter Labs
/// @notice Storage layout. No logic here.
abstract contract ProofManagerStorage {
    // /*////////////////////////
    //         Storage
    // ////////////////////////*/

    /// @dev Mapping for the source of truth for Proving Network's information.
    mapping(IProofManager.ProvingNetwork => IProofManager.ProvingNetworkInfo) public
        _provingNetworks;

    /// @dev Mapping for the source of truth on proof requests. (ProofRequestIdentifier => ProofRequest)
    mapping(uint256 chainId => mapping(uint256 blockNumber => IProofManager.ProofRequest)) internal
        _proofRequests;

    /// @dev Used to round robin proof requests between Proving Networks. Tracks number of requests that have been outsourced to Proving Networks.
    uint256 internal _requestCounter;

    /// @dev Proving Network that will receive more proof requests.
    ///     By default, None, but will be computed on a previous month basis and set by the owner.
    IProofManager.ProvingNetwork public preferredProvingNetwork;

    /// @dev USDC contract address used for paying proofs.
    IERC20 internal usdc;

    /// @dev Heap that holds all in-flight proof requests.
    ///      This way we can control amount of requests at certain moment of time and not exceed the funds capacity of the contract.
    MinHeapLib.Heap internal _heap;

    /// @dev Potential future reward - amount of funds for proof requests that were proven but not validated yet.
    uint256 internal potentialFutureReward;

    /// @dev Maximum reward that can be offered for a single proof request. Configurable by admin.
    ///      Stored as a variable (not a constant) so it can be adjusted without a contract upgrade.
    uint256 public maxReward;

    /// @dev Running sum of the per-request `maxReward` for every proof request currently in the heap.
    ///      Tracks the worst-case payout owed to in-flight requests, so that the capacity check in
    ///      `_can_accept_request` remains correct even when `maxReward` is lowered while the heap
    ///      is non-empty (older requests retain their original, potentially higher, cap).
    uint256 internal heapObligations;
}
