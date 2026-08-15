"""
Unit tests for SynonymExpander, FMIndex, and 5-Method Multi-Engine VectorEngine
"""

import os
import sys

from synonym_expander import SynonymExpander
from vector_engine import FMIndex, VectorEngine

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
    )


def test_synonym_expander():
    expander = SynonymExpander()

    # Test Japanese to English penetration testing expansion
    expanded_pentest = expander.expand_query("ペンテスト")
    assert "penetration testing" in expanded_pentest or "pentest" in expanded_pentest
    assert "exploit" in expanded_pentest

    # Test autonomous vehicle expansion
    expanded_av = expander.expand_query("自動運転")
    assert "autonomous vehicle" in expanded_av or "autonomous vehicles" in expanded_av


def test_fm_index_substring_search():
    fm = FMIndex("マルウェア解析と自動運転セキュリティの脆弱性")
    count1 = fm.count_substring("マルウェア")
    count2 = fm.count_substring("自動運転")
    assert count1 == 1
    assert count2 == 1


def test_vector_engine_multi_engine_search():
    engine = VectorEngine()
    results = engine.search("マルウェア解析", top_k=3)
    assert isinstance(results, list)
    if results:
        assert "score" in results[0]
        assert "path" in results[0]
        assert "annotated_keywords" in results[0]
