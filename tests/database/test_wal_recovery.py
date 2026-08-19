#!/usr/bin/env python3
"""
Unit and Integration Tests for WAL and ARIES Crash Recovery Subsystems.
Verifies WAL record serialization, LSN chaining, CRC32 checksums,
Steal/No-Force buffer policies in Pager, and ARIES 3-phase crash recovery.
"""

import os
import shutil
import struct
import sys
import tempfile
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    )

from database.pager import Pager
from database.recovery import ARIESRecoveryManager
from database.vfs import get_vfs
from database.wal import (
    DEFAULT_PAGE_SIZE,
    LogRecord,
    LogRecordType,
    WALReader,
    WALWriter,
)


class TestWALRecordSerialization(unittest.TestCase):
    """Tests for WAL record binary serialization and checksum integrity."""

    def test_record_serialize_deserialize_basic(self) -> None:
        rec = LogRecord(
            lsn=101,
            prev_lsn=50,
            tx_id=1,
            record_type=LogRecordType.UPDATE,
            page_id=3,
            offset=16,
            undo_data=b"old_payload_data",
            redo_data=b"new_payload_data",
            undo_next_lsn=20,
            extra_info={"tag": "test_update", "version": 2},
        )
        serialized = rec.serialize()
        self.assertIsInstance(serialized, bytes)

        deserialized, next_offset = LogRecord.deserialize(serialized, 0)
        self.assertEqual(next_offset, len(serialized))
        self.assertEqual(deserialized.lsn, 101)
        self.assertEqual(deserialized.prev_lsn, 50)
        self.assertEqual(deserialized.tx_id, 1)
        self.assertEqual(deserialized.record_type, LogRecordType.UPDATE)
        self.assertEqual(deserialized.page_id, 3)
        self.assertEqual(deserialized.offset, 16)
        self.assertEqual(deserialized.undo_data, b"old_payload_data")
        self.assertEqual(deserialized.redo_data, b"new_payload_data")
        self.assertEqual(deserialized.undo_next_lsn, 20)
        self.assertEqual(deserialized.extra_info, {"tag": "test_update", "version": 2})

    def test_record_checksum_corruption_detection(self) -> None:
        rec = LogRecord(
            lsn=1,
            prev_lsn=0,
            tx_id=10,
            record_type=LogRecordType.BEGIN,
        )
        data = bytearray(rec.serialize())
        # Corrupt one byte in header
        data[5] ^= 0xFF
        with self.assertRaises(ValueError):
            LogRecord.deserialize(bytes(data), 0)


