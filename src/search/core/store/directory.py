#!/usr/bin/env python3
"""
Lucene-style Directory Storage Abstraction.
Encapsulates file and in-memory IO for segments and index structures.
"""

import os
from typing import Dict, List


class Directory:
    """Base abstract Directory."""

    def list_all(self) -> List[str]:
        raise NotImplementedError

    def file_exists(self, name: str) -> bool:
        raise NotImplementedError

    def read_bytes(self, name: str) -> bytes:
        raise NotImplementedError

    def write_bytes(self, name: str, data: bytes) -> None:
        raise NotImplementedError

    def delete_file(self, name: str) -> None:
        raise NotImplementedError


class RAMDirectory(Directory):
    """In-memory Directory implementation for fast execution and lightweight testing."""

    def __init__(self) -> None:
        self.files: Dict[str, bytes] = {}

    def list_all(self) -> List[str]:
        return list(self.files.keys())

    def file_exists(self, name: str) -> bool:
        return name in self.files

    def read_bytes(self, name: str) -> bytes:
        if name not in self.files:
            raise FileNotFoundError(f"File not found in RAMDirectory: {name}")
        return self.files[name]

    def write_bytes(self, name: str, data: bytes) -> None:
        self.files[name] = data

    def delete_file(self, name: str) -> None:
        if name in self.files:
            del self.files[name]


class FSDirectory(Directory):
    """File-system based Directory implementation."""

    def __init__(self, path: str) -> None:
        self.path = os.path.abspath(path)
        os.makedirs(self.path, exist_ok=True)

    def _get_path(self, name: str) -> str:
        return os.path.join(self.path, name)

    def list_all(self) -> List[str]:
        if not os.path.exists(self.path):
            return []
        return os.listdir(self.path)

    def file_exists(self, name: str) -> bool:
        return os.path.exists(self._get_path(name))

    def read_bytes(self, name: str) -> bytes:
        with open(self._get_path(name), "rb") as f:
            return f.read()

    def write_bytes(self, name: str, data: bytes) -> None:
        with open(self._get_path(name), "wb") as f:
            f.write(data)

    def delete_file(self, name: str) -> None:
        target = self._get_path(name)
        if os.path.exists(target):
            os.remove(target)
