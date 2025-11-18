// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IProofManager.sol";

library MinHeapLib {
    struct Node {
        uint256 key; // priority (smaller = higher priority)
        IProofManager.ProofRequestIdentifier proofRequestIdentifier;
    }

    struct Heap {
        Node[] nodes;
        // heapIndexes[chainId][blockNumber] = heapIndex (1-based, 0 = not present)
        mapping(uint256 chainId => mapping(uint256 blockNumber => uint256 heapIndex)) heapIndexes;
    }

    // ---------------------------- View helpers ----------------------------

    function size(Heap storage heap) internal view returns (uint256) {
        if (heap.nodes.length == 0) return 0;
        // nodes[0] is sentinel
        return heap.nodes.length - 1;
    }

    function isEmpty(Heap storage heap) internal view returns (bool) {
        return size(heap) == 0;
    }

    function peek(Heap storage heap) internal view returns (Node memory) {
        require(size(heap) > 0, "Heap: empty");
        return heap.nodes[1];
    }

    function getHeapIndex(
        Heap storage heap,
        IProofManager.ProofRequestIdentifier memory proofRequestIdentifier
    ) internal view returns (uint256) {
        return heap.heapIndexes[proofRequestIdentifier.chainId][proofRequestIdentifier.blockNumber];
    }

    // ---------------------------- Mutations ----------------------------

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

    function extractMin(Heap storage heap) internal returns (Node memory minNode) {
        require(size(heap) > 0, "Heap: empty");

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

    function remove(
        Heap storage heap,
        IProofManager.ProofRequestIdentifier memory proofRequestIdentifier
    ) public {
        uint256 idx = heap.heapIndexes[
            proofRequestIdentifier.chainId
        ][proofRequestIdentifier.blockNumber];
        require(idx != 0 && idx < heap.nodes.length, "Heap: idx OOB");

        Node memory removed = heap.nodes[idx];

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

    function _siftUp(Heap storage heap, uint256 idx) private {
        while (idx > 1) {
            uint256 parent = idx / 2;
            if (heap.nodes[idx].key >= heap.nodes[parent].key) break;
            _swap(heap, idx, parent);
            idx = parent;
        }
    }

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
