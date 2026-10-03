#!/usr/bin/env python3
"""src/cli/commands/pdf_extract.py

PDF text extraction stream filter subcommand conforming to DSN-01 Section 5.2.
Consumes JSON Lines from stdin, extracts full text, and emits enriched JSON Lines to stdout.
Pure Python, zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

import argparse
import datetime
import os
from typing import Any, Dict, Optional, Tuple, Union

from pdf_engine.extractor import PurePdfTextExtractor
from ..base import BaseCommand
from ..stream import DiagnosticLogger, StreamErrorPolicy, StreamReader, StreamWriter


def _get_iso_timestamp() -> str:
    """Returns current UTC timestamp in ISO 8601 format."""
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _resolve_cached_pdf(cache_dir: str, arxiv_id: str) -> Optional[str]:
    """Finds cached PDF file path if it exists locally."""
    if not arxiv_id:
        return None
    clean_id = arxiv_id.replace("/", "_").replace(":", "_")
    candidate = os.path.join(cache_dir, f"{clean_id}.pdf")
    return candidate if os.path.isfile(candidate) else None


def _extract_text_safe(
    source: Union[str, bytes], logger: DiagnosticLogger
) -> Tuple[str, int]:
    """Extracts text safely using PurePdfTextExtractor returning text and approx page count."""
    try:
        text = PurePdfTextExtractor.extract_text(source)
        pages = max(1, text.count("\x0c") + 1) if text else 0
        return text, pages
    except Exception as exc:
        logger.warn(f"PDF extraction error: {exc}")
        return "", 0


def _process_single_record(
    record: Dict[str, Any], cache_dir: str, logger: DiagnosticLogger
) -> Dict[str, Any]:
    """Enriches a single paper record with extracted full text and metadata."""
    out = dict(record)
    arxiv_id = str(out.get("arxiv_id", ""))
    cached_path = _resolve_cached_pdf(cache_dir, arxiv_id)

    if "full_text" in out and out["full_text"]:
        return out

    if cached_path:
        text, pages = _extract_text_safe(cached_path, logger)
        out["full_text"] = text
        out["page_count"] = pages
    else:
        out["full_text"] = out.get("abstract", "")
        out["page_count"] = 1

    out["extracted_at"] = _get_iso_timestamp()
    return out


class PdfExtractCommand(BaseCommand):
    """Subcommand to extract full text from PDF and enrich stream."""

    name = "pdf-extract"
    help_text = "Extract PDF full text from stdin stream and emit enriched JSON Lines."

    def add_arguments(self, parser: argparse.ArgumentParser) -> None:
        parser.add_argument(
            "--pdf-cache-dir",
            dest="pdf_cache_dir",
            default="data/pdf_cache",
            help="Directory containing downloaded PDF files (default: data/pdf_cache).",
        )
        parser.add_argument(
            "--on-error",
            dest="on_error",
            choices=["skip", "abort"],
            default="skip",
            help="Error policy for malformed input (skip or abort, default: skip).",
        )

    def handle(self, args: argparse.Namespace) -> int:
        policy = StreamErrorPolicy(args.on_error)
        reader = StreamReader(on_error=policy)
        writer = StreamWriter()
        logger = DiagnosticLogger()

        logger.info(
            f"Starting PDF extraction filter (cache dir: '{args.pdf_cache_dir}')..."
        )

        for record in reader:
            enriched = _process_single_record(record, args.pdf_cache_dir, logger)
            writer.write_record(enriched)

        logger.info(f"Successfully processed {writer.written_count} paper records.")
        return 0
