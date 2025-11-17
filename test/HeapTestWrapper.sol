// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../src/store/MinHeapLib.sol";
import "../src/interfaces/IProofManager.sol";

contract HeapTestWrapper {
    using MinHeapLib for MinHeapLib.Heap;

    MinHeapLib.Heap internal heap;

    function add(uint256 key, uint256 chainId, uint256 blockNumber) external {
        IProofManager.ProofRequestIdentifier memory id =
            IProofManager.ProofRequestIdentifier({ chainId: chainId, blockNumber: blockNumber });
        heap.addProofRequest(key, id);
    }

    function extractMin() external returns (uint256 key, uint256 chainId, uint256 blockNumber) {
        MinHeapLib.Node memory node = heap.extractMin();
        key = node.key;
        chainId = node.proofRequestIdentifier.chainId;
        blockNumber = node.proofRequestIdentifier.blockNumber;
    }

    function remove(uint256 chainId, uint256 blockNumber) external {
        IProofManager.ProofRequestIdentifier memory id =
            IProofManager.ProofRequestIdentifier({ chainId: chainId, blockNumber: blockNumber });
        heap.removeAt(id);
    }

    function replaceKey(uint256 chainId, uint256 blockNumber, uint256 newKey) external {
        IProofManager.ProofRequestIdentifier memory id =
            IProofManager.ProofRequestIdentifier({ chainId: chainId, blockNumber: blockNumber });
        heap.replaceAt(id, newKey);
    }

    function getIndex(uint256 chainId, uint256 blockNumber) external view returns (uint256) {
        IProofManager.ProofRequestIdentifier memory id =
            IProofManager.ProofRequestIdentifier({ chainId: chainId, blockNumber: blockNumber });
        return heap.getHeapIndex(id);
    }

    function size() external view returns (uint256) {
        return heap.size();
    }

    function isEmpty() external view returns (bool) {
        return heap.isEmpty();
    }

    function peek() external view returns (uint256 key, uint256 chainId, uint256 blockNumber) {
        MinHeapLib.Node memory node = heap.peek();
        key = node.key;
        chainId = node.proofRequestIdentifier.chainId;
        blockNumber = node.proofRequestIdentifier.blockNumber;
    }
}
