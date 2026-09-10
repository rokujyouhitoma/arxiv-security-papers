"""High-performance, memory-efficient Radix Tree (Patricia Trie) implementation.

Provides compressed-edge prefix indexing, longest prefix matching, and fast autocomplete.
Unified across CTI taxonomy lookups (MITRE ATT&CK, CWE, CVE) and search query suggestions.
"""

from __future__ import annotations

from typing import Dict, Generic, Iterator, List, Optional, Tuple, TypeVar

T = TypeVar("T")

MAX_RADIX_KEY_LENGTH = 4096
DEFAULT_SUGGEST_LIMIT = 20
MAX_SUGGEST_LIMIT = 1000


def _common_prefix_len(str1: str, str2: str) -> int:
    """Calculate length of longest common prefix between two strings."""
    limit = min(len(str1), len(str2))
    idx = 0
    while idx < limit and str1[idx] == str2[idx]:
        idx += 1
    return idx


class RadixNode(Generic[T]):
    """Internal node in Radix Tree with compressed edge string."""

    def __init__(self, prefix: str = "") -> None:
        self.prefix: str = prefix
        self.children: Dict[str, RadixNode[T]] = {}
        self.is_terminal: bool = False
        self.value: Optional[T] = None

    def add_child(self, child: RadixNode[T]) -> None:
        """Register a child node mapped by its first character."""
        if not child.prefix:
            return
        self.children[child.prefix[0]] = child

    def remove_child(self, first_char: str) -> None:
        """Remove a child by its indexing character."""
        self.children.pop(first_char, None)


def _split_edge(
    parent: RadixNode[T],
    child: RadixNode[T],
    common_len: int,
) -> RadixNode[T]:
    """Split an existing edge by inserting an intermediate node."""
    split_node: RadixNode[T] = RadixNode(child.prefix[:common_len])
    parent.add_child(split_node)

    child.prefix = child.prefix[common_len:]
    split_node.add_child(child)
    return split_node


def _insert_leaf(curr: RadixNode[T], rem_key: str, value: T) -> None:
    """Create and attach a new terminal leaf node."""
    new_leaf: RadixNode[T] = RadixNode(rem_key)
    new_leaf.is_terminal = True
    new_leaf.value = value
    curr.add_child(new_leaf)


def _advance_insert_step(
    curr: RadixNode[T], child: RadixNode[T], rem_key: str
) -> Tuple[RadixNode[T], int]:
    """Determine next node in insertion path, performing edge split if needed."""
    c_len = _common_prefix_len(rem_key, child.prefix)
    if c_len < len(child.prefix):
        split = _split_edge(curr, child, c_len)
        return split, c_len
    return child, c_len


def _step_find_node(curr: RadixNode[T], rem: str) -> Optional[Tuple[RadixNode[T], str]]:
    """Advance exact search step if prefix matches."""
    child = curr.children.get(rem[0])
    if child is None or not rem.startswith(child.prefix):
        return None
    return child, rem[len(child.prefix) :]


def _step_prefix_match(
    curr: RadixNode[T], rem: str
) -> Tuple[Optional[RadixNode[T]], Optional[str], Optional[str]]:
    """Advance prefix navigation step.

    Returns:
        (next_node, next_rem, early_match_rest)
    """
    child = curr.children.get(rem[0])
    if child is None:
        return None, None, None

    if len(rem) <= len(child.prefix):
        if child.prefix.startswith(rem):
            return child, None, child.prefix
        return None, None, None

    if not rem.startswith(child.prefix):
        return None, None, None

    return child, rem[len(child.prefix) :], child.prefix


def _push_reverse_children(
    stack: List[Tuple[RadixNode[T], str]], curr: RadixNode[T], path_acc: str
) -> None:
    """Push children to stack in reverse sorted order for deterministic forward order."""
    for char_key in sorted(curr.children.keys(), reverse=True):
        ch_node = curr.children[char_key]
        stack.append((ch_node, path_acc + ch_node.prefix))


def _record_terminal_entry(
    results: List[Tuple[str, T]], curr: RadixNode[T], path_acc: str
) -> None:
    """Append entry if node is terminal and holds a value."""
    if curr.is_terminal and curr.value is not None:
        results.append((path_acc, curr.value))


def _step_longest_match(
    curr: RadixNode[T], rem: str
) -> Optional[Tuple[RadixNode[T], str, str]]:
    """Advance longest prefix step if prefix matches."""
    child = curr.children.get(rem[0])
    if child is None or not rem.startswith(child.prefix):
        return None
    return child, rem[len(child.prefix) :], child.prefix


