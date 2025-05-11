// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "../interfaces/IProofManager.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @author Matter Labs
/// @notice Storage layout. No logic here.
abstract contract ProofManagerStorage {
    /*////////////////////////
            Storage
    ////////////////////////*/

    /// @dev Mapping for the source of truth on Proving Network information.
    mapping(IProofManager.ProvingNetwork => IProofManager.ProvingNetworkInfo) internal
        _provingNetworks;

    /// @dev Mapping for the source of truth on proof requests. (ProofRequestIdentifier => ProofRequest)
    mapping(uint256 => mapping(uint256 => IProofManager.ProofRequest)) internal _proofRequests;

    /// @dev Proving Network that will receive more proof requests.
    ///     By default, None, but will be computed on a previous month basis and set by the owner.
    IProofManager.ProvingNetwork public preferredProvingNetwork;

    /// @dev Used to round robin proof requests between Proving Networks. Tracks number of requests that have been outsourced to Proving Networks.
    uint256 internal _requestCounter;

    /// @dev USDC contract address used for paying proofs.
    IERC20 internal USDC;

    /*////////////////////////
            Constants
    ////////////////////////*/

    /// @dev Hard-coded constant on Proof Request acknowledgement timeout time.
    ///     Proving Networks have 2 minutes to commit to proving a proof request once posted on chain.
    ///     Minimizes the proving downtime in case of communication failure.
    uint256 internal constant ACK_TIMEOUT = 2 minutes;

    /// @dev Maximum amount possible to withdraw at any given time by a proving network. Security measure to reduce amount of funds that can be withdrawn.
    ///     25k $ USDC per network => contract will hold 50k $ USDC total (max * 2 networks)
    uint256 internal constant WITHDRAW_LIMIT = 25_000e6; // 25 000 USDC
}
