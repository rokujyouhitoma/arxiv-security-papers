"""
Unit tests for VectorEngine and MCP Server
"""
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

from vector_engine import VectorEngine
from mcp_server import dispatch_tool, TOOLS_MANIFEST


def test_vector_engine_indexing_and_search():
    engine = VectorEngine()
    count = engine.build_index()
    assert count >= 0

    results = engine.search("security", top_k=3)
    assert isinstance(results, list)


def test_mcp_tools_manifest():
    assert isinstance(TOOLS_MANIFEST, list)
    tool_names = [t["name"] for t in TOOLS_MANIFEST]
    assert "search_security_papers" in tool_names
    assert "get_paper_summary" in tool_names
    assert "get_latest_trends" in tool_names
    assert "query_attack_technique" in tool_names


def test_mcp_dispatch_tool():
    res = dispatch_tool("search_security_papers", {"query": "malware", "top_k": 2})
    assert res["status"] == "success"
    assert "results" in res

    unknown = dispatch_tool("nonexistent_tool", {})
    assert unknown["status"] == "error"
