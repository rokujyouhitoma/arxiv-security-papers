"""Unit tests for polymorphic OKF Item Pipeline (Issue 208)."""

from __future__ import annotations

import asyncio
import os
import shutil
import tempfile
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

from spider.core.engine import ScrapedItem
from spider.pipeline.okf_pipeline import (
    OkfItemPipeline,
    _extract_date_folder,
    _format_cvss_meta,
    _sanitize_path_id,
    _sanitize_string,
    _score_to_severity,
)


@pytest.fixture
def temp_output_dir() -> Any:
    """Fixture providing an isolated temporary directory for OKF pipeline tests."""
    temp_dir = tempfile.mkdtemp()
    yield temp_dir
    shutil.rmtree(temp_dir, ignore_errors=True)


def test_sanitize_string() -> None:
    """Tests string sanitization for YAML frontmatter compatibility."""
    assert _sanitize_string(None) == ""
    assert _sanitize_string('Hello "World"') == r"Hello \"World\""
    assert _sanitize_string("Line 1\nLine 2\r\nLine 3") == "Line 1 Line 2 Line 3"
    assert _sanitize_string("Control\x00Char\x07Test") == "ControlCharTest"


def test_sanitize_path_id() -> None:
    """Tests Path Traversal (CWE-22) prevention in clean_id."""
    assert _sanitize_path_id("CVE-2026-1234") == "CVE-2026-1234"
    assert _sanitize_path_id("2608.12345") == "2608.12345"
    # Path traversal attempts
    assert ".." not in _sanitize_path_id("../../etc/passwd")
    assert "/" not in _sanitize_path_id("../../etc/passwd")
    assert "\\" not in _sanitize_path_id("..\\..\\windows\\system32")
    assert _sanitize_path_id("../../../passwd") == "passwd"
    assert _sanitize_path_id("") == "UNKNOWN_ID"
    assert _sanitize_path_id("....") == "UNKNOWN_ID"


def test_extract_date_folder() -> None:
    """Tests safe date extraction with fallback to UTC today."""
    assert _extract_date_folder("2026-09-07T12:00:00Z") == "2026-09-07"
    assert _extract_date_folder("2026-09-07") == "2026-09-07"
    today_folder = _extract_date_folder("invalid-date")
    assert len(today_folder) == 10
    assert today_folder[4] == "-" and today_folder[7] == "-"


def test_score_to_severity() -> None:
    """Tests mapping of numeric scores to qualitative severity."""
    assert _score_to_severity(None) == "UNKNOWN"
    assert _score_to_severity(9.8) == "CRITICAL"
    assert _score_to_severity(9.0) == "CRITICAL"
    assert _score_to_severity(7.5) == "HIGH"
    assert _score_to_severity(5.0) == "MEDIUM"
    assert _score_to_severity(2.1) == "LOW"
    assert _score_to_severity(0.0) == "NONE"


def test_format_cvss_meta() -> None:
    """Tests parsing diverse formats of CVSS input."""
    # Dict format
    score, sev, vec = _format_cvss_meta(
        {
            "base_score": 9.8,
            "severity": "CRITICAL",
            "vector_string": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H",
        }
    )
    assert score == 9.8
    assert sev == "CRITICAL"
    assert "CVSS:3.1" in vec

    # Float format
    score, sev, vec = _format_cvss_meta(7.2)
    assert score == 7.2
    assert sev == "HIGH"
    assert vec == ""

    # String float format
    score, sev, vec = _format_cvss_meta("4.5")
    assert score == 4.5
    assert sev == "MEDIUM"

    # None format
    score, sev, vec = _format_cvss_meta(None)
    assert score is None
    assert sev == "UNKNOWN"


