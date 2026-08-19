#!/usr/bin/env python3
"""
Write-Ahead Logging (WAL) Subsystem.
Implements disk-persistent WAL log records, LSN chaining, CRC32 checksum verification,
and sequential log writing/reading for ARIES crash recovery.
"""

import enum
import json
import struct
import threading
import zlib
from typing import Any, Dict, Iterator, List, Optional, Tuple, Union

from .vfs import VFS, VFSFile, get_vfs

WAL_MAGIC = b"VDBWAL01"
WAL_VERSION = 1
WAL_HEADER_SIZE = 16  # Magic (8B) + Version (2B) + PageSize (2B) + Checksum (4B)
DEFAULT_PAGE_SIZE = 4096

# Fixed Log Record Header Struct:
# LSN (8B: Q), PrevLSN (8B: Q), TxID (8B: Q), Type (1B: B), PageID (4B: I),
# Offset (2B: H), UndoLen (2B: H), RedoLen (2B: H), UndoNextLSN (8B: Q), ExtraLen (2B: H)
RECORD_HEADER_FORMAT = ">QQQBIHHHQH"
RECORD_HEADER_SIZE = struct.calcsize(RECORD_HEADER_FORMAT)  # 45 bytes
RECORD_TRAILER_FORMAT = ">II"  # Checksum (4B: I) + TotalRecordLen (4B: I)
RECORD_TRAILER_SIZE = struct.calcsize(RECORD_TRAILER_FORMAT)  # 8 bytes


class LogRecordType(enum.IntEnum):
    """Types of Write-Ahead Log records."""

    BEGIN = 1
    UPDATE = 2
    COMMIT = 3
    ABORT = 4
    CLR = 5  # Compensation Log Record (Undo)
    CHECKPOINT_BEGIN = 6
    CHECKPOINT_END = 7


