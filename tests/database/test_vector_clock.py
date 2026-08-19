#!/usr/bin/env python3
"""
Unit and Integration Tests for Vector Clock and Version Vector Conflict Resolution.
Verifies causal precedence (happens-before), concurrent conflict detection,
and LWW / Siblings multi-version reconciliation.
"""

import os
import sys
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    )

from database.distributed import (
    ConflictResolutionStrategy,
    VectorClock,
    VersionedValue,
    prune_dominated_versions,
    resolve_conflict,
)


class TestVectorClock(unittest.TestCase):
    """Tests for VectorClock logical timestamp progression and comparison."""

    def test_sequential_causality(self) -> None:
        # Event 1 on Node A
        vc_a1 = VectorClock().increment("nodeA")
        # Event 2 on Node A
        vc_a2 = vc_a1.increment("nodeA")

        self.assertTrue(vc_a1.happens_before(vc_a2))
        self.assertTrue(vc_a2.happens_after(vc_a1))
        self.assertFalse(vc_a2.happens_before(vc_a1))
        self.assertFalse(vc_a1.is_concurrent_with(vc_a2))

        # Node A sends to Node B
        vc_b1 = VectorClock().update("nodeB", vc_a2)
        self.assertTrue(vc_a2.happens_before(vc_b1))
        self.assertEqual(vc_b1.get("nodeA"), 2)
        self.assertEqual(vc_b1.get("nodeB"), 1)

    def test_concurrent_conflict_detection(self) -> None:
        # Initial shared state
        vc_base = VectorClock({"nodeA": 1, "nodeB": 1})

        # Concurrent update on Node A
        vc_a = vc_base.increment("nodeA")  # {A:2, B:1}
        # Concurrent update on Node B
        vc_b = vc_base.increment("nodeB")  # {A:1, B:2}

        self.assertFalse(vc_a.happens_before(vc_b))
        self.assertFalse(vc_b.happens_before(vc_a))
        self.assertTrue(vc_a.is_concurrent_with(vc_b))
        self.assertTrue(vc_b.is_concurrent_with(vc_a))

    def test_vector_clock_merge(self) -> None:
        vc1 = VectorClock({"nodeA": 3, "nodeB": 1})
        vc2 = VectorClock({"nodeA": 1, "nodeB": 4, "nodeC": 2})

        merged = vc1.merge(vc2)
        self.assertEqual(merged.get("nodeA"), 3)
        self.assertEqual(merged.get("nodeB"), 4)
        self.assertEqual(merged.get("nodeC"), 2)

    def test_serialization(self) -> None:
        vc = VectorClock({"nodeA": 5, "nodeB": 10})
        json_str = vc.to_json()
        restored = VectorClock.from_json(json_str)

        self.assertEqual(vc, restored)
        self.assertEqual(restored.get("nodeA"), 5)
        self.assertEqual(restored.get("nodeB"), 10)


class TestVersionVectorReconciliation(unittest.TestCase):
    """Tests for multi-version conflict resolution and sibling management."""

    def test_prune_dominated_versions(self) -> None:
        v1 = VersionedValue("v1_old", clock=VectorClock({"nodeA": 1}))
        v2 = VersionedValue("v2_new", clock=VectorClock({"nodeA": 2}))

        frontier = prune_dominated_versions([v1, v2])
        self.assertEqual(len(frontier), 1)
        self.assertEqual(frontier[0].value, "v2_new")

    def test_lww_conflict_resolution(self) -> None:
        # Two concurrent writes
        v_a = VersionedValue(
            "update_from_node_a",
            clock=VectorClock({"nodeA": 2, "nodeB": 1}),
            timestamp=100.0,
        )
        v_b = VersionedValue(
            "update_from_node_b",
            clock=VectorClock({"nodeA": 1, "nodeB": 2}),
            timestamp=105.0,  # Later timestamp
        )

        resolved = resolve_conflict([v_a, v_b], strategy=ConflictResolutionStrategy.LWW)
        self.assertEqual(len(resolved), 1)
        self.assertEqual(resolved[0].value, "update_from_node_b")
        # Winner clock merges both branches
        self.assertEqual(resolved[0].clock.get("nodeA"), 2)
        self.assertEqual(resolved[0].clock.get("nodeB"), 2)

    def test_siblings_conflict_resolution(self) -> None:
        v_a = VersionedValue("val_a", clock=VectorClock({"nodeA": 2, "nodeB": 1}))
        v_b = VersionedValue("val_b", clock=VectorClock({"nodeA": 1, "nodeB": 2}))

        siblings = resolve_conflict(
            [v_a, v_b], strategy=ConflictResolutionStrategy.SIBLINGS
        )
        self.assertEqual(len(siblings), 2)
        values = [s.value for s in siblings]
        self.assertIn("val_a", values)
        self.assertIn("val_b", values)


if __name__ == "__main__":
    unittest.main()
