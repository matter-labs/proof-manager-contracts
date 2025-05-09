// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

/*////////////////////////
        Errors
////////////////////////*/

// TODO: add later

/*////////////////////////
        Events
////////////////////////*/

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

/*////////////////////////
        Types
////////////////////////*/

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

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @title ProofManager contract interface
interface IProofManager {
    /*////////////////////////
            Administrator
    ////////////////////////*/

    function updateProvingNetworkAddress(ProvingNetwork network, address addr) external;

    function updateProvingNetworkStatus(ProvingNetwork network, ProvingNetworkStatus status)
        external;

    function updatePreferredProvingNetwork(ProvingNetwork network) external;

    /*////////////////////////
        Proving Network
    ////////////////////////*/

    function acknowledgeProofRequest(ProofRequestIdentifier calldata id, bool accept) external;

    function submitProof(
        ProofRequestIdentifier calldata id,
        bytes calldata proof,
        uint256 provingNetworkPrice
    ) external;

    function withdraw() external;

    // TODO: add withdraw(to: address)

    /*////////////////////////
            Sequencer
    ////////////////////////*/
    function submitProofRequest(
        ProofRequestIdentifier calldata id,
        ProofRequestParams calldata params
    ) external;

    function updateProofRequestStatus(ProofRequestIdentifier calldata id, ProofRequestStatus status)
        external;
}
