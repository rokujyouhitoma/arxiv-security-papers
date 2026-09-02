#!/usr/bin/env python3
"""
Slotted-Page Binary Storage Engine for Pure-Python Relational & Vector DBMS.

Implements the standard 4096-byte slotted page binary architecture:
- 24-byte page header with CRC32 integrity verification and LSN tracking.
- Slot array growing downwards from page header (offset + length).
- Variable & fixed-length tuple storage growing upwards from page bottom.
- Null-bitmap and typed column serializer (INT, FLOAT, BOOL, VARCHAR, BYTES, VECTOR).
- In-page compaction / defragmentation (VACUUM).
- Multi-page overflow management for large blobs/vectors.
"""

import enum
import math
import struct
import zlib
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple, Union

PAGE_SIZE = 4096
# Header: PageID(4B), LSN(8B), SlotCount(2B), FreeLower(2B), FreeUpper(2B), Flags(2B), NextPageID(4B) = 24B
# + Checksum(4B) = 28B
PAGE_HEADER_FORMAT = "<IQHHHHI"
PAGE_HEADER_SIZE = struct.calcsize(PAGE_HEADER_FORMAT) + 4  # 24B + Checksum(4B) = 28B
SLOT_FORMAT = "<HH"  # Offset (2B), Length (2B) = 4B
SLOT_SIZE = struct.calcsize(SLOT_FORMAT)


class PageType(enum.IntEnum):
    """Enumeration of page physical roles."""

    DATA = 0x0001
    OVERFLOW = 0x0002
    BTREE_INTERNAL = 0x0004
    BTREE_LEAF = 0x0008
    FREE = 0x0010


class SlottedPageError(Exception):
    """Base exception for slotted page storage errors."""

    pass


class PageCorruptionError(SlottedPageError):
    """Raised when page header or checksum verification fails."""

    pass


class PageFullError(SlottedPageError):
    """Raised when a tuple does not fit in the available page free space."""

    pass


