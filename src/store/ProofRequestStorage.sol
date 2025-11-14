// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IProofManager.sol";

/// @title Min-Heap / Priority Queue Library
/// @notice Min-heap keyed by uint256
/// @dev 1-based indexing: 0 is the root parent = i/2; children = 2*i, 2*i+1
library ProofRequestStorageLib {
    struct Node {
        uint256 key; // priority (smaller = higher priority)
        IProofManager.ProofRequestIdentifier proofRequestIdentifier;
    }

    struct Heap {
        Node[] nodes;

        /// @dev Mapping for the heap index of the proof request. (ProofRequestIdentifier => heapIndex)
        mapping(uint256 chainId => mapping(uint256 blockNumber => uint256 heapIndex)) heapIndexes;
    }

    // ---------------------------- View helpers ----------------------------

    function size(Heap storage heap) internal view returns (uint256) {
        return heap.nodes.length;
    }

    function isEmpty(Heap storage heap) internal view returns (bool) {
        return heap.nodes.length == 0;
    }

    /// @notice Read the minimal element without removing it.
    function peek(Heap storage heap) internal view returns (Node memory) {
        require(heap.nodes.length != 0, "Heap: empty");
        return heap.nodes[1];
    }

    function getHeapIndex(
        Heap storage heap,
        IProofManager.ProofRequestIdentifier memory proofRequestIdentifier
    ) internal view returns (uint256) {
        return heap.heapIndexes[proofRequestIdentifier.chainId][proofRequestIdentifier.blockNumber];
    }

    // ---------------------------- Mutations ----------------------------

    /// @notice Insert a new (key, value) into the heap.
    function addProofRequest(
        Heap storage heap,
        uint256 key,
        IProofManager.ProofRequestIdentifier memory proofRequestIdentifier
    ) internal {
        heap.nodes.push(Node({ key: key, proofRequestIdentifier: proofRequestIdentifier }));
        uint256 idx = heap.nodes.length;
        heap.heapIndexes[proofRequestIdentifier.chainId][proofRequestIdentifier.blockNumber] = idx;

        _siftUp(heap, idx);
    }

    /// @notice Remove and return the minimal element.
    function extractMin(Heap storage heap) internal returns (Node memory minNode) {
        require(heap.nodes.length <= 1, "Heap: empty");

        minNode = heap.nodes[1];

        if (heap.nodes.length == 2) {
            heap.nodes.pop();
            heap.heapIndexes[
                minNode.proofRequestIdentifier.chainId
            ][minNode.proofRequestIdentifier.blockNumber] = 0;
            return minNode;
        }

        // Move last to root, pop, then restore heap
        heap.nodes[1] = heap.nodes[heap.nodes.length - 1];
        heap.nodes.pop();
        _siftDown(heap, 0);

        heap.heapIndexes[
            minNode.proofRequestIdentifier.chainId
        ][minNode.proofRequestIdentifier.blockNumber] = 0;
    }

    /// @notice Remove and return the element at heap index `idx`.
    /// @dev If you only know an external id -> idx, keep that mapping in your contract.
    function removeAt(
        Heap storage heap,
        IProofManager.ProofRequestIdentifier memory proofRequestIdentifier
    ) public {
        uint256 idx = heap.heapIndexes[
            proofRequestIdentifier.chainId
        ][proofRequestIdentifier.blockNumber];
        require(idx < heap.nodes.length, "Heap: idx OOB");

        Node memory removed = heap.nodes[idx];

        if (idx == heap.nodes.length - 1) {
            heap.nodes.pop();

            heap.heapIndexes[proofRequestIdentifier.chainId][proofRequestIdentifier.blockNumber] = 0;

            return;
        }

        // Replace idx with last, pop, then fix heap both directions
        heap.nodes[idx] = heap.nodes[heap.nodes.length - 1];
        heap.nodes.pop();

        if (idx > 0 && heap.nodes[idx].key < heap.nodes[idx / 2].key) {
            _siftUp(heap, idx);
        } else {
            _siftDown(heap, idx);
        }

        heap.heapIndexes[proofRequestIdentifier.chainId][proofRequestIdentifier.blockNumber] = 0;
    }

    // ---------------------------- Internal heap ops ----------------------------

    function _siftUp(Heap storage heap, uint256 idx) private {
        while (idx > 1) {
            uint256 parent = idx / 2;
            if (heap.nodes[idx].key >= heap.nodes[parent].key) break;
            _swap(heap, idx, parent);
            idx = parent;
        }
    }

    function _siftDown(Heap storage heap, uint256 idx) private {
        while (idx < heap.nodes.length) {
            uint256 left = 2 * idx;
            if (left >= heap.nodes.length) break;

            uint256 right = left + 1;
            uint256 smallest = left;

            if (right < heap.nodes.length && heap.nodes[right].key < heap.nodes[left].key) {
                smallest = right;
            }

            if (heap.nodes[idx].key <= heap.nodes[smallest].key) break;

            _swap(heap, idx, smallest);
            idx = smallest;
        }
    }

    function _swap(Heap storage heap, uint256 i, uint256 j) private {
        if (i == j) return;

        Node memory ni = heap.nodes[i];
        Node memory nj = heap.nodes[j];

        heap.nodes[i] = nj;
        heap.nodes[j] = ni;

        heap.heapIndexes[ni.proofRequestIdentifier.chainId][ni.proofRequestIdentifier.blockNumber] =
            j;
        heap.heapIndexes[nj.proofRequestIdentifier.chainId][nj.proofRequestIdentifier.blockNumber] =
            i;
    }
}
