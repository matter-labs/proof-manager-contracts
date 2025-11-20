// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @title ProofManager contract interface
interface IProofManager {
    /*//////////////////////////////////////////
                    Types
    //////////////////////////////////////////*/

    /// @dev Proving Networks available
    /// @param None represents unset/non-existing ProvingNetwork (used where Option<ProvingNetwork> is required).
    enum ProvingNetwork {
        None,
        Fermah,
        Lagrange
    }

    /// @dev Proving Network status.
    ///     NOTE: In the near future, the enum will be expanded with more statuses (I.E. InOutage, Disabled, etc).
    /// @param Active Proving Network is active and will receive proof requests.
    /// @param Inactive Proving Network is inactive and all proof requests will be marked by default as Declined.
    enum ProvingNetworkStatus {
        Active,
        Inactive
    }

    /// @dev The states through which a proof request can pass.
    /// @param PendingAcknowledgement The state in which any request starts, waiting for the Proving Network to acknowledge it.
    /// @param Committed Proving Network has acknowledged the request and committed to prove it.
    /// @param Refused Proving Network has refused to prove the request (or the Proving Network is inactive).
    /// @param Unacknowledged Proving Network has not acknowledged the request before the acknowledgement timeout has passed (note, this is only visible in the getter, storage is modified only when the request is purged).
    /// @param Proven Proving Network has proven the request and is waiting for validation.
    /// @param TimedOut Proving Network has not proven the request before the proving timeout has passed (note, this is only visible in the getter, storage is modified only when the request is purged).
    /// @param Validated The proof has been validated on settlement layer and is ready due for payment.
    /// @param ValidationFailed The proof failed validation on settlement layer and will not be paid (impact Proving Network score).
    enum ProofRequestStatus {
        PendingAcknowledgement,
        Committed,
        Refused,
        Unacknowledged,
        Proven,
        TimedOut,
        Validated,
        ValidationFailed
    }

    /// @dev Proof Request identifier. (chainId, blockNumber) tuple is expected to be unique.
    struct ProofRequestIdentifier {
        uint256 chainId;
        uint256 blockNumber;
    }

    /// @dev Proof Request submission parameters. Defines what are the parameters for proof request submission.
    /// @param timeoutAfter Time duration (I.E. 2 hours) after which the proof request will be marked be considered as timed out.
    struct ProofRequestParams {
        uint32 protocolMajor;
        uint32 protocolMinor;
        uint32 protocolPatch;
        string proofInputsUrl;
        uint256 timeoutAfter;
        uint256 maxReward;
    }

    /// @dev Used to track information of each proving network. Relevant for proof request assignment, authorization and payments.
    /// @param addr Proving Network's address.
    /// @param status Proving Network's status. Controls what happens at proof request assignment.
    /// @param owedReward Amount of USDC owed (6 decimals => 10$ = 10e6) to the Proving Network for all proofs that have been proven & validated.
    struct ProvingNetworkInfo {
        ProvingNetworkStatus status;
        address addr;
        uint256 owedReward;
    }

    /// @dev Authoritative source of truth for proof requests.
    /// @param submittedAt block.timestamp when submitted.
    /// @param timeoutAfter Time duration (I.E. 1 hours) after which the proof request will pass proving deadline.
    /// @param maxReward max USDC sequencer is willing to pay for a proof (6 decimals) => 10$ = 10e6
    /// @param requestedReward price the proving network is willing to prove for (6 decimals) => 10$ = 10e6
    struct ProofRequest {
        uint32 protocolMajor;
        uint32 protocolMinor;
        uint32 protocolPatch;
        IProofManager.ProofRequestStatus status;
        IProofManager.ProvingNetwork assignedTo;
        string proofInputsUrl;
        uint256 submittedAt;
        uint256 timeoutAfter;
        uint256 maxReward;
        uint256 requestedReward;
        bytes proof;
        uint256 requestId;
    }

    /*//////////////////////////////////////////
                    Events
    //////////////////////////////////////////*/

    /// @dev Emitted when a proof request is submitted. Proving Networks will filter for events that are assigned to them.
    event ProofRequestSubmitted(
        uint256 indexed chainId,
        uint256 indexed blockNumber,
        ProvingNetwork indexed assignedTo,
        string proofInputsUrl,
        uint32 protocolMajor,
        uint32 protocolMinor,
        uint32 protocolPatch,
        uint256 timeoutAfter,
        uint256 maxReward,
        uint256 requestId
    );

    /// @dev Emitted when a proof request validation result is submitted.
    ///     Proving networks will filter for events that are assigned to them to understand if they need to claim rewards or if anything is broken with their stack.
    event ProofValidationResult(
        uint256 indexed chainId,
        uint256 indexed blockNumber,
        bool isProofValid,
        ProvingNetwork indexed assignedTo
    );

    /// @dev Emitted when a proof request is acknowledged. Used as a checkpoint and for Proving Network benchmarking.
    event ProofRequestAcknowledged(
        uint256 indexed chainId,
        uint256 indexed blockNumber,
        bool accepted,
        ProvingNetwork indexed assignedTo
    );

