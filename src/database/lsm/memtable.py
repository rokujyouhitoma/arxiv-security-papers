#!/usr/bin/env python3
"""
MemTable (In-Memory Sorted Buffer) Subsystem for LSM-Tree Storage.
Buffers writes, updates, and tombstones in sorted order before SSTable flush.
"""

import json
import threading
from typing import Any, Dict, List, Optional, Tuple

TOMBSTONE: bytes = b"__LSM_TOMBSTONE__"


class MemTable:
    """
    In-memory sorted write buffer with tombstone deletion support.
    """

    def __init__(self, max_bytes: int = 65536) -> None:
        self.max_bytes = max_bytes
        self._entries: Dict[str, bytes] = {}
        self._approx_bytes: int = 0
        self._lock = threading.RLock()
        self.is_immutable: bool = False

    def __len__(self) -> int:
        with self._lock:
            return len(self._entries)

    @property
    def byte_size(self) -> int:
        with self._lock:
            return self._approx_bytes

    def is_full(self) -> bool:
        """Returns True if the MemTable size has exceeded max_bytes capacity."""
        with self._lock:
            return self._approx_bytes >= self.max_bytes

    def put(self, key: str, value: Any) -> None:
        """Puts a key-value record into the MemTable."""
        if isinstance(value, (bytes, bytearray)):
            val_bytes = bytes(value)
        elif isinstance(value, str):
            val_bytes = value.encode("utf-8")
        else:
            val_bytes = json.dumps(value, ensure_ascii=False).encode("utf-8")

        key_bytes_len = len(key.encode("utf-8"))
        with self._lock:
            old_val = self._entries.get(key)
            if old_val is not None:
                self._approx_bytes -= len(old_val)
            else:
                self._approx_bytes += key_bytes_len

            self._entries[key] = val_bytes
            self._approx_bytes += len(val_bytes)

    def delete(self, key: str) -> None:
        """Records a tombstone deletion marker for key."""
        with self._lock:
            self.put(key, TOMBSTONE)

    def get(self, key: str) -> Tuple[bool, Optional[Any]]:
        """
        Looks up key in MemTable.
        Returns:
            (True, data) if key exists with normal data
            (True, None) if key exists as a TOMBSTONE (deleted)
            (False, None) if key is NOT in this MemTable
        """
        with self._lock:
            if key not in self._entries:
                return False, None

            raw = self._entries[key]
            if raw == TOMBSTONE:
                return True, None

            try:
                decoded_json = json.loads(raw.decode("utf-8"))
                return True, decoded_json
            except Exception:
                try:
                    return True, raw.decode("utf-8")
                except Exception:
                    return True, raw

    def items(self) -> List[Tuple[str, bytes]]:
        """Returns all entries sorted by key ascending."""
        with self._lock:
            return sorted(self._entries.items(), key=lambda x: x[0])

    @staticmethod
    def _is_before_start(k: str, start_key: Optional[str]) -> bool:
        if start_key is None:
            return False
        return k < start_key

    @staticmethod
    def _is_past_end(k: str, end_key: Optional[str]) -> bool:
        if end_key is None:
            return False
        return k >= end_key

    def scan(
        self,
        start_key: Optional[str] = None,
        end_key: Optional[str] = None,
    ) -> List[Tuple[str, bytes]]:
        """Scans range [start_key, end_key) in sorted key order."""
        with self._lock:
            result: List[Tuple[str, bytes]] = []
            for k, v in sorted(self._entries.items(), key=lambda x: x[0]):
                if self._is_before_start(k, start_key):
                    continue
                if self._is_past_end(k, end_key):
                    break
                result.append((k, v))
            return result

    def clear(self) -> None:
        """Clears all entries."""
        with self._lock:
            self._entries.clear()
            self._approx_bytes = 0
            self.is_immutable = False
