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

from ..storage.slotted_page import PAGE_SIZE, PageFullError, SlottedPage
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
        use_slotted_page: Optional[bool] = None,
    ) -> None:
        self.file_path = file_path
        self.vfs: VFS = vfs if vfs is not None else get_vfs()
        self.block_size = block_size
        if use_slotted_page is not None:
            self.use_slotted_page = use_slotted_page
        else:
            self.use_slotted_page = bool(block_size >= PAGE_SIZE)

    def _encode_record(self, key: str, val: bytes) -> bytes:
        k_bytes = key.encode("utf-8")
        return struct.pack("<HH", len(k_bytes), len(val)) + k_bytes + val

    def _flush_block(
        self,
        curr_block: bytearray,
        curr_first_key: Optional[str],
        sparse_index: List[Tuple[str, int, int]],
        data_blocks_bytes: bytearray,
    ) -> int:
        if curr_first_key is not None:
            sparse_index.append(
                (curr_first_key, len(data_blocks_bytes), len(curr_block))
            )
        data_blocks_bytes.extend(curr_block)
        return len(data_blocks_bytes)

    def _build_index_bytes(self, sparse_index: List[Tuple[str, int, int]]) -> bytearray:
        index_bytes = bytearray(struct.pack("<I", len(sparse_index)))
        for first_key, offset, length in sparse_index:
            fk_bytes = first_key.encode("utf-8")
            index_bytes.extend(
                struct.pack("<HII", len(fk_bytes), offset, length) + fk_bytes
            )
        return index_bytes

    def _should_flush_block(self, curr_block: bytearray, rec_len: int) -> bool:
        if not curr_block:
            return False
        return len(curr_block) + rec_len > self.block_size

    def _insert_slotted_entry(
        self,
        key: str,
        rec_bytes: bytes,
        curr_page: SlottedPage,
        page_id: int,
        curr_first_key: str,
        data_blocks: bytearray,
        sparse_index: List[Tuple[str, int, int]],
    ) -> Tuple[SlottedPage, int, str]:
        try:
            curr_page.insert_tuple(rec_bytes)
            return curr_page, page_id, curr_first_key
        except PageFullError:
            sparse_index.append((curr_first_key, len(data_blocks), PAGE_SIZE))
            data_blocks.extend(curr_page.data)
            new_page = SlottedPage(page_id=page_id + 1)
            new_page.insert_tuple(rec_bytes)
            return new_page, page_id + 1, key

    def _build_slotted_data_blocks(
        self, sorted_entries: List[Tuple[str, bytes]], bloom: BloomFilter
    ) -> Tuple[bytearray, List[Tuple[str, int, int]]]:
        data_blocks: bytearray = bytearray()
        sparse_index: List[Tuple[str, int, int]] = []
        page_id = 0
        curr_page = SlottedPage(page_id=page_id)
        curr_first_key: Optional[str] = None
        for key, val in sorted_entries:
            bloom.add(key)
            rec_bytes = self._encode_record(key, val)
            first_k = key if curr_first_key is None else curr_first_key
            curr_page, page_id, curr_first_key = self._insert_slotted_entry(
                key, rec_bytes, curr_page, page_id, first_k, data_blocks, sparse_index
            )
        if curr_first_key is not None and curr_page.slot_count > 0:
            sparse_index.append((curr_first_key, len(data_blocks), PAGE_SIZE))
            data_blocks.extend(curr_page.data)
        return data_blocks, sparse_index

    def _append_data_entry(
        self,
        key: str,
        rec_bytes: bytes,
        curr_block: bytearray,
        curr_first_key: Optional[str],
        sparse_index: List[Tuple[str, int, int]],
        data_blocks: bytearray,
    ) -> Tuple[bytearray, str]:
        if self._should_flush_block(curr_block, len(rec_bytes)):
            self._flush_block(curr_block, curr_first_key, sparse_index, data_blocks)
            curr_block = bytearray()
            curr_first_key = None
        first_k = key if curr_first_key is None else curr_first_key
        curr_block.extend(rec_bytes)
        return curr_block, first_k

    def _build_data_blocks(
        self, sorted_entries: List[Tuple[str, bytes]], bloom: BloomFilter
    ) -> Tuple[bytearray, List[Tuple[str, int, int]]]:
        if self.use_slotted_page:
            return self._build_slotted_data_blocks(sorted_entries, bloom)
        data_blocks: bytearray = bytearray()
        sparse_index: List[Tuple[str, int, int]] = []
        curr_block: bytearray = bytearray()
        curr_first_key: Optional[str] = None
        for key, val in sorted_entries:
            bloom.add(key)
            rec_bytes = self._encode_record(key, val)
            curr_block, curr_first_key = self._append_data_entry(
                key, rec_bytes, curr_block, curr_first_key, sparse_index, data_blocks
            )
        if curr_block:
            self._flush_block(curr_block, curr_first_key, sparse_index, data_blocks)
        return data_blocks, sparse_index

    @staticmethod
    def _assemble_sstable_payload(
        data_blocks_bytes: bytearray, index_bytes: bytearray, bloom_bytes: bytes
    ) -> bytes:
        index_offset = len(data_blocks_bytes)
        bloom_offset = index_offset + len(index_bytes)
        footer_payload = struct.pack(
            "<IIII8s",
            index_offset,
            len(index_bytes),
            bloom_offset,
            len(bloom_bytes),
            SSTABLE_MAGIC,
        )
        footer_bytes = footer_payload + struct.pack("<I", zlib.crc32(footer_payload))
        return (
            bytes(data_blocks_bytes)
            + bytes(index_bytes)
            + bytes(bloom_bytes)
            + bytes(footer_bytes)
        )

    def write(self, entries: List[Tuple[str, bytes]]) -> int:
        """
        Serializes sorted entries into Data Blocks, builds Sparse Index and Bloom Filter,
        and writes the SSTable file. Returns total bytes written.
        """
        if not entries:
            return 0
        sorted_entries = sorted(entries, key=lambda x: x[0])
        bloom = BloomFilter(expected_items=max(len(sorted_entries), 100), fp_rate=0.01)
        data_blocks_bytes, sparse_index = self._build_data_blocks(sorted_entries, bloom)
        index_bytes = self._build_index_bytes(sparse_index)
        full_payload = self._assemble_sstable_payload(
            data_blocks_bytes, index_bytes, bloom.to_bytes()
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

    @staticmethod
    def _read_block_entry(
        block_raw: bytes, pos: int
    ) -> Optional[Tuple[str, bytes, int]]:
        """Returns (curr_key, curr_val, next_pos) or None if end of block."""
        if pos + 4 > len(block_raw):
            return None
        k_len, v_len = struct.unpack_from("<HH", block_raw, pos)
        pos += 4
        if k_len == 0 or pos + k_len + v_len > len(block_raw):
            return None
        curr_key = block_raw[pos : pos + k_len].decode("utf-8")
        pos += k_len
        curr_val = block_raw[pos : pos + v_len]
        pos += v_len
        return curr_key, curr_val, pos

    def _match_page_tuple(
        self, raw_tuple: Optional[bytes], target_key: str
    ) -> Optional[Tuple[bool, Optional[Any]]]:
        if not raw_tuple:
            return None
        entry = self._read_block_entry(raw_tuple, 0)
        if entry is None:
            return None
        curr_key, curr_val, _ = entry
        if curr_key == target_key:
            return True, self._decode_val(curr_val)
        if curr_key > target_key:
            return False, None
        return None

    def _scan_slotted_page_for_key(
        self, block_raw: bytes, target_key: str
    ) -> Optional[Tuple[bool, Optional[Any]]]:
        if len(block_raw) != PAGE_SIZE:
            return None
        try:
            page = SlottedPage(raw_data=block_raw)
            for s_id in range(page.slot_count):
                res = self._match_page_tuple(page.get_tuple(s_id), target_key)
                if res is not None:
                    return res
            return False, None
        except Exception:
            return None

    def _scan_raw_block_for_key(
        self, block_raw: bytes, target_key: str
    ) -> Tuple[bool, Optional[Any]]:
        pos = 0
        while pos < len(block_raw):
            entry = self._read_block_entry(block_raw, pos)
            if entry is None:
                break
            curr_key, curr_val, pos = entry
            if curr_key == target_key:
                return True, self._decode_val(curr_val)
            if curr_key > target_key:
                break
        return False, None

    def _scan_block_for_key(
        self, block_raw: bytes, target_key: str
    ) -> Tuple[bool, Optional[Any]]:
        res = self._scan_slotted_page_for_key(block_raw, target_key)
        if res is not None:
            return res
        return self._scan_raw_block_for_key(block_raw, target_key)

    def _find_block_idx(self, key: str) -> int:
        keys_only = [item[0] for item in self.sparse_index]
        idx = bisect.bisect_right(keys_only, key) - 1
        return max(idx, 0)

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
        _, block_off, block_len = self.sparse_index[self._find_block_idx(key)]
        return self._scan_block_for_key(self.file.read(block_off, block_len), key)

    def _extract_tuple_entry(
        self, raw_tuple: Optional[bytes]
    ) -> Optional[Tuple[str, bytes]]:
        if not raw_tuple:
            return None
        entry = self._read_block_entry(raw_tuple, 0)
        return (entry[0], entry[1]) if entry is not None else None

    def _scan_slotted_entries(
        self, block_raw: bytes
    ) -> Optional[List[Tuple[str, bytes]]]:
        if len(block_raw) != PAGE_SIZE:
            return None
        try:
            page = SlottedPage(raw_data=block_raw)
            entries: List[Tuple[str, bytes]] = []
            for s_id in range(page.slot_count):
                item = self._extract_tuple_entry(page.get_tuple(s_id))
                if item is not None:
                    entries.append(item)
            return entries
        except Exception:
            return None

    def _scan_raw_entries(self, block_raw: bytes) -> List[Tuple[str, bytes]]:
        entries: List[Tuple[str, bytes]] = []
        pos = 0
        while pos < len(block_raw):
            entry = self._read_block_entry(block_raw, pos)
            if entry is None:
                break
            curr_key, curr_val, pos = entry
            entries.append((curr_key, curr_val))
        return entries

    def scan_all(self) -> List[Tuple[str, bytes]]:
        """Reads all entries from the SSTable in sorted key order."""
        results: List[Tuple[str, bytes]] = []
        for _, block_off, block_len in self.sparse_index:
            block_raw = self.file.read(block_off, block_len)
            slotted = self._scan_slotted_entries(block_raw)
            if slotted is not None:
                results.extend(slotted)
            else:
                results.extend(self._scan_raw_entries(block_raw))
        return results

    def close(self) -> None:
        """Closes the underlying VFS file handle."""
        self.file.close()
