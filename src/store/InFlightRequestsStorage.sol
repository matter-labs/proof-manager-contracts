// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IProofManager.sol";

library QueueLib {
    struct Request {
        IProofManager.ProofRequestIdentifier id;
        uint256 expirationTimestamp;
    }

    struct Queue {
        Request[] requests;
        uint256 startIndex;
    }

    function purgeExpired(
        Queue storage self,
        uint256 maxIterations,
        mapping(
            uint256 chainId => mapping(uint256 blockNumber => IProofManager.ProofRequest)
        ) storage requests,
        IProofManager.ProofRequestStatus status
    ) internal {
        while (
            self.startIndex < self.requests.length
                && (block.timestamp > self.requests[self.startIndex].expirationTimestamp
                    || requests[self.requests[self.startIndex].id
                            .chainId][self.requests[self.startIndex].id.blockNumber].status
                        != status) && maxIterations > 0
        ) {
            self.startIndex++;
            maxIterations--;
        }
    }

    function size(Queue storage self) internal view returns (uint256) {
        return self.requests.length - self.startIndex;
    }

    function add(
        Queue storage self,
        IProofManager.ProofRequestIdentifier memory id,
        uint256 expirationTimestamp
    ) internal {
        self.requests.push(Request({ id: id, expirationTimestamp: expirationTimestamp }));
    }
}

library InFlightRequestsStorageLib {
    using QueueLib for QueueLib.Queue;

    enum QueueId {
        Red,
        Blue
    }

    struct InFlightRequestStorage {
        QueueLib.Queue pendingAcknowledgmentQueue;
        QueueLib.Queue acknowledgedQueueRed;
        QueueLib.Queue acknowledgedQueueBlue;

        uint256 redQueueTimeout;
        uint256 blueQueueTimeout;

        QueueId mainQueue;

        uint256 maxIterations;
    }

    function setMaxIterations(InFlightRequestStorage storage self, uint256 maxIterations) internal {
        self.maxIterations = maxIterations;
    }

    function addNewTimeoutAfter(InFlightRequestStorage storage self, uint256 newTimeoutAfter)
        internal
    {
        if (self.mainQueue == QueueId.Red && self.acknowledgedQueueBlue.size() == 0) {
            self.blueQueueTimeout = newTimeoutAfter;
            self.mainQueue = QueueId.Blue;
        } else if (self.mainQueue == QueueId.Blue && self.acknowledgedQueueRed.size() == 0) {
            self.redQueueTimeout = newTimeoutAfter;
            self.mainQueue = QueueId.Red;
        } else {
            revert CannotChangeMainQueueWhenOldIsNotEmpty(self.mainQueue);
        }
    }

    error CannotChangeMainQueueWhenOldIsNotEmpty(QueueId mainQueue);

    function addPendingAcknowledgment(
        InFlightRequestStorage storage self,
        IProofManager.ProofRequestIdentifier memory id,
        uint256 expirationTimestamp
    ) internal {
        self.pendingAcknowledgmentQueue.add(id, expirationTimestamp);
    }

    function addAcknowledged(
        InFlightRequestStorage storage self,
        IProofManager.ProofRequestIdentifier memory id,
        uint256 timeoutAfter,
        uint256 expirationTimestamp
    ) internal {
        if (timeoutAfter == self.redQueueTimeout) {
            self.acknowledgedQueueRed.add(id, expirationTimestamp);
        } else if (timeoutAfter == self.blueQueueTimeout) {
            self.acknowledgedQueueBlue.add(id, expirationTimestamp);
        } else {
            revert UnsupportedTimeoutAfter(
                timeoutAfter, self.redQueueTimeout, self.blueQueueTimeout
            );
        }
    }

    error UnsupportedTimeoutAfter(
        uint256 timeoutAfter, uint256 redQueueTimeout, uint256 blueQueueTimeout
    );

    function purgeExpired(
        InFlightRequestStorage storage self,
        mapping(
            uint256 chainId => mapping(uint256 blockNumber => IProofManager.ProofRequest)
        ) storage proofRequests
    ) internal {
        self.pendingAcknowledgmentQueue
            .purgeExpired(
                self.maxIterations,
                proofRequests,
                IProofManager.ProofRequestStatus.PendingAcknowledgement
            );
        self.acknowledgedQueueRed
            .purgeExpired(
                self.maxIterations, proofRequests, IProofManager.ProofRequestStatus.Committed
            );
        self.acknowledgedQueueBlue
            .purgeExpired(
                self.maxIterations, proofRequests, IProofManager.ProofRequestStatus.Committed
            );
    }

    function size(InFlightRequestStorage storage self) internal view returns (uint256) {
        return self.pendingAcknowledgmentQueue.size() + self.acknowledgedQueueRed.size()
            + self.acknowledgedQueueBlue.size();
    }
}