def test_paper_okf_pipeline_generation(temp_output_dir: str) -> None:
    """Tests backward-compatible academic paper OKF generation."""

    async def _run() -> None:
        pipeline = OkfItemPipeline(output_dir=temp_output_dir)
        item = ScrapedItem(
            item_id="arxiv_2608.9999",
            source_url="https://arxiv.org/abs/2608.9999",
            title="Zero-Knowledge Privacy in Distributed Systems",
            payload={
                "type": "security-paper",
                "clean_id": "2608.9999",
                "source": "arxiv",
                "abstract": "A novel ZK protocol with linear verification complexity.",
                "authors": ["Alice Cryptographer", "Bob Verifier"],
                "published_date": "2026-09-07",
                "pdf_url": "https://arxiv.org/pdf/2608.9999.pdf",
                "tags": ["zero-knowledge", "privacy"],
            },
        )
        processed = await pipeline.process_item(item, spider=None)
        okf_path = processed.payload["okf_path"]
        assert os.path.exists(okf_path)
        assert "2026-09-07" in okf_path

        with open(okf_path, "r", encoding="utf-8") as f:
            content = f.read()

        assert 'type: "security-paper"' in content
        assert 'title: "Zero-Knowledge Privacy in Distributed Systems"' in content
        assert "Alice Cryptographer" in content
        assert "Bob Verifier" in content
        assert "outputs/raw_data/2026-09-07/2608.9999_meta.json" in content
        assert "## 概要 (Abstract)" in content
        assert "A novel ZK protocol" in content

    asyncio.run(_run())