class SlottedPage:
    """
    Manages a single 4096-byte slotted database page in binary format.

    Memory Layout:
    +---------------------------------------------------------------+
    | HEADER (28 Bytes):                                            |
    | - page_id: uint32 (4B)                                        |
    | - lsn: uint64 (8B)                                            |
    | - slot_count: uint16 (2B)                                     |
    | - free_lower: uint16 (2B) (Next slot write offset)            |
    | - free_upper: uint16 (2B) (Next tuple data write offset)      |
    | - flags: uint16 (2B)                                          |
    | - next_page_id: uint32 (4B) [For overflow/linked pages]       |
    | - checksum: uint32 (4B) [CRC32 of bytes 0..23 + 28..4096]     |
    +---------------------------------------------------------------+
    | SLOT ARRAY (slot_count * 4 Bytes):                            |
    | - Slot 0: [Offset (2B), Length (2B)]                          |
    | - Slot 1: [Offset (2B), Length (2B)]                          |
    |   ... (grows downwards)                                       |
    +---------------------------------------------------------------+
    |                     FREE SPACE                                |
    +---------------------------------------------------------------+
    | TUPLE STORAGE (grows upwards from byte 4095):                 |
    | - Tuple 1: [Binary Record Data]                               |
    | - Tuple 0: [Binary Record Data]                               |
    +---------------------------------------------------------------+
    """

    HEADER_BASE_FORMAT = "<IQHHHHI"  # 4 + 8 + 2 + 2 + 2 + 2 + 4 = 24 bytes
    HEADER_SIZE = 28  # 24B base + 4B CRC32
    MAX_USABLE_SPACE = PAGE_SIZE - HEADER_SIZE

    def __init__(
        self,
        page_id: int = 0,
        page_type: PageType = PageType.DATA,
        raw_data: Optional[Union[bytes, bytearray]] = None,
    ) -> None:
        self.data: bytearray = bytearray(PAGE_SIZE)
        if raw_data is not None:
            if len(raw_data) != PAGE_SIZE:
                raise SlottedPageError(
                    f"Invalid raw page size: {len(raw_data)}, expected {PAGE_SIZE}"
                )
            self.data[:] = raw_data
            self._unpack_header()
        else:
            self.page_id: int = page_id
            self.lsn: int = 0
            self.slot_count: int = 0
            self.free_lower: int = self.HEADER_SIZE
            self.free_upper: int = PAGE_SIZE
            self.flags: int = int(page_type)
            self.next_page_id: int = 0
            self._sync_header()

    def _unpack_header(self) -> None:
        base_bytes = bytes(self.data[:24])
        page_id, lsn, slot_count, free_lower, free_upper, flags, next_page_id = (
            struct.unpack(self.HEADER_BASE_FORMAT, base_bytes)
        )
        stored_checksum = struct.unpack("<I", bytes(self.data[24:28]))[0]

        self.page_id = page_id
        self.lsn = lsn
        self.slot_count = slot_count
        self.free_lower = free_lower
        self.free_upper = free_upper
        self.flags = flags
        self.next_page_id = next_page_id

        # Validate structural boundaries
        if not (self.HEADER_SIZE <= self.free_lower <= self.free_upper <= PAGE_SIZE):
            raise PageCorruptionError(
                f"Corrupt free pointers: lower={self.free_lower}, upper={self.free_upper}"
            )

        if stored_checksum != 0:
            computed = self.compute_checksum()
            if stored_checksum != computed:
                raise PageCorruptionError(
                    f"Checksum mismatch: stored={stored_checksum}, computed={computed}"
                )

    def _sync_header(self) -> None:
        base_bytes = struct.pack(
            self.HEADER_BASE_FORMAT,
            self.page_id,
            self.lsn,
            self.slot_count,
            self.free_lower,
            self.free_upper,
            self.flags,
            self.next_page_id,
        )
        self.data[0:24] = base_bytes
        # Write checksum
        checksum = self.compute_checksum()
        self.data[24:28] = struct.pack("<I", checksum)

    def compute_checksum(self) -> int:
        """Computes CRC32 checksum across entire page excluding the checksum field itself."""
        crc = zlib.crc32(bytes(self.data[0:24]))
        crc = zlib.crc32(bytes(self.data[28:PAGE_SIZE]), crc)
        return crc & 0xFFFFFFFF

    def validate_checksum(self) -> bool:
        """Validates stored checksum against actual payload bytes."""
        stored: int = int(struct.unpack("<I", bytes(self.data[24:28]))[0])
        if stored == 0:
            return True
        return bool(stored == self.compute_checksum())

    @property
    def free_space(self) -> int:
        """Returns contiguous free space between free_lower and free_upper."""
        return max(0, self.free_upper - self.free_lower)

    def get_slot(self, slot_id: int) -> Tuple[int, int]:
        """Returns (offset, length) for the given slot_id."""
        if slot_id < 0 or slot_id >= self.slot_count:
            raise IndexError(
                f"Slot ID {slot_id} out of bounds (0..{self.slot_count - 1})"
            )
        slot_offset = self.HEADER_SIZE + slot_id * SLOT_SIZE
        offset, length = struct.unpack(
            SLOT_FORMAT, bytes(self.data[slot_offset : slot_offset + SLOT_SIZE])
        )
        return offset, length

    def _set_slot(self, slot_id: int, offset: int, length: int) -> None:
        slot_offset = self.HEADER_SIZE + slot_id * SLOT_SIZE
        self.data[slot_offset : slot_offset + SLOT_SIZE] = struct.pack(
            SLOT_FORMAT, offset, length
        )

    def _find_recycled_slot(self) -> Optional[int]:
        """Returns the first tombstone slot ID, or None if none available."""
        for s_id in range(self.slot_count):
            off, _ = self.get_slot(s_id)
            if off == 0:
                return s_id
        return None

    def _ensure_free_space(self, needed_space: int) -> None:
        """Compacts page if needed; raises PageFullError if still insufficient."""
        if self.free_space < needed_space:
            self.compact()
        if self.free_space < needed_space:
            raise PageFullError(
                f"Insufficient page space: needed {needed_space}, available {self.free_space}"
            )

    def insert_tuple(self, tuple_bytes: bytes) -> int:
        """
        Inserts raw tuple bytes into the page, allocating a slot.
        Reuses tombstone slots if available, otherwise expands slot array.
        Returns the allocated slot_id.
        """
        tuple_len = len(tuple_bytes)
        if tuple_len > self.MAX_USABLE_SPACE:
            raise PageFullError(
                f"Tuple size {tuple_len} exceeds max page capacity {self.MAX_USABLE_SPACE}"
            )
        target_slot_id = self._find_recycled_slot()
        needed_space = tuple_len + (0 if target_slot_id is not None else SLOT_SIZE)
        self._ensure_free_space(needed_space)
        new_upper = self.free_upper - tuple_len
        self.data[new_upper : self.free_upper] = tuple_bytes
        self.free_upper = new_upper
        if target_slot_id is not None:
            self._set_slot(target_slot_id, new_upper, tuple_len)
            slot_id = target_slot_id
        else:
            slot_id = self.slot_count
            self._set_slot(slot_id, new_upper, tuple_len)
            self.slot_count += 1
            self.free_lower += SLOT_SIZE
        self._sync_header()
        return slot_id

    def get_tuple(self, slot_id: int) -> Optional[bytes]:
        """Retrieves raw tuple bytes by slot_id. Returns None if tombstone (deleted)."""
        offset, length = self.get_slot(slot_id)
        if offset == 0 or length == 0:
            return None
        return bytes(self.data[offset : offset + length])

    def update_tuple(self, slot_id: int, new_tuple_bytes: bytes) -> bool:
        """
        Updates an existing tuple at slot_id.
        If size <= existing, updates in-place; otherwise allocates new space and marks old space for compaction.
        """
        old_offset, old_length = self.get_slot(slot_id)
        if old_offset == 0:
            return False  # Cannot update deleted tuple

        new_len = len(new_tuple_bytes)
        if new_len <= old_length:
            # In-place update with padding
            self.data[old_offset : old_offset + new_len] = new_tuple_bytes
            self._set_slot(slot_id, old_offset, new_len)
            self._sync_header()
            return True

        # Need more space: mark old slot deleted, allocate new space, then re-assign
        self._set_slot(slot_id, 0, 0)
        if self.free_space < new_len:
            self.compact()

        if self.free_space < new_len:
            # Restore slot and fail
            self._set_slot(slot_id, old_offset, old_length)
            self._sync_header()
            raise PageFullError(
                f"Cannot update tuple {slot_id}: needed {new_len}, free {self.free_space}"
            )

        new_upper = self.free_upper - new_len
        self.data[new_upper : self.free_upper] = new_tuple_bytes
        self.free_upper = new_upper
        self._set_slot(slot_id, new_upper, new_len)
        self._sync_header()
        return True

    def delete_tuple(self, slot_id: int) -> bool:
        """Marks a tuple as deleted (tombstone)."""
        offset, _ = self.get_slot(slot_id)
        if offset == 0:
            return False
        self._set_slot(slot_id, 0, 0)
        self._sync_header()
        return True

    def compact(self) -> None:
        """
        Performs in-page defragmentation (VACUUM).
        Moves all active tuples to the very bottom of the page in contiguous order,
        reclaiming fragmented space from deleted or updated tuples.
        """
        active_tuples: List[Tuple[int, bytes]] = []
        for s_id in range(self.slot_count):
            off, length = self.get_slot(s_id)
            if off != 0 and length > 0:
                tuple_data = bytes(self.data[off : off + length])
                active_tuples.append((s_id, tuple_data))

        # Reset upper boundary to page end
        new_upper = PAGE_SIZE
        # Clear tuple space
        self.data[self.free_lower : PAGE_SIZE] = bytearray(PAGE_SIZE - self.free_lower)

        for s_id, t_bytes in active_tuples:
            t_len = len(t_bytes)
            new_upper -= t_len
            self.data[new_upper : new_upper + t_len] = t_bytes
            self._set_slot(s_id, new_upper, t_len)

        self.free_upper = new_upper
        self._sync_header()

    def serialize(self) -> bytes:
        """Serializes the entire 4096-byte page with valid checksum."""
        self._sync_header()
        return bytes(self.data)