    /// @dev Emitted when a proof is submitted. Used by sequencers to extract the proof (and later for Proving Networks benchmarking).
    event ProofRequestProven(
        uint256 indexed chainId, uint256 indexed blockNumber, bytes proof, ProvingNetwork assignedTo
    );

    /// @dev Emitted when Proving Network withdraws funds. Useful for troubleshooting.
    event RewardClaimed(ProvingNetwork indexed by, uint256 amount);

    /// @dev Emitted when Proving Network address is updated. Useful for transparency and catching unintended updates.
    event ProvingNetworkAddressUpdated(ProvingNetwork indexed provingNetwork, address addr);

    /// @dev Emitted when Proving Network status is changed. Useful for transparency and serves as communication medium for Proving Networks.
    ///     Proving Networks will filter for events that change their own status.
    event ProvingNetworkStatusUpdated(
        ProvingNetwork indexed provingNetwork, ProvingNetworkStatus status
    );

    /// @dev Emitted when Proving Network is updated (once per month). Useful for transparency and troubleshooting.
    event PreferredProvingNetworkUpdated(ProvingNetwork indexed provingNetwork);

    /*//////////////////////////////////////////
                      Errors
    //////////////////////////////////////////*/

    /// @param field the "field" for which we tried to set a 0 address (I.E. USDC, ProvingNetwork, etc.)
    error AddressCannotBeZero(string field);

    error DuplicatedProofRequest(uint256 chainId, uint256 blockNumber);

    error InvalidProofRequestTimeout();

    error MaxRewardOutOfBounds();

    error NoPaymentDue();

    /// @dev Thrown when the contract does not have enough funds to accept a new request.
    error NoFundsAvailable();

    /// @param sender the address that tried to call the function
    error OnlyProvingNetworkAllowed(address sender);

    /// @param sender the address that tried to call the function
    error OnlyProvingNetworkAssigneeAllowed(address sender);

    /// @param status the status of the proof request when proving was tried (must be different than Committed)
    error ProofRequestIsNotCommitted(ProofRequestStatus status);

    /// @param status the status of the proof request when acknowledgement was tried (must be different than PendingAcknowledgement)
    error ProofRequestIsNotPendingAcknowledgement(ProofRequestStatus status);

    /// @param status the status of the proof request when validation was tried (must be different than Proven)
    error ProofRequestIsNotProven(ProofRequestStatus status);

    error ProofRequestAcknowledgementDeadlinePassed();

    error ProofRequestProvingDeadlinePassed();

    error EmptyProof();

    error ProvingNetworkCannotBeNone();

    error UsdcTransferFailed();

    /*//////////////////////////////////////////
            Proving Network Management
    //////////////////////////////////////////*/

    /// @dev Useful for proving network key rotation or key compromise. Can be called only by owner and Proving Network cannot be None.
    ///     NOTE: In case of contract key compromise, the maximum amount of USDC that can be stolen is 50k (operations will not fund it with more, as agreed with Proving Networks).
    function updateProvingNetworkAddress(ProvingNetwork network, address addr) external;

    /// @dev Useful for Proving Network outage (Active to Inactive) or recovery (Inactive to Active).
    ///     Can be called only by owner and Proving Network cannot be None.
    function updateProvingNetworkStatus(ProvingNetwork network, ProvingNetworkStatus status)
        external;

    /// @dev Used once per month to direct more proofs to the network that scored best previous month.
    ///     Can be called only by owner.
    function updatePreferredProvingNetwork(ProvingNetwork network) external;

    /*//////////////////////////////////////////
            Proof Request Management
    //////////////////////////////////////////*/

    /// @dev Submits a proof request. The proof is assigned to the next proving network in round robin.
    ///     Can be called only by the submitter.
    function submitProofRequest(
        ProofRequestIdentifier calldata id,
        ProofRequestParams calldata params
    ) external;

    /// @dev Submits the result of proof validation on settlement layer. Can be called only by the submitter.
    ///     NOTE: Valid proofs are due for payment (Proving Network needs to call `claimReward()`), whilst invalid proofs are not (and Proving Network is penalized in monthly Preferred Proving Network assignment).
    function submitProofValidationResult(ProofRequestIdentifier calldata id, bool isProofValid)
        external;

    /*//////////////////////////////////////////
            Proving Network Interactions
    //////////////////////////////////////////*/

    /// @dev Acknowledges a proof request. The proving network can either commit to prove or refuse (due to price, availability, etc).
    ///     Can be called only by the Proving Network assigned to the proof request, on proof requests that exist and are in PendingAcknowledgement status.
    function acknowledgeProofRequest(ProofRequestIdentifier calldata id, bool accept) external;

    /// @dev Submit proof for proof request.
    ///     Can be called only by the Proving Network assigned to the proof request, on proof requests that exist and are in Committed status.
    function submitProof(
        ProofRequestIdentifier calldata id,
        bytes calldata proof,
        uint256 provingNetworkPrice
    ) external;

    /// @dev Claim rewards (in USDC) for already validated proofs.
    ///     Can be called only by the Proving Network, assuming there is a reward due.
    function claimReward() external;
}
