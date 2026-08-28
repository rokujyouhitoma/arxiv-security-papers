#!/usr/bin/env python3
"""Backward-compatibility shim for database.transaction.wal."""

from .transaction.wal import (
    DEFAULT_PAGE_SIZE,
    RECORD_HEADER_FORMAT,
    RECORD_HEADER_SIZE,
    RECORD_TRAILER_FORMAT,
    RECORD_TRAILER_SIZE,
    WAL_HEADER_SIZE,
    WAL_MAGIC,
    WAL_VERSION,
    LogRecord,
    LogRecordType,
    WALReader,
    WALWriter,
)

__all__ = [
    "DEFAULT_PAGE_SIZE",
    "LogRecord",
    "LogRecordType",
    "RECORD_HEADER_FORMAT",
    "RECORD_HEADER_SIZE",
    "RECORD_TRAILER_FORMAT",
    "RECORD_TRAILER_SIZE",
    "WALReader",
    "WALWriter",
    "WAL_HEADER_SIZE",
    "WAL_MAGIC",
    "WAL_VERSION",
]
