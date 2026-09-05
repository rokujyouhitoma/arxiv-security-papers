#!/usr/bin/env python3
"""
Unit and integration tests for CTIBackfillEnricher pipeline (Issue 153 & Issue 165).
Verifies EIROM inference integration, confidence tier and rule metadata in frontmatter,
hash-based idempotency, force override, PropertyGraphEngine synchronization, and audit reporting.
"""

import json
import os
import tempfile
from typing import Any, Dict

from pipeline.cti_backfill import CTIBackfillEnricher

SAMPLE_OKF_CONTENT = """---
type: "security-paper"
title: "Adversarial Code Injection and Remote Command Execution Attacks"
description: "Analysis of command injection techniques in enterprise software."
resource: "https://arxiv.org/abs/2401.99999"
tags:
  - "cybersecurity"
  - "cs.CR"
timestamp: "2026-09-01T00:00:00Z"
provenance:
  source: "arxiv.org"
---

# Adversarial Code Injection and Remote Command Execution Attacks

## Overview
This paper investigates command execution, powershell abuse, and code injection vulnerabilities.
Techniques matching T1059 and T1190 are demonstrated against vulnerable web endpoints.
"""


def test_parse_frontmatter_valid() -> None:
    """Tests frontmatter separation for valid OKF content."""
    fm, body = CTIBackfillEnricher._parse_frontmatter(SAMPLE_OKF_CONTENT)
    assert fm is not None
    assert 'type: "security-paper"' in fm
    assert "# Adversarial Code Injection" in body


def test_parse_frontmatter_invalid() -> None:
    """Tests frontmatter handling for non-frontmatter text."""
    fm, body = CTIBackfillEnricher._parse_frontmatter("Just a regular markdown file.")
    assert fm is None
    assert body == "Just a regular markdown file."


def test_determine_enrichments() -> None:
    """Tests technique extraction and mitigation mapping."""
    enricher = CTIBackfillEnricher()
    techs, mits = enricher._determine_enrichments(SAMPLE_OKF_CONTENT)

    assert len(techs) >= 1
    tech_ids = [t["technique_id"] for t in techs]
    assert "T1059" in tech_ids or "T1190" in tech_ids

    assert isinstance(mits, list)
    if mits:
        assert all(m["mitigation_id"].startswith("M") for m in mits)


def test_enrich_file_and_idempotency() -> None:
    """Tests full enrichment with EIROM properties and verifies hash-based idempotency."""
    with tempfile.TemporaryDirectory() as tmpdir:
        test_file = os.path.join(tmpdir, "paper-test.md")
        with open(test_file, "w", encoding="utf-8") as f:
            f.write(SAMPLE_OKF_CONTENT)

        enricher = CTIBackfillEnricher(workspace_dir=tmpdir, sync_graph=False)

        # 1. First enrichment (should update file)
        res1 = enricher.enrich_file(test_file, dry_run=False)
        assert res1["updated"] is True
        assert res1["technique_count"] >= 1
        assert "source_text_hash" in res1

        # Check modified file content
        with open(test_file, "r", encoding="utf-8") as f:
            updated_content = f.read()

        assert "inferred_techniques:" in updated_content
        assert "confidence_tier:" in updated_content
        assert "primary_rule_id:" in updated_content
        assert "source_text_hash:" in updated_content
        assert "cti_techniques:" in updated_content

        # 2. Second enrichment (should be idempotent: skipped by hash match)
        res2 = enricher.enrich_file(test_file, dry_run=False)
        assert res2["updated"] is False
        assert res2.get("skipped") is True
        assert "hash match" in str(res2.get("reason"))


def test_enrich_file_force_override() -> None:
    """Tests that force=True overrides hash match and re-processes the paper."""
    with tempfile.TemporaryDirectory() as tmpdir:
        test_file = os.path.join(tmpdir, "paper-force.md")
        with open(test_file, "w", encoding="utf-8") as f:
            f.write(SAMPLE_OKF_CONTENT)

        enricher = CTIBackfillEnricher(workspace_dir=tmpdir, sync_graph=False)

        res1 = enricher.enrich_file(test_file, dry_run=False)
        assert res1["updated"] is True

        # Force re-enrichment
        res2 = enricher.enrich_file(test_file, dry_run=False, force=True)
        assert res2["updated"] is True
        assert res2.get("skipped") is not True


