#!/usr/bin/env python3
"""src/cli/commands/summarize.py

Japanese executive summary stream filter subcommand conforming to DSN-01 Section 5.2.
Consumes JSON Lines from stdin and emits summary-enriched JSON Lines to stdout.
Pure Python, zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

import argparse
from typing import Any, Dict

from pipeline.transformer.structured_summarizer import generate_structured_summary
from pipeline.transformer.translator import translate_title_ja

from ..base import BaseCommand
from ..stream import DiagnosticLogger, StreamErrorPolicy, StreamReader, StreamWriter


def _resolve_paper_text(record: Dict[str, Any]) -> str:
    """Extracts abstract or full text fallback from paper record."""
    abstract = str(record.get("abstract", "")).strip()
    if abstract:
        return abstract
    full_text = str(record.get("full_text", "")).strip()
    return full_text if full_text else str(record.get("summary", "")).strip()


def _resolve_title_ja(record: Dict[str, Any], title: str) -> str:
    """Retrieves existing Japanese title or generates translation."""
    existing = record.get("title_ja")
    if existing:
        return str(existing)
    return translate_title_ja(title) if title else "無題"


def _enrich_summary(record: Dict[str, Any], style: str) -> Dict[str, Any]:
    """Applies NLP summarization and attaches summary fields to record."""
    title = str(record.get("title", ""))
    arxiv_id = str(record.get("arxiv_id", ""))
    clean_id = arxiv_id.replace("/", "_").replace(":", "_")
    title_ja = _resolve_title_ja(record, title)
    paper_text = _resolve_paper_text(record)

    sum_data = generate_structured_summary(
        title=title,
        abstract=paper_text,
        clean_id=clean_id,
        japanese_title=title_ja,
    )

    out = dict(record)
    out["title_ja"] = title_ja
    out["summary_ja"] = sum_data["executive_summary"]
    out["points_ja"] = {
        "threat": sum_data["threat"],
        "proposal": sum_data["proposal"],
        "impact": sum_data["impact"],
    }
    if style == "structured":
        out["structured_summary"] = (
            f"【課題】{sum_data['threat']}\n"
            f"【提案】{sum_data['proposal']}\n"
            f"【成果】{sum_data['impact']}"
        )
    return out


class SummarizeCommand(BaseCommand):
    """Subcommand to summarize paper records into structured Japanese summaries."""

    name = "summarize"
    help_text = "Generate Japanese executive summaries from stdin JSONL stream."

    def add_arguments(self, parser: argparse.ArgumentParser) -> None:
        parser.add_argument(
            "--style",
            dest="style",
            choices=["executive", "structured"],
            default="executive",
            help="Summary presentation style (executive or structured, default: executive).",
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

        logger.info(f"Starting NLP summarization filter (style: '{args.style}')...")

        for record in reader:
            enriched = _enrich_summary(record, args.style)
            writer.write_record(enriched)

        logger.info(f"Successfully summarized {writer.written_count} paper records.")
        return 0
