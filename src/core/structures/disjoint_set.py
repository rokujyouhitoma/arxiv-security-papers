#!/usr/bin/env python3
"""
Zero-dependency, memory-efficient Disjoint Set (Union-Find) data structure.
Provides near-constant time O(alpha(N)) operations using Path Compression and Union by Rank.
"""

from __future__ import annotations

from typing import Dict, Generic, Iterator, List, Optional, Set, TypeVar

T = TypeVar("T")


def _compress_path(parent_map: Dict[T, T], path: List[T], root: T) -> None:
    """Flattens traversal path so all nodes point directly to root."""
    for node in path:
        parent_map[node] = root


def _link_by_rank(
    root_x: T,
    root_y: T,
    parent: Dict[T, T],
    rank: Dict[T, int],
    size: Dict[T, int],
) -> T:
    """Links smaller rank tree under larger rank tree. Returns new root."""
    rank_x = rank[root_x]
    rank_y = rank[root_y]

    if rank_x < rank_y:
        parent[root_x] = root_y
        size[root_y] += size[root_x]
        return root_y

    parent[root_y] = root_x
    size[root_x] += size[root_y]
    if rank_x == rank_y:
        rank[root_x] += 1
    return root_x


class DisjointSet(Generic[T]):
    """
    Disjoint Set Union (DSU) / Union-Find data structure.
    Enables fast connected-component detection and clustering in CTI graphs.
    """

    def __init__(
        self, elements: Optional[Iterator[T] | List[T] | Set[T]] = None
    ) -> None:
        self._parent: Dict[T, T] = {}
        self._rank: Dict[T, int] = {}
        self._size: Dict[T, int] = {}
        self._components_count: int = 0

        if elements is not None:
            for elem in elements:
                self.add(elem)

    def __len__(self) -> int:
        """Returns the total number of distinct elements."""
        return len(self._parent)

    def __contains__(self, item: T) -> bool:
        """Checks if item is registered in the disjoint set."""
        return item in self._parent

    @property
    def component_count(self) -> int:
        """Returns the number of disjoint components."""
        return self._components_count

    def add(self, x: T) -> bool:
        """Adds a single element as its own representative if not present."""
        if x in self._parent:
            return False
        self._parent[x] = x
        self._rank[x] = 0
        self._size[x] = 1
        self._components_count += 1
        return True

    def find(self, x: T) -> T:
        """
        Finds representative root of element x using iterative path compression.
        Automatically registers x if not previously seen.
        """
        if x not in self._parent:
            self.add(x)
            return x

        path: List[T] = []
        curr = x
        while self._parent[curr] != curr:
            path.append(curr)
            curr = self._parent[curr]

        _compress_path(self._parent, path, curr)
        return curr

    def union(self, x: T, y: T) -> bool:
        """
        Merges sets containing x and y.
        Returns True if merged, False if already in the same set.
        """
        root_x = self.find(x)
        root_y = self.find(y)

        if root_x == root_y:
            return False

        _link_by_rank(root_x, root_y, self._parent, self._rank, self._size)
        self._components_count -= 1
        return True

    def connected(self, x: T, y: T) -> bool:
        """Returns True if x and y belong to the same connected component."""
        if x not in self._parent or y not in self._parent:
            return False
        return self.find(x) == self.find(y)

    def component_size(self, x: T) -> int:
        """Returns the size of the connected component containing x."""
        root = self.find(x)
        return self._size[root]

    def get_components(self) -> Dict[T, Set[T]]:
        """
        Groups all elements into disjoint sets keyed by their root representative.
        """
        groups: Dict[T, Set[T]] = {}
        for elem in self._parent:
            root = self.find(elem)
            if root not in groups:
                groups[root] = set()
            groups[root].add(elem)
        return groups

    def clear(self) -> None:
        """Resets the disjoint set."""
        self._parent.clear()
        self._rank.clear()
        self._size.clear()
        self._components_count = 0
