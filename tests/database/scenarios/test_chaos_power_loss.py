#!/usr/bin/env python3
"""
Chaos VFS Power-Loss and Crash Resilience Test Suite.
Verifies ARIES 3-phase crash recovery under simulated sudden power loss,
interrupted disk writes, and failed fsync operations using ChaosVFS.
"""

import os
import sys
import tempfile
import unittest
from typing import List, Tuple

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database.recovery import ARIESRecoveryManager
from database.storage.vfs import ChaosVFS, PosixVFS
from database.wal import LogRecordType, WALWriter


def _setup_empty_database(vfs: ChaosVFS, db_path: str, page_size: int = 4096) -> None:
    """Initializes an empty database file with zeroed pages."""
    f = vfs.open(db_path, mode="w+b")
    f.write(0, b"\x00" * (page_size * 2))
    f.sync()
    f.close()


def _write_sample_tx(
    writer: WALWriter, tx_id: int, offset: int, data: bytes, commit: bool
) -> None:
    """Helper to append a full transaction (BEGIN, UPDATE, optional COMMIT) to WAL."""
    r_begin = writer.append_record(tx_id=tx_id, record_type=LogRecordType.BEGIN)
    r_update = writer.append_record(
        tx_id=tx_id,
        record_type=LogRecordType.UPDATE,
        prev_lsn=r_begin.lsn,
        page_id=0,
        offset=offset,
        undo_data=b"\x00" * len(data),
        redo_data=data,
    )
    if commit:
        writer.append_record(
            tx_id=tx_id,
            record_type=LogRecordType.COMMIT,
            prev_lsn=r_update.lsn,
            force_sync=True,
        )


class TestChaosPowerLossRecovery(unittest.TestCase):
    """Verifies crash resilience of ARIES recovery engine under ChaosVFS."""

    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.tmpdir.name, "chaos_test.db")
        self.wal_path = f"{self.db_path}.vdb-wal"
        self.chaos_vfs = ChaosVFS(PosixVFS())

    def tearDown(self) -> None:
        self.tmpdir.cleanup()

    def test_chaos_interrupted_write_power_loss(self) -> None:
        """Verifies recovery when power cut interrupts WAL writing mid-stream."""
        _setup_empty_database(self.chaos_vfs, self.db_path)

        # 1. Commit Tx 101 successfully
        writer = WALWriter(self.wal_path, vfs=self.chaos_vfs)
        _write_sample_tx(
            writer, tx_id=101, offset=64, data=b"TX101_COMMITTED!", commit=True
        )

        # 2. Inject chaos: Fail after 1 write during uncommitted Tx 102
        self.chaos_vfs.set_fail_after_writes(1)
        r_begin = writer.append_record(tx_id=102, record_type=LogRecordType.BEGIN)

        with self.assertRaises(IOError):
            writer.append_record(
                tx_id=102,
                record_type=LogRecordType.UPDATE,
                prev_lsn=r_begin.lsn,
                page_id=0,
                offset=128,
                undo_data=b"\x00" * 16,
                redo_data=b"TX102_FAILED_MID",
            )

        writer.close()
        self.chaos_vfs.reset_stats()

        # 3. Recover database via ARIES
        recovery = ARIESRecoveryManager(self.db_path, self.wal_path, vfs=self.chaos_vfs)
        redo_count, undo_count = recovery.run_recovery()

        self.assertGreaterEqual(redo_count, 1)

        # 4. Verify disk consistency
        f = self.chaos_vfs.open(self.db_path, mode="rb")
        page_data = f.read(0, 4096)
        f.close()

        self.assertEqual(page_data[64:80], b"TX101_COMMITTED!")
        self.assertEqual(page_data[128:144], b"\x00" * 16)

    def test_chaos_power_loss_during_fsync(self) -> None:
        """Verifies recovery when power cut strikes during fsync disk flush."""
        _setup_empty_database(self.chaos_vfs, self.db_path)

        writer = WALWriter(self.wal_path, vfs=self.chaos_vfs)
        _write_sample_tx(
            writer, tx_id=201, offset=64, data=b"TX201_PRE_CRASH", commit=True
        )

        # Fail on fsync during uncommitted update
        self.chaos_vfs.set_fail_on_sync(True)
        r_begin = writer.append_record(tx_id=202, record_type=LogRecordType.BEGIN)
        with self.assertRaises(IOError):
            writer.append_record(
                tx_id=202,
                record_type=LogRecordType.UPDATE,
                prev_lsn=r_begin.lsn,
                page_id=0,
                offset=128,
                undo_data=b"\x00" * 16,
                redo_data=b"TX202_SYNC_CRASH",
                force_sync=True,
            )

        self.chaos_vfs.reset_stats()
        try:
            writer.close()
        except Exception:
            pass

        # Run ARIES Recovery
        recovery = ARIESRecoveryManager(self.db_path, self.wal_path, vfs=self.chaos_vfs)
        recovery.run_recovery()

        # Verify page content: TX 201 must exist, TX 202 must NOT exist
        f = self.chaos_vfs.open(self.db_path, mode="rb")
        page_data = f.read(0, 4096)
        f.close()

        self.assertEqual(page_data[64:79], b"TX201_PRE_CRASH")
        self.assertEqual(page_data[128:144], b"\x00" * 16)

    def test_chaos_multi_transaction_crash_matrix(self) -> None:
        """Simulates interleaved multi-transaction updates with sudden crash."""
        _setup_empty_database(self.chaos_vfs, self.db_path)

        writer = WALWriter(self.wal_path, vfs=self.chaos_vfs)
        tx_configs: List[Tuple[int, int, bytes, bool]] = [
            (301, 64, b"DATA_TX_301_PASS", True),
            (302, 128, b"DATA_TX_302_PASS", True),
            (303, 192, b"DATA_TX_303_LOSE", False),
            (304, 256, b"DATA_TX_304_PASS", True),
            (305, 320, b"DATA_TX_305_LOSE", False),
        ]

        for tx_id, offset, data, commit in tx_configs:
            _write_sample_tx(writer, tx_id, offset, data, commit)

        # Abrupt crash (close without checkpoint)
        writer.close()

        recovery = ARIESRecoveryManager(self.db_path, self.wal_path, vfs=self.chaos_vfs)
        redo_ops, undo_ops = recovery.run_recovery()

        self.assertGreaterEqual(redo_ops, 3)
        self.assertEqual(undo_ops, 2)  # Exactly 2 uncommitted loser transactions

        f = self.chaos_vfs.open(self.db_path, mode="rb")
        page = f.read(0, 4096)
        f.close()

        self.assertEqual(page[64:80], b"DATA_TX_301_PASS")
        self.assertEqual(page[128:144], b"DATA_TX_302_PASS")
        self.assertEqual(page[192:208], b"\x00" * 16)  # Undone
        self.assertEqual(page[256:272], b"DATA_TX_304_PASS")
        self.assertEqual(page[320:336], b"\x00" * 16)  # Undone


if __name__ == "__main__":
    unittest.main()