def test_vulnerability_okf_pipeline_generation(temp_output_dir: str) -> None:
    """Tests CTI vulnerability OKF v0.2 generation with threat metrics and mitigations."""

    async def _run() -> None:
        pipeline = OkfItemPipeline(output_dir=temp_output_dir)
        item = ScrapedItem(
            item_id="cve_2026_1234",
            source_url="https://nvd.nist.gov/vuln/detail/CVE-2026-1234",
            title="[CVE-2026-1234] ExampleCorp Server RCE Vulnerability",
            payload={
                "type": "vulnerability",
                "clean_id": "CVE-2026-1234",
                "cve_id": "CVE-2026-1234",
                "source": "cisa-kev",
                "description": "Unauthenticated remote code execution via unsafe deserialization.",
                "published_date": "2026-09-07",
                "cvss": {
                    "base_score": 9.8,
                    "severity": "CRITICAL",
                    "vector_string": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H",
                },
                "cwe": ["CWE-78", "CWE-94"],
                "epss_score": 0.952,
                "kev_status": True,
                "due_date": "2026-09-28",
                "affected_vendors": ["ExampleCorp"],
                "affected_products": ["ExampleServer < 4.2.1"],
                "remediation": "Apply vendor security update v4.2.1 immediately.",
                "references": [
                    "https://nvd.nist.gov/vuln/detail/CVE-2026-1234",
                    "https://www.cisa.gov/known-exploited-vulnerabilities-catalog",
                ],
                "tags": ["vulnerability", "cve", "cisa-kev", "rce"],
            },
        )
        processed = await pipeline.process_item(item, spider=None)
        okf_path = processed.payload["okf_path"]
        assert os.path.exists(okf_path)

        with open(okf_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Check YAML Frontmatter
        assert 'type: "vulnerability"' in content
        assert 'cve_id: "CVE-2026-1234"' in content
        assert "base_score: 9.8" in content
        assert 'severity: "CRITICAL"' in content
        assert "epss_score: 0.952" in content
        assert "kev_status: true" in content
        assert 'due_date: "2026-09-28"' in content
        assert '"CWE-78", "CWE-94"' in content
        assert '"ExampleServer < 4.2.1"' in content

        # Check Markdown Body sections
        assert "# [CVE-2026-1234] ExampleCorp Server RCE Vulnerability" in content
        assert "## 1. 脆弱性概要 (Overview)" in content
        assert "Unauthenticated remote code execution" in content
        assert "## 2. 脅威評価メトリクス (Threat Metrics)" in content
        assert "**9.8 (CRITICAL)**" in content
        assert "**悪用確認済み (Active in the Wild)**" in content
        assert "95.2%" in content
        assert "2026-09-28" in content
        assert "## 3. 影響を受けるベンダー・製品 (Affected Products)" in content
        assert "`ExampleServer < 4.2.1`" in content
        assert "## 4. 対策・緩和策 (Required Actions & Mitigations)" in content
        assert "Apply vendor security update v4.2.1 immediately." in content
        assert "## 5. 参考情報・一次ソースリンク (References)" in content

    asyncio.run(_run())


def test_security_advisory_okf_pipeline_generation(temp_output_dir: str) -> None:
    """Tests security-advisory OKF generation."""

    async def _run() -> None:
        pipeline = OkfItemPipeline(output_dir=temp_output_dir)
        item = ScrapedItem(
            item_id="adv_mitre_8888",
            source_url="https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2026-8888",
            title="Advisory for OpenSSL Buffer Overflow",
            payload={
                "type": "security-advisory",
                "clean_id": "CVE-2026-8888",
                "cve_id": "CVE-2026-8888",
                "published_date": "2026-09-07",
                "description": "Buffer overflow in TLS parsing logic.",
                "cvss": 7.5,
                "cwe": "CWE-120",
                "tags": ["advisory", "openssl"],
            },
        )
        processed = await pipeline.process_item(item, spider=None)
        okf_path = processed.payload["okf_path"]
        assert os.path.exists(okf_path)

        with open(okf_path, "r", encoding="utf-8") as f:
            content = f.read()

        assert 'type: "security-advisory"' in content
        assert 'severity: "HIGH"' in content
        assert "base_score: 7.5" in content
        assert "CWE-120" in content

    asyncio.run(_run())


def test_path_traversal_prevention_in_pipeline(temp_output_dir: str) -> None:
    """Tests that path traversal clean_id cannot escape output directory."""

    async def _run() -> None:
        pipeline = OkfItemPipeline(output_dir=temp_output_dir)
        item = ScrapedItem(
            item_id="evil_item",
            source_url="https://example.com/exploit",
            title="Directory Traversal Exploit Test",
            payload={
                "type": "vulnerability",
                "clean_id": "../../etc/passwd",
                "published_date": "2026-09-07",
            },
        )
        processed = await pipeline.process_item(item, spider=None)
        okf_path = processed.payload["okf_path"]
        # Must be located inside temp_output_dir
        rel = os.path.relpath(okf_path, temp_output_dir)
        assert not rel.startswith("..")
        assert os.path.exists(okf_path)
        assert "passwd.md" in okf_path

    asyncio.run(_run())


def test_db_persistence_dispatch(temp_output_dir: str) -> None:
    """Tests persistence to DSN-14 papers vs vulnerabilities tables."""

    async def _run() -> None:
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_conn.cursor.return_value = mock_cursor

        with patch("database.driver.connect", return_value=mock_conn):
            pipeline = OkfItemPipeline(
                output_dir=temp_output_dir, enable_db_persistence=True
            )

            # 1. Paper item -> papers table
            paper_item = ScrapedItem(
                item_id="paper_1",
                source_url="https://arxiv.org/abs/2608.0001",
                title="Paper Title",
                payload={"type": "security-paper", "clean_id": "2608.0001"},
            )
            await pipeline.process_item(paper_item, spider=None)
            paper_calls = [
                call
                for call in mock_cursor.execute.call_args_list
                if "INSERT OR REPLACE INTO papers" in call[0][0]
            ]
            assert len(paper_calls) == 1

            # 2. Vulnerability item -> vulnerabilities table
            vuln_item = ScrapedItem(
                item_id="vuln_1",
                source_url="https://nvd.nist.gov/vuln/detail/CVE-2026-5555",
                title="Vuln Title",
                payload={
                    "type": "vulnerability",
                    "clean_id": "CVE-2026-5555",
                    "cve_id": "CVE-2026-5555",
                    "cvss": {"base_score": 8.1, "severity": "HIGH"},
                },
            )
            await pipeline.process_item(vuln_item, spider=None)
            vuln_calls = [
                call
                for call in mock_cursor.execute.call_args_list
                if "INSERT OR REPLACE INTO vulnerabilities" in call[0][0]
            ]
            assert len(vuln_calls) == 1
            # Check values passed: cve_id, title, severity, base_score, source_url, okf_path
            args = vuln_calls[0][0][1]
            assert args[0] == "CVE-2026-5555"
            assert args[1] == "Vuln Title"
            assert args[2] == "HIGH"
            assert args[3] == 8.1

    asyncio.run(_run())
