"""
Core data structures for arxiv-security-papers.
Provides high-performance, space-efficient pure-Python algorithms and containers.
"""

from core.structures.bloom_filter import BloomFilter, ScalableBloomFilter
from core.structures.radix_trie import (
    MAX_RADIX_KEY_LENGTH,
    MAX_SUGGEST_LIMIT,
    RadixNode,
    RadixTrie,
)
from core.structures.roaring_bitmap import (
    ARRAY_MAX_CAPACITY,
    BITMAP_WORDS,
    CHUNK_SIZE,
    SERIAL_COOKIE,
    TYPE_ARRAY,
    TYPE_BITMAP,
    TYPE_RUN,
    ArrayContainer,
    BitmapContainer,
    Container,
    RoaringBitmap,
    RunContainer,
)

__all__ = [
    "SERIAL_COOKIE",
    "CHUNK_SIZE",
    "ARRAY_MAX_CAPACITY",
    "BITMAP_WORDS",
    "TYPE_ARRAY",
    "TYPE_BITMAP",
    "TYPE_RUN",
    "Container",
    "ArrayContainer",
    "BitmapContainer",
    "RunContainer",
    "RoaringBitmap",
    "BloomFilter",
    "ScalableBloomFilter",
    "RadixNode",
    "RadixTrie",
    "MAX_RADIX_KEY_LENGTH",
    "MAX_SUGGEST_LIMIT",
]
