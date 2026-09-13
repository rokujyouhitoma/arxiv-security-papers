#!/usr/bin/env python3
"""
Unit and Concurrency Tests for Lehman-Yao B-link Tree (Issue 251).
Validates High Key Invariants, Right Link Invariants, Atomic Half-Split,
Latch-Free Reader Drift, Cycle Detection, and Multithreaded Scalability.
"""

import concurrent.futures
import os
import random
import sys
import tempfile
import threading
from typing import List

import pytest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database.btree import BPlusTree, BTreeNode, CyclicPointerError
from database.pager import Pager


def test_blink_node_high_key_split() -> None:
    """Validates BTreeNode High Key and Right Link invariants upon split."""
    node = BTreeNode(page_id=1, is_leaf=True)
    for i in range(10):
        node.insert_leaf_entry(f"key_{i:03d}", i * 10)

    # Initial rightmost node has no high_key and no right_link
    assert node.high_key is None
    assert node.right_link is None

    # Perform B-link Split
    promoted_key, sibling = node.split(new_page_id=2)

    assert sibling.page_id == 2
    assert sibling.is_leaf is True
    assert len(node.keys) == 5
    assert len(sibling.keys) == 5

    # Lehman-Yao Invariant 1: all keys in node <= node.high_key
    assert node.high_key == "key_004"
    assert node.right_link == 2
    assert node.next_leaf == 2  # Backward-compatibility alias
    high_k = node.high_key
    assert high_k is not None
    for k in node.keys:
        assert str(k) <= str(high_k)

    # Lehman-Yao Invariant 2: node.high_key < all keys in sibling
    for k in sibling.keys:
        assert str(high_k) < str(k)

    # Sibling inherits original node's high_key (None for rightmost)
    assert sibling.high_key is None
    assert sibling.right_link is None

    # Verify serialization and deserialization preserves high_key & right_link
    raw_node = node.serialize()
    deserialized_node = BTreeNode.deserialize(1, raw_node)
    assert deserialized_node.high_key == "key_004"
    assert deserialized_node.right_link == 2
    assert deserialized_node.next_leaf == 2

    raw_sibling = sibling.serialize()
    deserialized_sibling = BTreeNode.deserialize(2, raw_sibling)
    assert deserialized_sibling.high_key is None
    assert deserialized_sibling.right_link is None


def test_blink_interior_node_split() -> None:
    """Validates B-link interior node splitting and high_key propagation."""
    node = BTreeNode(page_id=10, is_leaf=False)
    node.keys = [10, 20, 30, 40]
    node.children = [1, 2, 3, 4, 5]

    promoted_key, sibling = node.split(new_page_id=11)

    assert promoted_key == 30
    assert node.keys == [10, 20]
    assert node.children == [1, 2, 3]
    assert node.high_key == 30
    assert node.right_link == 11

    assert sibling.keys == [40]
    assert sibling.children == [4, 5]
    assert sibling.high_key is None
    assert sibling.right_link is None


def test_blink_tree_half_split_reader_drift() -> None:
    """
    Demonstrates Lehman-Yao reader drift:
    When a leaf node has split into (A -> B), but the parent has NOT been updated
    (parent still directs searches for B's keys to A), a reader reaching A follows
    A.right_link via _move_right to find the key in B without locks.
    """
    tree = BPlusTree(column_name="score")

    # Manually construct a tree with root -> Leaf A
    leaf_a = BTreeNode(page_id=1, is_leaf=True)
    for i in range(10):
        leaf_a.insert_leaf_entry(f"item_{i:02d}", i)
    tree._write_node(leaf_a)
    tree.root_page_id = 1

    # Simulate an atomic Half-Split:
    # Phase 1 & 2: Split leaf_a into leaf_a -> leaf_b, and write both to disk/memory.
    # Note: Parent is NOT updated (root still points to page 1).
    promoted_key, leaf_b = leaf_a.split(new_page_id=2)
    tree._write_node(leaf_b)
    tree._write_node(leaf_a)

    # Verify state of leaf_a and leaf_b
    assert leaf_a.high_key == "item_04"
    assert leaf_a.right_link == 2
    assert "item_07" in leaf_b.keys
    assert "item_07" not in leaf_a.keys

    # A reader searches for "item_07":
    # Root points to page 1 (leaf_a).
    # Lehman-Yao right-drift automatically follows leaf_a.right_link to leaf_b!
    results = tree.search("item_07")
    assert results == [7]

    # Reader searches for an item in leaf_a:
    results_a = tree.search("item_02")
    assert results_a == [2]

    # Range scan across the un-parented split:
    all_rows = tree.range_scan()
    assert all_rows == list(range(10))


