// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @title ProofManager contract interface
interface IProofManager {
    /*//////////////////////////////////////////
                    Types
    //////////////////////////////////////////*/

    /// @dev Proving Networks available, None represents unset/non-existing ProvingNetwork (used where Option<ProvingNetwork> is required).
    enum ProvingNetwork {
        None,
        Fermah,
        Lagrange
    }

    /// @dev Proving Network status. Inactive networks do not receive proof requests.
    enum ProvingNetworkStatus {
        Active,
        Inactive
    }

    /// @dev State machine for proof request lifecycle transitions.
    enum ProofRequestStatus {
        Ready,
        Committed,
        Refused,
        Unacknowledged,
        Proven,
        TimedOut,
        Validated,
        ValidationFailed,
        Paid
    }

    /// @dev Proof Request identifier. (chainId, blockNumber) tuple is expected to be unique.
    struct ProofRequestIdentifier {
        uint256 chainId;
        uint256 blockNumber;
    }

    /// @dev Proof Request submission parameters. Defines what are the parameters for proof request submission.
    struct ProofRequestParams {
        string proofInputsUrl;
        uint32 protocolMajor;
        uint32 protocolMinor;
        uint32 protocolPatch;
        // time duration (I.E. 2 hours)
        uint256 timeoutAfter;
        uint256 maxReward;
    }

    /// @dev Used to track information of each proving network. Relevant for proof request assignment, authorization and payments.
    struct ProvingNetworkInfo {
        address addr;
        IProofManager.ProvingNetworkStatus status;
        IProofManager.ProofRequestIdentifier[] unclaimedProofs;
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
        IProofManager.ProofRequestStatus status;
        IProofManager.ProvingNetwork assignedTo;
        // price the proving network is willing to prove for (6 decimals) => 10$ = 10e6
        uint256 provingNetworkPrice;
        bytes proof;
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
        uint256 maxReward
    );

    /// @dev Emitted when a proof request status is changed. Useful for troubleshooting.
    event ProofStatusChanged(
        uint256 indexed chainId, uint256 indexed blockNumber, ProofRequestStatus status
    );

    /// @dev Emitted when Proving Network withdraws funds. Useful for troubleshooting.
    event PaymentWithdrawn(ProvingNetwork indexed by, uint256 amount);

    /// @dev Emitted when Proving Network address is changed. Useful for transparency and catching unintended changes.
    event ProvingNetworkAddressChanged(ProvingNetwork indexed provingNetwork, address addr);

    /// @dev Emitted when Proving Network status is changed. Useful for transparency and serves as communication medium for Proving Networks.
    ///     Proving Networks will filter for events that change their own status.
    event ProvingNetworkStatusChanged(
        ProvingNetwork indexed provingNetwork, ProvingNetworkStatus status
    );

    /// @dev Emitted when Proving Network is set as preferred (once per month). Useful for transparency and troubleshooting.
    event PreferredProvingNetworkSet(ProvingNetwork indexed provingNetwork);

    /*//////////////////////////////////////////
                    Errors
    //////////////////////////////////////////*/

    /// @dev field - what was the "field" for which we tried to set a 0 address (I.E. USDC or Fermah)
    error AddressCannotBeZero(string field);
    error DuplicatedProofRequest(uint256 chainId, uint256 blockNumber);
    error InvalidProofRequestTimeout();
    error NoPaymentDue();
    error OnlyProvingNetworkAllowed(address sender);
    error OnlyProvingNetworkAssigneedAllowed(address sender);
    error ProofRequestAcknowledgementDeadlinePassed();
    error ProofRequestDidNotReachDeadline();
    error ProofRequestProvingDeadlinePassed();
    error ProvingNetworkCannotBeNone();
    error RewardBiggerThanLimit(uint256 reward);
    error TransitionNotAllowed(ProofRequestStatus from, ProofRequestStatus to);
    error TransitionNotAllowedForProofRequestManager(ProofRequestStatus from, ProofRequestStatus to);
    error TransitionNotAllowedForProvingNetwork(ProofRequestStatus from, ProofRequestStatus to);
    error USDCTransferFailed();

    /*//////////////////////////////////////////
            Proving Network Management
    //////////////////////////////////////////*/

    function updateProvingNetworkAddress(ProvingNetwork network, address addr) external;

    function updateProvingNetworkStatus(ProvingNetwork network, ProvingNetworkStatus status)
        external;

    function updatePreferredProvingNetwork(ProvingNetwork network) external;

    /*//////////////////////////////////////////
            Proof Request Management
    //////////////////////////////////////////*/
    function submitProofRequest(
        ProofRequestIdentifier calldata id,
        ProofRequestParams calldata params
    ) external;

    function updateProofRequestStatus(ProofRequestIdentifier calldata id, ProofRequestStatus status)
        external;

    /*//////////////////////////////////////////
            Proving Network Interactions
    //////////////////////////////////////////*/

    function acknowledgeProofRequest(ProofRequestIdentifier calldata id, bool accept) external;

    function submitProof(
        ProofRequestIdentifier calldata id,
        bytes calldata proof,
        uint256 provingNetworkPrice
    ) external;

    function withdraw() external;

    // TODO: add withdraw(to: address)
}
