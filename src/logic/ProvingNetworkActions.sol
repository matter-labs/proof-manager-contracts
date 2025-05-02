// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.29;

import "../store/ProofManagerStorage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @author Matter Labs
/// @notice This contract is used for Proving Networks to interact with proof requests.
abstract contract ProvingNetworkActions is ProofManagerStorage {
    /*////////////////////////
            Modifiers
    ////////////////////////*/

    /// @dev You need to be a proving network to call this function.
    modifier onlyProvingNetwork() {
        require(
            msg.sender == _provingNetworks[ProvingNetwork.Fermah].addr
                || msg.sender == _provingNetworks[ProvingNetwork.Lagrange].addr,
            "only proving network"
        );
        _;
    }

    /// @dev You need the proof request to be assigned to you to call this function.
    modifier onlyAssignee(ProofRequestIdentifier calldata id) {
        require(
            msg.sender
                == _provingNetworks[_proofRequests[id.chainId][id.blockNumber].assignedTo].addr,
            "only proving network assignee"
        );
        _;
    }

    /* immutable injected via constructor of final contract */
    /// @dev USDC contract address, injected via constructor from ProofManager. Used for withdrawals.
    function _USDC() internal view virtual returns (IERC20);

    /*////////////////////////
            Public API
    ////////////////////////*/

    /// @dev Acknowledges a proof request. The proving network can either commit to prove or refuse (due to price, availability, etc).
    function acknowledgeProofRequest(ProofRequestIdentifier calldata id, bool accept)
        external
        onlyAssignee(id)
    {
        // NOTE: Checking if the proof request exists is not necessary. By default, a proof request that doesn't exist is assigned to ProvingNetwork None.
        //      As such, onlyAssignee(id) will fail.
        ProofRequest storage proofRequest = _proofRequests[id.chainId][id.blockNumber];
        require(
            proofRequest.status == ProofRequestStatus.Ready,
            "cannot acknowledge proof request that is not ready"
        );
        require(
            block.timestamp <= proofRequest.submittedAt + ACK_TIMEOUT,
            "proof request passed acknowledgement deadline"
        );

        proofRequest.status = accept ? ProofRequestStatus.Committed : ProofRequestStatus.Refused;

        emit ProofStatusChanged(id.chainId, id.blockNumber, proofRequest.status);
    }

    /// @dev Submit proof for proof request.
    function submitProof(
        ProofRequestIdentifier calldata id,
        bytes calldata proof,
        uint256 provingNetworkPrice
    ) external onlyAssignee(id) {
        ProofRequest storage proofRequest = _proofRequests[id.chainId][id.blockNumber];
        require(
            proofRequest.status == ProofRequestStatus.Committed,
            "cannot submit proof for non committed proof request"
        );
        require(
            block.timestamp <= proofRequest.submittedAt + proofRequest.timeoutAfter,
            "proof request passed proving deadline"
        );

        proofRequest.status = ProofRequestStatus.Proven;
        proofRequest.proof = proof;
        proofRequest.provingNetworkPrice = provingNetworkPrice <= proofRequest.maxReward
            ? provingNetworkPrice
            : proofRequest.maxReward;

        emit ProofStatusChanged(id.chainId, id.blockNumber, proofRequest.status);
    }

    /// @dev Withdraws payment for already validated proofs, up to WITHDRAW_LIMIT.
    ///     NOTE: Successive calls can be made if you reached the limit.
    function withdraw() external onlyProvingNetwork {
        ProvingNetwork provingNetwork = msg.sender == _provingNetworks[ProvingNetwork.Fermah].addr
            ? ProvingNetwork.Fermah
            : ProvingNetwork.Lagrange;

        ProvingNetworkInfo storage info = _provingNetworks[provingNetwork];
        uint256 payableAmount = info.paymentDue;
        require(payableAmount > 0, "no payment due");

        if (payableAmount > WITHDRAW_LIMIT) {
            payableAmount = WITHDRAW_LIMIT;
        }

        uint256 paid = 0;
        uint256 i = 0;

        while (i < info.unclaimedProofs.length && paid < payableAmount) {
            ProofRequestIdentifier memory id = info.unclaimedProofs[i];

            ProofRequest storage proofRequest = _proofRequests[id.chainId][id.blockNumber];

            uint256 price = proofRequest.provingNetworkPrice;
            if (paid + price > payableAmount) break;

            proofRequest.status = ProofRequestStatus.Paid;
            paid += price;

            // swap and pop to reduce gas utilization
            info.unclaimedProofs[i] = info.unclaimedProofs[info.unclaimedProofs.length - 1];
            info.unclaimedProofs.pop();
        }

        info.paymentDue -= paid;
        // sanity check, "should never happen"
        require(paid > 0, "paid==0");

        require(_USDC().transfer(msg.sender, paid), "USDC transfer fail");
        emit PaymentWithdrawn(provingNetwork, paid);
    }
}
