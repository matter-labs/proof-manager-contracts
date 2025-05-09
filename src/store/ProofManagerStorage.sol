// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import {
    ProvingNetworkStatus,
    ProofRequestIdentifier,
    ProofRequestStatus,
    ProvingNetwork
} from "../interfaces/IProofManager.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*////////////////////////
        Types
////////////////////////*/

/// @dev Used to track information of each proving network. Relevant for proof request assignment, authorization and payments.
struct ProvingNetworkInfo {
    address addr;
    ProvingNetworkStatus status;
    ProofRequestIdentifier[] unclaimedProofs;
    // owed in USDC (6 decimals) => 10$ = 10e6
    uint256 paymentDue;
}

/// @dev Authoritative source of truth for proof requests.
struct ProofRequest {
    string proofInputsUrl;
    uint32 protocolMajor;
    uint32 protocolMinor;
    uint32 protocolPatch;
    // block.timestamp when submitted
    uint256 submittedAt;
    // time duration (I.E. 1 hours)
    uint256 timeoutAfter;
    // max USDC sequencer is willing to pay (6 decimals) => 10$ = 10e6
    uint256 maxReward;
    ProofRequestStatus status;
    ProvingNetwork assignedTo;
    // price the proving network is willing to prove for (6 decimals) => 10$ = 10e6
    uint256 provingNetworkPrice;
    bytes proof;
}

/// @author Matter Labs
/// @notice Storage layout. No logic here.
abstract contract ProofManagerStorage {
    /*////////////////////////
            Storage
    ////////////////////////*/

    /// @dev Mapping for the source of truth on Proving Network information.
    mapping(ProvingNetwork => ProvingNetworkInfo) internal _provingNetworks;

    /// @dev Mapping for the source of truth on proof requests. (ProofRequestIdentifier => ProofRequest)
    mapping(uint256 => mapping(uint256 => ProofRequest)) internal _proofRequests;

    /// @dev Proving Network that will receive more proof requests.
    ///     By default, None, but will be computed on a previous month basis and set by the owner.
    ProvingNetwork public preferredProvingNetwork;

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
