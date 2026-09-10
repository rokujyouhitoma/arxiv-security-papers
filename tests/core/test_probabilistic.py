#!/usr/bin/env python3
"""
Unit tests for core probabilistic data structures: CountMinSketch and TDigest.
"""

import math
import random

import pytest

from core.structures.probabilistic import CountMinSketch, TDigest


def test_count_min_sketch_basic() -> None:
    cms = CountMinSketch(width=512, depth=5)
    assert cms.total_count == 0
    assert cms.estimate("APT28") == 0

    cms.add("APT28", 10)
    cms.add("APT29", 25)
    cms.add("Lazarus", 5)

    assert cms.total_count == 40
    # No underestimate guarantee
    assert cms.estimate("APT28") >= 10
    assert cms.estimate("APT29") >= 25
    assert cms.estimate("Lazarus") >= 5
    # Unseen item should have low/zero estimate
    assert cms.estimate("UnseenGroup") < 5

    # Negative or zero counts ignored
    cms.add("APT28", 0)
    cms.add("APT28", -5)
    assert cms.total_count == 40

    # Clear
    cms.clear()
    assert cms.total_count == 0
    assert cms.estimate("APT28") == 0


def test_count_min_sketch_merge() -> None:
    cms1 = CountMinSketch(width=256, depth=4)
    cms2 = CountMinSketch(width=256, depth=4)

    cms1.add("CVE-2024-0001", 15)
    cms2.add("CVE-2024-0001", 30)
    cms2.add("CVE-2024-0002", 7)

    cms1.merge(cms2)
    assert cms1.total_count == 52
    assert cms1.estimate("CVE-2024-0001") >= 45
    assert cms1.estimate("CVE-2024-0002") >= 7

    # Incompatible merge
    diff_dim = CountMinSketch(width=128, depth=4)
    with pytest.raises(ValueError, match="Cannot merge"):
        cms1.merge(diff_dim)


def test_count_min_sketch_heavy_hitters_accuracy() -> None:
    cms = CountMinSketch(width=1024, depth=5)
    oracle: dict[str, int] = {}

    rng = random.Random(42)
    # Heavy hitters
    oracle["T1059"] = 500
    oracle["T1071"] = 300
    cms.add("T1059", 500)
    cms.add("T1071", 300)

    # 1000 low-frequency noise items
    for i in range(1000):
        key = f"noise_{i}"
        cnt = rng.randint(1, 3)
        cms.add(key, cnt)
        oracle[key] = cnt

    # Estimate of heavy hitters should be within 5% error
    est_1059 = cms.estimate("T1059")
    est_1071 = cms.estimate("T1071")
    assert est_1059 >= 500
    assert est_1059 <= 500 + 0.05 * cms.total_count
    assert est_1071 >= 300
    assert est_1071 <= 300 + 0.05 * cms.total_count


def test_tdigest_basic_and_constants() -> None:
    td = TDigest(delta=0.02)
    assert len(td) == 0
    assert td.total_weight == 0.0
    assert td.quantile(0.5) == 0.0

    # Add single value
    td.add(42.0)
    assert td.quantile(0.0) == 42.0
    assert td.quantile(0.5) == 42.0
    assert td.quantile(1.0) == 42.0

    with pytest.raises(ValueError, match="Quantile must be in"):
        td.quantile(-0.1)
    with pytest.raises(ValueError, match="Quantile must be in"):
        td.quantile(1.1)

    # Add invalid values (NaN, Inf)
    td.add(float("nan"))
    td.add(float("inf"))
    td.add(10.0, weight=-1.0)
    assert td.total_weight == 1.0


def test_tdigest_uniform_distribution_accuracy() -> None:
    td = TDigest(delta=0.01)
    rng = random.Random(42)
    n = 10000
    samples = [rng.uniform(0.0, 100.0) for _ in range(n)]

    for s in samples:
        td.add(s)

    td.compress()
    # Centroid count bounded (O(1/delta))
    assert len(td.centroids) <= 5 * td.max_centroids

    # p50 expected around 50.0 (+/- 2.0)
    p50 = td.quantile(0.5)
    assert math.isclose(p50, 50.0, abs_tol=2.0)

    # p90 expected around 90.0 (+/- 2.0)
    p90 = td.quantile(0.9)
    assert math.isclose(p90, 90.0, abs_tol=2.0)

    # p99 expected around 99.0 (+/- 1.5)
    p99 = td.quantile(0.99)
    assert math.isclose(p99, 99.0, abs_tol=1.5)


def test_tdigest_tail_latency_accuracy() -> None:
    # Simulates web response latency: most are 10-30ms, tail up to 1000ms
    td = TDigest(delta=0.01)
    rng = random.Random(123)

    for _ in range(9500):
        td.add(rng.uniform(10.0, 30.0))
    for _ in range(500):
        td.add(rng.uniform(100.0, 1000.0))

    p50 = td.quantile(0.5)
    assert 10.0 <= p50 <= 30.0

    p99 = td.quantile(0.99)
    assert p99 >= 100.0


def test_tdigest_clear() -> None:
    td = TDigest()
    td.add(10.0)
    td.add(20.0)
    td.clear()
    assert len(td) == 0
    assert td.total_weight == 0.0
    assert td.quantile(0.5) == 0.0
