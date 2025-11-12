// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IProofManager.sol";

/// @title Min-Heap / Priority Queue Library
/// @notice Min-heap keyed by uint256
/// @dev 0-based indexing: parent = (i-1)/2; children = 2*i+1, 2*i+2
library MinHeapLib {
    struct Node {
        uint256 key;   // priority (smaller = higher priority)
        IProofManager.ProofRequestIdentifier proofRequestIdentifier;
    }

    struct Heap {
        Node[] nodes;
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
        return heap.nodes[0];
    }

    // ---------------------------- Mutations ----------------------------

    /// @notice Insert a new (key, value) into the heap.
    function insert(Heap storage heap, uint256 key, uint256 value)
        internal
        returns (uint256 idx)
    {
        heap.nodes.push(Node({key: key, value: value}));
        idx = heap.nodes.length - 1;
        idx = _siftUp(heap, idx); // returns final position after swaps
    }

    /// @notice Remove and return the minimal element.
    function extractMin(Heap storage heap) internal returns (Node memory minNode) {
        uint256 n = heap.nodes.length;
        require(n != 0, "Heap: empty");

        minNode = heap.nodes[0];

        if (n == 1) {
            heap.nodes.pop();
            return minNode;
        }

        // Move last to root, pop, then restore heap
        heap.nodes[0] = heap.nodes[n - 1];
        heap.nodes.pop();
        _siftDown(heap, 0);
    }

    /// @notice Remove and return the element at heap index `idx`.
    /// @dev If you only know an external id -> idx, keep that mapping in your contract.
    function removeAt(Heap storage heap, uint256 idx) internal returns (Node memory removed) {
        uint256 n = heap.nodes.length;
        require(idx < n, "Heap: idx OOB");

        removed = heap.nodes[idx];

        if (idx == n - 1) {
            // last element—just pop
            heap.nodes.pop();
            return removed;
        }

        // Replace idx with last, pop, then fix heap both directions
        heap.nodes[idx] = heap.nodes[n - 1];
        heap.nodes.pop();

        // We don't know if the new node at idx should go up or down.
        // Try both directions: a bounded number of swaps either way.
        if (idx > 0 && heap.nodes[idx].key < heap.nodes[(idx - 1) / 2].key) {
            _siftUp(heap, idx);
        } else {
            _siftDown(heap, idx);
        }
    }

    // ---------------------------- Internal heap ops ----------------------------

    function _siftUp(Heap storage heap, uint256 idx) private {
        while (idx > 0) {
            uint256 parent = (idx - 1) / 2;
            if (heap.nodes[idx].key >= heap.nodes[parent].key) break;
            _swap(heap, idx, parent);
            idx = parent;
        }
    }

    function _siftDown(Heap storage heap, uint256 idx) private {
        uint256 n = heap.nodes.length;
        while (true) {
            uint256 left = 2 * idx + 1;
            if (left >= n) break;

            uint256 right = left + 1;
            uint256 smallest = left;

            if (right < n && heap.nodes[right].key < heap.nodes[left].key) {
                smallest = right;
            }

            if (heap.nodes[idx].key <= heap.nodes[smallest].key) break;

            _swap(heap, idx, smallest);
            idx = smallest;
        }
    }

    function _swap(Heap storage heap, uint256 i, uint256 j) private {
        if (i == j) return;
        Node memory tmp = heap.nodes[i];
        heap.nodes[i] = heap.nodes[j];
        heap.nodes[j] = tmp;
    }
}
