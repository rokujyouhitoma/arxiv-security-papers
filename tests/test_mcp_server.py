"""
Unit tests for VectorEngine and MCP Server
"""

import os
import sys

from mcp_server import TOOLS_MANIFEST, dispatch_tool
from vector_engine import VectorEngine

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
    )


def test_vector_engine_indexing_and_search():
    engine = VectorEngine()
    assert isinstance(engine.documents, list)

    results = engine.search("security", top_k=3)
    assert isinstance(results, list)


def test_mcp_tools_manifest():
    assert isinstance(TOOLS_MANIFEST, list)
    tool_names = [t["name"] for t in TOOLS_MANIFEST]
    assert "search_security_papers" in tool_names
    assert "search_papers_hybrid" in tool_names
    assert "query_knowledge_graph" in tool_names
    assert "get_paper_summary" in tool_names
    assert "get_latest_trends" in tool_names
    assert "query_attack_technique" in tool_names


def test_mcp_dispatch_tool():
    res = dispatch_tool("search_security_papers", {"query": "malware", "top_k": 2})
    assert res["status"] == "success"
    assert "results" in res

    res_hybrid = dispatch_tool(
        "search_papers_hybrid", {"query": "jailbreak", "top_k": 2}
    )
    assert res_hybrid["status"] == "success"
    assert "data" in res_hybrid

    res_kg = dispatch_tool(
        "query_knowledge_graph", {"entity": "マルウェア・脅威解析", "max_depth": 1}
    )
    assert res_kg["status"] == "success"
    assert "graph" in res_kg

    unknown = dispatch_tool("nonexistent_tool", {})
    assert unknown["status"] == "error"
