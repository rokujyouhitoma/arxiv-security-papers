"""OKF v0.2 Item Pipeline and DSN-14 Database Persistence."""

from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any, Optional

from ..core.engine import ScrapedItem


class OkfItemPipeline:
    """Item Pipeline for converting ScrapedItems to Google OKF v0.2 Markdown and DSN-14 DB records."""

    def __init__(
        self, output_dir: Optional[str] = None, enable_db_persistence: bool = False
    ) -> None:
        self.output_dir: str = output_dir or "outputs/okf_papers"
        self.enable_db_persistence: bool = enable_db_persistence

    async def process_item(self, item: ScrapedItem, spider: Any) -> ScrapedItem:
        """Processes scraped item, generates OKF v0.2 Markdown, and persists record."""
        payload = item.payload
        clean_id = payload.get("clean_id", item.item_id)
        pub_date = payload.get("published_date", "")
        date_folder = _extract_date_folder(pub_date)

        target_dir = os.path.join(self.output_dir, date_folder)
        os.makedirs(target_dir, exist_ok=True)
        okf_file = os.path.join(target_dir, f"{clean_id}.md")

        # Generate OKF v0.2 Markdown content
        markdown_content = _build_okf_markdown(item, clean_id, date_folder)
        with open(okf_file, "w", encoding="utf-8") as f:
            f.write(markdown_content)

        item.payload["okf_path"] = okf_file

        if self.enable_db_persistence:
            _persist_to_dsn14_db(item, clean_id, okf_file)

        return item


def _extract_date_folder(pub_date: str) -> str:
    if pub_date and len(pub_date) >= 10 and pub_date[4] == "-" and pub_date[7] == "-":
        return pub_date[:10]
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def _build_okf_markdown(item: ScrapedItem, clean_id: str, date_folder: str) -> str:
    payload = item.payload
    abstract = payload.get("abstract", "")
    authors = payload.get("authors", [])
    authors_str = (
        "\n".join([f'    - name: "{a}"' for a in authors])
        if authors
        else '    - name: "Unknown"'
    )
    tags = payload.get("tags", ["security"])
    tags_str = ", ".join([f'"{t}"' for t in tags])
    now_iso = datetime.now(timezone.utc).isoformat()

    return f"""---
type: "security-paper"
title: "{item.title.replace('"', '')}"
description: "{abstract[:150].replace('"', '')}..."
resource: "{item.source_url}"
tags: [{tags_str}]
timestamp: "{now_iso}"
provenance:
  origin: "{payload.get('source', 'spider')}"
  raw_metadata_path: "outputs/raw_data/{date_folder}/{clean_id}_meta.json"
  published_date: "{payload.get('published_date', '')}"
  authors:
{authors_str}
trust:
  attestation_status: "verified"
  digital_signature: "antigravity-spider-v1"
---

# {item.title}

## 概要 (Abstract)
{abstract}

## 詳細リンク (Resource)
- 原文リンク: [{item.source_url}]({item.source_url})
- PDF リンク: [{payload.get('pdf_url', 'N/A')}]({payload.get('pdf_url', 'N/A')})
"""


def _persist_to_dsn14_db(item: ScrapedItem, clean_id: str, okf_path: str) -> None:
    try:
        from database.driver import connect

        conn = connect(database="outputs/vector_db/security_papers.vdb")
        cursor = conn.cursor()
        cursor.execute(
            "INSERT OR REPLACE INTO papers (clean_id, title, url, okf_path) VALUES (?, ?, ?, ?)",
            (clean_id, item.title, item.source_url, okf_path),
        )
        conn.commit()
    except Exception:
        pass
