#!/usr/bin/env python3
"""
Storage Abstraction Layer for Core Search Engine (Lucene Paradigm).
Provides Directory, RAMDirectory, FSDirectory, and IndexIO.
"""

import os
from abc import ABC, abstractmethod
from typing import Dict, List


class IndexOutput:
    """Byte writer for index segment files."""

    def __init__(self) -> None:
        self.buffer = bytearray()

    def write_bytes(self, b: bytes) -> None:
        self.buffer.extend(b)

    def write_int(self, val: int) -> None:
        self.buffer.extend(val.to_bytes(4, byteorder="little", signed=True))

    def write_string(self, s: str) -> None:
        encoded = s.encode("utf-8")
        self.write_int(len(encoded))
        self.write_bytes(encoded)

    def get_bytes(self) -> bytes:
        return bytes(self.buffer)


class IndexInput:
    """Byte reader for index segment files."""

    def __init__(self, data: bytes) -> None:
        self.data = data
        self.pos = 0

    def read_bytes(self, length: int) -> bytes:
        if self.pos + length > len(self.data):
            raise EOFError("Unexpected end of IndexInput buffer")
        res = self.data[self.pos : self.pos + length]
        self.pos += length
        return res

    def read_int(self) -> int:
        b = self.read_bytes(4)
        return int.from_bytes(b, byteorder="little", signed=True)

    def read_string(self) -> str:
        length = self.read_int()
        b = self.read_bytes(length)
        return b.decode("utf-8")

    def is_eof(self) -> bool:
        return self.pos >= len(self.data)


class Directory(ABC):
    """Abstract directory interface representing a flat list of index files."""

    @abstractmethod
    def list_all(self) -> List[str]:
        raise NotImplementedError

    @abstractmethod
    def file_exists(self, name: str) -> bool:
        raise NotImplementedError

    @abstractmethod
    def delete_file(self, name: str) -> None:
        raise NotImplementedError

    @abstractmethod
    def open_input(self, name: str) -> IndexInput:
        raise NotImplementedError

    @abstractmethod
    def create_output(self, name: str) -> IndexOutput:
        raise NotImplementedError

    @abstractmethod
    def save_output(self, name: str, output: IndexOutput) -> None:
        raise NotImplementedError


class RAMDirectory(Directory):
    """In-memory Directory implementation for fast unit testing and ephemeral indices."""

    def __init__(self) -> None:
        self._files: Dict[str, bytes] = {}

    def list_all(self) -> List[str]:
        return sorted(list(self._files.keys()))

    def file_exists(self, name: str) -> bool:
        return name in self._files

    def delete_file(self, name: str) -> None:
        if name in self._files:
            del self._files[name]

    def open_input(self, name: str) -> IndexInput:
        if name not in self._files:
            raise FileNotFoundError(f"File '{name}' not found in RAMDirectory")
        return IndexInput(self._files[name])

    def create_output(self, name: str) -> IndexOutput:
        return IndexOutput()

    def save_output(self, name: str, output: IndexOutput) -> None:
        self._files[name] = output.get_bytes()


class FSDirectory(Directory):
    """Filesystem-backed Directory implementation with crash resilience."""

    def __init__(self, path: str) -> None:
        self.path = os.path.abspath(path)
        os.makedirs(self.path, exist_ok=True)

    def list_all(self) -> List[str]:
        if not os.path.exists(self.path):
            return []
        return sorted(os.listdir(self.path))

    def file_exists(self, name: str) -> bool:
        return os.path.exists(os.path.join(self.path, name))

    def delete_file(self, name: str) -> None:
        fpath = os.path.join(self.path, name)
        if os.path.exists(fpath):
            os.remove(fpath)

    def open_input(self, name: str) -> IndexInput:
        fpath = os.path.join(self.path, name)
        if not os.path.exists(fpath):
            raise FileNotFoundError(
                f"File '{name}' not found in FSDirectory '{self.path}'"
            )
        with open(fpath, "rb") as f:
            return IndexInput(f.read())

    def create_output(self, name: str) -> IndexOutput:
        return IndexOutput()

    def save_output(self, name: str, output: IndexOutput) -> None:
        fpath = os.path.join(self.path, name)
        temp_path = fpath + ".tmp"
        with open(temp_path, "wb") as f:
            f.write(output.get_bytes())
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp_path, fpath)
