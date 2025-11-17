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
    mapping(uint256 chainId => mapping(uint256 blockNumber => IProofManager.ProofRequest))
        _proofRequests;

    /// @dev Used to round robin proof requests between Proving Networks. Tracks number of requests that have been outsourced to Proving Networks.
    uint256 internal _requestCounter;

    /// @dev Proving Network that will receive more proof requests.
    ///     By default, None, but will be computed on a previous month basis and set by the owner.
    IProofManager.ProvingNetwork public preferredProvingNetwork;

    /// @dev USDC contract address used for paying proofs.
    IERC20 internal usdc;

    /// @dev Heap that holds all in-flight proof requests.
    MinHeapLib.Heap internal _heap;

    /// @dev Unstable reward - amount of funds for proof requests that were proven but not validated yet.
    uint256 internal unstableReward;
}
