"""
Unit tests for Web Server API handlers
"""

import os
import sys

from web_server import VECTOR_ENGINE

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
    )


def test_vector_engine_ready():
    assert VECTOR_ENGINE is not None
    assert isinstance(VECTOR_ENGINE.documents, list)


def test_search_handler_logic():
    results = VECTOR_ENGINE.search("malware", top_k=2)
    assert isinstance(results, list)
