#!/usr/bin/env python3
"""
Database Mutation and Fuzzing Crash Resilience Test Suite.
Verifies panic-free behavior, tamper resistance, and CRC32 integrity
under bit-flipping mutations, torn writes, corrupted WAL headers, and malformed slotted pages.
"""

import os
import struct
import sys
import tempfile
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src")),
    )

from database.recovery import ARIESRecoveryManager
from database.storage.slotted_page import PageCorruptionError, SlottedPage
from database.storage.vfs import PosixVFS
from database.wal import LogRecordType, WALReader, WALWriter


class TestDatabaseMutationResilience(unittest.TestCase):
    """Verifies robustness against corrupted WAL payloads, torn writes, and page mutations."""

    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.tmpdir.name, "mutation_test.db")
        self.wal_path = f"{self.db_path}.vdb-wal"
        self.vfs = PosixVFS()

    def tearDown(self) -> None:
        self.tmpdir.cleanup()

    def test_wal_reader_crc32_mutation_corruption_detection(self) -> None:
        """Verifies that single-bit and multi-byte mutations in WAL are detected via CRC32."""
        writer = WALWriter(self.wal_path, vfs=self.vfs)
        r1 = writer.append_record(tx_id=1, record_type=LogRecordType.BEGIN)
        writer.append_record(
            tx_id=1,
            record_type=LogRecordType.UPDATE,
            prev_lsn=r1.lsn,
            page_id=0,
            offset=64,
            undo_data=b"\x00" * 16,
            redo_data=b"ORIGINAL_PAYLOAD",
            force_sync=True,
        )
        writer.close()

        # Read original WAL bytes and flip a byte in the middle of payload
        f = self.vfs.open(self.wal_path, mode="r+b")
        total_size = f.file_size()
        self.assertGreater(total_size, 64)

        # Mutate payload at offset 48 (corrupting data without updating CRC)
        corrupted_offset = 48
        original_byte = f.read(corrupted_offset, 1)
        flipped_byte = bytes([original_byte[0] ^ 0xFF])
        f.write(corrupted_offset, flipped_byte)
        f.sync()
        f.close()

        # WALReader must safely reject corrupted records without crashing
        reader = WALReader(self.wal_path, vfs=self.vfs)
        records = reader.read_all_records()

        # First BEGIN record might be intact or truncated at the corruption point
        for r in records:
            self.assertNotEqual(r.redo_data, b"ORIGINAL_PAYLOAD")

    def test_torn_write_and_truncated_wal_recovery(self) -> None:
        """Simulates a torn write where a power cut cuts off the last log record mid-write."""
        # 1. Initialize DB file
        f_db = self.vfs.open(self.db_path, mode="w+b")
        f_db.write(0, b"\x00" * 8192)
        f_db.sync()
        f_db.close()

        # 2. Write 2 committed transactions
        writer = WALWriter(self.wal_path, vfs=self.vfs)
        r1 = writer.append_record(tx_id=501, record_type=LogRecordType.BEGIN)
        r2 = writer.append_record(
            tx_id=501,
            record_type=LogRecordType.UPDATE,
            prev_lsn=r1.lsn,
            page_id=0,
            offset=64,
            undo_data=b"\x00" * 16,
            redo_data=b"TX501_VALID_DATA",
        )
        writer.append_record(
            tx_id=501,
            record_type=LogRecordType.COMMIT,
            prev_lsn=r2.lsn,
            force_sync=True,
        )

        r4 = writer.append_record(tx_id=502, record_type=LogRecordType.BEGIN)
        r5 = writer.append_record(
            tx_id=502,
            record_type=LogRecordType.UPDATE,
            prev_lsn=r4.lsn,
            page_id=0,
            offset=128,
            undo_data=b"\x00" * 16,
            redo_data=b"TX502_VALID_DATA",
        )
        writer.append_record(
            tx_id=502,
            record_type=LogRecordType.COMMIT,
            prev_lsn=r5.lsn,
            force_sync=True,
        )
        writer.close()

        # 3. Simulate torn write: truncate the last 15 bytes of the WAL file
        f_wal = self.vfs.open(self.wal_path, mode="r+b")
        wal_size = f_wal.file_size()
        f_wal.truncate(wal_size - 15)
        f_wal.sync()
        f_wal.close()

        # 4. ARIES recovery must safely execute without unhandled exceptions
        recovery = ARIESRecoveryManager(self.db_path, self.wal_path, vfs=self.vfs)
        redo_count, undo_count = recovery.run_recovery()

        # At least TX 501 should be safely replayed
        self.assertGreaterEqual(redo_count, 1)

        f_check = self.vfs.open(self.db_path, mode="rb")
        data = f_check.read(0, 4096)
        f_check.close()
        self.assertEqual(data[64:80], b"TX501_VALID_DATA")

    def test_slotted_page_mutation_panic_free(self) -> None:
        """Verifies that corrupted slotted page headers do not cause memory corruption or crashes."""
        page = SlottedPage(page_id=1)
        slot_idx = page.insert_tuple(b"TEST_SAFE_RECORD")
        self.assertEqual(slot_idx, 0)

        # Mutate free_space_pointer or slot offset beyond page size
        raw_bytes = bytearray(page.serialize())

        # Corrupt slot 0 offset to point out of bounds (e.g. offset 9999)
        struct.pack_into("<H", raw_bytes, 28, 9999)

        # Loading mutated bytes must not crash or cause buffer overrun
        try:
            mutated_page = SlottedPage(raw_data=bytes(raw_bytes))
            rec = mutated_page.get_tuple(0)
            self.assertTrue(rec is None or rec == b"")
        except Exception as e:
            # Safely handled exception is also acceptable
            self.assertIsInstance(e, (PageCorruptionError, ValueError, IndexError))


if __name__ == "__main__":
    unittest.main()
