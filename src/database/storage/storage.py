#!/usr/bin/env python3
"""
Zero-Dependency Binary Vector Storage Layer with Memory-Mapped I/O (mmap).
Provides high-throughput Float32 vector serialization, deserialization, and indexing
using Python standard library (struct, mmap, array, json).
"""

import io
import json
import mmap
import os
import struct
from typing import Any, Dict, List, Optional, Sequence, Tuple


class VectorStorageSecurityError(Exception):
    """Raised when binary header tampering or bounds corruption is detected."""

    pass


def _meta_json_default(obj: Any) -> Any:
    if isinstance(obj, (bytes, bytearray)):
        return f"__bytes_hex__{obj.hex()}"
    return str(obj)


def _parse_bytes_hex(val: str) -> Any:
    if val.startswith("__bytes_hex__"):
        try:
            return bytes.fromhex(val[13:])
        except ValueError:
            return val
    return val


def _decode_dict(val: Dict[str, Any]) -> Dict[str, Any]:
    res: Dict[str, Any] = {}
    for k, v in val.items():
        res[k] = _decode_meta_bytes(v)
    return res


def _decode_meta_bytes(val: Any) -> Any:
    if isinstance(val, str):
        return _parse_bytes_hex(val)
    if isinstance(val, dict):
        return _decode_dict(val)
    if isinstance(val, list):
        res: List[Any] = []
        for item in val:
            res.append(_decode_meta_bytes(item))
        return res
    return val


