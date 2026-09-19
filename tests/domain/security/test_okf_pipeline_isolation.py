"""Unit tests for OKF Pipeline storage isolation (Issue 337).

Verifies that SecurityOkfItemPipeline automatically routes items to their
dedicated storage roots:
  - 'security-paper' -> 'outputs/okf_papers'
  - 'vulnerability' / 'security-advisory' -> 'outputs/okf_vulnerabilities'
  - 'weakness' -> 'outputs/okf_weaknesses'
while preserving full backward compatibility when custom output_dir is supplied.
"""

from __future__ import annotations

import os
import shutil
import tempfile

from domain.security.pipeline.okf_pipeline import SecurityOkfItemPipeline
from spider.core.engine import ScrapedItem


def test_resolve_output_root_defaults() -> None:
    """Verifies default directory routing by item type."""
    pipeline = SecurityOkfItemPipeline()

    assert pipeline.resolve_output_root("security-paper") == "outputs/okf_papers"
    assert pipeline.resolve_output_root("paper") == "outputs/okf_papers"
    assert (
        pipeline.resolve_output_root("vulnerability") == "outputs/okf_vulnerabilities"
    )
    assert (
        pipeline.resolve_output_root("security-advisory")
        == "outputs/okf_vulnerabilities"
    )
    assert (
        pipeline.resolve_output_root("security_advisory")
        == "outputs/okf_vulnerabilities"
    )
    assert pipeline.resolve_output_root("weakness") == "outputs/okf_weaknesses"


def test_resolve_output_root_custom_dir() -> None:
    """Verifies custom directory overrides default routing (backward compatibility)."""
    custom_dir = "/tmp/custom_test_dir"
    pipeline = SecurityOkfItemPipeline(output_dir=custom_dir)

    assert pipeline.resolve_output_root("security-paper") == custom_dir
    assert pipeline.resolve_output_root("vulnerability") == custom_dir
    assert pipeline.resolve_output_root("weakness") == custom_dir


def test_resolve_output_root_disabled_isolation() -> None:
    """Verifies isolate_by_type=False uses output_dir for all types."""
    pipeline = SecurityOkfItemPipeline(
        output_dir="outputs/monolithic", isolate_by_type=False
    )

    assert pipeline.resolve_output_root("security-paper") == "outputs/monolithic"
    assert pipeline.resolve_output_root("vulnerability") == "outputs/monolithic"
    assert pipeline.resolve_output_root("weakness") == "outputs/monolithic"


def test_pipeline_process_item_storage_isolation() -> None:
    """Verifies end-to-end item processing writes to type-isolated directory."""
    import asyncio

    async def _run() -> None:
        temp_dir = tempfile.mkdtemp(prefix="test_okf_isolation_")
        try:
            # Mock class with custom base paths pointing inside temp_dir
            class TestIsolatedPipeline(SecurityOkfItemPipeline):
                DEFAULT_PAPER_DIR = os.path.join(temp_dir, "papers")
                DEFAULT_VULN_DIR = os.path.join(temp_dir, "vulns")
                DEFAULT_WEAKNESS_DIR = os.path.join(temp_dir, "weaknesses")

                def resolve_output_root(self, item_type: str) -> str:
                    normalized = item_type.lower()
                    if normalized in (
                        "vulnerability",
                        "security-advisory",
                        "security_advisory",
                    ):
                        return self.DEFAULT_VULN_DIR
                    if normalized == "weakness":
                        return self.DEFAULT_WEAKNESS_DIR
                    return self.DEFAULT_PAPER_DIR

            pipeline = TestIsolatedPipeline()

            # 1. Paper
            paper_item = ScrapedItem(
                item_id="2609.99999",
                source_url="https://arxiv.org/abs/2609.99999",
                title="A Secure Paper",
                payload={"type": "security-paper", "published_date": "2026-09-19"},
            )
            res_paper = await pipeline.process_item(paper_item, spider=None)
            assert res_paper.payload["okf_path"].startswith(
                TestIsolatedPipeline.DEFAULT_PAPER_DIR
            )
            assert os.path.exists(res_paper.payload["okf_path"])

            # 2. Vulnerability
            vuln_item = ScrapedItem(
                item_id="CVE-2026-9999",
                source_url="https://nvd.nist.gov/vuln/detail/CVE-2026-9999",
                title="Critical Vuln",
                payload={
                    "type": "vulnerability",
                    "published_date": "2026-09-19",
                    "cve_id": "CVE-2026-9999",
                },
            )
            res_vuln = await pipeline.process_item(vuln_item, spider=None)
            assert res_vuln.payload["okf_path"].startswith(
                TestIsolatedPipeline.DEFAULT_VULN_DIR
            )
            assert os.path.exists(res_vuln.payload["okf_path"])

            # 3. Weakness
            weakness_item = ScrapedItem(
                item_id="CWE-9999",
                source_url="https://cwe.mitre.org/data/definitions/9999.html",
                title="Sample Weakness",
                payload={"type": "weakness", "cwe_id": "CWE-9999"},
            )
            res_weakness = await pipeline.process_item(weakness_item, spider=None)
            assert res_weakness.payload["okf_path"].startswith(
                TestIsolatedPipeline.DEFAULT_WEAKNESS_DIR
            )
            assert os.path.exists(res_weakness.payload["okf_path"])

        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    asyncio.run(_run())
