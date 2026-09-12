#!/usr/bin/env python3
"""Unit tests for MITRE CWE Catalog Spider and Plugin Registry Integration."""

from __future__ import annotations

import asyncio
import json
from typing import List, Union

from domain.security.spiders.cwe_spider import (
    CweSpider,
    _build_cwe_tags,
    _extract_cwe_records,
    _normalize_cwe_id,
)
from spider.core.downloader import Request, Response
from spider.core.engine import ScrapedItem
from spider.registry import get_spider_registry
from spider.runner import get_available_spiders


def test_cwe_spider_attributes() -> None:
    """Verifies that CweSpider adheres to MITRE terms and spider base contracts."""
    spider = CweSpider()
    assert spider.name == "cwe_spider"
    assert spider.download_delay == 5.0
    assert "cwe.mitre.org" in spider.allowed_domains
    assert "cwe-api.mitre.org" in spider.allowed_domains
    assert len(spider.start_urls) == 1
    assert "cwe-api.mitre.org" in spider.start_urls[0]


def test_normalize_cwe_id() -> None:
    """Verifies standard CWE-ID prefix normalization."""
    assert _normalize_cwe_id("79") == "CWE-79"
    assert _normalize_cwe_id("cwe-89") == "CWE-89"
    assert _normalize_cwe_id("CWE-502") == "CWE-502"
    assert _normalize_cwe_id("") == ""
    assert _normalize_cwe_id(None) == ""


def test_build_cwe_tags() -> None:
    """Verifies tags generation including Top 25 critical tags."""
    tags_standard = _build_cwe_tags("CWE-79", is_top25=False)
    assert "weakness" in tags_standard
    assert "mitre-cwe" in tags_standard
    assert "cwe-79" in tags_standard
    assert "cwe-top25" not in tags_standard

    tags_top25 = _build_cwe_tags("CWE-89", is_top25=True)
    assert "cwe-top25" in tags_top25
    assert "critical-weakness" in tags_top25


def test_extract_cwe_records_list_and_dict_formats() -> None:
    """Verifies robust extraction across different JSON schema responses."""
    # 1. Direct list
    req1 = Request(url="https://cwe-api.mitre.org/api/v1/cwe/weakness")
    resp1 = Response(
        url="https://cwe-api.mitre.org/api/v1/cwe/weakness",
        status_code=200,
        headers={"Content-Type": "application/json"},
        body=json.dumps([{"id": "79", "name": "XSS"}]).encode("utf-8"),
        request=req1,
    )
    assert len(_extract_cwe_records(resp1)) == 1

    # 2. Wrapped dictionary with 'weaknesses'
    req2 = Request(url="https://cwe-api.mitre.org/api/v1/cwe/weakness")
    resp2 = Response(
        url="https://cwe-api.mitre.org/api/v1/cwe/weakness",
        status_code=200,
        headers={"Content-Type": "application/json"},
        body=json.dumps({"weaknesses": [{"id": "89", "name": "SQLi"}]}).encode("utf-8"),
        request=req2,
    )
    assert len(_extract_cwe_records(resp2)) == 1

    # 3. Invalid payload returns empty
    req_inv = Request(url="https://cwe-api.mitre.org/api/v1/cwe/weakness")
    resp_invalid = Response(
        url="https://cwe-api.mitre.org/api/v1/cwe/weakness",
        status_code=200,
        headers={"Content-Type": "application/json"},
        body=b"not-json",
        request=req_inv,
    )
    assert _extract_cwe_records(resp_invalid) == []


def test_cwe_spider_parse_normalized_item() -> None:
    """Verifies parse generator maps raw weakness JSON into a valid ScrapedItem."""

    async def _run() -> None:
        mock_body = {
            "weaknesses": [
                {
                    "id": "79",
                    "name": "Improper Neutralization of Input During Web Page Generation ('Cross-site Scripting')",
                    "abstraction": "Class",
                    "status": "Incomplete",
                    "description": (
                        "The product does not neutralize or incorrectly neutralizes "
                        "user-controllable input before it is placed in output that is used as a web page."
                    ),
                    "top25_rank": 2,
                    "potential_mitigations": [
                        {
                            "phase": "Architecture and Design",
                            "strategy": "Libraries or Frameworks",
                            "description": (
                                "Use a vetted library or framework that does not allow this weakness to occur."
                            ),
                        }
                    ],
                    "related_weaknesses": [{"nature": "ChildOf", "cwe_id": "74"}],
                    "related_attack_patterns": ["63", "85"],
                },
                {
                    "id": "9999",
                    "name": "Missing Attributes",
                    # Minimal entry
                },
            ]
        }
        req = Request(url="https://cwe-api.mitre.org/api/v1/cwe/weakness")
        response = Response(
            url="https://cwe-api.mitre.org/api/v1/cwe/weakness",
            status_code=200,
            headers={"Content-Type": "application/json"},
            body=json.dumps(mock_body).encode("utf-8"),
            request=req,
        )

        spider = CweSpider()
        results: List[Union[Request, ScrapedItem]] = []
        async for item in spider.parse(response):
            results.append(item)

        assert len(results) == 2
        item1 = results[0]
        assert isinstance(item1, ScrapedItem)
        assert item1.item_id == "cwe_cwe-79"
        assert "https://cwe.mitre.org/data/definitions/79.html" in item1.source_url
        assert "[CWE-79]" in item1.title

        payload = item1.payload
        assert payload["type"] == "weakness"
        assert payload["source"] == "mitre-cwe"
        assert payload["cwe_id"] == "CWE-79"
        assert payload["abstraction"] == "Class"
        assert payload["top25_rank"] == 2
        assert payload["is_top25"] is True
        assert len(payload["mitigations"]) == 1
        assert payload["mitigations"][0]["strategy"] == "Libraries or Frameworks"
        assert len(payload["relationships"]) == 1
        assert payload["relationships"][0]["target_cwe_id"] == "CWE-74"
        assert payload["relationships"][0]["relation_type"] == "ChildOf"
        assert payload["related_attack_ids"] == ["63", "85"]
        assert "cwe-top25" in payload["tags"]

    asyncio.run(_run())


def test_spider_registry_integration() -> None:
    """Verifies that CweSpider is auto-discovered via SpiderRegistry and get_available_spiders."""
    spiders = get_available_spiders()
    assert "cwe_spider" in spiders

    registry = get_spider_registry()
    spider_cls = registry.get("cwe_spider")
    assert spider_cls is not None
    instance = spider_cls()
    assert isinstance(instance, CweSpider)
