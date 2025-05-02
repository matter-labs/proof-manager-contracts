// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import {
    ProvingNetworkStatus,
    ProofRequestIdentifier,
    ProofRequestStatus,
    ProvingNetwork
} from "../interfaces/IProofManager.sol";

/// @author Matter Labs
/// @notice Storage layout. No logic here.
abstract contract ProofManagerStorage {
    /*////////////////////////
            Types
    ////////////////////////*/

    // /// @dev Proving Networks available, None used for lack of Option<> on _preferredNetwork.
    // enum ProvingNetwork {
    //     None,
    //     Fermah,
    //     Lagrange
    // }

    // /// @dev Proving Network status. Inactive networks do not receive proof requests.
    // enum ProvingNetworkStatus {
    //     Active,
    //     Inactive
    // }

    // /// @dev State machine for proof request lifecycle transitions.
    // enum ProofRequestStatus {
    //     Ready,
    //     Committed,
    //     Refused,
    //     Unacknowledged,
    //     Proven,
    //     TimedOut,
    //     Validated,
    //     ValidationFailed,
    //     Paid
    // }

    // /// @dev Proof Request identifier. chainId and blockNumber tuple is expected to be unique.
    // struct ProofRequestIdentifier {
    //     uint256 chainId;
    //     uint256 blockNumber;
    // }

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

    // /// @dev Helper struct to help with proof request submission interface. Subset of ProofRequest.
    // struct ProofRequestParams {
    //     string proofInputsUrl;
    //     uint32 protocolMajor;
    //     uint32 protocolMinor;
    //     uint32 protocolPatch;
    //     // time duration (I.E. 1 hours)
    //     uint256 timeoutAfter;
    //     uint256 maxReward;
    // }
    /*////////////////////////
            Storage
    ////////////////////////*/

    /// @dev Mapping for the source of truth on Proving Network information.
    mapping(ProvingNetwork => ProvingNetworkInfo) internal _provingNetworks;

    /// @dev Mapping for the source of truth on proof requests. (ProofRequestIdentifier => ProofRequest)
    mapping(uint256 => mapping(uint256 => ProofRequest)) internal _proofRequests;

    /// @dev Proving Network that will receive more proof requests.
    ///     By default, None, but will be computed on a previous month basis and set by the owner.
    ProvingNetwork internal _preferredNetwork;

    /// @dev Used to round robin proof requests between Proving Networks. Tracks number of requests that have been outsourced to Proving Networks.
    uint256 internal _requestCounter;

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
