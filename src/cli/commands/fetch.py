#!/usr/bin/env python3
"""src/cli/commands/fetch.py

Fetch management subcommand conforming to DSN-01 Section 5.2 and REQ-FR-09.
Fetches security paper metadata from arXiv/RSS and emits JSON Lines to stdout.
Pure Python, zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

import argparse
from typing import Any, Dict

from pipeline.ingestion.adapters.arxiv_adapter import ArxivSourceAdapter
from ..base import BaseCommand
from ..stream import DiagnosticLogger, StreamWriter


def _resolve_pdf_url(meta: Dict[str, Any], arxiv_id: str) -> str:
    """Resolves paper PDF URL with fallback to standard arXiv URL."""
    url = meta.get("pdf_url")
    if url:
        return str(url)
    return f"https://arxiv.org/pdf/{arxiv_id}.pdf" if arxiv_id else ""


def _extract_paper_record(item: Any) -> Dict[str, Any]:
    """Converts a RawItem or raw paper dict into a clean stream record."""
    meta = getattr(item, "metadata", item)
    arxiv_id = str(meta.get("arxiv_id") or getattr(item, "source_id", ""))
    abstract = meta.get("abstract") or getattr(item, "raw_content", "")
    return {
        "arxiv_id": arxiv_id,
        "title": meta.get("title", ""),
        "authors": meta.get("authors", []),
        "abstract": abstract,
        "published": meta.get("published", ""),
        "categories": meta.get("categories", []),
        "pdf_url": _resolve_pdf_url(meta, arxiv_id),
    }


class FetchCommand(BaseCommand):
    """Subcommand to fetch paper metadata and stream JSONL to stdout."""

    name = "fetch"
    help_text = "Fetch paper metadata from arXiv/RSS and emit JSON Lines to stdout."

    def add_arguments(self, parser: argparse.ArgumentParser) -> None:
        parser.add_argument(
            "-c",
            "--category",
            dest="category",
            default="cs.CR",
            help="arXiv category to fetch (default: cs.CR).",
        )
        parser.add_argument(
            "-n",
            "--limit",
            dest="limit",
            type=int,
            default=20,
            help="Maximum number of papers to fetch (default: 20).",
        )
        parser.add_argument(
            "--since",
            dest="since",
            default=None,
            help="Optional start date filter (YYYY-MM-DD).",
        )
        parser.add_argument(
            "-s",
            "--stream",
            dest="stream",
            action="store_true",
            default=True,
            help="Emit JSON Lines stream to stdout (default: True).",
        )

    def handle(self, args: argparse.Namespace) -> int:
        logger = DiagnosticLogger()
        writer = StreamWriter()
        logger.info(
            f"Fetching up to {args.limit} papers for category '{args.category}'..."
        )

        adapter = ArxivSourceAdapter(default_category=args.category)
        items = adapter.fetch_items(
            max_results=args.limit,
            category=args.category,
        )

        for item in items:
            record = _extract_paper_record(item)
            writer.write_record(record)

        logger.info(f"Successfully streamed {writer.written_count} paper records.")
        return 0