class LogRecord:
    """Represents a single WAL log record."""

    def __init__(
        self,
        lsn: int,
        prev_lsn: int,
        tx_id: int,
        record_type: Union[LogRecordType, int],
        page_id: int = 0xFFFFFFFF,
        offset: int = 0,
        undo_data: bytes = b"",
        redo_data: bytes = b"",
        undo_next_lsn: int = 0,
        extra_info: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.lsn = lsn
        self.prev_lsn = prev_lsn
        self.tx_id = tx_id
        self.record_type = LogRecordType(record_type)
        self.page_id = page_id
        self.offset = offset
        self.undo_data = bytes(undo_data) if undo_data else b""
        self.redo_data = bytes(redo_data) if redo_data else b""
        self.undo_next_lsn = undo_next_lsn
        self.extra_info = extra_info or {}

    def serialize(self) -> bytes:
        """Serializes the log record to bytes with CRC32 checksum."""
        extra_bytes = (
            json.dumps(self.extra_info, ensure_ascii=False).encode("utf-8")
            if self.extra_info
            else b""
        )
        undo_len = len(self.undo_data)
        redo_len = len(self.redo_data)
        extra_len = len(extra_bytes)

        if undo_len > 65535 or redo_len > 65535 or extra_len > 65535:
            raise ValueError("Log record payload exceeds 64KB field limit")

        header_bytes = struct.pack(
            RECORD_HEADER_FORMAT,
            self.lsn,
            self.prev_lsn,
            self.tx_id,
            int(self.record_type),
            self.page_id,
            self.offset,
            undo_len,
            redo_len,
            self.undo_next_lsn,
            extra_len,
        )

        payload = self.undo_data + self.redo_data + extra_bytes
        content_to_hash = header_bytes + payload
        checksum = zlib.crc32(content_to_hash) & 0xFFFFFFFF
        total_len = RECORD_HEADER_SIZE + len(payload) + RECORD_TRAILER_SIZE

        trailer_bytes = struct.pack(RECORD_TRAILER_FORMAT, checksum, total_len)
        return header_bytes + payload + trailer_bytes

    @classmethod
    def deserialize(cls, data: bytes, offset: int = 0) -> Tuple["LogRecord", int]:
        """
        Deserializes a log record starting from offset in data buffer.
        Returns (LogRecord, next_offset).
        """
        if len(data) < offset + RECORD_HEADER_SIZE + RECORD_TRAILER_SIZE:
            raise ValueError("Insufficient data for log record header/trailer")

        (
            lsn,
            prev_lsn,
            tx_id,
            raw_type,
            page_id,
            page_offset,
            undo_len,
            redo_len,
            undo_next_lsn,
            extra_len,
        ) = struct.unpack_from(RECORD_HEADER_FORMAT, data, offset)

        payload_offset = offset + RECORD_HEADER_SIZE
        payload_len = undo_len + redo_len + extra_len
        trailer_offset = payload_offset + payload_len

        if len(data) < trailer_offset + RECORD_TRAILER_SIZE:
            raise ValueError("Insufficient data for complete log record payload")

        expected_checksum, total_len = struct.unpack_from(
            RECORD_TRAILER_FORMAT, data, trailer_offset
        )

        actual_len = RECORD_HEADER_SIZE + payload_len + RECORD_TRAILER_SIZE
        if total_len != actual_len:
            raise ValueError(
                f"Record length mismatch: expected {total_len}, got {actual_len}"
            )

        content_to_hash = data[offset:trailer_offset]
        actual_checksum = zlib.crc32(content_to_hash) & 0xFFFFFFFF
        if expected_checksum != actual_checksum:
            raise ValueError(
                f"CRC32 checksum mismatch: expected {expected_checksum:#x}, got {actual_checksum:#x}"
            )

        undo_data = data[payload_offset : payload_offset + undo_len]
        redo_offset = payload_offset + undo_len
        redo_data = data[redo_offset : redo_offset + redo_len]
        extra_offset = redo_offset + redo_len
        extra_bytes = data[extra_offset : extra_offset + extra_len]

        extra_info: Dict[str, Any] = {}
        if extra_bytes:
            extra_info = json.loads(extra_bytes.decode("utf-8"))

        record = cls(
            lsn=lsn,
            prev_lsn=prev_lsn,
            tx_id=tx_id,
            record_type=LogRecordType(raw_type),
            page_id=page_id,
            offset=page_offset,
            undo_data=undo_data,
            redo_data=redo_data,
            undo_next_lsn=undo_next_lsn,
            extra_info=extra_info,
        )
        return record, trailer_offset + RECORD_TRAILER_SIZE

    def __repr__(self) -> str:
        return (
            f"<LogRecord LSN={self.lsn} Tx={self.tx_id} Type={self.record_type.name} "
            f"Page={self.page_id} PrevLSN={self.prev_lsn}>"
        )


class WALWriter:
    """
    Manages sequential writes to the on-disk WAL file (<dbname>.vdb-wal).
    Assigns monotonically increasing 64-bit LSNs and coordinates fsync boundaries.
    """

    def __init__(
        self,
        wal_path: str,
        vfs_name: Optional[str] = None,
        vfs: Optional[VFS] = None,
        page_size: int = DEFAULT_PAGE_SIZE,
    ) -> None:
        self.wal_path = wal_path
        self.vfs_name = vfs_name
        self.vfs = vfs if vfs is not None else get_vfs(vfs_name)
        self.page_size = page_size
        self._lock = threading.RLock()
        self.file: VFSFile = self.vfs.open(wal_path, mode="a+b")
        self._next_lsn = 1
        self._flushed_lsn = 0
        self._init_header_if_needed()

    def _init_header_if_needed(self) -> None:
        with self._lock:
            size = self.file.file_size()
            if size == 0:
                header_data = bytearray(WAL_HEADER_SIZE)
                struct.pack_into(
                    ">8sHH", header_data, 0, WAL_MAGIC, WAL_VERSION, self.page_size
                )
                chk = zlib.crc32(header_data[:12]) & 0xFFFFFFFF
                struct.pack_into(">I", header_data, 12, chk)
                self.file.write(0, bytes(header_data))
                self.file.sync()
                self._next_lsn = 1
                self._flushed_lsn = 0
            else:
                # Scan existing records to find highest LSN
                reader = WALReader(self.wal_path, vfs=self.vfs)
                records = reader.read_all_records()
                if records:
                    self._next_lsn = records[-1].lsn + 1
                    self._flushed_lsn = records[-1].lsn
                else:
                    self._next_lsn = 1
                    self._flushed_lsn = 0

    @property
    def next_lsn(self) -> int:
        with self._lock:
            return self._next_lsn

    @property
    def flushed_lsn(self) -> int:
        with self._lock:
            return self._flushed_lsn

    def append_record(
        self,
        tx_id: int,
        record_type: LogRecordType,
        prev_lsn: int = 0,
        page_id: int = 0xFFFFFFFF,
        offset: int = 0,
        undo_data: bytes = b"",
        redo_data: bytes = b"",
        undo_next_lsn: int = 0,
        extra_info: Optional[Dict[str, Any]] = None,
        force_sync: bool = False,
    ) -> LogRecord:
        """Appends a new log record to the WAL file with atomic LSN generation."""
        with self._lock:
            lsn = self._next_lsn
            self._next_lsn += 1

            record = LogRecord(
                lsn=lsn,
                prev_lsn=prev_lsn,
                tx_id=tx_id,
                record_type=record_type,
                page_id=page_id,
                offset=offset,
                undo_data=undo_data,
                redo_data=redo_data,
                undo_next_lsn=undo_next_lsn,
                extra_info=extra_info,
            )

            serialized = record.serialize()
            current_file_size = self.file.file_size()
            self.file.write(current_file_size, serialized)

            if force_sync or record_type in (
                LogRecordType.COMMIT,
                LogRecordType.ABORT,
                LogRecordType.CHECKPOINT_END,
            ):
                self.flush()
            else:
                self._flushed_lsn = lsn

            return record

    def flush(self) -> None:
        """Flushes written WAL records to disk via fsync."""
        with self._lock:
            self.file.sync()
            self._flushed_lsn = self._next_lsn - 1

    def truncate(self) -> None:
        """Truncates WAL file to header size and resets LSN counters."""
        with self._lock:
            header_data = bytearray(WAL_HEADER_SIZE)
            struct.pack_into(
                ">8sHH", header_data, 0, WAL_MAGIC, WAL_VERSION, self.page_size
            )
            chk = zlib.crc32(header_data[:12]) & 0xFFFFFFFF
            struct.pack_into(">I", header_data, 12, chk)
            self.file.truncate(WAL_HEADER_SIZE)
            self.file.write(0, bytes(header_data))
            self.file.sync()
            self._next_lsn = 1
            self._flushed_lsn = 0

    def close(self) -> None:
        with self._lock:
            self.flush()
            self.file.close()


class WALReader:
    """
    Reads and validates WAL records sequentially or from a specific LSN.
    Used by ARIES recovery and transaction rollback.
    """

    def __init__(
        self,
        wal_path: str,
        vfs_name: Optional[str] = None,
        vfs: Optional[VFS] = None,
    ) -> None:
        self.wal_path = wal_path
        self.vfs_name = vfs_name
        self.vfs = vfs if vfs is not None else get_vfs(vfs_name)

    def validate_header(self, file_handle: VFSFile) -> int:
        """Validates WAL file header and returns page_size."""
        if file_handle.file_size() < WAL_HEADER_SIZE:
            raise ValueError("WAL file is smaller than WAL_HEADER_SIZE")

        raw_header = file_handle.read(0, WAL_HEADER_SIZE)
        magic, version, page_size, expected_chk = struct.unpack(">8sHHI", raw_header)
        if magic != WAL_MAGIC:
            raise ValueError(f"Invalid WAL magic header: {magic!r}")
        if version != WAL_VERSION:
            raise ValueError(f"Unsupported WAL version: {version}")

        actual_chk = zlib.crc32(raw_header[:12]) & 0xFFFFFFFF
        if expected_chk != actual_chk:
            raise ValueError("WAL header CRC32 checksum corruption detected")

        return int(page_size)

    def read_all_records(self) -> List[LogRecord]:
        """Reads all valid log records in the WAL file."""
        records: List[LogRecord] = []
        if not self.vfs.exists(self.wal_path):
            return records

        file_handle = self.vfs.open(self.wal_path, mode="rb")
        try:
            if file_handle.file_size() < WAL_HEADER_SIZE:
                return records
            self.validate_header(file_handle)

            offset = WAL_HEADER_SIZE
            total_size = file_handle.file_size()
            raw_data = file_handle.read(0, total_size)

            while offset < len(raw_data):
                try:
                    record, next_offset = LogRecord.deserialize(raw_data, offset)
                    records.append(record)
                    offset = next_offset
                except Exception:
                    # Encountered corrupted or partially written record at EOF
                    break
            return records
        finally:
            file_handle.close()

    def iter_records_from(self, start_lsn: int = 1) -> Iterator[LogRecord]:
        """Yields log records sequentially starting at or after start_lsn."""
        for rec in self.read_all_records():
            if rec.lsn >= start_lsn:
                yield rec
