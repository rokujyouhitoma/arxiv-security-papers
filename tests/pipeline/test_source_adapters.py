#!/usr/bin/env python3
"""
Unit tests for Pluggable Source Adapters and Registry.
"""

import os
import tempfile
from datetime import datetime, timezone
from typing import Any
from unittest.mock import MagicMock, patch

from pipeline.ingestion.adapters import (
    ArxivSourceAdapter,
    BaseSourceAdapter,
    FeedSourceAdapter,
    IacrEprintSourceAdapter,
    RawItem,
    SourceRegistry,
    get_source_registry,
)


def test_raw_item_serialization_and_deserialization() -> None:
    now = datetime.now(timezone.utc).isoformat()
    item = RawItem(
        item_id="arxiv_2608.12345",
        clean_id="2608.12345",
        title="Zero-Trust Architecture",
        abstract="A paper about ZTA.",
        authors=["Alice", "Bob"],
        published=now,
        updated=now,
        url="https://arxiv.org/abs/2608.12345",
        pdf_url="https://arxiv.org/pdf/2608.12345.pdf",
        primary_category="cs.CR",
        categories=["cs.CR", "cs.NI"],
        source_type="arxiv",
    )

    d = item.to_dict()
    assert d["item_id"] == "arxiv_2608.12345"
    assert d["arxiv_id"] == "arxiv_2608.12345"  # Legacy compat
    assert d["summary"] == "A paper about ZTA."  # Legacy compat

    reconstructed = RawItem.from_dict(d)
    assert reconstructed.item_id == item.item_id
    assert reconstructed.title == item.title
    assert reconstructed.authors == item.authors
    assert reconstructed.categories == ["cs.CR", "cs.NI"]


def test_source_registry_registration_and_lookup() -> None:
    registry = SourceRegistry()
    assert registry.get("arxiv") is not None
    assert registry.get("iacr_eprint") is not None
    assert registry.get("rss_feed") is not None

    class CustomAdapter(BaseSourceAdapter):
        @property
        def source_name(self) -> str:
            return "custom_source"

        def fetch_items(self, *args: Any, **kwargs: Any) -> list[RawItem]:
            return []

        def fetch_content_and_text(self, item: RawItem, raw_dir: str) -> None:
            pass

    registry.register(CustomAdapter())
    assert registry.get("custom_source") is not None
    assert "custom_source" in registry.list_sources()

    global_reg = get_source_registry()
    assert global_reg.get("arxiv") is not None


@patch("pipeline.ingestion.adapters.arxiv_adapter.fetch_arxiv_papers")
def test_arxiv_source_adapter_fetch(mock_fetch: MagicMock) -> None:
    mock_fetch.return_value = [
        {
            "arxiv_id": "2608.99999v1",
            "clean_id": "2608.99999",
            "title": "Adversarial Robustness in LLM Agents",
            "summary": "Investigating prompt injection vectors.",
            "authors": ["Carol White"],
            "published": "2026-08-21T00:00:00Z",
            "updated": "2026-08-21T00:00:00Z",
            "abs_url": "https://arxiv.org/abs/2608.99999",
            "pdf_url": "https://arxiv.org/pdf/2608.99999.pdf",
            "primary_category": "cs.AI",
            "categories": ["cs.AI", "cs.CR"],
        }
    ]

    adapter = ArxivSourceAdapter(default_category="cs.AI")
    items = adapter.fetch_items(query="cat:cs.AI", max_results=10)

    assert len(items) == 1
    assert items[0].item_id == "2608.99999v1"
    assert items[0].clean_id == "2608.99999"
    assert items[0].source_type == "arxiv"
    assert items[0].primary_category == "cs.AI"


def test_iacr_eprint_xml_parsing() -> None:
    sample_rss = b"""<?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0">
      <channel>
        <title>Cryptology ePrint Archive</title>
        <link>https://eprint.iacr.org/</link>
        <description>Latest Cryptology Preprints</description>
        <item>
          <title>Post-Quantum Zero-Knowledge Arguments for Lattice Relations</title>
          <link>https://eprint.iacr.org/2026/999</link>
          <description>We propose a new post-quantum ZK argument system.</description>
          <author>David Crypto</author>
          <pubDate>Thu, 20 Aug 2026 12:00:00 GMT</pubDate>
        </item>
      </channel>
    </rss>
    """
    adapter = IacrEprintSourceAdapter()
    items = adapter._parse_feed_xml(sample_rss, max_results=10)

    assert len(items) == 1
    assert items[0].item_id == "iacr-2026-999"
    assert (
        items[0].title == "Post-Quantum Zero-Knowledge Arguments for Lattice Relations"
    )
    assert items[0].authors == ["David Crypto"]
    assert items[0].source_type == "iacr_eprint"
    assert items[0].primary_category == "cryptography"

    with tempfile.TemporaryDirectory() as tmpdir:
        adapter.fetch_content_and_text(items[0], tmpdir)
        txt_path = os.path.join(tmpdir, f"{items[0].clean_id}.txt")
        assert os.path.exists(txt_path)
        with open(txt_path, "r", encoding="utf-8") as f:
            content = f.read()
            assert "Post-Quantum" in content


def test_feed_source_adapter_rss_and_atom_parsing() -> None:
    sample_atom = b"""<?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Security Research Blog</title>
      <entry>
        <title>Critical Zero-Day in Cloud Virtualization Engine</title>
        <link href="https://security.example.com/advisories/sec-2026-01"/>
        <summary>Analysis of hypervisor escape vulnerability.</summary>
        <author><name>SecTeam</name></author>
        <published>2026-08-21T08:00:00Z</published>
      </entry>
    </feed>
    """
    adapter = FeedSourceAdapter()
    items = adapter._parse_feed(
        sample_atom, max_results=5, feed_url="https://security.example.com/atom.xml"
    )

    assert len(items) == 1
    assert "Critical Zero-Day" in items[0].title
    assert items[0].url == "https://security.example.com/advisories/sec-2026-01"
    assert items[0].source_type == "rss_feed"
    assert items[0].primary_category == "security_advisory"

    with tempfile.TemporaryDirectory() as tmpdir:
        adapter.fetch_content_and_text(items[0], tmpdir)
        txt_path = os.path.join(tmpdir, f"{items[0].clean_id}.txt")
        assert os.path.exists(txt_path)
