#!/usr/bin/env python3
"""
Unit and Integration Tests for Consistent Hashing Ring
and Distributed Shard Manager.
"""

import os
import sys
import unittest
from collections import Counter
from typing import Dict

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "src")
        ),
    )

from database.distributed.sharding import ConsistentHashRing, ShardManager


class TestConsistentHashing(unittest.TestCase):
    """Tests for ConsistentHashRing token resolution and key distribution."""

    def test_uniform_key_distribution_with_vnodes(self) -> None:
        ring = ConsistentHashRing(vnodes=128)
        nodes = ["node_alpha", "node_beta", "node_gamma"]
        for n in nodes:
            ring.add_node(n)

        # Map 1,200 synthetic keys
        counts: Counter[str] = Counter()
        for i in range(1200):
            key = f"crypto_paper_hash_key_{i}"
            assigned = ring.get_node(key)
            self.assertIsNotNone(assigned)
            assert assigned is not None
            counts[assigned] += 1

        # Each node should receive roughly 1/3 (around 400 keys, bounded between 280 and 520)
        for node in nodes:
            self.assertGreater(counts[node], 280)
            self.assertLess(counts[node], 520)

    def test_minimal_key_migration_on_node_addition(self) -> None:
        ring = ConsistentHashRing(vnodes=128)
        initial_nodes = ["node_1", "node_2", "node_3"]
        for n in initial_nodes:
            ring.add_node(n)

        initial_mapping: Dict[str, str] = {}
        for i in range(1000):
            key = f"paper_key_{i}"
            node = ring.get_node(key)
            assert node is not None
            initial_mapping[key] = node

        # Add a 4th node
        ring.add_node("node_4")

        migrated_keys = 0
        for i in range(1000):
            key = f"paper_key_{i}"
            new_node = ring.get_node(key)
            if new_node != initial_mapping[key]:
                migrated_keys += 1
                # If it migrated, it must have migrated to the new node
                self.assertEqual(new_node, "node_4")

        # Theoretical migration should be approx 1/4 = 25% (around 150 to 350 keys)
        self.assertGreater(migrated_keys, 150)
        self.assertLess(migrated_keys, 350)

    def test_preference_list_uniqueness(self) -> None:
        ring = ConsistentHashRing(vnodes=64)
        nodes = ["node_A", "node_B", "node_C", "node_D"]
        for n in nodes:
            ring.add_node(n)

        pref_list = ring.get_preference_list("security_paper_2408_001", n=3)
        self.assertEqual(len(pref_list), 3)
        # All replica nodes must be unique physical nodes
        self.assertEqual(len(set(pref_list)), 3)


class TestShardManager(unittest.TestCase):
    """Tests for ShardManager multi-replica CRUD and rebalancing."""

    def test_shard_manager_crud_and_rebalance(self) -> None:
        manager = ShardManager(
            node_ids=["shard_1", "shard_2", "shard_3"],
            replication_factor=2,
            vnodes=64,
        )

        # Put keys
        written1 = manager.put("paper:001", {"title": "Post-Quantum Cryptography"})
        written2 = manager.put("paper:002", {"title": "Zero-Trust Architecture"})

        self.assertEqual(len(written1), 2)
        self.assertEqual(len(written2), 2)

        # Read back
        val1 = manager.get("paper:001")
        self.assertIsNotNone(val1)
        assert val1 is not None
        self.assertEqual(val1["title"], "Post-Quantum Cryptography")

        # Rebalance onto a new 4th shard node
        migrated = manager.rebalance("shard_4")
        self.assertGreaterEqual(migrated, 0)
        self.assertIn("shard_4", manager.shards)

        # Data remains accessible after rebalancing
        val1_after = manager.get("paper:001")
        self.assertEqual(val1_after, val1)


if __name__ == "__main__":
    unittest.main()
