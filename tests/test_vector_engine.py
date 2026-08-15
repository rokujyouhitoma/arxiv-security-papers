"""
Unit tests for SynonymExpander and enhanced VectorEngine
"""
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

from synonym_expander import SynonymExpander
from vector_engine import VectorEngine


def test_synonym_expander():
    expander = SynonymExpander()
    
    # Test Japanese to English penetration testing expansion
    expanded_pentest = expander.expand_query("ペンテスト")
    assert "penetration testing" in expanded_pentest or "pentest" in expanded_pentest
    assert "exploit" in expanded_pentest

    # Test autonomous vehicle expansion
    expanded_av = expander.expand_query("自動運転")
    assert "autonomous vehicle" in expanded_av or "autonomous vehicles" in expanded_av


def test_vector_engine_enhanced_search():
    engine = VectorEngine()
    results = engine.search("ペンテスト自動化", top_k=3)
    assert isinstance(results, list)
    if results:
        assert "score" in results[0]
        assert "path" in results[0]
