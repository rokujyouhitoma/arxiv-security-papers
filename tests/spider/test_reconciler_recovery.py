"""tests/spider/test_reconciler_recovery.py

Unit and integration tests for Spider Crash Recovery and Autonomous Resume Policy
(Issue 403 / Pillar 4: Daemon & Distributed Spider Resilience).
"""

from __future__ import annotations

import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock

from src.spider.daemon.reconciler import SpiderReconciler
from src.spider.distributed.state_storage import StateStorage
from src.web.gateway.handlers import _enrich_spider_recovery


class TestSpiderCrashRecovery(unittest.TestCase):
    def setUp(self) -> None:
        self.test_dir = tempfile.mkdtemp()
        self.base_dir = Path(self.test_dir) / "outputs" / "spider" / "checkpoints"
        self.recovery_dir = Path(self.test_dir) / "outputs" / "spider" / "recovery"
        self.quarantine_dir = self.base_dir / "quarantine"
        self.base_dir.mkdir(parents=True, exist_ok=True)
        self.recovery_dir.mkdir(parents=True, exist_ok=True)

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_validate_checkpoint_missing(self) -> None:
        """Missing checkpoint returns False and informative message."""
        valid, reason = StateStorage.validate_checkpoint(
            "arxiv", base_dir=str(self.base_dir)
        )
        self.assertFalse(valid)
        self.assertIsNotNone(reason)
        assert reason is not None
        self.assertIn("does not exist or is empty", reason)

    def test_validate_checkpoint_corrupted_json(self) -> None:
        """Corrupted JSON returns False and indicates parse error."""
        ckpt_path = self.base_dir / "arxiv.state"
        ckpt_path.write_text("{corrupted-json-data...", encoding="utf-8")

        valid, reason = StateStorage.validate_checkpoint(
            "arxiv", base_dir=str(self.base_dir)
        )
        self.assertFalse(valid)
        self.assertIsNotNone(reason)
        assert reason is not None
        self.assertIn("JSON parse error", reason)

    def test_validate_checkpoint_invalid_structure(self) -> None:
        """JSON that lacks valid queue data returns False."""
        ckpt_path = self.base_dir / "cwe.state"
        ckpt_path.write_text(json.dumps(["not", "a", "dict"]), encoding="utf-8")

        valid, reason = StateStorage.validate_checkpoint(
            "cwe", base_dir=str(self.base_dir)
        )
        self.assertFalse(valid)
        self.assertIsNotNone(reason)
        assert reason is not None
        self.assertIn("must contain pending requests", reason)

    def test_validate_checkpoint_valid(self) -> None:
        """Valid checkpoint returns True and None for error."""
        ckpt_path = self.base_dir / "arxiv.state"
        sample_data = {
            "version": "1.0",
            "pending_count": 2,
            "pending_requests": [
                {"url": "https://arxiv.org/abs/2601.0001", "depth": 0},
                {"url": "https://arxiv.org/abs/2601.0002", "depth": 1},
            ],
            "bloom_count": 1,
            "bloom_state": [],
        }
        ckpt_path.write_text(json.dumps(sample_data), encoding="utf-8")

        valid, reason = StateStorage.validate_checkpoint(
            "arxiv", base_dir=str(self.base_dir)
        )
        self.assertTrue(valid)
        self.assertIsNone(reason)

    def test_quarantine_corrupted_checkpoint(self) -> None:
        """Quarantine moves corrupted checkpoint to quarantine directory."""
        ckpt_path = self.base_dir / "arxiv.state"
        ckpt_path.write_text("corrupted content", encoding="utf-8")

        quarantine_path = StateStorage.quarantine_checkpoint(
            "arxiv",
            base_dir=str(self.base_dir),
            quarantine_dir=str(self.quarantine_dir),
            reason="corrupt",
        )

        self.assertIsNotNone(quarantine_path)
        assert quarantine_path is not None
        self.assertTrue(os.path.exists(quarantine_path))
        self.assertFalse(ckpt_path.exists())
        self.assertIn("arxiv.state.corrupt.", quarantine_path)

    def test_recovery_attempts_and_exhaustion(self) -> None:
        """Recovery attempts increment and exhaust beyond max_attempts."""
        # Attempt 1
        rec1 = StateStorage.record_recovery_attempt(
            "arxiv", base_dir=str(self.recovery_dir), max_attempts=3
        )
        self.assertEqual(rec1.get("attempts"), 1)
        self.assertEqual(rec1.get("status"), "RECOVERABLE")
        self.assertFalse(rec1.get("is_exhausted"))

        # Attempt 2
        rec2 = StateStorage.record_recovery_attempt(
            "arxiv", base_dir=str(self.recovery_dir), max_attempts=3
        )
        self.assertEqual(rec2.get("attempts"), 2)
        self.assertEqual(rec2.get("status"), "RECOVERABLE")

        # Attempt 3 (Threshold boundary)
        rec3 = StateStorage.record_recovery_attempt(
            "arxiv", base_dir=str(self.recovery_dir), max_attempts=3
        )
        self.assertEqual(rec3.get("attempts"), 3)
        self.assertFalse(rec3.get("is_exhausted"))

        # Attempt 4 (Exhausted)
        rec4 = StateStorage.record_recovery_attempt(
            "arxiv", base_dir=str(self.recovery_dir), max_attempts=3
        )
        self.assertEqual(rec4.get("attempts"), 4)
        self.assertEqual(rec4.get("status"), "EXHAUSTED")
        self.assertTrue(rec4.get("is_exhausted"))

        # Check get_recovery_info
        info = StateStorage.get_recovery_info("arxiv", base_dir=str(self.recovery_dir))
        self.assertTrue(info.get("has_recovery"))
        self.assertEqual(info.get("attempts"), 4)
        self.assertTrue(info.get("is_exhausted"))

        # Clear recovery state
        cleared = StateStorage.clear_recovery_state(
            "arxiv", base_dir=str(self.recovery_dir)
        )
        self.assertTrue(cleared)
        info_cleared = StateStorage.get_recovery_info(
            "arxiv", base_dir=str(self.recovery_dir)
        )
        self.assertEqual(info_cleared.get("attempts"), 0)
        self.assertFalse(info_cleared.get("has_recovery"))

    def test_reconciler_recover_cycle(self) -> None:
        """SpiderReconciler classifies none, corrupted, recoverable, and exhausted correctly."""
        mock_storage = MagicMock()
        mock_storage.reconcile_stale_jobs.return_value = 1

        reconciler = SpiderReconciler(
            storage=mock_storage,
            checkpoints_dir=str(self.base_dir),
            recovery_dir=str(self.recovery_dir),
            max_attempts=3,
        )

        # 1. No checkpoints present: actions list should be empty (all None)
        report1 = reconciler.reconcile_and_recover(timeout_seconds=3600.0)
        self.assertEqual(report1["stale_jobs_count"], 1)
        self.assertEqual(len(report1["actions"]), 0)
        self.assertEqual(report1["recoverable_count"], 0)
        self.assertEqual(report1["quarantined_count"], 0)

        # 2. Corrupted checkpoint for CWE
        cwe_ckpt = self.base_dir / "cwe.state"
        cwe_ckpt.write_text("{bad-json", encoding="utf-8")

        # 3. Valid checkpoint for arXiv
        arxiv_ckpt = self.base_dir / "arxiv.state"
        arxiv_ckpt.write_text(
            json.dumps({"version": "1.0", "pending_count": 5, "pending_requests": []}),
            encoding="utf-8",
        )

        report2 = reconciler.reconcile_and_recover(timeout_seconds=3600.0)
        self.assertEqual(report2["recoverable_count"], 1)
        self.assertEqual(report2["quarantined_count"], 1)
        self.assertEqual(len(report2["actions"]), 2)

        arxiv_action = next(
            a for a in report2["actions"] if a["spider_name"] == "arxiv"
        )
        cwe_action = next(a for a in report2["actions"] if a["spider_name"] == "cwe")

        self.assertEqual(arxiv_action["action"], "RECOVERABLE")
        self.assertEqual(arxiv_action["attempts"], 1)

        self.assertEqual(cwe_action["action"], "QUARANTINED")
        self.assertFalse(cwe_ckpt.exists())  # moved to quarantine

    def test_enrich_spider_recovery_helper(self) -> None:
        """_enrich_spider_recovery helper produces expected dict structure."""
        summary = {"arxiv": {}, "cwe": {}, "kev_cve": {}}
        _enrich_spider_recovery(summary, str(self.test_dir))
        arxiv_rec = summary["arxiv"].get("recovery", {})
        self.assertIn("has_recovery", arxiv_rec)
        self.assertIn("status", arxiv_rec)
        self.assertIn("attempts", arxiv_rec)
        self.assertIn("max_attempts", arxiv_rec)
        self.assertIn("can_resume", arxiv_rec)
        self.assertIsInstance(arxiv_rec["has_recovery"], bool)


if __name__ == "__main__":
    unittest.main()