class TestWALWriterReader(unittest.TestCase):
    """Tests for WALWriter and WALReader file operations."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.mkdtemp()
        self.wal_path = os.path.join(self.temp_dir, "test.db.vdb-wal")

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_wal_write_and_read_sequential(self) -> None:
        writer = WALWriter(self.wal_path)
        r1 = writer.append_record(tx_id=1, record_type=LogRecordType.BEGIN)
        r2 = writer.append_record(
            tx_id=1,
            record_type=LogRecordType.UPDATE,
            prev_lsn=r1.lsn,
            page_id=0,
            offset=0,
            undo_data=b"AAAA",
            redo_data=b"BBBB",
        )
        r3 = writer.append_record(
            tx_id=1,
            record_type=LogRecordType.COMMIT,
            prev_lsn=r2.lsn,
            force_sync=True,
        )
        writer.close()

        self.assertEqual(r1.lsn, 1)
        self.assertEqual(r2.lsn, 2)
        self.assertEqual(r3.lsn, 3)

        reader = WALReader(self.wal_path)
        records = reader.read_all_records()
        self.assertEqual(len(records), 3)
        self.assertEqual(records[0].record_type, LogRecordType.BEGIN)
        self.assertEqual(records[1].record_type, LogRecordType.UPDATE)
        self.assertEqual(records[2].record_type, LogRecordType.COMMIT)


class TestPagerWALIntegration(unittest.TestCase):
    """Tests for Pager integration with WAL and Steal/No-Force buffer policies."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.temp_dir, "test_pager.db")

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_pager_transaction_commit_and_wal(self) -> None:
        pager = Pager(self.db_path, cache_capacity=10, use_wal=True)
        pager.begin()
        self.assertTrue(pager.is_in_transaction)

        # Write page 0
        payload0 = b"Hello, WAL World!" + b"\x00" * (DEFAULT_PAGE_SIZE - 17)
        pager.write_page(0, payload0)

        # Write page 1
        payload1 = b"Second Page Data" + b"\x00" * (DEFAULT_PAGE_SIZE - 16)
        pager.write_page(1, payload1)

        pager.commit()
        self.assertFalse(pager.is_in_transaction)
        pager.close()

        # Read back with new Pager
        pager2 = Pager(self.db_path, cache_capacity=10, use_wal=True)
        p0 = pager2.read_page(0)
        p1 = pager2.read_page(1)
        self.assertEqual(p0[:17], b"Hello, WAL World!")
        self.assertEqual(p1[:16], b"Second Page Data")
        pager2.close()

    def test_pager_transaction_rollback(self) -> None:
        pager = Pager(self.db_path, cache_capacity=10, use_wal=True)
        # Initialize page 0
        init_data = b"Initial Base Data" + b"\x00" * (DEFAULT_PAGE_SIZE - 17)
        pager.write_page(0, init_data)
        pager.flush_all()

        # Start transaction and modify page 0
        pager.begin()
        mod_data = b"MODIFIED_CORRUPT" + b"\x00" * (DEFAULT_PAGE_SIZE - 16)
        pager.write_page(0, mod_data)

        # Rollback
        pager.rollback()
        self.assertFalse(pager.is_in_transaction)

        reverted_data = pager.read_page(0)
        self.assertEqual(reverted_data[:17], b"Initial Base Data")
        pager.close()

    def test_pager_steal_policy_wal_first(self) -> None:
        # Cache capacity = 1 so write to page 1 will evict page 0
        pager = Pager(self.db_path, cache_capacity=1, use_wal=True)
        pager.begin()

        # Write page 0
        pager.write_page(0, b"P0" + b"\x00" * (DEFAULT_PAGE_SIZE - 2))
        page0 = pager.cache.get(0)
        self.assertIsNotNone(page0)
        p0_lsn = page0.page_lsn

        # Writing page 1 will evict dirty page 0 to disk (Steal)
        pager.write_page(1, b"P1" + b"\x00" * (DEFAULT_PAGE_SIZE - 2))

        # Check WAL was flushed up to at least page 0's LSN before disk write
        self.assertGreaterEqual(pager.wal.flushed_lsn, p0_lsn)
        pager.commit()
        pager.close()