def _update_best_prefix_match(
    curr: RadixNode[T], accum: List[str]
) -> Optional[Tuple[str, T]]:
    """Return key-value match if current node is a valid terminal."""
    if curr.is_terminal and curr.value is not None:
        return "".join(accum), curr.value
    return None


class RadixTrie(Generic[T]):
    """Radix Tree (Compressed Trie) providing O(K) prefix operations."""

    def __init__(self) -> None:
        self.root: RadixNode[T] = RadixNode("")
        self._size: int = 0

    def __len__(self) -> int:
        return self._size

    def insert(self, key: str, value: T) -> None:
        """Insert or update a key-value pair in the Radix Tree."""
        if len(key) > MAX_RADIX_KEY_LENGTH:
            raise ValueError(
                f"Key length {len(key)} exceeds safe limit {MAX_RADIX_KEY_LENGTH}"
            )

        curr = self.root
        rem_key = key

        while rem_key:
            first_char = rem_key[0]
            if first_char not in curr.children:
                _insert_leaf(curr, rem_key, value)
                self._size += 1
                return

            curr, c_len = _advance_insert_step(curr, curr.children[first_char], rem_key)
            rem_key = rem_key[c_len:]

        if not curr.is_terminal:
            curr.is_terminal = True
            self._size += 1
        curr.value = value

    def get(self, key: str, default: Optional[T] = None) -> Optional[T]:
        """Retrieve value associated with exact key match."""
        node = self._find_exact_node(key)
        if node is not None and node.is_terminal:
            return node.value
        return default

    def contains(self, key: str) -> bool:
        """Check if exact key exists in the tree."""
        node = self._find_exact_node(key)
        return node is not None and node.is_terminal

    def __contains__(self, key: str) -> bool:
        return self.contains(key)

    def _find_exact_node(self, key: str) -> Optional[RadixNode[T]]:
        """Navigate to node exactly corresponding to key."""
        curr: Optional[RadixNode[T]] = self.root
        rem = key
        while curr is not None and rem:
            step = _step_find_node(curr, rem)
            if step is None:
                return None
            curr, rem = step
        return curr

    def _find_prefix_node(self, prefix: str) -> Optional[Tuple[RadixNode[T], str]]:
        """Locate root of subtree matching prefix and reconstructed key prefix."""
        curr: RadixNode[T] = self.root
        rem: Optional[str] = prefix
        accum: List[str] = []

        while rem is not None:
            child, next_rem, edge_str = _step_prefix_match(curr, rem)
            if child is None or edge_str is None:
                return None
            accum.append(edge_str)
            curr = child
            rem = next_rem

        return curr, "".join(accum)

    def find_by_prefix(
        self, prefix: str, limit: int = DEFAULT_SUGGEST_LIMIT
    ) -> List[Tuple[str, T]]:
        """Find all key-value entries starting with prefix up to limit."""
        eff_limit = max(1, min(limit, MAX_SUGGEST_LIMIT))
        matched = self._find_prefix_node(prefix)
        if matched is None:
            return []

        start_node, base_key = matched
        results: List[Tuple[str, T]] = []
        stack: List[Tuple[RadixNode[T], str]] = [(start_node, base_key)]

        while stack:
            if len(results) >= eff_limit:
                break
            curr, path_acc = stack.pop()
            _record_terminal_entry(results, curr, path_acc)
            _push_reverse_children(stack, curr, path_acc)

        return results

    def longest_prefix(self, text: str) -> Optional[Tuple[str, T]]:
        """Find the longest matching prefix key present in the tree."""
        curr: Optional[RadixNode[T]] = self.root
        rem = text
        accum: List[str] = []
        best_match: Optional[Tuple[str, T]] = None

        while curr is not None and rem:
            step = _step_longest_match(curr, rem)
            if step is None:
                break
            curr, rem, edge_str = step
            accum.append(edge_str)
            match = _update_best_prefix_match(curr, accum)
            if match is not None:
                best_match = match

        return best_match

    def items(self) -> Iterator[Tuple[str, T]]:
        """Iterate over all stored key-value pairs."""
        for entry in self.find_by_prefix("", limit=MAX_SUGGEST_LIMIT):
            yield entry

    def clear(self) -> None:
        """Clear all entries from the tree."""
        self.root = RadixNode("")
        self._size = 0
