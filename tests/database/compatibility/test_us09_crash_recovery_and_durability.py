#!/usr/bin/env python3
"""
US-09: Crash Recovery and ARIES Replay in src/database.
Tests ARIES 3-phase recovery (Analysis, Redo, Undo) restoring committed state
and reverting uncommitted loser transactions after sudden crash.
"""

import os
import sys
import tempfile
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database.recovery import ARIESRecoveryManager
from database.vfs import get_vfs
from database.wal import LogRecordType, WALWriter


class TestUS09CrashRecoveryAndDurability(unittest.TestCase):
    """Verifies crash resilience and ARIES redo/undo recovery."""

    def test_aries_crash_recovery_and_redo_replay(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = os.path.join(tmpdir, "crash_aries.db")
            wal_path = f"{db_path}.vdb-wal"
            vfs = get_vfs()

            # 1. Initialize disk file
            f = vfs.open(db_path, mode="w+b")
            f.write(0, b"\x00" * (4096 * 2))
            f.sync()
            f.close()

            # 2. Write WAL representing committed transaction 1
            writer = WALWriter(wal_path)
            r1 = writer.append_record(tx_id=1, record_type=LogRecordType.BEGIN)
            r2 = writer.append_record(
                tx_id=1,
                record_type=LogRecordType.UPDATE,
                prev_lsn=r1.lsn,
                page_id=0,
                offset=32,
                undo_data=b"\x00" * 8,
                redo_data=b"REDO_OK!",
            )
            writer.append_record(
                tx_id=1,
                record_type=LogRecordType.COMMIT,
                prev_lsn=r2.lsn,
                force_sync=True,
            )

            # Uncommitted transaction 2 (Loser)
            r3 = writer.append_record(tx_id=2, record_type=LogRecordType.BEGIN)
            writer.append_record(
                tx_id=2,
                record_type=LogRecordType.UPDATE,
                prev_lsn=r3.lsn,
                page_id=0,
                offset=48,
                undo_data=b"\x00" * 8,
                redo_data=b"LOSER_DAT",
            )
            # Sudden crash without commit
            writer.close()

            # 3. Execute ARIES Recovery
            recovery_mgr = ARIESRecoveryManager(db_path, wal_path)
            redo_cnt, undo_cnt = recovery_mgr.run_recovery()

            # Committed Tx1 was redone, uncommitted Tx2 was undone
            self.assertEqual(redo_cnt, 2)
            self.assertEqual(undo_cnt, 1)

            # 4. Verify DB file contains Tx1 data and DOES NOT contain Tx2 uncommitted data
            f_check = vfs.open(db_path, mode="rb")
            page0 = f_check.read(0, 4096)
            f_check.close()

            self.assertEqual(page0[32:40], b"REDO_OK!")
            self.assertEqual(page0[48:56], b"\x00" * 8)


if __name__ == "__main__":
    unittest.main()
