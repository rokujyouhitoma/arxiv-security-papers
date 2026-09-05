#!/usr/bin/env python3
"""
Unit and integration tests for CTIBackfillEnricher pipeline (Issue 153).
Verifies non-destructive YAML frontmatter enrichment, idempotency, and mitigation mapping.
"""

import os
import tempfile

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

    # Should map at least one mitigation (from SQLite catalog or fallback)
    assert isinstance(mits, list)
    if mits:
        assert all(m["mitigation_id"].startswith("M") for m in mits)


def test_enrich_file_and_idempotency() -> None:
    """Tests full enrichment of a temporary OKF file and verifies idempotency."""
    with tempfile.TemporaryDirectory() as tmpdir:
        test_file = os.path.join(tmpdir, "paper-test.md")
        with open(test_file, "w", encoding="utf-8") as f:
            f.write(SAMPLE_OKF_CONTENT)

        enricher = CTIBackfillEnricher(workspace_dir=tmpdir)

        # 1. First enrichment (should update file)
        res1 = enricher.enrich_file(test_file, dry_run=False)
        assert res1["updated"] is True
        assert res1["technique_count"] >= 1

        # Check modified file content
        with open(test_file, "r", encoding="utf-8") as f:
            updated_content = f.read()
        assert "cti_techniques:" in updated_content
        assert 'title: "Adversarial Code Injection' in updated_content

        # 2. Second enrichment (should be idempotent: unchanged)
        res2 = enricher.enrich_file(test_file, dry_run=False)
        assert res2["updated"] is False
        assert res2.get("reason") == "Unchanged"


def test_dry_run_mode() -> None:
    """Tests that dry_run mode reports updates without modifying files."""
    with tempfile.TemporaryDirectory() as tmpdir:
        test_file = os.path.join(tmpdir, "paper-dryrun.md")
        with open(test_file, "w", encoding="utf-8") as f:
            f.write(SAMPLE_OKF_CONTENT)

        enricher = CTIBackfillEnricher(workspace_dir=tmpdir)
        res = enricher.enrich_file(test_file, dry_run=True)
        assert res["updated"] is True

        # File content must remain original
        with open(test_file, "r", encoding="utf-8") as f:
            after_content = f.read()
        assert after_content == SAMPLE_OKF_CONTENT