def test_blink_tree_cyclic_pointer_detection() -> None:
    """Verifies that circular sibling pointers raise CyclicPointerError."""
    tree = BPlusTree(column_name="val")

    # Create two nodes in an intentional cycle: 1 -> 2 -> 1
    node1 = BTreeNode(page_id=1, is_leaf=True, high_key=10, right_link=2)
    node2 = BTreeNode(page_id=2, is_leaf=True, high_key=20, right_link=1)
    tree._write_node(node1)
    tree._write_node(node2)

    # _move_right searching for key 50 (exceeds high_key of both 1 and 2)
    with pytest.raises(CyclicPointerError, match="B-link cycle detected"):
        tree._move_right(node1, 50)

    # range_scan encountering cycle
    with pytest.raises(CyclicPointerError, match="B-link cycle"):
        tree.range_scan()


def test_blink_tree_with_pager_persistence() -> None:
    """Tests B-link tree on a 4KB disk pager with 500+ inserts and range scan."""
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "blink_test.db")
        pager = Pager(db_path, vfs_name="posix")
        tree = BPlusTree(pager=pager, column_name="seq")

        # Insert 500 items triggering multiple leaf and interior splits
        for i in range(500):
            tree.insert(i, i * 2)

        pager.commit()

        # Point searches
        assert tree.search(0) == [0]
        assert tree.search(250) == [500]
        assert tree.search(499) == [998]
        assert tree.search(500) == []

        # Range scan [100, 110]
        scan_res = tree.range_scan(min_key=100, max_key=110)
        expected = [i * 2 for i in range(100, 111)]
        assert scan_res == expected

        pager.close()


def test_blink_tree_multithreaded_concurrent_crud() -> None:
    """
    Stress-tests B-link tree with 12 concurrent threads:
    6 writer threads inserting 1200 entries and 6 reader threads
    performing concurrent point lookups and range scans.
    """
    tree = BPlusTree(column_name="concurrent_key")
    num_writers = 6
    keys_per_writer = 200  # Total 1200 items
    stop_readers = threading.Event()
    exceptions: List[Exception] = []

    def writer_task(worker_id: int) -> None:
        try:
            for idx in range(keys_per_writer):
                key = worker_id * 10000 + idx
                tree.insert(key, key)
        except Exception as exc:
            exceptions.append(exc)

    def reader_task() -> None:
        try:
            while not stop_readers.is_set():
                # Random point search
                target_key = random.randint(
                    0, num_writers - 1
                ) * 10000 + random.randint(0, keys_per_writer - 1)
                tree.search(target_key)

                # Random bounded range scan
                low = random.randint(0, 50000)
                tree.range_scan(min_key=low, max_key=low + 50)
        except Exception as exc:
            exceptions.append(exc)

    with concurrent.futures.ThreadPoolExecutor(max_workers=num_writers + 6) as executor:
        writer_futures = [executor.submit(writer_task, w) for w in range(num_writers)]
        reader_futures = [executor.submit(reader_task) for _ in range(6)]

        # Wait for all writers to complete
        for wf in writer_futures:
            wf.result()

        # Stop readers
        stop_readers.set()
        for rf in reader_futures:
            rf.result()

    # Verify zero exceptions occurred during concurrent read/write execution
    assert len(exceptions) == 0, f"Concurrent exceptions caught: {exceptions}"

    # Verify all 1200 keys were successfully inserted and retrieved
    for w in range(num_writers):
        for idx in range(keys_per_writer):
            key = w * 10000 + idx
            found = tree.search(key)
            assert found == [key], f"Key {key} not found or corrupted: {found}"

    # Verify full range scan contains all 1200 items in sorted order
    full_scan = tree.range_scan()
    assert len(full_scan) == num_writers * keys_per_writer
    assert full_scan == sorted(full_scan)
