"""
Unit tests for VectorEngine and MCP Server
"""

import os
import sys

from mcp_server import (
    PROMPTS_MANIFEST,
    RESOURCES_MANIFEST,
    TOOLS_MANIFEST,
    dispatch_tool,
    handle_get_prompt,
    handle_read_resource,
)
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


def test_mcp_manifests():
    assert isinstance(TOOLS_MANIFEST, list)
    tool_names = [t["name"] for t in TOOLS_MANIFEST]
    assert "search_security_papers" in tool_names
    assert "search_papers_hybrid" in tool_names
    assert "query_knowledge_graph" in tool_names
    assert "get_paper_summary" in tool_names
    assert "get_latest_trends" in tool_names
    assert "query_attack_technique" in tool_names
    assert "get_related_papers_graph" in tool_names
    assert "verify_code_security" in tool_names
    assert "get_cwe_mitigation_recipe" in tool_names

    assert isinstance(RESOURCES_MANIFEST, list)
    res_uris = [r["uri"] for r in RESOURCES_MANIFEST]
    assert "arxiv://paper/{arxiv_id}" in res_uris
    assert "arxiv://trends/latest" in res_uris
    assert "arxiv://cwe-taxonomy" in res_uris

    assert isinstance(PROMPTS_MANIFEST, list)
    prompt_names = [p["name"] for p in PROMPTS_MANIFEST]
    assert "audit_code_with_papers" in prompt_names
    assert "generate_exploit_poc_tests" in prompt_names
    assert "recommend_cwe_mitigation" in prompt_names


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

    res_rel = dispatch_tool(
        "get_related_papers_graph", {"arxiv_id": "nonexistent_id_9999"}
    )
    assert res_rel["status"] == "error"

    # verify_code_security
    code = (
        "def query_db(uid):\n    cursor.execute(f'SELECT * FROM users WHERE id={uid}')"
    )
    res_sec = dispatch_tool("verify_code_security", {"code_snippet": code})
    assert res_sec["status"] == "success"
    assert res_sec["risk_level"] == "HIGH"
    assert any(w["cwe_id"] == "CWE-89" for w in res_sec["warnings"])

    # get_cwe_mitigation_recipe
    res_cwe = dispatch_tool("get_cwe_mitigation_recipe", {"cwe_id": "CWE-89"})
    assert res_cwe["status"] == "success"
    assert res_cwe["cwe_id"] == "CWE-89"
    assert len(res_cwe["secure_coding_patterns"]) > 0

    unknown = dispatch_tool("nonexistent_tool", {})
    assert unknown["status"] == "error"


def test_mcp_resources_and_prompts():
    # Resource read
    res_tax = handle_read_resource("arxiv://cwe-taxonomy")
    assert res_tax["mimeType"] == "application/json"
    assert "CWE-89" in res_tax["text"]

    # Prompts get
    p_audit = handle_get_prompt(
        "audit_code_with_papers", {"code": "print('hello')", "language": "python"}
    )
    assert "messages" in p_audit
    assert len(p_audit["messages"]) > 0

    p_cwe = handle_get_prompt(
        "recommend_cwe_mitigation", {"cwe_id": "CWE-78", "language": "python"}
    )
    assert "messages" in p_cwe
