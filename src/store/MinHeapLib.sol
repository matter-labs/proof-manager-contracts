// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IProofManager } from "../interfaces/IProofManager.sol";

/// @title MinHeapLib
/// @notice A library implementing a min-heap data structure for managing proof request identifiers
///         with priority-based ordering. The heap maintains O(log n) insertion and extraction,
///         and O(1) lookup via a mapping from proof request identifiers to heap indices.
/// @dev The heap uses a 1-based indexing scheme with a sentinel node at index 0 to simplify
///      parent/child calculations. The heap property ensures that the root node always has
///      the minimum key value.
library MinHeapLib {
    /// @notice Represents a single node in the heap
    /// @param key The priority key (smaller values have higher priority)
    /// @param proofRequestIdentifier The proof request identifier associated with this node
    struct Node {
        uint256 key; // priority (smaller = higher priority)
        IProofManager.ProofRequestIdentifier proofRequestIdentifier;
    }

    /// @notice The heap data structure
    /// @param nodes Array of nodes, with index 0 reserved as a sentinel node
    /// @param heapIndexes Mapping from (chainId, blockNumber) to heap index (1-based, 0 = not present)
    ///                    Enables O(1) lookup of nodes by their proof request identifier
    struct Heap {
        Node[] nodes;
        // heapIndexes[chainId][blockNumber] = heapIndex (1-based, 0 = not present)
        mapping(uint256 chainId => mapping(uint256 blockNumber => uint256 heapIndex)) heapIndexes;
    }

    // ---------------------------- View helpers ----------------------------

    /// @notice Returns the number of elements in the heap
    /// @param heap The heap to query
    /// @return The number of elements (excluding the sentinel node at index 0)
    function size(Heap storage heap) internal view returns (uint256) {
        if (heap.nodes.length == 0) return 0;
        // nodes[0] is sentinel
        return heap.nodes.length - 1;
    }

    /// @notice Checks if the heap is empty
    /// @param heap The heap to check
    /// @return True if the heap contains no elements, false otherwise
    function isEmpty(Heap storage heap) internal view returns (bool) {
        return size(heap) == 0;
    }

    /// @notice Returns the minimum element (root) without removing it
    /// @param heap The heap to peek at
    /// @return The node with the minimum key value
    /// @dev Reverts if the heap is empty
    function peek(Heap storage heap) internal view returns (Node memory) {
        require(!isEmpty(heap), "Heap: empty");
        return heap.nodes[1];
    }

    /// @notice Gets the heap index for a given proof request identifier
    /// @param heap The heap to query
    /// @param proofRequestIdentifier The proof request identifier to look up
    /// @return The 1-based heap index, or 0 if the identifier is not in the heap
    function getHeapIndex(
        Heap storage heap,
        IProofManager.ProofRequestIdentifier memory proofRequestIdentifier
    ) internal view returns (uint256) {
        return heap.heapIndexes[proofRequestIdentifier.chainId][proofRequestIdentifier.blockNumber];
    }

    // ---------------------------- Mutations ----------------------------

    /// @notice Adds a new proof request to the heap
    /// @param heap The heap to add to
    /// @param key The priority key for the proof request (smaller = higher priority)
    /// @param proofRequestIdentifier The proof request identifier to add
    /// @dev Automatically initializes the sentinel node if the heap is empty.
    ///      The new node is added at the end and then sifted up to maintain heap property.
    function addProofRequest(
        Heap storage heap,
        uint256 key,
        IProofManager.ProofRequestIdentifier memory proofRequestIdentifier
    ) internal {
        // Ensure sentinel at index 0
        if (heap.nodes.length == 0) {
            heap.nodes.push(); // empty slot at index 0
        }

        heap.nodes.push(Node({ key: key, proofRequestIdentifier: proofRequestIdentifier }));
        uint256 idx = heap.nodes.length - 1; // 1-based

        heap.heapIndexes[proofRequestIdentifier.chainId][proofRequestIdentifier.blockNumber] = idx;

        _siftUp(heap, idx);
    }

    /// @notice Removes and returns the minimum element from the heap
    /// @param heap The heap to extract from
    /// @return minNode The node with the minimum key value
    /// @dev Reverts if the heap is empty. After extraction, the last element is moved
    ///      to the root and sifted down to restore the heap property.
    function extractMin(Heap storage heap) internal returns (Node memory minNode) {
        require(!isEmpty(heap), "Heap: empty");

        minNode = heap.nodes[1];

        // Only one real element (sentinel + root)
        if (heap.nodes.length == 2) {
            heap.nodes.pop(); // remove root, sentinel remains
        } else {
            // Move last to root
            Node memory moved = heap.nodes[heap.nodes.length - 1];
            heap.nodes[1] = moved;
            heap.nodes.pop();

            // Update mapping for moved node
            heap.heapIndexes[
                moved.proofRequestIdentifier.chainId
            ][moved.proofRequestIdentifier.blockNumber] = 1;

            _siftDown(heap, 1);
        }

        // Clear mapping for removed node
        heap.heapIndexes[
            minNode.proofRequestIdentifier.chainId
        ][minNode.proofRequestIdentifier.blockNumber] = 0;
    }

    /// @notice Removes a specific proof request from the heap by its identifier
    /// @param heap The heap to remove from
    /// @param proofRequestIdentifier The proof request identifier to remove
    /// @dev Reverts if the identifier is not found in the heap. The last element
    ///      replaces the removed element and is sifted up or down to restore heap property.
    function remove(
        Heap storage heap,
        IProofManager.ProofRequestIdentifier memory proofRequestIdentifier
    ) public {
        uint256 idx = heap.heapIndexes[
            proofRequestIdentifier.chainId
        ][proofRequestIdentifier.blockNumber];
        require(idx != 0 && idx < heap.nodes.length, "Heap: idx OOB");

        uint256 lastIdx = heap.nodes.length - 1;

        if (idx == lastIdx) {
            // Just pop last
            heap.nodes.pop();
            heap.heapIndexes[proofRequestIdentifier.chainId][proofRequestIdentifier.blockNumber] = 0;
            return;
        }

        // Replace idx with last
        Node memory moved = heap.nodes[lastIdx];
        heap.nodes[idx] = moved;
        heap.nodes.pop();

        // Update mapping for moved node
        heap.heapIndexes[
            moved.proofRequestIdentifier.chainId
        ][moved.proofRequestIdentifier.blockNumber] = idx;

        // Restore heap property
        if (idx > 1 && heap.nodes[idx].key < heap.nodes[idx / 2].key) {
            _siftUp(heap, idx);
        } else {
            _siftDown(heap, idx);
        }

        // Clear mapping for removed node
        heap.heapIndexes[proofRequestIdentifier.chainId][proofRequestIdentifier.blockNumber] = 0;
    }

    /// @notice Updates the key of an existing proof request in the heap
    /// @param heap The heap to update
    /// @param proofRequestIdentifier The proof request identifier to update
    /// @param newKey The new key value
    /// @dev Reverts if the identifier is not found in the heap. After updating the key,
    ///      the node is sifted up or down to restore the heap property.
    function replaceAt(
        Heap storage heap,
        IProofManager.ProofRequestIdentifier memory proofRequestIdentifier,
        uint256 newKey
    ) public {
        uint256 idx = heap.heapIndexes[
            proofRequestIdentifier.chainId
        ][proofRequestIdentifier.blockNumber];
        require(idx != 0 && idx < heap.nodes.length, "Heap: idx OOB");

        heap.nodes[idx].key = newKey;

        // Restore heap property
        if (idx > 1 && heap.nodes[idx].key < heap.nodes[idx / 2].key) {
            _siftUp(heap, idx);
        } else {
            _siftDown(heap, idx);
        }
    }

    // ---------------------------- Internal heap ops ----------------------------

    /// @notice Moves a node up the heap until the heap property is satisfied
    /// @param heap The heap to operate on
    /// @param idx The 1-based index of the node to sift up
    /// @dev Compares the node with its parent and swaps if the node's key is smaller.
    ///      Continues until the node is at the root or its parent has a smaller key.
    function _siftUp(Heap storage heap, uint256 idx) private {
        while (idx > 1) {
            uint256 parent = idx / 2;
            if (heap.nodes[idx].key >= heap.nodes[parent].key) break;
            _swap(heap, idx, parent);
            idx = parent;
        }
    }

    /// @notice Moves a node down the heap until the heap property is satisfied
    /// @param heap The heap to operate on
    /// @param idx The 1-based index of the node to sift down
    /// @dev Compares the node with its children and swaps with the smallest child if needed.
    ///      Continues until the node is a leaf or both children have larger keys.
    function _siftDown(Heap storage heap, uint256 idx) private {
        uint256 n = heap.nodes.length;
        while (true) {
            uint256 left = 2 * idx;
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

    /// @notice Swaps two nodes in the heap and updates their index mappings
    /// @param heap The heap to operate on
    /// @param i The 1-based index of the first node
    /// @param j The 1-based index of the second node
    /// @dev Updates both the nodes array and the heapIndexes mapping to maintain consistency.
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
