#!/usr/bin/env python3
"""
Copy-on-Write (CoW) B-Tree Engine with Shadow Paging.
Provides lock-free, zero-copy reads, immutable path replication on writes,
and crash consistency without Write-Ahead Logging (WAL-less ACID).
"""

import bisect
import struct
from typing import List, Optional, Tuple

from .mmap_file import MMapFile

MAX_LEAF_KEYS: int = 32
MAX_INTERNAL_KEYS: int = 32


class CoWNode:
    """
    In-memory representation of a CoW B-Tree 4KB node.
    """

    def __init__(
        self,
        is_leaf: bool = True,
        keys: Optional[List[str]] = None,
        values: Optional[List[bytes]] = None,
        children: Optional[List[int]] = None,
    ) -> None:
        self.is_leaf = is_leaf
        self.keys: List[str] = keys if keys is not None else []
        self.values: List[bytes] = values if values is not None else []
        self.children: List[int] = children if children is not None else []

    def _serialize_leaf(self, buf: bytearray, leaf_flag: int) -> None:
        buf.extend(struct.pack("<BH", leaf_flag, len(self.keys)))
        for k, v in zip(self.keys, self.values):
            k_bytes = k.encode("utf-8")
            buf.extend(struct.pack("<HH", len(k_bytes), len(v)) + k_bytes + v)

    def _serialize_internal(self, buf: bytearray, leaf_flag: int) -> None:
        first_child = self.children[0] if self.children else 0
        buf.extend(struct.pack("<BHI", leaf_flag, len(self.keys), first_child))
        for i, k in enumerate(self.keys):
            k_bytes = k.encode("utf-8")
            child_pid = self.children[i + 1] if i + 1 < len(self.children) else 0
            buf.extend(struct.pack("<HI", len(k_bytes), child_pid) + k_bytes)

    def serialize(self) -> bytes:
        """Serializes node into 4096-byte payload."""
        buf = bytearray()
        leaf_flag = 1 if self.is_leaf else 0
        if self.is_leaf:
            self._serialize_leaf(buf, leaf_flag)
        else:
            self._serialize_internal(buf, leaf_flag)
        if len(buf) > 4096:
            raise ValueError(f"CoW node serialized size {len(buf)} exceeds 4096 bytes")
        return bytes(buf)

    @classmethod
    def _deserialize_leaf(cls, data: memoryview, key_count: int) -> "CoWNode":
        keys: List[str] = []
        values: List[bytes] = []
        pos = 3
        for _ in range(key_count):
            if pos + 4 > len(data):
                break
            k_len, v_len = struct.unpack_from("<HH", data, pos)
            pos += 4
            keys.append(bytes(data[pos : pos + k_len]).decode("utf-8"))
            pos += k_len
            values.append(bytes(data[pos : pos + v_len]))
            pos += v_len
        return cls(is_leaf=True, keys=keys, values=values)

    @classmethod
    def _deserialize_internal(cls, data: memoryview, key_count: int) -> "CoWNode":
        if len(data) < 7:
            return cls(is_leaf=False)
        first_child = struct.unpack_from("<I", data, 3)[0]
        children: List[int] = [first_child]
        keys_internal: List[str] = []
        pos = 7
        for _ in range(key_count):
            if pos + 6 > len(data):
                break
            k_len, child_pid = struct.unpack_from("<HI", data, pos)
            pos += 6
            keys_internal.append(bytes(data[pos : pos + k_len]).decode("utf-8"))
            pos += k_len
            children.append(child_pid)
        return cls(is_leaf=False, keys=keys_internal, children=children)

    @classmethod
    def deserialize(cls, data: memoryview) -> "CoWNode":
        """Deserializes node from memoryview slice."""
        if len(data) < 3:
            return cls(is_leaf=True)
        leaf_flag, key_count = struct.unpack_from("<BH", data, 0)
        if leaf_flag == 1:
            return cls._deserialize_leaf(data, key_count)
        return cls._deserialize_internal(data, key_count)


