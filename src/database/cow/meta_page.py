#!/usr/bin/env python3
"""
Double Meta Page Management for CoW B-Tree Storage.
Provides crash-resilient ACID durability via Ping-Pong alternating Meta Pages (Page 0 and 1).
"""

import struct
import zlib
from typing import Optional, Tuple

from .mmap_file import MMapFile

META_MAGIC: bytes = b"VDBCOW01"
META_FORMAT: str = "<8sQQIII"
META_SIZE: int = struct.calcsize(META_FORMAT)  # 8 + 8 + 8 + 4 + 4 + 4 = 36 bytes


class MetaPage:
    """
    Metadata header describing database snapshot root, transaction ID, and free list.
    """

    def __init__(
        self,
        tx_id: int = 0,
        root_page_id: int = 0,
        page_count: int = 2,
        free_list_head: int = 0,
        slot: int = 0,
    ) -> None:
        self.tx_id = tx_id
        self.root_page_id = root_page_id
        self.page_count = page_count
        self.free_list_head = free_list_head
        self.slot = slot

    def serialize(self) -> bytes:
        """Packs meta page header with CRC32 checksum."""
        payload = struct.pack(
            "<8sQQII",
            META_MAGIC,
            self.tx_id,
            self.root_page_id,
            self.page_count,
            self.free_list_head,
        )
        crc = zlib.crc32(payload)
        return payload + struct.pack("<I", crc)

    @classmethod
    def deserialize(cls, data: memoryview, slot: int = 0) -> Optional["MetaPage"]:
        """Parses and validates meta page binary header with CRC32 verification."""
        if len(data) < META_SIZE:
            return None

        magic, tx_id, root_pid, page_cnt, free_head, crc = struct.unpack_from(
            META_FORMAT, data, 0
        )
        if magic != META_MAGIC:
            return None

        payload = bytes(data[: META_SIZE - 4])
        if zlib.crc32(payload) != crc:
            return None

        return cls(
            tx_id=tx_id,
            root_page_id=root_pid,
            page_count=page_cnt,
            free_list_head=free_head,
            slot=slot,
        )

    @classmethod
    def _select_latest_meta(
        cls,
        meta_0: Optional["MetaPage"],
        meta_1: Optional["MetaPage"],
        page_count: int,
    ) -> "MetaPage":
        if meta_0 is None and meta_1 is None:
            return cls(
                tx_id=0,
                root_page_id=0,
                page_count=page_count,
                free_list_head=0,
                slot=0,
            )
        valid = [m for m in (meta_0, meta_1) if m is not None]
        return max(valid, key=lambda m: m.tx_id)

    @classmethod
    def load_latest(cls, mmap_file: MMapFile) -> "MetaPage":
        """
        Reads Page 0 and Page 1, validates CRC32, and returns the MetaPage with highest tx_id.
        """
        view_0 = mmap_file.read_page_view(0)
        view_1 = mmap_file.read_page_view(1)
        meta_0 = cls.deserialize(view_0, slot=0)
        meta_1 = cls.deserialize(view_1, slot=1)
        return cls._select_latest_meta(meta_0, meta_1, mmap_file.page_count)

    @classmethod
    def commit_next(
        cls,
        mmap_file: MMapFile,
        next_tx_id: int,
        root_page_id: int,
        page_count: int,
        free_list_head: int = 0,
    ) -> Tuple["MetaPage", int]:
        """
        Commits next snapshot by writing to alternate slot (tx_id % 2) and syncing to disk.
        """
        slot = next_tx_id % 2
        meta = cls(
            tx_id=next_tx_id,
            root_page_id=root_page_id,
            page_count=page_count,
            free_list_head=free_list_head,
            slot=slot,
        )
        data = meta.serialize()
        mmap_file.write_page(slot, data)
        mmap_file.sync()
        return meta, slot
