#!/usr/bin/env python3
"""
FM-Index / Suffix Array Substring Search Engine
Allows exact substring count and matching across full text.
"""

from typing import List


class FMIndex:
    """
    FM-Index / Suffix Array Substring Search Engine
    Allows exact substring count and matching across full text.
    """

    def __init__(self, text: str = ""):
        self.text = text.lower() if text else ""
        self.suffix_array: List[int] = []
        if text:
            self.build(text)

    def build(self, text: str) -> None:
        self.text = text.lower()
        suffixes = sorted((self.text[i:], i) for i in range(len(self.text)))
        self.suffix_array = [idx for _, idx in suffixes]

    def count_substring(self, query: str) -> int:
        """Counts exact substring occurrences using binary search on Suffix Array or fast substring search."""
        if not query or not self.text:
            return 0
        q = query.lower()
        if len(self.text) > 1000 and self.suffix_array:
            n = len(self.suffix_array)
            low, high = 0, n - 1
            left = n
            while low <= high:
                mid = (low + high) // 2
                idx = self.suffix_array[mid]
                if self.text[idx:].startswith(q) or self.text[idx:] >= q:
                    left = mid
                    high = mid - 1
                else:
                    low = mid + 1

            low, high = 0, n - 1
            right = -1
            while low <= high:
                mid = (low + high) // 2
                idx = self.suffix_array[mid]
                if self.text[idx:].startswith(q):
                    right = mid
                    low = mid + 1
                elif self.text[idx:] < q:
                    low = mid + 1
                else:
                    high = mid - 1

            if left <= right:
                return right - left + 1
            return 0
        else:
            return self.text.count(q)