class VectorStorage:
    """
    High-performance binary vector storage using custom OKFVEC01 format.

    Binary Layout:
    +-------------------------------------------------------------------+
    | Header (32 bytes):                                                |
    | - Magic Bytes: "OKFVEC01" (8B)                                    |
    | - Version: uint16 (2B) = 1                                        |
    | - Dimension: uint32 (4B)                                          |
    | - Vector Count: uint64 (8B)                                       |
    | - Metadata Offset: uint64 (8B)                                    |
    | - Reserved: uint16 (2B) = 0                                       |
    +-------------------------------------------------------------------+
    | Vector Data Block (count * dim * 4 bytes):                        |
    | - Raw Float32 vectors in Little-Endian format                     |
    +-------------------------------------------------------------------+
    | Metadata Block (variable length):                                 |
    | - UTF-8 JSON encoded metadata list: [{"id": str, ...}, ...]       |
    +-------------------------------------------------------------------+
    """

    MAGIC = b"OKFVEC01"
    HEADER_FORMAT = "<8sHIQQH"  # 8s(8B), H(2B), I(4B), Q(8B), Q(8B), H(2B) = 32B
    HEADER_SIZE = struct.calcsize(HEADER_FORMAT)
    MAX_DIMENSION = 4096
    MAX_VECTOR_COUNT = 10_000_000

    def _validate_dimension(self, dim: int) -> int:
        if 0 < dim <= self.MAX_DIMENSION:
            return dim
        raise ValueError(
            f"Dimension {dim} out of valid bounds (1..{self.MAX_DIMENSION})"
        )

    def _init_memory_state(self) -> None:
        self.file_path = ":memory:"
        self._memory_buffer: Optional[io.BytesIO] = io.BytesIO()

    def _init_disk_state(self, file_path: str) -> None:
        self.file_path = os.path.abspath(file_path)
        self._memory_buffer = None
        if os.path.exists(self.file_path):
            self._load_existing_file()

    def __init__(self, file_path: str, dim: int = 128) -> None:
        self.dim = self._validate_dimension(int(dim))
        self.is_memory = (
            file_path == ":memory:" or os.path.basename(file_path) == ":memory:"
        )
        self.count: int = 0
        self.metadata: List[Dict[str, Any]] = []
        self.id_to_idx: Dict[str, int] = {}
        self._file_obj: Optional[Any] = None
        self._mmap: Optional[mmap.mmap] = None
        self._memory_vectors: List[Tuple[float, ...]] = []
        if self.is_memory:
            self._init_memory_state()
        else:
            self._init_disk_state(file_path)

    def _validate_and_read_header(self, f: Any, file_size: int) -> Tuple[int, int]:
        header_bytes = f.read(self.HEADER_SIZE)
        magic, version, dim, count, meta_offset, _ = struct.unpack(
            self.HEADER_FORMAT, header_bytes
        )
        if magic != self.MAGIC:
            raise VectorStorageSecurityError(
                f"Invalid magic bytes: {magic!r}, expected {self.MAGIC!r}"
            )
        if version != 1:
            raise VectorStorageSecurityError(f"Unsupported format version: {version}")
        if dim != self.dim:
            self.dim = dim
        self.count = count

        expected_vec_bytes = self.count * self.dim * 4
        if meta_offset < self.HEADER_SIZE + expected_vec_bytes:
            raise VectorStorageSecurityError("Corrupt metadata offset in header")
        return count, meta_offset

    def _read_metadata_block(self, f: Any, meta_offset: int, file_size: int) -> None:
        if meta_offset < file_size:
            f.seek(meta_offset)
            meta_bytes = f.read()
            if meta_bytes:
                try:
                    raw_meta = json.loads(meta_bytes.decode("utf-8"))
                    self.metadata = _decode_meta_bytes(raw_meta)
                except Exception as e:
                    raise VectorStorageSecurityError(
                        f"Corrupt metadata JSON: {e}"
                    ) from e

    def _load_existing_file(self) -> None:
        """Reads header, validates format integrity, and maps memory."""
        file_size = os.path.getsize(self.file_path)
        if file_size < self.HEADER_SIZE:
            raise VectorStorageSecurityError(
                f"File size {file_size} is smaller than header size {self.HEADER_SIZE}"
            )

        with open(self.file_path, "rb") as f:
            _, meta_offset = self._validate_and_read_header(f, file_size)
            self._read_metadata_block(f, meta_offset, file_size)

        # Build index mapping
        self.id_to_idx = {
            m["id"]: idx
            for idx, m in enumerate(self.metadata)
            if isinstance(m, dict) and "id" in m
        }

    def _read_vectors_from_stream(
        self, f: io.BytesIO, count: int
    ) -> List[Tuple[float, ...]]:
        f.seek(self.HEADER_SIZE)
        raw = f.read(count * self.dim * 4)
        fmt = f"<{self.dim}f"
        stride = self.dim * 4
        return [
            struct.unpack(fmt, raw[i * stride : (i + 1) * stride]) for i in range(count)
        ]

    def load_from_bytes(self, raw_bytes: bytes) -> None:
        """Loads and parses storage state directly from binary OKFVEC01 bytes."""
        if len(raw_bytes) < self.HEADER_SIZE:
            raise VectorStorageSecurityError(
                f"Byte size {len(raw_bytes)} < header {self.HEADER_SIZE}"
            )
        f = io.BytesIO(raw_bytes)
        count, meta_offset = self._validate_and_read_header(f, len(raw_bytes))
        self._read_metadata_block(f, meta_offset, len(raw_bytes))
        self._memory_vectors = self._read_vectors_from_stream(f, count)
        self._rebuild_index_mapping(count, self.metadata)
        if self.is_memory:
            self._memory_buffer = io.BytesIO(raw_bytes)

    def open_mmap(self) -> None:
        """Opens memory map for zero-copy vector reads."""
        if self.is_memory or self._mmap is not None:
            return
        if not os.path.exists(self.file_path):
            return
        self._file_obj = open(self.file_path, "r+b")
        if os.path.getsize(self.file_path) > 0:
            self._mmap = mmap.mmap(self._file_obj.fileno(), 0, access=mmap.ACCESS_READ)

    def _close_memory(self) -> None:
        self.count = 0
        self._memory_vectors.clear()
        self.metadata.clear()
        self.id_to_idx.clear()
        if self._memory_buffer is not None:
            self._memory_buffer.close()
            self._memory_buffer = None

    def close(self) -> None:
        """Closes memory map and underlying file handle."""
        if self.is_memory:
            self._close_memory()
            return
        if self._mmap is not None:
            self._mmap.close()
            self._mmap = None
        if self._file_obj is not None:
            self._file_obj.close()
            self._file_obj = None

    def __enter__(self) -> "VectorStorage":
        self.open_mmap()
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        self.close()

    def __del__(self) -> None:
        try:
            self.close()
        except Exception:
            pass

    def _prepare_metadata(
        self,
        count: int,
        metadata: Optional[List[Dict[str, Any]]] = None,
        offset: int = 0,
    ) -> List[Dict[str, Any]]:
        meta_list = metadata or [{"id": str(offset + i)} for i in range(count)]
        if count != len(meta_list):
            raise ValueError(
                f"Vectors count ({count}) != metadata count ({len(meta_list)})"
            )
        return meta_list

    def _write_tmp_file(
        self,
        tmp_path: str,
        vectors: Sequence[Sequence[float]],
        meta_list: List[Dict[str, Any]],
        count: int,
    ) -> None:
        meta_json_bytes = json.dumps(
            meta_list, ensure_ascii=False, default=_meta_json_default
        ).encode("utf-8")
        meta_offset = self.HEADER_SIZE + (count * self.dim * 4)
        header_bytes = struct.pack(
            self.HEADER_FORMAT,
            self.MAGIC,
            1,  # Version
            self.dim,
            count,
            meta_offset,
            0,  # Reserved
        )
        with open(tmp_path, "wb") as f:
            f.write(header_bytes)
            for vec in vectors:
                if len(vec) != self.dim:
                    raise ValueError(
                        f"Vector dimension {len(vec)} != expected {self.dim}"
                    )
                f.write(struct.pack(f"<{self.dim}f", *vec))
            f.write(meta_json_bytes)

    def _write_memory_buffer(
        self,
        vectors: Sequence[Sequence[float]],
        meta_list: List[Dict[str, Any]],
        count: int,
    ) -> None:
        meta_json_bytes = json.dumps(
            meta_list, ensure_ascii=False, default=_meta_json_default
        ).encode("utf-8")
        meta_offset = self.HEADER_SIZE + (count * self.dim * 4)
        header_bytes = struct.pack(
            self.HEADER_FORMAT,
            self.MAGIC,
            1,  # Version
            self.dim,
            count,
            meta_offset,
            0,  # Reserved
        )
        buf = io.BytesIO()
        buf.write(header_bytes)
        for vec in vectors:
            buf.write(struct.pack(f"<{self.dim}f", *vec))
        buf.write(meta_json_bytes)
        if self._memory_buffer is not None and not self._memory_buffer.closed:
            self._memory_buffer.close()
        self._memory_buffer = buf

    def _rebuild_index_mapping(
        self, count: int, meta_list: List[Dict[str, Any]]
    ) -> None:
        self.count = count
        self.metadata = list(meta_list)
        self.id_to_idx = {
            m["id"]: idx
            for idx, m in enumerate(self.metadata)
            if isinstance(m, dict) and "id" in m
        }

    def _write_all_memory(
        self,
        valid_vecs: List[Tuple[float, ...]],
        meta_list: List[Dict[str, Any]],
        count: int,
    ) -> None:
        self._memory_vectors = valid_vecs
        self._rebuild_index_mapping(count, meta_list)
        self._write_memory_buffer(valid_vecs, meta_list, count)

    def _write_all_disk(
        self,
        valid_vecs: List[Tuple[float, ...]],
        meta_list: List[Dict[str, Any]],
        count: int,
    ) -> None:
        self.close()
        os.makedirs(os.path.dirname(self.file_path), exist_ok=True)
        tmp_path = self.file_path + ".tmp"
        self._write_tmp_file(tmp_path, valid_vecs, meta_list, count)
        os.replace(tmp_path, self.file_path)
        self._rebuild_index_mapping(count, meta_list)
        self.open_mmap()

    def write_all(
        self,
        vectors: Sequence[Sequence[float]],
        metadata: Optional[List[Dict[str, Any]]] = None,
    ) -> None:
        """
        Atomically writes full vector set and metadata to binary storage.
        """
        count = len(vectors)
        if count > self.MAX_VECTOR_COUNT:
            raise ValueError(
                f"Vector count {count} exceeds MAX_VECTOR_COUNT {self.MAX_VECTOR_COUNT}"
            )
        valid_vecs = self._validate_vectors(vectors)
        meta_list = self._prepare_metadata(count, metadata, 0)
        if self.is_memory:
            self._write_all_memory(valid_vecs, meta_list, count)
        else:
            self._write_all_disk(valid_vecs, meta_list, count)

    def _validate_vectors(
        self, vectors: Sequence[Sequence[float]]
    ) -> List[Tuple[float, ...]]:
        res: List[Tuple[float, ...]] = []
        for v in vectors:
            if len(v) != self.dim:
                raise ValueError(f"Vector dimension {len(v)} != expected {self.dim}")
            res.append(tuple(v))
        return res

    def append_batch(
        self,
        vectors: Sequence[Sequence[float]],
        metadata: Optional[List[Dict[str, Any]]] = None,
    ) -> List[int]:
        """
        Appends a batch of vectors and metadata to binary storage.
        """
        if not vectors:
            return []
        count = len(vectors)
        meta_list = self._prepare_metadata(count, metadata, self.count)
        all_vecs = self.get_all_vectors()
        all_vecs.extend(self._validate_vectors(vectors))
        new_meta = list(self.metadata) + meta_list
        start_idx = len(all_vecs) - count
        self.write_all(all_vecs, new_meta)
        return list(range(start_idx, len(all_vecs)))

    def append(
        self, vector: Sequence[float], metadata: Optional[Dict[str, Any]] = None
    ) -> int:
        """
        Appends a single vector to binary storage and updates header & metadata.
        Returns the index of the newly added vector.
        """
        if len(vector) != self.dim:
            raise ValueError(f"Vector dimension {len(vector)} != expected {self.dim}")

        all_vecs = self.get_all_vectors()
        all_vecs.append(tuple(vector))
        new_meta = list(self.metadata)
        new_meta.append(metadata or {"id": str(len(all_vecs) - 1)})

        self.write_all(all_vecs, new_meta)
        return len(all_vecs) - 1

    def to_bytes(self) -> bytes:
        """Serializes current storage to binary OKFVEC01 bytes."""
        if self.is_memory:
            if self._memory_buffer is not None and not self._memory_buffer.closed:
                return self._memory_buffer.getvalue()
            return b""
        if not os.path.exists(self.file_path):
            return b""
        with open(self.file_path, "rb") as f:
            return f.read()

    def _read_disk_vector_bytes(self, offset: int) -> bytes:
        if self._mmap is not None:
            return self._mmap[offset : offset + (self.dim * 4)]
        with open(self.file_path, "rb") as f:
            f.seek(offset)
            return f.read(self.dim * 4)

    def get_vector(self, idx: int) -> Tuple[float, ...]:
        """
        Retrieves float32 vector at index `idx` using zero-copy memory mapping.
        """
        if idx < 0 or idx >= self.count:
            raise IndexError(f"Vector index {idx} out of range (0..{self.count-1})")

        if self.is_memory:
            return self._memory_vectors[idx]

        offset = self.HEADER_SIZE + (idx * self.dim * 4)
        raw_bytes = self._read_disk_vector_bytes(offset)
        return struct.unpack(f"<{self.dim}f", raw_bytes)

    def get_vector_by_id(self, doc_id: str) -> Optional[Tuple[float, ...]]:
        """Retrieves vector by document ID."""
        idx = self.id_to_idx.get(doc_id)
        if idx is None:
            return None
        return self.get_vector(idx)

    def get_all_vectors(self) -> List[Tuple[float, ...]]:
        """Retrieves all stored vectors."""
        if self.is_memory:
            return list(self._memory_vectors)
        return [self.get_vector(i) for i in range(self.count)]

    def get_metadata(self, idx: int) -> Dict[str, Any]:
        """Retrieves metadata dict for vector at index `idx`."""
        if idx < 0 or idx >= len(self.metadata):
            raise IndexError(
                f"Metadata index {idx} out of range (0..{len(self.metadata)-1})"
            )
        return self.metadata[idx]
