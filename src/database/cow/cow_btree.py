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

    def serialize(self) -> bytes:
        """Serializes node into 4096-byte payload."""
        buf = bytearray()
        leaf_flag = 1 if self.is_leaf else 0
        key_count = len(self.keys)

        if self.is_leaf:
            # Format: <BH (leaf_flag, key_count)
            buf.extend(struct.pack("<BH", leaf_flag, key_count))
            for k, v in zip(self.keys, self.values):
                k_bytes = k.encode("utf-8")
                buf.extend(struct.pack("<HH", len(k_bytes), len(v)) + k_bytes + v)
        else:
            # Format: <BHI (leaf_flag, key_count, first_child_pid)
            first_child = self.children[0] if self.children else 0
            buf.extend(struct.pack("<BHI", leaf_flag, key_count, first_child))
            for i, k in enumerate(self.keys):
                k_bytes = k.encode("utf-8")
                child_pid = self.children[i + 1] if i + 1 < len(self.children) else 0
                buf.extend(struct.pack("<HI", len(k_bytes), child_pid) + k_bytes)

        if len(buf) > 4096:
            raise ValueError(f"CoW node serialized size {len(buf)} exceeds 4096 bytes")
        return bytes(buf)

    @classmethod
    def deserialize(cls, data: memoryview) -> "CoWNode":
        """Deserializes node from memoryview slice."""
        if len(data) < 3:
            return cls(is_leaf=True)

        leaf_flag, key_count = struct.unpack_from("<BH", data, 0)
        is_leaf = leaf_flag == 1

        if is_leaf:
            keys: List[str] = []
            values: List[bytes] = []
            pos = 3
            for _ in range(key_count):
                if pos + 4 > len(data):
                    break
                k_len, v_len = struct.unpack_from("<HH", data, pos)
                pos += 4
                k_str = bytes(data[pos : pos + k_len]).decode("utf-8")
                pos += k_len
                v_bytes = bytes(data[pos : pos + v_len])
                pos += v_len
                keys.append(k_str)
                values.append(v_bytes)
            return cls(is_leaf=True, keys=keys, values=values)
        else:
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
                k_str = bytes(data[pos : pos + k_len]).decode("utf-8")
                pos += k_len
                keys_internal.append(k_str)
                children.append(child_pid)
            return cls(is_leaf=False, keys=keys_internal, children=children)


class CoWBTree:
    """
    Copy-on-Write B-Tree algorithm with shadow paging.
    """

    def __init__(self, mmap_file: MMapFile) -> None:
        self.mmap_file = mmap_file

    def get(self, root_page_id: int, key: str) -> Optional[bytes]:
        """
        Performs a zero-copy lock-free lookup for key starting from root_page_id.
        """
        if root_page_id == 0:
            return None

        curr_pid = root_page_id
        while curr_pid != 0:
            view = self.mmap_file.read_page_view(curr_pid)
            node = CoWNode.deserialize(view)

            if node.is_leaf:
                idx = bisect.bisect_left(node.keys, key)
                if idx < len(node.keys) and node.keys[idx] == key:
                    return node.values[idx]
                return None
            else:
                idx = bisect.bisect_right(node.keys, key)
                curr_pid = node.children[idx]

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
        retired_pages.append(curr_pid)
        view = self.mmap_file.read_page_view(curr_pid)
        node = CoWNode.deserialize(view)

        new_pid = self.mmap_file.allocate_page()

        if node.is_leaf:
            # Insert into cloned leaf
            idx = bisect.bisect_left(node.keys, key)
            if idx < len(node.keys) and node.keys[idx] == key:
                node.values[idx] = value
            else:
                node.keys.insert(idx, key)
                node.values.insert(idx, value)

            # Check if leaf needs splitting
            if len(node.keys) > MAX_LEAF_KEYS:
                mid = len(node.keys) // 2
                split_key = node.keys[mid]

                right_pid = self.mmap_file.allocate_page()
                right_leaf = CoWNode(
                    is_leaf=True,
                    keys=node.keys[mid:],
                    values=node.values[mid:],
                )
                self.mmap_file.write_page(right_pid, right_leaf.serialize())

                node.keys = node.keys[:mid]
                node.values = node.values[:mid]
                self.mmap_file.write_page(new_pid, node.serialize())
                return new_pid, split_key, right_pid
            else:
                self.mmap_file.write_page(new_pid, node.serialize())
                return new_pid, None, None
        else:
            # Route to appropriate child
            idx = bisect.bisect_right(node.keys, key)
            child_pid = node.children[idx]

            new_c_pid, split_k, split_r_pid = self._cow_insert_recursive(
                child_pid, key, value, retired_pages
            )
            node.children[idx] = new_c_pid

            if split_k is not None and split_r_pid is not None:
                insert_idx = bisect.bisect_right(node.keys, split_k)
                node.keys.insert(insert_idx, split_k)
                node.children.insert(insert_idx + 1, split_r_pid)

            # Check if internal node needs splitting
            if len(node.keys) > MAX_INTERNAL_KEYS:
                mid = len(node.keys) // 2
                promote_key = node.keys[mid]

                right_pid = self.mmap_file.allocate_page()
                right_node = CoWNode(
                    is_leaf=False,
                    keys=node.keys[mid + 1 :],
                    children=node.children[mid + 1 :],
                )
                self.mmap_file.write_page(right_pid, right_node.serialize())

                node.keys = node.keys[:mid]
                node.children = node.children[: mid + 1]
                self.mmap_file.write_page(new_pid, node.serialize())
                return new_pid, promote_key, right_pid
            else:
                self.mmap_file.write_page(new_pid, node.serialize())
                return new_pid, None, None

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
            # Key not found: no change
            return root_page_id, []

        # Check if root is an internal node with 0 keys
        view = self.mmap_file.read_page_view(new_root_pid)
        root_node = CoWNode.deserialize(view)
        if not root_node.is_leaf and len(root_node.keys) == 0:
            retired_pages.append(new_root_pid)
            return root_node.children[0] if root_node.children else 0, retired_pages

        return new_root_pid, retired_pages

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

    def _scan_recursive(
        self,
        curr_pid: int,
        start_key: Optional[str],
        end_key: Optional[str],
        results: List[Tuple[str, bytes]],
    ) -> None:
        view = self.mmap_file.read_page_view(curr_pid)
        node = CoWNode.deserialize(view)

        if node.is_leaf:
            for k, v in zip(node.keys, node.values):
                if start_key is not None and k < start_key:
                    continue
                if end_key is not None and k >= end_key:
                    return
                results.append((k, v))
        else:
            for i, child_pid in enumerate(node.children):
                self._scan_recursive(child_pid, start_key, end_key, results)
