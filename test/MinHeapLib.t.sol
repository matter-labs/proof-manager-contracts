// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/store/MinHeapLib.sol";
import "../src/interfaces/IProofManager.sol";
import "./HeapTestWrapper.sol"; // or adjust path if you place it elsewhere

contract MinHeapLibTest is Test {
    HeapTestWrapper internal heapWrapper;

    function setUp() public {
        heapWrapper = new HeapTestWrapper();
    }

    // ---------------------------
    // Basic add / size / peek
    // ---------------------------

    function test_AddSingleElement() public {
        heapWrapper.add(10, 1, 100);
        assertEq(heapWrapper.size(), 1);
        assertFalse(heapWrapper.isEmpty());

        (uint256 key, uint256 chainId, uint256 blockNumber) = heapWrapper.peek();
        assertEq(key, 10);
        assertEq(chainId, 1);
        assertEq(blockNumber, 100);

        uint256 idx = heapWrapper.getIndex(1, 100);
        assertEq(idx, 1); // first real node is at index 1
    }

    function test_AddMultipleAndPeekMin() public {
        // Keys are 50, 20, 30 – min is 20 (chainId 2, block 200)
        heapWrapper.add(50, 1, 100);
        heapWrapper.add(20, 2, 200);
        heapWrapper.add(30, 3, 300);

        assertEq(heapWrapper.size(), 3);

        (uint256 key, uint256 chainId, uint256 blockNumber) = heapWrapper.peek();
        assertEq(key, 20);
        assertEq(chainId, 2);
        assertEq(blockNumber, 200);
    }

    // ---------------------------
    // extractMin behavior
    // ---------------------------

    function test_ExtractMinReturnsInSortedOrder() public {
        heapWrapper.add(50, 1, 100);
        heapWrapper.add(20, 2, 200);
        heapWrapper.add(30, 3, 300);
        heapWrapper.add(10, 4, 400);

        assertEq(heapWrapper.size(), 4);

        (uint256 k1, uint256 c1, uint256 b1) = heapWrapper.extractMin();
        (uint256 k2, uint256 c2, uint256 b2) = heapWrapper.extractMin();
        (uint256 k3, uint256 c3, uint256 b3) = heapWrapper.extractMin();
        (uint256 k4, uint256 c4, uint256 b4) = heapWrapper.extractMin();

        assertEq(k1, 10);
        assertEq(c1, 4);
        assertEq(b1, 400);

        assertEq(k2, 20);
        assertEq(c2, 2);
        assertEq(b2, 200);

        assertEq(k3, 30);
        assertEq(c3, 3);
        assertEq(b3, 300);

        assertEq(k4, 50);
        assertEq(c4, 1);
        assertEq(b4, 100);

        // Now heap is empty
        assertTrue(heapWrapper.isEmpty());
        assertEq(heapWrapper.size(), 0);

        // Indexes should all be zero now
        assertEq(heapWrapper.getIndex(1, 100), 0);
        assertEq(heapWrapper.getIndex(2, 200), 0);
        assertEq(heapWrapper.getIndex(3, 300), 0);
        assertEq(heapWrapper.getIndex(4, 400), 0);
    }

    function test_ExtractMinOnSingleElementLeavesHeapEmpty() public {
        heapWrapper.add(42, 10, 1000);

        (uint256 key, uint256 chainId, uint256 blockNumber) = heapWrapper.extractMin();
        assertEq(key, 42);
        assertEq(chainId, 10);
        assertEq(blockNumber, 1000);

        assertTrue(heapWrapper.isEmpty());
        assertEq(heapWrapper.size(), 0);
        assertEq(heapWrapper.getIndex(10, 1000), 0);
    }

    function test_Revert_ExtractMinOnEmptyHeap() public {
        vm.expectRevert("Heap: empty");
        heapWrapper.extractMin();
    }

    function test_Revert_PeekOnEmptyHeap() public {
        vm.expectRevert("Heap: empty");
        heapWrapper.peek();
    }

    // ---------------------------
    // removeAt behavior
    // ---------------------------

    function test_RemoveLastElementViaRemoveAt() public {
        // Arrange: 2 nodes
        heapWrapper.add(10, 1, 100);
        heapWrapper.add(20, 2, 200);

        // Remove node with chainId=2, blockNumber=200 (likely last node)
        heapWrapper.remove(2, 200);

        assertEq(heapWrapper.size(), 1);
        assertEq(heapWrapper.getIndex(2, 200), 0); // cleared
        assertTrue(heapWrapper.getIndex(1, 100) != 0);

        // Only remaining node should be (1,100)
        (uint256 key, uint256 chainId, uint256 blockNumber) = heapWrapper.peek();
        assertEq(key, 10);
        assertEq(chainId, 1);
        assertEq(blockNumber, 100);
    }

    function test_RemoveMiddleElementAndCheckMapping() public {
        // Make sure we have >2 nodes in some order
        heapWrapper.add(50, 1, 100);
        heapWrapper.add(20, 2, 200);
        heapWrapper.add(30, 3, 300);

        uint256 idx1Before = heapWrapper.getIndex(1, 100);
        uint256 idx2Before = heapWrapper.getIndex(2, 200);
        uint256 idx3Before = heapWrapper.getIndex(3, 300);
        assertGt(idx1Before, 0);
        assertGt(idx2Before, 0);
        assertGt(idx3Before, 0);

        // Remove node (2,200) – mapping for it should be zero afterwards
        heapWrapper.remove(2, 200);
        assertEq(heapWrapper.getIndex(2, 200), 0);

        // The others should still have non-zero index
        assertGt(heapWrapper.getIndex(1, 100), 0);
        assertGt(heapWrapper.getIndex(3, 300), 0);

        // Size should be 2 now
        assertEq(heapWrapper.size(), 2);
    }

    function test_Revert_RemoveNonExistingNode() public {
        // Heap is empty
        vm.expectRevert(bytes("Heap: idx OOB"));
        heapWrapper.remove(999, 999);
    }

    // ---------------------------
    // replaceAt behavior
    // ---------------------------

    function test_ReplaceAt_DecreaseKey_SiftsUp() public {
        // Make a heap where node (2,200) is not the min initially
        heapWrapper.add(50, 1, 100); // bigger
        heapWrapper.add(30, 2, 200); // medium
        heapWrapper.add(10, 3, 300); // smallest

        (uint256 keyBefore,,) = heapWrapper.peek();
        assertEq(keyBefore, 10); // min is key=10 (3,300)

        // Now decrease key of (2,200) to 1 -> should become new min
        heapWrapper.replaceKey(2, 200, 1);

        (uint256 keyAfter, uint256 cAfter, uint256 bAfter) = heapWrapper.peek();
        assertEq(keyAfter, 1);
        assertEq(cAfter, 2);
        assertEq(bAfter, 200);
    }

    function test_ReplaceAt_IncreaseKey_SiftsDown() public {
        // Setup:
        //  key=10 => (1,100)
        //  key=20 => (2,200)
        //  key=30 => (3,300)
        heapWrapper.add(10, 1, 100);
        heapWrapper.add(20, 2, 200);
        heapWrapper.add(30, 3, 300);

        (uint256 keyBefore,,) = heapWrapper.peek();
        assertEq(keyBefore, 10);

        // Increase key of min node (1,100) to 40
        heapWrapper.replaceKey(1, 100, 40);

        // New min should be key=20 (2,200)
        (uint256 keyAfter, uint256 cAfter, uint256 bAfter) = heapWrapper.peek();
        assertEq(keyAfter, 20);
        assertEq(cAfter, 2);
        assertEq(bAfter, 200);

        // Check mapping is still valid for all nodes
        assertGt(heapWrapper.getIndex(1, 100), 0);
        assertGt(heapWrapper.getIndex(2, 200), 0);
        assertGt(heapWrapper.getIndex(3, 300), 0);
    }

    function test_Revert_ReplaceNonExistingNode() public {
        vm.expectRevert(bytes("Heap: idx OOB"));
        heapWrapper.replaceKey(42, 42, 100);
    }

    // ---------------------------
    // Fuzzy-ish property test
    // ---------------------------

    function testFuzz_HeapPropertyMaintained(uint256[10] memory keys) public {
        // normalize keys to a smaller range to avoid overflows / giant gas
        for (uint256 i = 0; i < 10; i++) {
            uint256 k = keys[i] % 1_000_000;
            heapWrapper.add(k, 1, i + 1);
        }

        // Extract in order and ensure non-decreasing keys
        uint256 lastKey = 0;
        bool first = true;
        while (!heapWrapper.isEmpty()) {
            (uint256 k,,) = heapWrapper.extractMin();
            if (!first) {
                assertLe(lastKey, k);
            }
            lastKey = k;
            first = false;
        }
    }
}
