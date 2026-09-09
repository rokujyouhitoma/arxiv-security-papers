"""Unit tests for ARIES Crash Recovery HSM lifecycle governance."""

from __future__ import annotations

import shutil
import tempfile
import unittest

from database.storage.vfs import get_vfs
from database.transaction.contracts import (
    EVENT_ANALYSIS_DONE,
    EVENT_FAIL,
    EVENT_NO_RECOVERY,
    EVENT_REDO_DONE,
    EVENT_START_RECOVERY,
    EVENT_UNDO_DONE,
    build_aries_recovery_state_tree,
)
from database.transaction.recovery import ARIESRecoveryManager
from database.transaction.wal import DEFAULT_PAGE_SIZE, LogRecordType, WALWriter


class TestARIESRecoveryHSM(unittest.TestCase):
    """Verifies HSM state tree and ARIESRecoveryManager lifecycle governance."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.mkdtemp(prefix="test_aries_hsm_")
        self.vfs = get_vfs()

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_aries_state_tree_transitions(self) -> None:
        """Verifies full ARIES Recovery HSM transition pathway."""
        hsm = build_aries_recovery_state_tree()
        self.assertEqual(hsm.current_state.name, "IDLE")
        self.assertEqual(hsm.current_state.get_path(), "OPERATIONAL.IDLE")

        self.assertTrue(hsm.send_event(EVENT_START_RECOVERY))
        self.assertEqual(hsm.current_state.name, "ANALYSIS")
        self.assertEqual(hsm.current_state.get_path(), "OPERATIONAL.RECOVERY.ANALYSIS")

        self.assertTrue(hsm.send_event(EVENT_ANALYSIS_DONE))
        self.assertEqual(hsm.current_state.name, "REDO")
        self.assertEqual(hsm.current_state.get_path(), "OPERATIONAL.RECOVERY.REDO")

        self.assertTrue(hsm.send_event(EVENT_REDO_DONE))
        self.assertEqual(hsm.current_state.name, "UNDO")
        self.assertEqual(hsm.current_state.get_path(), "OPERATIONAL.RECOVERY.UNDO")

        self.assertTrue(hsm.send_event(EVENT_UNDO_DONE))
        self.assertEqual(hsm.current_state.name, "COMPLETED")
        self.assertEqual(hsm.current_state.get_path(), "TERMINATED.COMPLETED")

    def test_aries_state_tree_no_recovery_needed(self) -> None:
        """Verifies transition to NO_RECOVERY_NEEDED when WAL is absent."""
        hsm = build_aries_recovery_state_tree()
        self.assertTrue(hsm.send_event(EVENT_NO_RECOVERY))
        self.assertEqual(hsm.current_state.name, "NO_RECOVERY_NEEDED")
        self.assertEqual(hsm.current_state.get_path(), "TERMINATED.NO_RECOVERY_NEEDED")

    def test_aries_state_tree_fail_secure_trap(self) -> None:
        """Verifies fail-secure transition to FAILED from any recovery subphase."""
        hsm = build_aries_recovery_state_tree()
        hsm.send_event(EVENT_START_RECOVERY)
        self.assertEqual(hsm.current_state.name, "ANALYSIS")

        self.assertTrue(hsm.send_event(EVENT_FAIL, {"error": "Corrupt WAL"}))
        self.assertEqual(hsm.current_state.name, "FAILED")
        self.assertEqual(hsm.current_state.get_path(), "TERMINATED.FAILED")

    def test_manager_no_wal_file_hsm_state(self) -> None:
        """Verifies ARIESRecoveryManager sets NO_RECOVERY_NEEDED when WAL missing."""
        db_path = f"{self.temp_dir}/test.db"
        wal_path = f"{self.temp_dir}/test.db-wal"

        manager = ARIESRecoveryManager(
            db_file_path=db_path, wal_file_path=wal_path, vfs=self.vfs
        )
        self.assertEqual(manager.hsm.current_state.name, "IDLE")

        redo_cnt, undo_cnt = manager.run_recovery()
        self.assertEqual((redo_cnt, undo_cnt), (0, 0))
        self.assertEqual(manager.hsm.current_state.name, "NO_RECOVERY_NEEDED")

    def test_manager_successful_recovery_hsm_state(self) -> None:
        """Verifies ARIESRecoveryManager transitions through full ARIES lifecycle on real WAL."""
        db_path = f"{self.temp_dir}/test.db"
        wal_path = f"{self.temp_dir}/test.db-wal"

        # Create dummy database file
        f = self.vfs.open(db_path, "wb")
        f.write(0, b"\x00" * DEFAULT_PAGE_SIZE)
        f.close()

        # Write valid WAL records (Begin Tx 1, Update Page 0, Commit Tx 1)
        writer = WALWriter(wal_path, vfs=self.vfs)
        r1 = writer.append_record(tx_id=1, record_type=LogRecordType.BEGIN)
        r2 = writer.append_record(
            tx_id=1,
            record_type=LogRecordType.UPDATE,
            prev_lsn=r1.lsn,
            page_id=0,
            offset=10,
            undo_data=b"hello",
            redo_data=b"world",
        )
        writer.append_record(
            tx_id=1,
            record_type=LogRecordType.COMMIT,
            prev_lsn=r2.lsn,
            force_sync=True,
        )
        writer.close()

        manager = ARIESRecoveryManager(
            db_file_path=db_path, wal_file_path=wal_path, vfs=self.vfs
        )
        redo_cnt, undo_cnt = manager.run_recovery()
        self.assertGreaterEqual(redo_cnt, 1)
        self.assertEqual(undo_cnt, 0)
        self.assertEqual(manager.hsm.current_state.name, "COMPLETED")
        self.assertEqual(manager.hsm.current_state.get_path(), "TERMINATED.COMPLETED")


if __name__ == "__main__":
    unittest.main()
