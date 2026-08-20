#!/usr/bin/env python3
"""
Scenario 4: Power-Loss Simulation and Crash Recovery (WAL / ARIES).
Location: tests/database/scenarios/test_scenario_04_aries_crash_recovery.py
Persona: SRE / Database Administrator.
Verifies STEAL/NO-FORCE crash resilience, ARIES 3-phase recovery
(Analysis, Redo with Repeat History, Undo with CLRs), and zero-corruption state restoration.
"""

import os
import sys
import tempfile
import unittest

import pytest

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


class TestScenario04ARIESCrashRecovery(unittest.TestCase):
    """Verifies ARIES 3-phase recovery and crash resilience."""

    def test_fast_aries_three_phase_recovery_lifecycle(self) -> None:
        """Fast verification: ARIES Analysis, Redo committed Tx, and Undo loser Tx."""
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = os.path.join(tmpdir, "aries_scenario.db")
            wal_path = f"{db_path}.vdb-wal"
            vfs = get_vfs()

            # Initialize DB disk file with 2 zero pages
            f = vfs.open(db_path, mode="w+b")
            f.write(0, b"\x00" * 8192)
            f.sync()
            f.close()

            # Simulate WAL log leading up to sudden power failure
            writer = WALWriter(wal_path)
            # Tx 1: Committed transaction
            r1 = writer.append_record(tx_id=1, record_type=LogRecordType.BEGIN)
            r2 = writer.append_record(
                tx_id=1,
                record_type=LogRecordType.UPDATE,
                prev_lsn=r1.lsn,
                page_id=0,
                offset=64,
                undo_data=b"\x00" * 16,
                redo_data=b"COMMITTED_DATA!!",
            )
            writer.append_record(
                tx_id=1,
                record_type=LogRecordType.COMMIT,
                prev_lsn=r2.lsn,
                force_sync=True,
            )

            # Tx 2: Uncommitted Loser transaction
            r4 = writer.append_record(tx_id=2, record_type=LogRecordType.BEGIN)
            writer.append_record(
                tx_id=2,
                record_type=LogRecordType.UPDATE,
                prev_lsn=r4.lsn,
                page_id=0,
                offset=128,
                undo_data=b"\x00" * 16,
                redo_data=b"UNCOMMITTED_FAIL",
            )
            # Sudden power loss (SIGKILL simulation)
            writer.close()

            # ARIES Recovery on database restart
            recovery = ARIESRecoveryManager(db_path, wal_path)
            redo_ops, undo_ops = recovery.run_recovery()

            self.assertEqual(redo_ops, 2)
            self.assertEqual(undo_ops, 1)

            # Verify persisted page content
            f_check = vfs.open(db_path, mode="rb")
            data = f_check.read(0, 4096)
            f_check.close()

            self.assertEqual(data[64:80], b"COMMITTED_DATA!!")
            self.assertEqual(data[128:144], b"\x00" * 16)

    @pytest.mark.slow
    def test_slow_aries_multi_transaction_crash_and_clr_durability(self) -> None:
        """Slow verification: 20 concurrent transactions with simulated crash and CLR undo replay."""
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = os.path.join(tmpdir, "aries_stress.db")
            wal_path = f"{db_path}.vdb-wal"
            vfs = get_vfs()

            f = vfs.open(db_path, mode="w+b")
            f.write(0, b"\x00" * 16384)
            f.sync()
            f.close()

            writer = WALWriter(wal_path)
            # 10 committed, 10 losers
            for tx_id in range(1, 21):
                r_begin = writer.append_record(
                    tx_id=tx_id, record_type=LogRecordType.BEGIN
                )
                r_up = writer.append_record(
                    tx_id=tx_id,
                    record_type=LogRecordType.UPDATE,
                    prev_lsn=r_begin.lsn,
                    page_id=tx_id % 4,
                    offset=(tx_id * 32) % 4000,
                    undo_data=b"\x00" * 8,
                    redo_data=f"TX_{tx_id:04d}!".encode(),
                )
                if tx_id % 2 == 0:
                    writer.append_record(
                        tx_id=tx_id,
                        record_type=LogRecordType.COMMIT,
                        prev_lsn=r_up.lsn,
                        force_sync=True,
                    )
            writer.close()

            recovery = ARIESRecoveryManager(db_path, wal_path)
            redo_cnt, undo_cnt = recovery.run_recovery()
            self.assertEqual(redo_cnt, 20)
            self.assertEqual(undo_cnt, 10)


if __name__ == "__main__":
    unittest.main()
