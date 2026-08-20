#!/usr/bin/env python3
"""
Unit and Integration Tests for Merkle Tree and CRDT Anti-Entropy Synchronization.
Verifies O(log N) difference detection, PNCounter / ORSet semilattice convergence,
and automated background replica reconciliation.
"""

import os
import sys
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database.distributed import (
    AntiEntropySynchronizer,
    MerkleTree,
    ORSet,
    PNCounter,
    QuorumReplica,
    VectorClock,
    VersionedValue,
)


class TestMerkleTree(unittest.TestCase):
    """Tests for Merkle Tree cryptographic hash construction and diff detection."""

    def test_identical_datasets_match(self) -> None:
        data1 = {f"k{i}": f"val_{i}" for i in range(50)}
        data2 = {f"k{i}": f"val_{i}" for i in range(50)}

        tree1 = MerkleTree(data1)
        tree2 = MerkleTree(data2)

        self.assertEqual(tree1.root_hash, tree2.root_hash)
        self.assertEqual(tree1.find_diff_keys(tree2), [])

    def test_single_key_difference_detection(self) -> None:
        data1 = {f"k{i}": f"val_{i}" for i in range(100)}
        data2 = dict(data1)
        data2["k42"] = "MODIFIED_VALUE"

        tree1 = MerkleTree(data1)
        tree2 = MerkleTree(data2)

        self.assertNotEqual(tree1.root_hash, tree2.root_hash)
        diff_keys = tree1.find_diff_keys(tree2)
        self.assertEqual(diff_keys, ["k42"])

    def test_missing_and_added_keys(self) -> None:
        data1 = {"k1": "v1", "k2": "v2", "k3": "v3"}
        data2 = {"k1": "v1", "k2": "v2_changed", "k4": "v4_new"}

        tree1 = MerkleTree(data1)
        tree2 = MerkleTree(data2)

        diff_keys = tree1.find_diff_keys(tree2)
        self.assertEqual(sorted(diff_keys), ["k2", "k3", "k4"])


class TestCRDTs(unittest.TestCase):
    """Tests for PN-Counter and OR-Set CRDT properties."""

    def test_pn_counter_convergence_and_properties(self) -> None:
        # Node A increments
        c_a = PNCounter()
        c_a.increment("nodeA", 10)
        c_a.decrement("nodeA", 2)

        # Node B concurrently increments and decrements
        c_b = PNCounter()
        c_b.increment("nodeB", 5)
        c_b.decrement("nodeB", 1)

        # Commutative: A merge B == B merge A
        merged_ab = c_a.merge(c_b)
        merged_ba = c_b.merge(c_a)

        self.assertEqual(merged_ab.value, 12)  # (10+5) - (2+1) = 12
        self.assertEqual(merged_ab.value, merged_ba.value)

        # Idempotent: A merge A == A
        merged_aa = c_a.merge(c_a)
        self.assertEqual(merged_aa.value, c_a.value)

    def test_or_set_add_wins_and_convergence(self) -> None:
        set_a = ORSet[str]()
        set_b = ORSet[str]()

        # Node A adds "crypto" and "zero-trust"
        set_a.add("crypto")
        set_a.add("zero-trust")

        # Synchronize A -> B
        set_b = set_b.merge(set_a)
        self.assertEqual(set_b.read(), {"crypto", "zero-trust"})

        # Node A removes "crypto"
        set_a.remove("crypto")

        # Node B concurrently adds "crypto" again (new unique tag)
        set_b.add("crypto")

        # Merge should keep "crypto" because B's add has a newer un-removed tag (Add-Wins)
        converged = set_a.merge(set_b)
        self.assertIn("crypto", converged)
        self.assertIn("zero-trust", converged)


class TestAntiEntropy(unittest.TestCase):
    """Tests for Merkle Tree-driven replica synchronization."""

    def test_anti_entropy_synchronization(self) -> None:
        r1 = QuorumReplica("replica_1")
        r2 = QuorumReplica("replica_2")

        # Populate replica 1 with 20 records
        for i in range(20):
            clock = VectorClock({"r1": 1})
            r1.put(
                f"doc:{i}", VersionedValue(f"content_{i}", clock=clock, timestamp=100.0)
            )

        # Populate replica 2 with stale doc:5 and missing doc:19
        for i in range(19):
            if i == 5:
                # Stale clock
                stale_clock = VectorClock({"r1": 0})
                r2.put(
                    "doc:5",
                    VersionedValue(
                        "stale_content_5", clock=stale_clock, timestamp=50.0
                    ),
                )
            else:
                clock = VectorClock({"r1": 1})
                r2.put(
                    f"doc:{i}",
                    VersionedValue(f"content_{i}", clock=clock, timestamp=100.0),
                )

        synchronizer = AntiEntropySynchronizer()
        reconciled = synchronizer.synchronize(r1, r2)

        # doc:5 and doc:19 should be reconciled on r2
        self.assertGreaterEqual(reconciled, 1)

        # Verify r2 now has latest doc:5 and doc:19
        self.assertEqual(r2.get("doc:5").value, "content_5")
        self.assertEqual(r2.get("doc:19").value, "content_19")

        # Subsequent sync detects 0 differences
        reconciled_after = synchronizer.synchronize(r1, r2)
        self.assertEqual(reconciled_after, 0)


if __name__ == "__main__":
    unittest.main()