class CoWBTree:
    """
    Copy-on-Write B-Tree algorithm with shadow paging.
    """

    def __init__(self, mmap_file: MMapFile) -> None:
        self.mmap_file = mmap_file

    def _get_leaf_value(self, node: CoWNode, key: str) -> Optional[bytes]:
        idx = bisect.bisect_left(node.keys, key)
        if idx < len(node.keys) and node.keys[idx] == key:
            return node.values[idx]
        return None

    def get(self, root_page_id: int, key: str) -> Optional[bytes]:
        """
        Performs a zero-copy lock-free lookup for key starting from root_page_id.
        """
        if root_page_id == 0:
            return None
        curr_pid = root_page_id
        while curr_pid != 0:
            node = CoWNode.deserialize(self.mmap_file.read_page_view(curr_pid))
            if node.is_leaf:
                return self._get_leaf_value(node, key)
            curr_pid = node.children[bisect.bisect_right(node.keys, key)]
        return None

    def insert(
        self, root_page_id: int, key: str, value: bytes
    ) -> Tuple[int, List[int]]:
        """
        Inserts key-value pair via CoW shadow paging.
        Returns: (new_root_page_id, retired_old_page_ids)
        """
        if root_page_id == 0:
            # Allocate initial root leaf node
            new_root_pid = self.mmap_file.allocate_page()
            leaf = CoWNode(is_leaf=True, keys=[key], values=[value])
            self.mmap_file.write_page(new_root_pid, leaf.serialize())
            return new_root_pid, []

        retired_pages: List[int] = []
        new_child_pid, split_key, split_pid = self._cow_insert_recursive(
            root_page_id, key, value, retired_pages
        )

        if split_key is not None and split_pid is not None:
            # Root was split: create a new root internal node
            new_root_pid = self.mmap_file.allocate_page()
            new_root = CoWNode(
                is_leaf=False,
                keys=[split_key],
                children=[new_child_pid, split_pid],
            )
            self.mmap_file.write_page(new_root_pid, new_root.serialize())
            return new_root_pid, retired_pages

        return new_child_pid, retired_pages

    def _cow_insert_leaf(
        self,
        node: CoWNode,
        key: str,
        value: bytes,
        new_pid: int,
        retired_pages: List[int],
        curr_pid: int,
    ) -> Tuple[int, Optional[str], Optional[int]]:
        retired_pages.append(curr_pid)
        idx = bisect.bisect_left(node.keys, key)
        if idx < len(node.keys) and node.keys[idx] == key:
            node.values[idx] = value
        else:
            node.keys.insert(idx, key)
            node.values.insert(idx, value)
        if len(node.keys) > MAX_LEAF_KEYS:
            mid = len(node.keys) // 2
            split_key = node.keys[mid]
            right_pid = self.mmap_file.allocate_page()
            self.mmap_file.write_page(
                right_pid,
                CoWNode(
                    is_leaf=True, keys=node.keys[mid:], values=node.values[mid:]
                ).serialize(),
            )
            node.keys = node.keys[:mid]
            node.values = node.values[:mid]
            self.mmap_file.write_page(new_pid, node.serialize())
            return new_pid, split_key, right_pid
        self.mmap_file.write_page(new_pid, node.serialize())
        return new_pid, None, None

    def _cow_insert_internal(
        self,
        node: CoWNode,
        key: str,
        value: bytes,
        new_pid: int,
        retired_pages: List[int],
        curr_pid: int,
    ) -> Tuple[int, Optional[str], Optional[int]]:
        retired_pages.append(curr_pid)
        idx = bisect.bisect_right(node.keys, key)
        new_c_pid, split_k, split_r_pid = self._cow_insert_recursive(
            node.children[idx], key, value, retired_pages
        )
        node.children[idx] = new_c_pid
        if split_k is not None and split_r_pid is not None:
            insert_idx = bisect.bisect_right(node.keys, split_k)
            node.keys.insert(insert_idx, split_k)
            node.children.insert(insert_idx + 1, split_r_pid)
        if len(node.keys) > MAX_INTERNAL_KEYS:
            mid = len(node.keys) // 2
            promote_key = node.keys[mid]
            right_pid = self.mmap_file.allocate_page()
            self.mmap_file.write_page(
                right_pid,
                CoWNode(
                    is_leaf=False,
                    keys=node.keys[mid + 1 :],
                    children=node.children[mid + 1 :],
                ).serialize(),
            )
            node.keys = node.keys[:mid]
            node.children = node.children[: mid + 1]
            self.mmap_file.write_page(new_pid, node.serialize())
            return new_pid, promote_key, right_pid
        self.mmap_file.write_page(new_pid, node.serialize())
        return new_pid, None, None

    def _cow_insert_recursive(
        self,
        curr_pid: int,
        key: str,
        value: bytes,
        retired_pages: List[int],
    ) -> Tuple[int, Optional[str], Optional[int]]:
        """
        Recursive CoW insertion. Clones the modified path into newly allocated pages.
        Returns: (new_pid, split_key, split_pid)
        """
        node = CoWNode.deserialize(self.mmap_file.read_page_view(curr_pid))
        new_pid = self.mmap_file.allocate_page()
        if node.is_leaf:
            return self._cow_insert_leaf(
                node, key, value, new_pid, retired_pages, curr_pid
            )
        return self._cow_insert_internal(
            node, key, value, new_pid, retired_pages, curr_pid
        )

    def _collapse_empty_root(self, new_root_pid: int, retired_pages: List[int]) -> int:
        root_node = CoWNode.deserialize(self.mmap_file.read_page_view(new_root_pid))
        if not root_node.is_leaf and len(root_node.keys) == 0:
            retired_pages.append(new_root_pid)
            return root_node.children[0] if root_node.children else 0
        return new_root_pid

    def delete(self, root_page_id: int, key: str) -> Tuple[int, List[int]]:
        """
        Deletes key via CoW shadow paging.
        Returns: (new_root_page_id, retired_old_page_ids)
        """
        if root_page_id == 0:
            return 0, []
        retired_pages: List[int] = []
        new_root_pid, deleted = self._cow_delete_recursive(
            root_page_id, key, retired_pages
        )
        if not deleted:
            return root_page_id, []
        return self._collapse_empty_root(new_root_pid, retired_pages), retired_pages

    def _cow_delete_recursive(
        self,
        curr_pid: int,
        key: str,
        retired_pages: List[int],
    ) -> Tuple[int, bool]:
        view = self.mmap_file.read_page_view(curr_pid)
        node = CoWNode.deserialize(view)

        new_pid = self.mmap_file.allocate_page()

        if node.is_leaf:
            idx = bisect.bisect_left(node.keys, key)
            if idx < len(node.keys) and node.keys[idx] == key:
                retired_pages.append(curr_pid)
                node.keys.pop(idx)
                node.values.pop(idx)
                self.mmap_file.write_page(new_pid, node.serialize())
                return new_pid, True
            return curr_pid, False
        else:
            idx = bisect.bisect_right(node.keys, key)
            child_pid = node.children[idx]
            new_c_pid, deleted = self._cow_delete_recursive(
                child_pid, key, retired_pages
            )
            if deleted:
                retired_pages.append(curr_pid)
                node.children[idx] = new_c_pid
                self.mmap_file.write_page(new_pid, node.serialize())
                return new_pid, True
            return curr_pid, False

    def scan(
        self,
        root_page_id: int,
        start_key: Optional[str] = None,
        end_key: Optional[str] = None,
    ) -> List[Tuple[str, bytes]]:
        """
        Performs in-order range scan [start_key, end_key) starting from root_page_id.
        """
        results: List[Tuple[str, bytes]] = []
        if root_page_id == 0:
            return results

        self._scan_recursive(root_page_id, start_key, end_key, results)
        return results

    @staticmethod
    def _key_in_range(k: str, start_key: Optional[str], end_key: Optional[str]) -> bool:
        if start_key is not None and k < start_key:
            return False
        if end_key is not None and k >= end_key:
            return False
        return True

    def _scan_leaf(
        self,
        node: CoWNode,
        start_key: Optional[str],
        end_key: Optional[str],
        results: List[Tuple[str, bytes]],
    ) -> None:
        for k, v in zip(node.keys, node.values):
            if end_key is not None and k >= end_key:
                return
            if self._key_in_range(k, start_key, None):
                results.append((k, v))

    def _scan_recursive(
        self,
        curr_pid: int,
        start_key: Optional[str],
        end_key: Optional[str],
        results: List[Tuple[str, bytes]],
    ) -> None:
        node = CoWNode.deserialize(self.mmap_file.read_page_view(curr_pid))
        if node.is_leaf:
            self._scan_leaf(node, start_key, end_key, results)
        else:
            for child_pid in node.children:
                self._scan_recursive(child_pid, start_key, end_key, results)
