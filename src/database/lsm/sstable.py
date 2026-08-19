#!/usr/bin/env python3
"""
SSTable (Sorted String Table) Binary Format, Sparse Index, and Reader/Writer.
Provides immutable on-disk storage with 4KB Data Blocks, Sparse Index binary search,
Bloom Filter integration, and CRC32 integrity verification.
"""

import bisect
import json
import struct
import zlib
from typing import Any, List, Optional, Tuple

from ..vfs import VFS, VFSFile, get_vfs
from .bloom_filter import BloomFilter
from .memtable import TOMBSTONE

SSTABLE_MAGIC: bytes = b"VDBSST01"
FOOTER_FORMAT: str = "<IIII8sI"
FOOTER_SIZE: int = struct.calcsize(
    FOOTER_FORMAT
)  # 4 + 4 + 4 + 4 + 8 + 4 = 28 bytes (+ 4 pad = 32)
BLOCK_SIZE_TARGET: int = 4096


class SSTableWriter:
    """Writes sorted key-value pairs into an immutable SSTable file."""

    def __init__(
        self,
        file_path: str,
        vfs: Optional[VFS] = None,
        block_size: int = BLOCK_SIZE_TARGET,
    ) -> None:
        self.file_path = file_path
        self.vfs: VFS = vfs if vfs is not None else get_vfs()
        self.block_size = block_size

    def write(self, entries: List[Tuple[str, bytes]]) -> int:
        """
        Serializes sorted entries into Data Blocks, builds Sparse Index and Bloom Filter,
        and writes the SSTable file. Returns total bytes written.
        """
        if not entries:
            return 0

        # Sort entries ascending by key
        sorted_entries = sorted(entries, key=lambda x: x[0])
        bloom = BloomFilter(expected_items=max(len(sorted_entries), 100), fp_rate=0.01)

        data_blocks_bytes = bytearray()
        sparse_index: List[Tuple[str, int, int]] = []  # (first_key, offset, length)

        curr_block = bytearray()
        curr_first_key: Optional[str] = None
        block_start_offset = 0

        for key, val in sorted_entries:
            bloom.add(key)
            k_bytes = key.encode("utf-8")
            v_bytes = val

            rec_bytes = (
                struct.pack("<HH", len(k_bytes), len(v_bytes)) + k_bytes + v_bytes
            )

            if len(curr_block) + len(rec_bytes) > self.block_size and curr_block:
                # Flush current block
                if curr_first_key is not None:
                    sparse_index.append(
                        (curr_first_key, block_start_offset, len(curr_block))
                    )
                data_blocks_bytes.extend(curr_block)
                block_start_offset = len(data_blocks_bytes)
                curr_block = bytearray()
                curr_first_key = None

            if curr_first_key is None:
                curr_first_key = key
            curr_block.extend(rec_bytes)

        if curr_block:
            if curr_first_key is not None:
                sparse_index.append(
                    (curr_first_key, block_start_offset, len(curr_block))
                )
            data_blocks_bytes.extend(curr_block)

        # Build Sparse Index binary
        index_bytes = bytearray(struct.pack("<I", len(sparse_index)))
        for first_key, offset, length in sparse_index:
            fk_bytes = first_key.encode("utf-8")
            index_bytes.extend(
                struct.pack("<HII", len(fk_bytes), offset, length) + fk_bytes
            )

        # Build Bloom Filter binary
        bloom_bytes = bloom.to_bytes()

        index_offset = len(data_blocks_bytes)
        index_len = len(index_bytes)
        bloom_offset = index_offset + index_len
        bloom_len = len(bloom_bytes)

        # Build Footer
        footer_payload = struct.pack(
            "<IIII8s",
            index_offset,
            index_len,
            bloom_offset,
            bloom_len,
            SSTABLE_MAGIC,
        )
        footer_crc = zlib.crc32(footer_payload)
        footer_bytes = footer_payload + struct.pack("<I", footer_crc)

        full_payload = (
            bytes(data_blocks_bytes)
            + bytes(index_bytes)
            + bytes(bloom_bytes)
            + bytes(footer_bytes)
        )

        f: VFSFile = self.vfs.open(self.file_path, mode="w+b")
        try:
            f.write(0, full_payload)
            f.sync()
        finally:
            f.close()

        return len(full_payload)


