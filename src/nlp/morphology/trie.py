"""Prefix Trie container for fast dictionary lookups.

Provides memory-efficient prefix tree structure optimized for morphological
analysis and compound keyphrase extraction.
Guaranteed O(L) lookup where L is word length and Xenon CC <= 3.
Zero external dependencies.
"""

from typing import Any, Dict, List, Optional, Tuple


class TrieNode:
    """Internal node of PrefixTrie."""

    __slots__ = ("children", "is_terminal", "value")

    def __init__(self) -> None:
        """Initialize empty trie node."""
        self.children: Dict[str, TrieNode] = {}
        self.is_terminal: bool = False
        self.value: Any = None


class PrefixTrie:
    """Prefix Trie supporting exact match and common prefix search."""

    def __init__(self) -> None:
        """Initialize empty PrefixTrie."""
        self._root = TrieNode()
        self._size = 0

    def __len__(self) -> int:
        """Return number of unique words stored in trie."""
        return self._size

    def __contains__(self, word: str) -> bool:
        """Return True if word exists as exact match."""
        return self.search(word) is not None

    def insert(self, word: str, value: Any = True) -> None:
        """Insert a word and associated value into trie."""
        if not word:
            return
        node = self._root
        for char in word:
            if char not in node.children:
                node.children[char] = TrieNode()
            node = node.children[char]
        if not node.is_terminal:
            self._size += 1
            node.is_terminal = True
        node.value = value

    def search(self, word: str) -> Optional[Any]:
        """Search exact match for word and return associated value."""
        if not word:
            return None
        node = self._traverse(word)
        if node is not None and node.is_terminal:
            return node.value
        return None

    def longest_prefix(self, text: str, start: int = 0) -> Optional[Tuple[str, Any]]:
        """Find longest matching prefix starting at text[start]."""
        matches = self.common_prefix_search(text, start)
        if not matches:
            return None
        return matches[-1]

    def _is_invalid_offset(self, text: str, start: int) -> bool:
        """Check if start offset is out of bounds."""
        return start < 0 or start >= len(text)

    def _collect_prefix_matches(self, text: str, start: int) -> List[Tuple[str, Any]]:
        """Traverse characters from start collecting terminal prefix nodes."""
        results: List[Tuple[str, Any]] = []
        node = self._root
        prefix_chars: List[str] = []
        for i in range(start, len(text)):
            next_node = node.children.get(text[i])
            if next_node is None:
                break
            node = next_node
            prefix_chars.append(text[i])
            if node.is_terminal:
                results.append(("".join(prefix_chars), node.value))
        return results

    def common_prefix_search(self, text: str, start: int = 0) -> List[Tuple[str, Any]]:
        """Return all matching prefixes from text[start] in ascending length."""
        if self._is_invalid_offset(text, start):
            return []
        return self._collect_prefix_matches(text, start)

    def _traverse(self, text: str) -> Optional[TrieNode]:
        """Traverse trie nodes following text path."""
        node = self._root
        for char in text:
            if char not in node.children:
                return None
            node = node.children[char]
        return node
