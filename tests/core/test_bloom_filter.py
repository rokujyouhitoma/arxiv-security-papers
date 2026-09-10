"""Unit tests for core BloomFilter and ScalableBloomFilter implementations."""

import pytest

from core.structures.bloom_filter import (
    BloomFilter,
    ScalableBloomFilter,
    _calculate_optimal_bits,
    _calculate_optimal_hashes,
)


def test_bloom_filter_math_helpers() -> None:
    """Test optimal bits and hash functions calculations."""
    bits = _calculate_optimal_bits(1000, 0.01)
    assert bits > 64
    hashes = _calculate_optimal_hashes(bits, 1000)
    assert 1 <= hashes <= 32


def test_bloom_filter_validation_errors() -> None:
    """Test input argument validation on BloomFilter."""
    with pytest.raises(ValueError, match="Capacity must be greater than 0"):
        BloomFilter(capacity=0)

    with pytest.raises(ValueError, match="Capacity must be greater than 0"):
        BloomFilter(capacity=-10)

    with pytest.raises(
        ValueError, match="Error rate must be between 0 and 1 exclusive"
    ):
        BloomFilter(capacity=100, error_rate=0.0)

    with pytest.raises(
        ValueError, match="Error rate must be between 0 and 1 exclusive"
    ):
        BloomFilter(capacity=100, error_rate=1.0)


def test_bloom_filter_basic_operations() -> None:
    """Test standard membership testing, count, and clear."""
    bf = BloomFilter(capacity=500, error_rate=0.01)
    assert len(bf) == 0

    assert bf.add("paper:2609.0001") is True
    assert bf.add("paper:2609.0001") is False  # Duplicate
    assert len(bf) == 1

    assert bf.contains("paper:2609.0001") is True
    assert "paper:2609.0001" in bf
    assert "paper:2609.9999" not in bf

    # Clear
    bf.clear()
    assert len(bf) == 0
    assert "paper:2609.0001" not in bf


def test_bloom_filter_expected_items_alias() -> None:
    """Test backwards-compatible alias expected_items and fp_rate."""
    bf = BloomFilter(expected_items=200, fp_rate=0.05)
    assert bf.capacity == 200
    assert bf.error_rate == 0.05
    bf.add("test_key")
    assert "test_key" in bf


def test_bloom_filter_zero_false_negatives_and_fpp() -> None:
    """Verify zero false negatives and empirical false positive rate within bounds."""
    capacity = 1000
    bf = BloomFilter(capacity=capacity, error_rate=0.01)

    # Insert elements
    keys = [f"item:key:{i:05d}" for i in range(capacity)]
    for k in keys:
        bf.add(k)

    # 1. Zero False Negatives
    for k in keys:
        assert bf.contains(k) is True
        assert k in bf

    # 2. False Positive Rate
    probe_keys = [f"absent:key:{i:05d}" for i in range(1000)]
    false_positives = sum(1 for k in probe_keys if k in bf)
    observed_fpp = false_positives / len(probe_keys)

    # Expected ~1%, allow generous upper bound 5% due to finite random sample
    assert observed_fpp < 0.05


def test_bloom_filter_serialization_roundtrip() -> None:
    """Verify binary serialization and deserialization."""
    bf = BloomFilter(capacity=500, error_rate=0.01)
    for i in range(100):
        bf.add(f"key:{i}")

    raw = bf.to_bytes()
    assert len(raw) > 6

    restored = BloomFilter.from_bytes(raw, count=100)
    assert len(restored) == 100
    for i in range(100):
        assert f"key:{i}" in restored
    assert "key:9999" not in restored


def test_bloom_filter_from_bytes_corrupted() -> None:
    """Test payload validation on from_bytes."""
    with pytest.raises(ValueError, match="too short"):
        BloomFilter.from_bytes(b"short")

    with pytest.raises(ValueError, match="Payload size mismatch"):
        # Header specifies 1000 bits (~125 bytes) but only provides 10 bytes
        import struct

        header = struct.pack("<IH", 1000, 5)
        BloomFilter.from_bytes(header + b"\x00" * 10)


def test_scalable_bloom_filter_validation() -> None:
    """Test validation errors for ScalableBloomFilter."""
    with pytest.raises(ValueError, match="Initial capacity must be greater than 0"):
        ScalableBloomFilter(initial_capacity=0)

    with pytest.raises(
        ValueError, match="Error rate must be between 0 and 1 exclusive"
    ):
        ScalableBloomFilter(initial_capacity=100, error_rate=1.5)

    with pytest.raises(ValueError, match="Scale factor must be greater than 1"):
        ScalableBloomFilter(initial_capacity=100, scale_factor=1)


def test_scalable_bloom_filter_auto_growth() -> None:
    """Test dynamic scaling and sub-filter growth."""
    sbf = ScalableBloomFilter(initial_capacity=10, error_rate=0.001, scale_factor=2)
    assert len(sbf) == 0

    # Insert 35 elements
    for i in range(35):
        added = sbf.add(f"url:https://arxiv.org/abs/{i}")
        assert added is True

    # Duplicate should return False
    assert sbf.add("url:https://arxiv.org/abs/0") is False
    assert len(sbf) == 35

    # Membership tests
    for i in range(35):
        assert f"url:https://arxiv.org/abs/{i}" in sbf
        assert sbf.contains(f"url:https://arxiv.org/abs/{i}") is True

    assert "url:https://arxiv.org/abs/999" not in sbf
    assert len(sbf.filters) > 1
