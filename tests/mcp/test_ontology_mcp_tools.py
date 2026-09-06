#!/usr/bin/env python3
"""
Unit and Integration Tests for Ontology Causal Chain and Evidence MCP Tools (Issue 200).
Verifies CausalChainFinder, EvidenceInspector, and MCP tool handlers across servers.
"""

from __future__ import annotations

import unittest

from graph.engine import PropertyGraphEngine
from mcp.papers_server import TOOLS_MANIFEST as PAPERS_MANIFEST
from mcp.papers_server import dispatch_tool, handle_query_ontology_evidence
from mcp.threat_defense_server import TOOL_HANDLERS as DEFENSE_HANDLERS
from mcp.threat_defense_server import TOOLS_MANIFEST as DEFENSE_MANIFEST
from mcp.threat_defense_server import handle_search_defense_causal_chains
from mcp.tools.ontology_tools import (
    CausalChainFinder,
    EvidenceInspector,
    _sanitize_identifier,
)


class TestOntologyMCPTools(unittest.TestCase):
    """Test suite for ontology causal search and evidence inspection tools."""

    def setUp(self) -> None:
        # Create an isolated in-memory property graph engine
        self.engine = PropertyGraphEngine(memory_only=True)

        # Populate with a representative causal defense chain
        # AttackTechnique -> REQUIRES_PRECONDITION -> Precondition
        # DefenseMechanism -> NEUTRALIZES_PRECONDITION -> Precondition
        # DefenseMechanism -> MITIGATES -> AttackTechnique
        # AttackTechnique -> HAS_IMPACT -> Impact
        self.engine.add_vertex(
            "AttackTechnique:T1059",
            label="AttackTechnique",
            properties={
                "name": "Command and Scripting Interpreter",
                "technique_id": "T1059",
            },
        )
        self.engine.add_vertex(
            "Precondition:ShellExecution",
            label="Precondition",
            properties={"name": "Unrestricted Shell Execution"},
        )
        self.engine.add_vertex(
            "DefenseMechanism:AppArmor",
            label="DefenseMechanism",
            properties={"name": "AppArmor Profile Enforcement"},
        )
        self.engine.add_vertex(
            "Impact:ArbitraryCodeExecution",
            label="Impact",
            properties={"severity": "Critical", "cvss": 9.8},
        )
        self.engine.add_edge(
            "AttackTechnique:T1059",
            "Precondition:ShellExecution",
            label="REQUIRES_PRECONDITION",
            weight=1.0,
            properties={"confidence": 0.95, "inference_rule_id": "EIROM-PRE-01"},
        )
        self.engine.add_edge(
            "DefenseMechanism:AppArmor",
            "Precondition:ShellExecution",
            label="NEUTRALIZES_PRECONDITION",
            weight=1.0,
            properties={"confidence": 0.90, "inference_rule_id": "EIROM-NEUT-01"},
        )
        self.engine.add_edge(
            "DefenseMechanism:AppArmor",
            "AttackTechnique:T1059",
            label="MITIGATES",
            weight=1.0,
            properties={"confidence": 0.88, "inference_rule_id": "EIROM-MIT-01"},
        )
        self.engine.add_edge(
            "AttackTechnique:T1059",
            "Impact:ArbitraryCodeExecution",
            label="HAS_IMPACT",
            weight=1.0,
            properties={"confidence": 0.99, "inference_rule_id": "EIROM-IMP-01"},
        )

        # Populate with Paper -> Claim -> Evidence & PoC
        self.engine.add_vertex(
            "Paper:2403.99999",
            label="Paper",
            properties={"title": "Hardening Systems Against Scripting Attacks"},
        )
        self.engine.add_vertex(
            "Claim:C01",
            label="Claim",
            properties={
                "description": "Achieves 99.2% reduction in command injection risk"
            },
        )
        self.engine.add_vertex(
            "EvaluationResult:ER01",
            label="EvaluationResult",
            properties={"metric": "Accuracy", "value": 99.2},
        )
        self.engine.add_vertex(
            "PoCArtifact:PoC01",
            label="PoCArtifact",
            properties={"repository": "https://github.com/example/script-guard-poc"},
        )
        self.engine.add_edge(
            "Paper:2403.99999",
            "Claim:C01",
            label="ASSERTS_CLAIM",
            properties={"confidence": 0.95},
        )
        self.engine.add_edge(
            "Paper:2403.99999",
            "EvaluationResult:ER01",
            label="YIELDS_EVALUATION",
            properties={"confidence": 0.92, "evidence_snippet": "Table 3 benchmark"},
        )
        self.engine.add_edge(
            "Paper:2403.99999",
            "PoCArtifact:PoC01",
            label="HAS_POC",
            properties={"confidence": 1.0},
        )

        self.finder = CausalChainFinder(graph_engine=self.engine)
        self.inspector = EvidenceInspector(graph_engine=self.engine)

    def test_sanitize_identifier(self) -> None:
        """Verifies identifier sanitizer removes invalid symbols."""
        self.assertEqual(_sanitize_identifier("  T1059  "), "T1059")
        self.assertEqual(_sanitize_identifier("Paper:2403.12345"), "Paper:2403.12345")
        self.assertEqual(
            _sanitize_identifier("T1059'; DROP TABLE--"), "T1059DROPTABLE--"
        )
        self.assertEqual(_sanitize_identifier(""), "")
        self.assertEqual(_sanitize_identifier(None), "")

    def test_causal_chain_finder_success(self) -> None:
        """Verifies traversal discovers preconditions, neutralizing defenses, and direct mitigations."""
        res = self.finder.find_defense_chains("T1059", max_depth=3, min_confidence=0.5)
        self.assertEqual(res.get("status"), "success")
        self.assertEqual(res.get("threat_id"), "AttackTechnique:T1059")
        self.assertEqual(len(res.get("impacts", [])), 1)
        self.assertEqual(len(res.get("preconditions", [])), 1)
        pre = res["preconditions"][0]
        self.assertEqual(pre["name"], "Unrestricted Shell Execution")
        self.assertEqual(len(pre["neutralized_by"]), 1)
        self.assertEqual(
            pre["neutralized_by"][0]["name"], "AppArmor Profile Enforcement"
        )
        self.assertEqual(len(res.get("direct_mitigations", [])), 1)

    def test_causal_chain_finder_not_found(self) -> None:
        """Verifies non-existent threat IDs return not_found status safely."""
        res = self.finder.find_defense_chains("T9999_NON_EXISTENT")
        self.assertEqual(res.get("status"), "not_found")
        self.assertEqual(res.get("chains"), [])

    def test_causal_chain_finder_empty(self) -> None:
        """Verifies empty input returns error status."""
        res = self.finder.find_defense_chains("")
        self.assertEqual(res.get("status"), "error")

    def test_evidence_inspector_success(self) -> None:
        """Verifies evidence inspector aggregates claims, evaluation results, and PoC artifacts."""
        res = self.inspector.get_evidence_for_entity("2403.99999", include_pocs=True)
        self.assertEqual(res.get("status"), "success")
        self.assertEqual(len(res.get("claims", [])), 1)
        self.assertEqual(len(res.get("evaluations", [])), 1)
        self.assertEqual(len(res.get("pocs", [])), 1)
        self.assertEqual(res.get("evidence_count"), 3)

    def test_evidence_inspector_exclude_pocs(self) -> None:
        """Verifies PoCs can be excluded when include_pocs=False."""
        res = self.inspector.get_evidence_for_entity("2403.99999", include_pocs=False)
        self.assertEqual(res.get("status"), "success")
        self.assertEqual(len(res.get("pocs", [])), 0)

    def test_threat_defense_server_manifest_and_handler(self) -> None:
        """Verifies search_defense_causal_chains is in manifest and handles requests."""
        names = [t["name"] for t in DEFENSE_MANIFEST]
        self.assertIn("search_defense_causal_chains", names)
        self.assertIn("search_defense_causal_chains", DEFENSE_HANDLERS)

        # Handler call test with empty input
        res_err = handle_search_defense_causal_chains({})
        self.assertEqual(res_err.get("status"), "error")

        # Handler call test with valid input (using real storage or graceful not_found)
        res_call = handle_search_defense_causal_chains({"threat_id": "T1059"})
        self.assertIn(res_call.get("status"), ("success", "not_found"))

    def test_papers_server_manifest_and_handler(self) -> None:
        """Verifies query_ontology_evidence is in papers manifest and dispatch works."""
        names = [t["name"] for t in PAPERS_MANIFEST]
        self.assertIn("query_ontology_evidence", names)

        # Handler call test with empty input
        res_err = handle_query_ontology_evidence({})
        self.assertEqual(res_err.get("status"), "error")

        # Dispatch call test
        res_disp = dispatch_tool("query_ontology_evidence", {"entity_id": "2403.12345"})
        self.assertIn(res_disp.get("status"), ("success", "not_found"))


if __name__ == "__main__":
    unittest.main()