# ---------------------------------------------------------------------------
# Column & Tuple Serializer Layer
# ---------------------------------------------------------------------------


class DataType(str, enum.Enum):
    """Supported SQL / Vector data types."""

    INT = "INT"  # 64-bit signed integer (8B)
    FLOAT = "FLOAT"  # 64-bit IEEE double (8B)
    BOOL = "BOOL"  # 8-bit unsigned integer (1B)
    VARCHAR = "VARCHAR"  # Variable-length UTF-8 string
    TEXT = "TEXT"  # Variable-length UTF-8 text
    BYTES = "BYTES"  # Variable-length raw binary blob
    VECTOR = "VECTOR"  # Float32 dense vector array


class TupleSerializer:
    """
    Serializes and deserializes structured rows into compact binary representation.

    Tuple Binary Layout:
    +-------------------------------------------------------------------+
    | Null-Bitmap: ceil(num_columns / 8) bytes                          |
    | - Bit 1 = Column is NULL, Bit 0 = Column is NOT NULL              |
    +-------------------------------------------------------------------+
    | Variable-Length Offset Table: (num_columns * 2 bytes)             |
    | - Relative offset of each column from start of payload            |
    +-------------------------------------------------------------------+
    | Payload: Column values tightly packed                             |
    +-------------------------------------------------------------------+
    """

    @staticmethod
    def serialize(schema: Sequence[Tuple[str, DataType]], row: Dict[str, Any]) -> bytes:
        """Serializes a dictionary row into binary format according to column schema."""
        num_cols = len(schema)
        null_bytes_len = math.ceil(num_cols / 8)
        null_bitmap = bytearray(null_bytes_len)

        encoded_columns: List[bytes] = []

        for i, (col_name, col_type) in enumerate(schema):
            val = row.get(col_name)
            if val is None:
                # Set bit in null bitmap
                byte_idx = i // 8
                bit_idx = i % 8
                null_bitmap[byte_idx] |= 1 << bit_idx
                encoded_columns.append(b"")
            else:
                encoded = TupleSerializer._encode_value(col_type, val)
                encoded_columns.append(encoded)

        # Build payload & offset table
        payload = bytearray()
        offset_table = bytearray()
        current_offset = 0

        for enc in encoded_columns:
            offset_table.extend(struct.pack("<H", current_offset))
            payload.extend(enc)
            current_offset += len(enc)

        return bytes(null_bitmap) + bytes(offset_table) + bytes(payload)

    @staticmethod
    @staticmethod
    def _parse_tuple_layout(
        raw_bytes: bytes, num_cols: int
    ) -> Tuple[bytes, List[int], bytes]:
        null_bytes_len = math.ceil(num_cols / 8)
        offset_table_len = num_cols * 2
        header_len = null_bytes_len + offset_table_len
        if len(raw_bytes) < header_len:
            raise ValueError("Corrupt tuple binary: header truncated")
        null_bitmap = raw_bytes[:null_bytes_len]
        offset_table_bytes = raw_bytes[null_bytes_len:header_len]
        payload = raw_bytes[header_len:]
        offsets = [
            struct.unpack("<H", offset_table_bytes[i * 2 : (i + 1) * 2])[0]
            for i in range(num_cols)
        ]
        return null_bitmap, offsets, payload

    @staticmethod
    def _deserialize_field(
        i: int,
        col_type: DataType,
        null_bitmap: bytes,
        offsets: List[int],
        payload: bytes,
        num_cols: int,
    ) -> Any:
        if (null_bitmap[i // 8] & (1 << (i % 8))) != 0:
            return None
        start_off = offsets[i]
        end_off = offsets[i + 1] if i + 1 < num_cols else len(payload)
        return TupleSerializer._decode_value(col_type, payload[start_off:end_off])

    @staticmethod
    def deserialize(
        schema: Sequence[Tuple[str, DataType]], raw_bytes: bytes
    ) -> Dict[str, Any]:
        """Deserializes binary bytes into a structured row dictionary."""
        num_cols = len(schema)
        null_bitmap, offsets, payload = TupleSerializer._parse_tuple_layout(
            raw_bytes, num_cols
        )
        return {
            col_name: TupleSerializer._deserialize_field(
                i, col_type, null_bitmap, offsets, payload, num_cols
            )
            for i, (col_name, col_type) in enumerate(schema)
        }

    @staticmethod
    def _encode_str_type(val: Any) -> bytes:
        b = str(val).encode("utf-8")
        return struct.pack("<H", len(b)) + b

    @staticmethod
    def _encode_bytes_type(val: Any) -> bytes:
        raw = (
            bytes(val)
            if isinstance(val, (bytes, bytearray))
            else bytes(str(val), "utf-8")
        )
        return struct.pack("<I", len(raw)) + raw

    @staticmethod
    def _encode_vector_type(val: Any) -> bytes:
        vec = list(val)
        dim = len(vec)
        return struct.pack("<H", dim) + struct.pack(
            f"<{dim}f", *[float(x) for x in vec]
        )

    _ENCODE_DISPATCH: "Dict[DataType, Any]"

    @staticmethod
    def _encode_value(col_type: DataType, val: Any) -> bytes:
        _dispatch = TupleSerializer._get_encode_dispatch()
        fn = _dispatch.get(col_type)
        if fn is None:
            raise ValueError(f"Unsupported data type: {col_type}")
        return fn(val)

    @staticmethod
    def _get_encode_dispatch() -> Dict[DataType, Callable[[Any], bytes]]:
        return {
            DataType.INT: lambda v: struct.pack("<q", int(v)),
            DataType.FLOAT: lambda v: struct.pack("<d", float(v)),
            DataType.BOOL: lambda v: struct.pack("<?", bool(v)),
            DataType.VARCHAR: TupleSerializer._encode_str_type,
            DataType.TEXT: TupleSerializer._encode_str_type,
            DataType.BYTES: TupleSerializer._encode_bytes_type,
            DataType.VECTOR: TupleSerializer._encode_vector_type,
        }

    @staticmethod
    def _decode_str_type(raw: bytes) -> str:
        length = struct.unpack("<H", raw[:2])[0]
        return raw[2 : 2 + length].decode("utf-8")

    @staticmethod
    def _decode_bytes_type(raw: bytes) -> bytes:
        length = struct.unpack("<I", raw[:4])[0]
        return raw[4 : 4 + length]

    @staticmethod
    def _decode_vector_type(raw: bytes) -> List[float]:
        dim = struct.unpack("<H", raw[:2])[0]
        return list(struct.unpack(f"<{dim}f", raw[2 : 2 + dim * 4]))

    @staticmethod
    def _get_decode_dispatch() -> Dict[DataType, Callable[[bytes], Any]]:
        return {
            DataType.INT: lambda r: struct.unpack("<q", r)[0],
            DataType.FLOAT: lambda r: struct.unpack("<d", r)[0],
            DataType.BOOL: lambda r: struct.unpack("<?", r)[0],
            DataType.VARCHAR: TupleSerializer._decode_str_type,
            DataType.TEXT: TupleSerializer._decode_str_type,
            DataType.BYTES: TupleSerializer._decode_bytes_type,
            DataType.VECTOR: TupleSerializer._decode_vector_type,
        }

    @staticmethod
    def _decode_value(col_type: DataType, raw: bytes) -> Any:
        fn = TupleSerializer._get_decode_dispatch().get(col_type)
        if fn is None:
            raise ValueError(f"Unsupported data type: {col_type}")
        return fn(raw)


# ---------------------------------------------------------------------------
# Overflow Manager for Multi-Page Large Objects
# ---------------------------------------------------------------------------


class OverflowManager:
    """
    Splits and reassembles payloads exceeding single-page capacity across linked OVERFLOW pages.
    """

    OVERFLOW_HEADER_SIZE = 28  # Uses SlottedPage header with next_page_id pointer
    CHUNK_SIZE = PAGE_SIZE - OVERFLOW_HEADER_SIZE

    @staticmethod
    def _get_page_id(page_allocator: Any, start_page_id: int, i: int) -> int:
        if i == 0:
            return start_page_id
        if hasattr(page_allocator, "allocate_page_id"):
            return int(page_allocator.allocate_page_id())
        return start_page_id + i

    @staticmethod
    def write_overflow(
        start_page_id: int,
        large_data: bytes,
        page_allocator: Any,
    ) -> List[SlottedPage]:
        """
        Splits large_data into linked overflow pages.
        Returns the list of populated SlottedPage instances.
        """
        pages: List[SlottedPage] = []
        num_pages = math.ceil(len(large_data) / OverflowManager.CHUNK_SIZE)
        prev_page: Optional[SlottedPage] = None
        for i in range(num_pages):
            chunk = large_data[
                i * OverflowManager.CHUNK_SIZE : (i + 1) * OverflowManager.CHUNK_SIZE
            ]
            current_pid = OverflowManager._get_page_id(page_allocator, start_page_id, i)
            page = SlottedPage(page_id=current_pid, page_type=PageType.OVERFLOW)
            page.data[page.HEADER_SIZE : page.HEADER_SIZE + len(chunk)] = chunk
            page.free_upper = page.HEADER_SIZE + len(chunk)
            if prev_page is not None:
                prev_page.next_page_id = current_pid
                prev_page.serialize()
            pages.append(page)
            prev_page = page
        if prev_page is not None:
            prev_page.next_page_id = 0
            prev_page.serialize()
        return pages

    @staticmethod
    def read_overflow(
        first_page: SlottedPage,
        page_fetcher: Any,
    ) -> bytes:
        """
        Reassembles large_data from linked overflow pages starting from first_page.
        """
        chunks: List[bytes] = []
        curr_page: Optional[SlottedPage] = first_page

        while curr_page is not None:
            data_len = curr_page.free_upper - curr_page.HEADER_SIZE
            chunk = bytes(
                curr_page.data[curr_page.HEADER_SIZE : curr_page.HEADER_SIZE + data_len]
            )
            chunks.append(chunk)
            if curr_page.next_page_id != 0:
                raw_page_data = page_fetcher(curr_page.next_page_id)
                curr_page = SlottedPage(raw_data=raw_page_data)
            else:
                curr_page = None

        return b"".join(chunks)
