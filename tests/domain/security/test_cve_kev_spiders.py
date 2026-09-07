#!/usr/bin/env python3
"""Unit tests for CISA KEV and NVD CVE Domain Spiders and Pipeline Integration."""

from __future__ import annotations

import asyncio
import json
import os
import shutil
import tempfile
from typing import List, Union

import pytest

from domain.security.spiders.cisa_kev_spider import CisaKevSpider
from domain.security.spiders.nvd_cve_spider import NvdCveSpider
from pipeline.ingestion.adapters.registry import get_source_registry
from spider.core.downloader import Request, Response
from spider.core.engine import ScrapedItem
from spider.pipeline.okf_pipeline import OkfItemPipeline
from spider.registry import get_spider_registry
from spider.runner import get_available_spiders


def test_cisa_kev_spider_attributes() -> None:
    spider = CisaKevSpider()
    assert spider.name == "cisa_kev_spider"
    assert spider.download_delay == 5.0
    assert "cisa.gov" in spider.allowed_domains
    assert "www.cisa.gov" in spider.allowed_domains
    assert len(spider.start_urls) == 1
    assert "known_exploited_vulnerabilities.json" in spider.start_urls[0]


def test_nvd_cve_spider_attributes_and_rate_limits(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("NVD_API_KEY", raising=False)

    # 1. Without API Key: 6.5s delay
    spider_no_key = NvdCveSpider()
    assert spider_no_key.name == "nvd_cve_spider"
    assert spider_no_key.download_delay == 6.5
    assert spider_no_key.api_key == ""
    assert "apiKey" not in spider_no_key.custom_headers
    assert "services.nvd.nist.gov" in spider_no_key.allowed_domains

    # 2. With constructor API Key: 0.8s delay
    spider_with_key = NvdCveSpider(api_key="custom-key-123")
    assert spider_with_key.download_delay == 0.8
    assert spider_with_key.api_key == "custom-key-123"
    assert spider_with_key.custom_headers["apiKey"] == "custom-key-123"

    reqs = spider_with_key.start_requests()
    assert len(reqs) == 1
    assert reqs[0].headers.get("apiKey") == "custom-key-123"

    # 3. With Environment Variable API Key: 0.8s delay
    monkeypatch.setenv("NVD_API_KEY", "env-key-456")
    spider_env_key = NvdCveSpider()
    assert spider_env_key.download_delay == 0.8
    assert spider_env_key.api_key == "env-key-456"
    assert spider_env_key.custom_headers["apiKey"] == "env-key-456"


def test_cisa_kev_spider_parse() -> None:
    async def _run() -> None:
        mock_payload = {
            "title": "CISA Catalog of Known Exploited Vulnerabilities",
            "catalogVersion": "2026.09.01",
            "count": 2,
            "vulnerabilities": [
                {
                    "cveID": "CVE-2021-44228",
                    "vendorProject": "Apache",
                    "product": "Log4j",
                    "vulnerabilityName": "Apache Log4j RCE",
                    "dateAdded": "2021-12-10",
                    "shortDescription": "Uncontrolled JNDI lookup leading to RCE.",
                    "requiredAction": "Apply vendor updates immediately.",
                    "dueDate": "2021-12-24",
                    "knownRansomwareCampaignUse": "Known",
                    "notes": "https://nvd.nist.gov/vuln/detail/CVE-2021-44228",
                },
                {
                    "cveID": "CVE-2023-9999",
                    "vendorProject": "ExampleVendor",
                    "product": "ExampleApp",
                    "vulnerabilityName": "ExampleApp Auth Bypass",
                    "dateAdded": "2023-05-15",
                    "shortDescription": "Authentication bypass vulnerability.",
                    "requiredAction": "Patch to version 2.0.",
                    "dueDate": "2023-06-01",
                    "knownRansomwareCampaignUse": "Unknown",
                    "notes": "Internal report",
                },
            ],
        }

        req = Request(url=CisaKevSpider.start_urls[0])
        resp = Response(
            url=req.url,
            status_code=200,
            headers={"content-type": "application/json"},
            body=json.dumps(mock_payload).encode("utf-8"),
            request=req,
        )

        spider = CisaKevSpider()
        results: List[Union[Request, ScrapedItem]] = []
        async for item in spider.parse(resp):
            results.append(item)

        assert len(results) == 2
        item1 = results[0]
        assert isinstance(item1, ScrapedItem)
        assert item1.item_id == "cisa_kev_CVE-2021-44228"
        assert item1.title == "Apache Log4j RCE"
        assert item1.payload["type"] == "vulnerability"
        assert item1.payload["source"] == "cisa-kev"
        assert item1.payload["cve_id"] == "CVE-2021-44228"
        assert item1.payload["clean_id"] == "CVE-2021-44228"
        assert item1.payload["due_date"] == "2021-12-24"
        assert item1.payload["kev_status"] is True
        assert item1.payload["affected_vendors"] == ["Apache"]
        assert item1.payload["affected_products"] == ["Log4j"]
        assert "ransomware" in item1.payload["tags"]
        assert (
            "https://nvd.nist.gov/vuln/detail/CVE-2021-44228"
            in item1.payload["references"]
        )

        item2 = results[1]
        assert isinstance(item2, ScrapedItem)
        assert item2.item_id == "cisa_kev_CVE-2023-9999"
        assert "ransomware" not in item2.payload["tags"]

    asyncio.run(_run())


def test_nvd_cve_spider_parse_and_pagination() -> None:
    async def _run() -> None:
        mock_nvd_data = {
            "resultsPerPage": 2000,
            "startIndex": 0,
            "totalResults": 3500,
            "format": "NVD_CVE",
            "version": "2.0",
            "vulnerabilities": [
                {
                    "cve": {
                        "id": "CVE-2024-1234",
                        "published": "2024-01-15T10:00:00.000",
                        "descriptions": [
                            {"lang": "es", "value": "Descripcion en espanol"},
                            {
                                "lang": "en",
                                "value": "Critical SQL Injection in portal.",
                            },
                        ],
                        "metrics": {
                            "cvssMetricV31": [
                                {
                                    "cvssData": {
                                        "version": "3.1",
                                        "vectorString": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H",
                                        "baseScore": 9.8,
                                        "baseSeverity": "CRITICAL",
                                    }
                                }
                            ]
                        },
                        "weaknesses": [
                            {
                                "description": [
                                    {"lang": "en", "value": "CWE-89"},
                                    {"lang": "en", "value": "CWE-20"},
                                ]
                            }
                        ],
                        "configurations": [
                            {
                                "nodes": [
                                    {
                                        "cpeMatch": [
                                            {
                                                "criteria": "cpe:2.3:a:oracle:database_server:19c:*:*:*:*:*:*:*"
                                            }
                                        ]
                                    }
                                ]
                            }
                        ],
                        "references": [
                            {
                                "url": "https://www.oracle.com/security-alerts/cpujan2024.html"
                            }
                        ],
                    }
                }
            ],
        }

        spider = NvdCveSpider(api_key="my-key")
        req = Request(url=spider.start_urls[0])
        resp = Response(
            url=req.url,
            status_code=200,
            headers={"content-type": "application/json"},
            body=json.dumps(mock_nvd_data).encode("utf-8"),
            request=req,
        )

        results: List[Union[Request, ScrapedItem]] = []
        async for item in spider.parse(resp):
            results.append(item)

        # 1 ScrapedItem + 1 next page Request
        assert len(results) == 2
        scraped = results[0]
        assert isinstance(scraped, ScrapedItem)
        assert scraped.item_id == "nvd_cve_CVE-2024-1234"
        assert scraped.payload["type"] == "vulnerability"
        assert scraped.payload["source"] == "nvd-cve"
        assert scraped.payload["cve_id"] == "CVE-2024-1234"
        assert scraped.payload["abstract"] == "Critical SQL Injection in portal."
        assert scraped.payload["cvss"]["base_score"] == 9.8
        assert scraped.payload["cvss"]["severity"] == "CRITICAL"
        assert "CWE-89" in scraped.payload["cwe"]
        assert "CWE-20" in scraped.payload["cwe"]
        assert "oracle" in scraped.payload["affected_vendors"]
        assert "database_server" in scraped.payload["affected_products"]
        assert (
            "https://www.oracle.com/security-alerts/cpujan2024.html"
            in scraped.payload["references"]
        )

        next_req = results[1]
        assert isinstance(next_req, Request)
        assert next_req.params is not None
        assert next_req.params.get("startIndex") == 2000
        assert next_req.params.get("resultsPerPage") == 2000
        assert next_req.headers.get("apiKey") == "my-key"

    asyncio.run(_run())


def test_nvd_cve_spider_pagination_stops_at_final_page() -> None:
    async def _run() -> None:
        mock_nvd_last_page = {
            "resultsPerPage": 2000,
            "startIndex": 2000,
            "totalResults": 3500,
            "vulnerabilities": [],
        }

        spider = NvdCveSpider()
        req = Request(url=spider.start_urls[0])
        resp = Response(
            url=req.url,
            status_code=200,
            headers={"content-type": "application/json"},
            body=json.dumps(mock_nvd_last_page).encode("utf-8"),
            request=req,
        )

        results: List[Union[Request, ScrapedItem]] = []
        async for item in spider.parse(resp):
            results.append(item)

        assert len(results) == 0

    asyncio.run(_run())


def test_okf_pipeline_integration_with_cisa_and_nvd() -> None:
    async def _run() -> None:
        temp_dir = tempfile.mkdtemp()
        try:
            pipeline = OkfItemPipeline(output_dir=temp_dir)

            # 1. Test CISA KEV item through OkfItemPipeline
            cisa_item = ScrapedItem(
                item_id="cisa_kev_CVE-2021-44228",
                source_url="https://nvd.nist.gov/vuln/detail/CVE-2021-44228",
                title="Apache Log4j RCE",
                payload={
                    "type": "vulnerability",
                    "source": "cisa-kev",
                    "cve_id": "CVE-2021-44228",
                    "clean_id": "CVE-2021-44228",
                    "title": "Apache Log4j RCE",
                    "abstract": "Uncontrolled JNDI lookup.",
                    "published_date": "2021-12-10",
                    "due_date": "2021-12-24",
                    "kev_status": True,
                    "affected_vendors": ["Apache"],
                    "affected_products": ["Log4j"],
                    "required_action": "Update to 2.15.0",
                    "tags": ["vulnerability", "cisa-kev", "ransomware"],
                },
            )

            res_cisa = await pipeline.process_item(cisa_item, spider=None)
            okf_cisa_path = res_cisa.payload["okf_path"]
            assert os.path.exists(okf_cisa_path)

            with open(okf_cisa_path, "r", encoding="utf-8") as f:
                cisa_content = f.read()

            assert 'type: "vulnerability"' in cisa_content
            assert 'cve_id: "CVE-2021-44228"' in cisa_content
            assert "kev_status: true" in cisa_content
            assert "悪用確認済み (Active in the Wild)" in cisa_content
            assert "2021-12-24" in cisa_content
            assert "Apache" in cisa_content
            assert "Log4j" in cisa_content

            # 2. Test NVD CVE item through OkfItemPipeline
            nvd_item = ScrapedItem(
                item_id="nvd_cve_CVE-2024-1234",
                source_url="https://nvd.nist.gov/vuln/detail/CVE-2024-1234",
                title="[CVE-2024-1234] Vulnerability",
                payload={
                    "type": "vulnerability",
                    "source": "nvd-cve",
                    "cve_id": "CVE-2024-1234",
                    "clean_id": "CVE-2024-1234",
                    "title": "[CVE-2024-1234] Vulnerability",
                    "abstract": "SQL injection in web portal.",
                    "published_date": "2024-01-15",
                    "cvss": {
                        "base_score": 9.8,
                        "severity": "CRITICAL",
                        "vector_string": "CVSS:3.1/...",
                    },
                    "cwe": ["CWE-89"],
                    "affected_vendors": ["Oracle"],
                    "affected_products": ["Database"],
                    "tags": ["vulnerability", "nvd-cve"],
                },
            )

            res_nvd = await pipeline.process_item(nvd_item, spider=None)
            okf_nvd_path = res_nvd.payload["okf_path"]
            assert os.path.exists(okf_nvd_path)

            with open(okf_nvd_path, "r", encoding="utf-8") as f:
                nvd_content = f.read()

            assert 'type: "vulnerability"' in nvd_content
            assert "CRITICAL" in nvd_content
            assert "9.8" in nvd_content
            assert "CWE-89" in nvd_content
        finally:
            shutil.rmtree(temp_dir)

    asyncio.run(_run())


def test_spider_registry_and_runner_integration() -> None:
    registry = get_spider_registry()
    assert registry.get("cisa_kev_spider") == CisaKevSpider
    assert registry.get("nvd_cve_spider") == NvdCveSpider

    spiders = get_available_spiders()
    assert "cisa_kev_spider" in spiders
    assert "cisa_kev" in spiders
    assert "nvd_cve_spider" in spiders
    assert "nvd_cve" in spiders

    src_registry = get_source_registry()
    assert "spider_cisa_kev" in src_registry.list_sources()
    assert "spider_nvd_cve" in src_registry.list_sources()