class SSTableReader:
    """Reads and queries an immutable SSTable file using Sparse Index and Bloom Filter."""

    def __init__(self, file_path: str, vfs: Optional[VFS] = None) -> None:
        self.file_path = file_path
        self.vfs: VFS = vfs if vfs is not None else get_vfs()
        self.file: VFSFile = self.vfs.open(self.file_path, mode="r+b")
        self.sparse_index: List[Tuple[str, int, int]] = []
        self.bloom: Optional[BloomFilter] = None
        self._load_metadata()

    def _load_metadata(self) -> None:
        file_size = self.file.file_size()
        if file_size < FOOTER_SIZE:
            raise ValueError(
                f"SSTable file {self.file_path!r} is too small to contain a footer"
            )

        # Read Footer
        footer_raw = self.file.read(file_size - FOOTER_SIZE, FOOTER_SIZE)
        index_offset, index_len, bloom_offset, bloom_len, magic, crc = (
            struct.unpack_from(FOOTER_FORMAT, footer_raw, 0)
        )
        if magic != SSTABLE_MAGIC:
            raise ValueError(f"Invalid SSTable magic header: {magic!r}")

        expected_crc = zlib.crc32(footer_raw[:24])
        if crc != expected_crc:
            raise ValueError("SSTable footer CRC32 checksum verification failed")

        # Read Bloom Filter
        bloom_raw = self.file.read(bloom_offset, bloom_len)
        self.bloom = BloomFilter.from_bytes(bloom_raw)

        # Read Sparse Index
        index_raw = self.file.read(index_offset, index_len)
        idx_count = struct.unpack_from("<I", index_raw, 0)[0]
        pos = 4
        self.sparse_index = []
        for _ in range(idx_count):
            fk_len, off, length = struct.unpack_from("<HII", index_raw, pos)
            pos += 10
            first_key = index_raw[pos : pos + fk_len].decode("utf-8")
            pos += fk_len
            self.sparse_index.append((first_key, off, length))

    def _decode_val(self, raw_val: bytes) -> Optional[Any]:
        if raw_val == TOMBSTONE:
            return None
        try:
            return json.loads(raw_val.decode("utf-8"))
        except Exception:
            try:
                return raw_val.decode("utf-8")
            except Exception:
                return raw_val

    def _scan_block_for_key(
        self, block_raw: bytes, target_key: str
    ) -> Tuple[bool, Optional[Any]]:
        pos = 0
        while pos < len(block_raw):
            if pos + 4 > len(block_raw):
                break
            k_len, v_len = struct.unpack_from("<HH", block_raw, pos)
            pos += 4
            if k_len == 0 or pos + k_len + v_len > len(block_raw):
                break
            curr_key = block_raw[pos : pos + k_len].decode("utf-8")
            pos += k_len
            curr_val = block_raw[pos : pos + v_len]
            pos += v_len

            if curr_key == target_key:
                return True, self._decode_val(curr_val)
            if curr_key > target_key:
                break
        return False, None

    def get(self, key: str) -> Tuple[bool, Optional[Any]]:
        """
        Looks up key in SSTable.
        Returns:
            (True, data) if key found
            (True, None) if key found as TOMBSTONE (deleted)
            (False, None) if key is NOT in this SSTable
        """
        if self.bloom is not None and not self.bloom.contains(key):
            return False, None

        if not self.sparse_index:
            return False, None

        keys_only = [item[0] for item in self.sparse_index]
        idx = bisect.bisect_right(keys_only, key) - 1
        if idx < 0:
            idx = 0

        first_key, block_off, block_len = self.sparse_index[idx]
        block_raw = self.file.read(block_off, block_len)
        return self._scan_block_for_key(block_raw, key)

    def scan_all(self) -> List[Tuple[str, bytes]]:
        """Reads all entries from the SSTable in sorted key order."""
        results: List[Tuple[str, bytes]] = []
        for _, block_off, block_len in self.sparse_index:
            block_raw = self.file.read(block_off, block_len)
            pos = 0
            while pos < len(block_raw):
                if pos + 4 > len(block_raw):
                    break
                k_len, v_len = struct.unpack_from("<HH", block_raw, pos)
                pos += 4
                if k_len == 0 or pos + k_len + v_len > len(block_raw):
                    break
                curr_key = block_raw[pos : pos + k_len].decode("utf-8")
                pos += k_len
                curr_val = block_raw[pos : pos + v_len]
                pos += v_len
                results.append((curr_key, curr_val))
        return results

    def close(self) -> None:
        """Closes the underlying VFS file handle."""
        self.file.close()
