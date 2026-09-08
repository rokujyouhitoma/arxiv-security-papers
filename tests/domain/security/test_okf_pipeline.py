"""Unit tests for Security OKF Item Pipeline in domain.security.pipeline (Issue 210)."""

from __future__ import annotations

import asyncio
import os
import shutil
import tempfile
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

from domain.security.pipeline.okf_pipeline import (
    OkfItemPipeline,
    SecurityOkfItemPipeline,
)
from spider.core.engine import ScrapedItem


@pytest.fixture
def temp_output_dir() -> Any:
    td = tempfile.mkdtemp()
    yield td
    shutil.rmtree(td, ignore_errors=True)


def test_domain_security_okf_pipeline_identity() -> None:
    """Verifies OkfItemPipeline is an alias for SecurityOkfItemPipeline."""
    assert OkfItemPipeline is SecurityOkfItemPipeline


def test_backward_compatibility_shim_identity() -> None:
    """Verifies importing from spider.pipeline.okf_pipeline provides identical class."""
    import spider.pipeline.okf_pipeline as shim_pipe

    assert shim_pipe.OkfItemPipeline is SecurityOkfItemPipeline
    assert shim_pipe.SecurityOkfItemPipeline is SecurityOkfItemPipeline


def test_paper_okf_generation(temp_output_dir: str) -> None:
    """Verifies SecurityOkfItemPipeline formats security-paper OKF Markdown."""

    async def _run() -> None:
        pipeline = SecurityOkfItemPipeline(output_dir=temp_output_dir)
        item = ScrapedItem(
            item_id="arxiv_2609.9999",
            source_url="https://arxiv.org/abs/2609.9999",
            title="Quantum-Resilient Mesh Routing",
            payload={
                "clean_id": "2609.9999",
                "source": "arxiv",
                "abstract": "Novel post-quantum secure routing protocol.",
                "authors": ["Alice Cryptographer"],
                "published_date": "2026-09-08",
                "pdf_url": "https://arxiv.org/pdf/2609.9999.pdf",
                "tags": ["quantum-security", "network"],
            },
        )
        processed = await pipeline.process_item(item, spider=None)
        okf_path = processed.payload.get("okf_path")
        assert okf_path is not None
        assert os.path.exists(okf_path)

        with open(okf_path, "r", encoding="utf-8") as f:
            content = f.read()

        assert 'type: "security-paper"' in content
        assert "Quantum-Resilient Mesh Routing" in content
        assert "Alice Cryptographer" in content
        assert "Alice Cryptographer" in content
        assert "2609.9999" in content

    asyncio.run(_run())


def test_vulnerability_okf_generation(temp_output_dir: str) -> None:
    """Verifies SecurityOkfItemPipeline formats vulnerability CTI OKF Markdown."""

    async def _run() -> None:
        pipeline = SecurityOkfItemPipeline(output_dir=temp_output_dir)
        item = ScrapedItem(
            item_id="cve_2026_1111",
            source_url="https://nvd.nist.gov/vuln/detail/CVE-2026-1111",
            title="CVE-2026-1111 Critical Auth Bypass",
            payload={
                "type": "vulnerability",
                "cve_id": "CVE-2026-1111",
                "source": "nvd-cve-spider",
                "description": "Authentication bypass vulnerability.",
                "cvss": {
                    "base_score": 9.8,
                    "severity": "CRITICAL",
                    "vector_string": "CVSS:3.1/AV:N/AC:L",
                },
                "cwe": ["CWE-287"],
                "epss": 0.85,
                "kev_status": True,
                "due_date": "2026-09-20",
                "affected_vendors": ["Acme Corp"],
                "affected_products": ["Acme Gateway"],
                "published_date": "2026-09-08",
            },
        )
        processed = await pipeline.process_item(item, spider=None)
        okf_path = processed.payload.get("okf_path")
        assert okf_path is not None
        assert os.path.exists(okf_path)

        with open(okf_path, "r", encoding="utf-8") as f:
            content = f.read()

        assert 'type: "vulnerability"' in content
        assert "CVE-2026-1111" in content
        assert "CRITICAL" in content
        assert "CWE-287" in content
        assert "悪用確認済み (Active in the Wild)" in content
        assert "85.0%" in content
        assert "Acme Corp" in content

    asyncio.run(_run())


def test_db_persistence_dispatch(temp_output_dir: str) -> None:
    """Verifies DSN-14 DB persistence dispatch when enable_db_persistence=True."""

    async def _run() -> None:
        pipeline = SecurityOkfItemPipeline(
            output_dir=temp_output_dir, enable_db_persistence=True
        )
        item = ScrapedItem(
            item_id="paper_persist",
            source_url="https://arxiv.org/abs/2609.1234",
            title="DB Persist Test",
            payload={
                "clean_id": "2609.1234",
                "published_date": "2026-09-08",
                "type": "security-paper",
            },
        )

        mock_cursor = MagicMock()
        mock_conn = MagicMock()
        mock_conn.cursor.return_value = mock_cursor

        with patch("database.driver.connect", return_value=mock_conn) as mock_connect:
            await pipeline.process_item(item, spider=None)
            assert mock_connect.called
            assert mock_cursor.execute.called
            sql_executed = mock_cursor.execute.call_args[0][0]
            assert "INSERT OR REPLACE INTO papers" in sql_executed

    asyncio.run(_run())