class TestARIESCrashRecovery(unittest.TestCase):
    """Comprehensive tests for ARIES 3-Phase Crash Recovery (Analysis, Redo, Undo)."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.temp_dir, "crash_test.db")
        self.wal_path = f"{self.db_path}.vdb-wal"

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_aries_redo_committed_transaction_after_crash(self) -> None:
        """
        Simulates scenario where Tx committed in WAL, but dirty pages were NOT
        flushed to the DB file before sudden crash. Redo phase must restore changes.
        """
        # Create empty DB file
        vfs = get_vfs()
        f = vfs.open(self.db_path, mode="w+b")
        f.write(0, b"\x00" * (DEFAULT_PAGE_SIZE * 2))
        f.sync()
        f.close()

        # Manually write WAL records representing a committed transaction
        writer = WALWriter(self.wal_path)
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
        writer.close()

        # Run ARIES recovery
        recovery_mgr = ARIESRecoveryManager(self.db_path, self.wal_path)
        redo_cnt, undo_cnt = recovery_mgr.run_recovery()

        self.assertEqual(redo_cnt, 1)
        self.assertEqual(undo_cnt, 0)

        # Verify DB file has REDO_OK! on page 0 at offset 32
        f = vfs.open(self.db_path, mode="rb")
        data = f.read(0, DEFAULT_PAGE_SIZE)
        f.close()
        self.assertEqual(data[32:40], b"REDO_OK!")

    def test_aries_undo_uncommitted_loser_transaction(self) -> None:
        """
        Simulates scenario where Tx was active when system crashed (loser transaction),
        and its dirty page had already been written to disk (Steal).
        Undo phase must revert the page using undo_data and write CLRs.
        """
        vfs = get_vfs()
        # Disk has the modified data (Steal happened before crash)
        f = vfs.open(self.db_path, mode="w+b")
        initial_page = bytearray(DEFAULT_PAGE_SIZE)
        initial_page[20:28] = b"UNCOMMTD"
        struct.pack_into(">IQ", initial_page, 0, 0, 2)  # PageID=0, PageLSN=2
        f.write(0, bytes(initial_page))
        f.sync()
        f.close()

        # WAL contains BEGIN and UPDATE, but NO COMMIT
        writer = WALWriter(self.wal_path)
        r1 = writer.append_record(tx_id=2, record_type=LogRecordType.BEGIN)
        writer.append_record(
            tx_id=2,
            record_type=LogRecordType.UPDATE,
            prev_lsn=r1.lsn,
            page_id=0,
            offset=20,
            undo_data=b"ORIGINAL",
            redo_data=b"UNCOMMTD",
        )
        writer.flush()
        writer.close()

        # Run recovery
        recovery_mgr = ARIESRecoveryManager(self.db_path, self.wal_path)
        redo_cnt, undo_cnt = recovery_mgr.run_recovery()

        self.assertEqual(undo_cnt, 1)

        # Verify DB file page 0 at offset 20 was reverted to ORIGINAL
        f = vfs.open(self.db_path, mode="rb")
        data = f.read(0, DEFAULT_PAGE_SIZE)
        f.close()
        self.assertEqual(data[20:28], b"ORIGINAL")

        # Verify CLR and ABORT records were written to WAL
        reader = WALReader(self.wal_path)
        records = reader.read_all_records()
        record_types = [r.record_type for r in records]
        self.assertIn(LogRecordType.CLR, record_types)
        self.assertIn(LogRecordType.ABORT, record_types)

    def test_aries_recovery_with_clr_and_repeat_crash(self) -> None:
        """
        Simulates crash during recovery (after CLR was logged).
        Second recovery run should not repeat undo for CLR-logged updates.
        """
        vfs = get_vfs()
        f = vfs.open(self.db_path, mode="w+b")
        initial_page = bytearray(DEFAULT_PAGE_SIZE)
        initial_page[30:38] = b"RESTORED"
        struct.pack_into(">IQ", initial_page, 0, 0, 3)  # PageID=0, PageLSN=3 (from CLR)
        f.write(0, bytes(initial_page))
        f.sync()
        f.close()

        writer = WALWriter(self.wal_path)
        r1 = writer.append_record(tx_id=3, record_type=LogRecordType.BEGIN)
        r2 = writer.append_record(
            tx_id=3,
            record_type=LogRecordType.UPDATE,
            prev_lsn=r1.lsn,
            page_id=0,
            offset=30,
            undo_data=b"RESTORED",
            redo_data=b"CRASHED!",
        )
        writer.append_record(
            tx_id=3,
            record_type=LogRecordType.CLR,
            prev_lsn=r2.lsn,
            page_id=0,
            offset=30,
            redo_data=b"RESTORED",
            undo_next_lsn=0,
        )
        writer.flush()
        writer.close()

        # Run recovery on crash-after-CLR state
        recovery_mgr = ARIESRecoveryManager(self.db_path, self.wal_path)
        redo_cnt, undo_cnt = recovery_mgr.run_recovery()

        # Because CLR already undone the action and undo_next_lsn=0, no further undo is needed
        self.assertEqual(undo_cnt, 0)

        f = vfs.open(self.db_path, mode="rb")
        data = f.read(0, DEFAULT_PAGE_SIZE)
        f.close()
        self.assertEqual(data[30:38], b"RESTORED")

    def test_fuzzy_checkpoint_recovery(self) -> None:
        """
        Tests recovery starting from a Fuzzy Checkpoint record.
        """
        pager = Pager(self.db_path, cache_capacity=10, use_wal=True)
        pager.begin()
        pager.write_page(0, b"Tx1 Data" + b"\x00" * (DEFAULT_PAGE_SIZE - 8))
        pager.commit()

        # Take fuzzy checkpoint
        chk_lsn, dirty_cnt = pager.checkpoint()
        self.assertGreater(chk_lsn, 0)

        # Start Tx2
        pager.begin()
        pager.write_page(1, b"Tx2 Uncommitted" + b"\x00" * (DEFAULT_PAGE_SIZE - 15))
        # Flush dirty pages to simulate Steal policy before crash
        pager._flush_page_to_disk(pager.cache.get(1))
        # Sudden crash: close file handles directly without committing
        pager.file.sync()
        pager.file.close()
        if pager.wal:
            pager.wal.close()
        pager.cache.clear()
        pager.is_in_transaction = False

        # Reopen with automatic ARIES recovery
        pager_recovered = Pager(
            self.db_path, cache_capacity=10, use_wal=True, auto_recover=True
        )
        p0 = pager_recovered.read_page(0)
        self.assertEqual(p0[:8], b"Tx1 Data")
        # Page 1 must have been rolled back by Undo phase
        p1 = pager_recovered.read_page(1)
        self.assertEqual(p1[:15], b"\x00" * 15)
        pager_recovered.close()


if __name__ == "__main__":
    unittest.main()
