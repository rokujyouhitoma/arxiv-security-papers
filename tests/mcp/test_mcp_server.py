import os
import sys

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
    )

from mcp.papers_server import (
    PROMPTS_MANIFEST,
    RESOURCES_MANIFEST,
    TOOLS_MANIFEST,
    dispatch_tool,
    handle_get_prompt,
    handle_read_resource,
    set_vector_engine,
)
from search.vector_engine import VectorEngine


def setup_module():
    engine = VectorEngine(lazy=True)
    engine.knowledge_graph.add_entity(
        "マルウェア・脅威解析", "domain", "malware", "test_id_1"
    )
    set_vector_engine(engine)


def test_vector_engine_indexing_and_search():
    engine = VectorEngine(lazy=True)
    assert isinstance(engine.documents, list)
    assert len(engine.documents) == 0

    results = engine.search("security", top_k=3)
    assert isinstance(results, list)
    assert len(results) == 0


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


def test_threat_defense_caldera_and_sigma():
    from mcp.threat_defense_server import TOOL_HANDLERS

    assert "generate_caldera_playbook" in TOOL_HANDLERS
    assert "generate_sigma_rule" in TOOL_HANDLERS

    # Test Caldera playbook generation
    res_caldera = TOOL_HANDLERS["generate_caldera_playbook"]({"tech_id": "T1059"})
    assert res_caldera["status"] == "success"
    assert "caldera_ability_yaml" in res_caldera
    assert "T1059" in res_caldera["caldera_ability_yaml"]

    # Test Sigma rule generation
    res_sigma = TOOL_HANDLERS["generate_sigma_rule"]({"tech_id": "T1190"})
    assert res_sigma["status"] == "success"
    assert "sigma_rule_yaml" in res_sigma
    assert "T1190" in res_sigma["sigma_rule_yaml"]


def test_mcp_dispatch_tool_with_search_client_ipc():
    """Verifies that MCP tools operate seamlessly over SearchClient IPC without VectorEngine."""
    from unittest.mock import MagicMock

    from mcp.papers_server import set_search_client, set_vector_engine

    # Clear direct vector engine
    set_vector_engine(None)

    mock_client = MagicMock()
    mock_client.search.return_value = {
        "status": "success",
        "results": [
            {
                "id": "2502.99999",
                "title": "IPC Test Paper",
                "score": 0.95,
                "category": "cs.CR",
                "tags": ["ipc", "test"],
                "description": "Abstract of IPC test paper",
            }
        ],
    }
    mock_client.get_related.return_value = {
        "status": "success",
        "paper_id": "2502.99999",
        "related_papers": [{"id": "2502.88888", "score": 0.88}],
        "mermaid_graph": "graph TD; root[2502.99999] --> node_2502.88888",
    }
    set_search_client(mock_client)

    res = dispatch_tool("search_security_papers", {"query": "ipc test", "top_k": 1})
    assert res["status"] == "success"
    assert len(res["results"]) == 1
    assert res["results"][0]["id"] == "2502.99999"
    assert mock_client.search.called

    res_rel = dispatch_tool("get_related_papers_graph", {"arxiv_id": "2502.99999"})
    assert res_rel["status"] == "success"
    assert res_rel["paper_id"] == "2502.99999"
    assert mock_client.get_related.called
