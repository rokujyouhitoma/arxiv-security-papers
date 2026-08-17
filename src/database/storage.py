#!/usr/bin/env python3
"""
Zero-Dependency Binary Vector Storage Layer with Memory-Mapped I/O (mmap).
Provides high-throughput Float32 vector serialization, deserialization, and indexing
using Python standard library (struct, mmap, array, json).
"""

import json
import mmap
import os
import struct
from typing import Any, Dict, List, Optional, Sequence, Tuple


class VectorStorageSecurityError(Exception):
    """Raised when binary header tampering or bounds corruption is detected."""

    pass


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

    def __init__(self, file_path: str, dim: int = 128) -> None:
        self.file_path = os.path.abspath(file_path)
        self.dim = int(dim)
        self.count: int = 0
        self.metadata: List[Dict[str, Any]] = []
        self.id_to_idx: Dict[str, int] = {}
        self._file_obj: Optional[Any] = None
        self._mmap: Optional[mmap.mmap] = None

        if self.dim <= 0 or self.dim > self.MAX_DIMENSION:
            raise ValueError(
                f"Dimension {dim} out of valid bounds (1..{self.MAX_DIMENSION})"
            )

        if os.path.exists(self.file_path):
            self._load_existing_file()

    def _load_existing_file(self) -> None:
        """Reads header, validates format integrity, and maps memory."""
        file_size = os.path.getsize(self.file_path)
        if file_size < self.HEADER_SIZE:
            raise VectorStorageSecurityError(
                f"File size {file_size} is smaller than header size {self.HEADER_SIZE}"
            )

        with open(self.file_path, "rb") as f:
            header_bytes = f.read(self.HEADER_SIZE)
            magic, version, dim, count, meta_offset, _ = struct.unpack(
                self.HEADER_FORMAT, header_bytes
            )

            if magic != self.MAGIC:
                raise VectorStorageSecurityError(
                    f"Invalid magic bytes: {magic!r}, expected {self.MAGIC!r}"
                )
            if version != 1:
                raise VectorStorageSecurityError(
                    f"Unsupported format version: {version}"
                )
            if dim != self.dim:
                self.dim = dim

            self.count = count

            # Validate vector block boundary
            expected_vec_bytes = self.count * self.dim * 4
            if meta_offset < self.HEADER_SIZE + expected_vec_bytes:
                raise VectorStorageSecurityError("Corrupt metadata offset in header")

            # Read metadata JSON
            if meta_offset < file_size:
                f.seek(meta_offset)
                meta_bytes = f.read()
                if meta_bytes:
                    try:
                        self.metadata = json.loads(meta_bytes.decode("utf-8"))
                    except Exception as e:
                        raise VectorStorageSecurityError(
                            f"Corrupt metadata JSON: {e}"
                        ) from e

        # Build index mapping
        self.id_to_idx = {
            m["id"]: idx
            for idx, m in enumerate(self.metadata)
            if isinstance(m, dict) and "id" in m
        }

    def open_mmap(self) -> None:
        """Opens memory map for zero-copy vector reads."""
        if self._mmap is not None:
            return
        if not os.path.exists(self.file_path):
            return
        self._file_obj = open(self.file_path, "r+b")
        if os.path.getsize(self.file_path) > 0:
            self._mmap = mmap.mmap(self._file_obj.fileno(), 0, access=mmap.ACCESS_READ)

    def close(self) -> None:
        """Closes memory map and underlying file handle."""
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

    def write_all(
        self,
        vectors: Sequence[Sequence[float]],
        metadata: Optional[List[Dict[str, Any]]] = None,
    ) -> None:
        """
        Atomically writes full vector set and metadata to binary storage.
        """
        self.close()
        os.makedirs(os.path.dirname(self.file_path), exist_ok=True)
        count = len(vectors)
        meta_list = metadata or [{"id": str(i)} for i in range(count)]

        if count != len(meta_list):
            raise ValueError(
                f"Vectors count ({count}) != metadata count ({len(meta_list)})"
            )

        meta_json_bytes = json.dumps(meta_list, ensure_ascii=False).encode("utf-8")
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

        tmp_path = self.file_path + ".tmp"
        with open(tmp_path, "wb") as f:
            f.write(header_bytes)
            for vec in vectors:
                if len(vec) != self.dim:
                    raise ValueError(
                        f"Vector dimension {len(vec)} != expected {self.dim}"
                    )
                f.write(struct.pack(f"<{self.dim}f", *vec))
            f.write(meta_json_bytes)

        os.replace(tmp_path, self.file_path)

        self.count = count
        self.metadata = meta_list
        self.id_to_idx = {
            m["id"]: idx
            for idx, m in enumerate(self.metadata)
            if isinstance(m, dict) and "id" in m
        }
        self.open_mmap()

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
        meta_list = metadata or [{"id": str(self.count + i)} for i in range(count)]
        if count != len(meta_list):
            raise ValueError(
                f"Vectors count ({count}) != metadata count ({len(meta_list)})"
            )

        all_vecs = self.get_all_vectors()
        for v in vectors:
            if len(v) != self.dim:
                raise ValueError(f"Vector dimension {len(v)} != expected {self.dim}")
            all_vecs.append(tuple(v))

        new_meta = list(self.metadata)
        new_meta.extend(meta_list)
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

    def get_vector(self, idx: int) -> Tuple[float, ...]:
        """
        Retrieves float32 vector at index `idx` using zero-copy memory mapping.
        """
        if idx < 0 or idx >= self.count:
            raise IndexError(f"Vector index {idx} out of range (0..{self.count-1})")

        offset = self.HEADER_SIZE + (idx * self.dim * 4)

        if self._mmap is not None:
            raw_bytes = self._mmap[offset : offset + (self.dim * 4)]
        else:
            with open(self.file_path, "rb") as f:
                f.seek(offset)
                raw_bytes = f.read(self.dim * 4)

        return struct.unpack(f"<{self.dim}f", raw_bytes)

    def get_vector_by_id(self, doc_id: str) -> Optional[Tuple[float, ...]]:
        """Retrieves vector by document ID."""
        idx = self.id_to_idx.get(doc_id)
        if idx is None:
            return None
        return self.get_vector(idx)

    def get_all_vectors(self) -> List[Tuple[float, ...]]:
        """Retrieves all stored vectors."""
        return [self.get_vector(i) for i in range(self.count)]

    def get_metadata(self, idx: int) -> Dict[str, Any]:
        """Retrieves metadata dict for vector at index `idx`."""
        if idx < 0 or idx >= len(self.metadata):
            raise IndexError(
                f"Metadata index {idx} out of range (0..{len(self.metadata)-1})"
            )
        return self.metadata[idx]