def test_dry_run_mode() -> None:
    """Tests that dry_run mode reports updates without modifying files."""
    with tempfile.TemporaryDirectory() as tmpdir:
        test_file = os.path.join(tmpdir, "paper-dryrun.md")
        with open(test_file, "w", encoding="utf-8") as f:
            f.write(SAMPLE_OKF_CONTENT)

        enricher = CTIBackfillEnricher(workspace_dir=tmpdir, sync_graph=False)
        res = enricher.enrich_file(test_file, dry_run=True)
        assert res["updated"] is True

        # File content must remain original
        with open(test_file, "r", encoding="utf-8") as f:
            after_content = f.read()
        assert after_content == SAMPLE_OKF_CONTENT


def test_property_graph_sync() -> None:
    """Tests synchronization of paper and technique edges into PropertyGraphEngine."""
    with tempfile.TemporaryDirectory() as tmpdir:
        test_file = os.path.join(tmpdir, "paper-graph.md")
        with open(test_file, "w", encoding="utf-8") as f:
            f.write(SAMPLE_OKF_CONTENT)

        db_path = os.path.join(tmpdir, "test_graph.db")
        enricher = CTIBackfillEnricher(
            workspace_dir=tmpdir,
            graph_db_path=db_path,
            sync_graph=True,
        )

        res = enricher.enrich_file(test_file, dry_run=False)
        assert res["updated"] is True
        assert res.get("edges_synced", 0) >= 1

        # Check PropertyGraphEngine vertices and edges
        engine = enricher.graph_engine
        paper_vertices = [v for v in engine.get_all_vertices() if v.label == "Paper"]
        assert len(paper_vertices) >= 1

        tech_vertices = [
            v for v in engine.get_all_vertices() if v.label == "AttackTechnique"
        ]
        assert len(tech_vertices) >= 1

        # Check edge properties
        edges = engine.get_out_edges(paper_vertices[0].id)
        assert len(edges) >= 1
        edge = edges[0]
        assert "confidence" in edge.properties
        assert "confidence_tier" in edge.properties
        assert "primary_rule_id" in edge.properties
        assert "evidence_quote" in edge.properties


def test_run_backfill_batch_and_report() -> None:
    """Tests batch execution of run_backfill across discovered OKF files with JSON report."""
    with tempfile.TemporaryDirectory() as tmpdir:
        papers_dir = os.path.join(tmpdir, "outputs", "okf_papers", "2026-09-01")
        os.makedirs(papers_dir, exist_ok=True)

        file1 = os.path.join(papers_dir, "2401.00001.md")
        file2 = os.path.join(papers_dir, "2401.00002.md")
        with open(file1, "w", encoding="utf-8") as f:
            f.write(SAMPLE_OKF_CONTENT)
        with open(file2, "w", encoding="utf-8") as f:
            f.write(SAMPLE_OKF_CONTENT)

        report_file = os.path.join(tmpdir, "audit_report.json")
        enricher = CTIBackfillEnricher(workspace_dir=tmpdir, sync_graph=False)

        stats = enricher.run_backfill(
            dry_run=False,
            max_papers=10,
            report_file=report_file,
        )

        assert stats["total_scanned"] == 2
        assert stats["updated_count"] == 2
        assert stats["skipped_count"] == 0
        assert stats["error_count"] == 0
        assert "tier_breakdown" in stats
        assert isinstance(stats["top_techniques"], list)

        # Check written report file
        assert os.path.exists(report_file)
        with open(report_file, "r", encoding="utf-8") as f:
            saved_report: Dict[str, Any] = json.load(f)
        assert saved_report["total_scanned"] == 2
        assert saved_report["updated_count"] == 2

        # Second batch run should skip unchanged files
        stats2 = enricher.run_backfill(dry_run=False)
        assert stats2["updated_count"] == 0
        assert stats2["skipped_count"] == 2
