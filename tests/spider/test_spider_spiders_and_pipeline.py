"""Unit tests for domain spiders and OKF Item Pipeline."""

import os
import shutil
import tempfile

from src.spider.core.downloader import Request, Response
from src.spider.core.engine import ScrapedItem
from src.spider.pipeline.okf_pipeline import OkfItemPipeline
from src.spider.spiders.advisory_spider import AdvisorySpider
from src.spider.spiders.arxiv_spider import ArxivSpider
from src.spider.spiders.iacr_spider import IacrSpider


def test_arxiv_spider_atom_parsing() -> None:
    async def _run() -> None:
        atom_xml = """<?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
                <id>http://arxiv.org/abs/2608.12345v1</id>
                <title>Robust Zero-Trust Identity Federation</title>
                <summary>We propose a decentralized protocol for cross-domain security.</summary>
                <published>2026-08-21T10:00:00Z</published>
                <author><name>Bob Smith</name></author>
            </entry>
        </feed>
        """
        spider = ArxivSpider()
        req = Request(url="https://export.arxiv.org/api/query?search_query=cat:cs.CR")
        resp = Response(
            url=req.url,
            status_code=200,
            headers={"content-type": "application/atom+xml"},
            body=atom_xml.encode("utf-8"),
            request=req,
        )
        items = []
        async for item in spider.parse(resp):
            items.append(item)

        assert len(items) == 1
        assert isinstance(items[0], ScrapedItem)
        assert items[0].title == "Robust Zero-Trust Identity Federation"
        assert items[0].payload["clean_id"] == "2608.12345"
        assert items[0].payload["authors"] == ["Bob Smith"]

    import asyncio

    asyncio.run(_run())


def test_iacr_spider_rss_parsing() -> None:
    async def _run() -> None:
        rss_xml = """<?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0">
            <channel>
                <item>
                    <title>Lattice-Based Zero-Knowledge Signatures</title>
                    <link>https://eprint.iacr.org/2026/999</link>
                    <description>A succinct proof system with post-quantum security.</description>
                    <pubDate>Fri, 21 Aug 2026 08:00:00 GMT</pubDate>
                </item>
            </channel>
        </rss>
        """
        spider = IacrSpider()
        req = Request(url="https://eprint.iacr.org/rss/rss.xml")
        resp = Response(
            url=req.url,
            status_code=200,
            headers={"content-type": "text/xml"},
            body=rss_xml.encode("utf-8"),
            request=req,
        )
        items = []
        async for item in spider.parse(resp):
            items.append(item)

        assert len(items) == 1
        assert items[0].payload["clean_id"] == "2026_999"

    import asyncio

    asyncio.run(_run())


def test_advisory_spider_parsing() -> None:
    async def _run() -> None:
        adv_xml = """<?xml version="1.0"?>
        <rss version="2.0">
            <channel>
                <item>
                    <title>CVE-2026-8888 Remote Code Execution in TLS Parser</title>
                    <description>Critical vulnerability allowing buffer overflow.</description>
                    <link>https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2026-8888</link>
                </item>
            </channel>
        </rss>
        """
        spider = AdvisorySpider()
        req = Request(url="https://cve.mitre.org/data/downloads/allitems.xml")
        resp = Response(
            url=req.url,
            status_code=200,
            headers={"content-type": "text/xml"},
            body=adv_xml.encode("utf-8"),
            request=req,
        )
        items = []
        async for item in spider.parse(resp):
            items.append(item)

        assert len(items) == 1
        assert items[0].payload["clean_id"] == "CVE-2026-8888"

    import asyncio

    asyncio.run(_run())


def test_okf_pipeline_output() -> None:
    async def _run() -> None:
        temp_dir = tempfile.mkdtemp()
        try:
            pipeline = OkfItemPipeline(output_dir=temp_dir)
            item = ScrapedItem(
                item_id="arxiv_2608.1111",
                source_url="https://arxiv.org/abs/2608.1111",
                title="Formal Verification of Microkernel",
                payload={
                    "clean_id": "2608.1111",
                    "source": "arxiv",
                    "abstract": "We prove functional correctness using interactive theorem provers.",
                    "authors": ["Carol"],
                    "published_date": "2026-08-21",
                    "pdf_url": "https://arxiv.org/pdf/2608.1111.pdf",
                    "tags": ["formal-methods", "os-security"],
                },
            )
            processed = await pipeline.process_item(item, spider=None)
            okf_path = processed.payload["okf_path"]
            assert os.path.exists(okf_path)

            with open(okf_path, "r", encoding="utf-8") as f:
                content = f.read()

            assert 'type: "security-paper"' in content
            assert "Formal Verification of Microkernel" in content
            assert "Carol" in content
            assert "https://arxiv.org/abs/2608.1111" in content
        finally:
            shutil.rmtree(temp_dir)

    import asyncio

    asyncio.run(_run())
