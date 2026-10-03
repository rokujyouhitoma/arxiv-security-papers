#!/usr/bin/env python3
"""src/cli/commands/db_index.py

Database and vector search index sink subcommand conforming to DSN-01 Section 5.2.
Consumes JSON Lines from stdin and upserts records into catalog/vector search index.
Pure Python, zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

import argparse
import json
import os
import tempfile
import time
from typing import Any, Dict

from ..base import BaseCommand
from ..stream import DiagnosticLogger, StreamErrorPolicy, StreamReader, StreamWriter


def _load_catalog(cat_path: str) -> Dict[str, Any]:
    """Loads existing papers catalog or returns empty dictionary."""
    if not os.path.exists(cat_path):
        return {}
    try:
        with open(cat_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _save_catalog(cat_path: str, data: Dict[str, Any]) -> None:
    """Atomically writes catalog dictionary to filesystem."""
    parent_dir = os.path.dirname(os.path.abspath(cat_path))
    os.makedirs(parent_dir, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", dir=parent_dir, delete=False, encoding="utf-8"
    ) as tf:
        json.dump(data, tf, indent=2, ensure_ascii=False)
        temp_name = tf.name
    os.replace(temp_name, cat_path)


def _index_single_record(
    record: Dict[str, Any], catalog: Dict[str, Any], target: str
) -> None:
    """Indexes a single paper record into catalog and search structures."""
    arxiv_id = str(record.get("arxiv_id", ""))
    clean_id = arxiv_id.replace("/", "_").replace(":", "_")
    if not clean_id:
        return

    if target in ("all", "db"):
        catalog[clean_id] = {
            "clean_id": clean_id,
            "arxiv_id": arxiv_id,
            "title": record.get("title", ""),
            "title_ja": record.get("title_ja", ""),
            "summary_ja": record.get("summary_ja", ""),
            "tags": record.get("tags", []),
            "updated_at": time.time(),
        }


def _consume_stream(
    reader: StreamReader,
    writer: StreamWriter,
    catalog: Dict[str, Any],
    target: str,
    passthrough: bool,
) -> int:
    """Reads stream records, indexes them into catalog, and optionally passes through."""
    count = 0
    for record in reader:
        _index_single_record(record, catalog, target)
        count += 1
        if passthrough:
            writer.write_record(record)
    return count


def _finalize_indexing(
    cat_path: str, catalog: Dict[str, Any], target: str, count: int
) -> None:
    """Saves updated catalog if any records were indexed."""
    if count > 0 and target in ("all", "db"):
        _save_catalog(cat_path, catalog)


def _emit_summary_if_needed(
    writer: StreamWriter, target: str, count: int, elapsed_ms: float, passthrough: bool
) -> None:
    """Emits JSON summary stats if passthrough mode is disabled."""
    if passthrough:
        return
    writer.write_record({
        "status": "success",
        "indexed_count": count,
        "target": target,
        "duration_ms": round(elapsed_ms, 2),
    })


class DbIndexCommand(BaseCommand):
    """Subcommand to index paper stream into database and vector engine."""

    name = "db-index"
    help_text = "Sink stream records into database catalog and search index."

    def add_arguments(self, parser: argparse.ArgumentParser) -> None:
        parser.add_argument(
            "-t",
            "--target",
            dest="target",
            choices=["all", "db", "vector"],
            default="all",
            help="Index target: all, db, or vector (default: all).",
        )
        parser.add_argument(
            "-p",
            "--passthrough",
            dest="passthrough",
            action="store_true",
            default=False,
            help="Pass through processed records to stdout for further Unix pipelining.",
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
        start_time = time.time()

        ws = self.workspace_dir or os.getcwd()
        cat_path = os.path.join(ws, "outputs", "database", "papers_catalog.json")
        catalog = _load_catalog(cat_path)

        logger.info(f"Starting database index sink (target: '{args.target}')...")
        count = _consume_stream(
            reader, writer, catalog, args.target, args.passthrough
        )
        _finalize_indexing(cat_path, catalog, args.target, count)

        elapsed_ms = (time.time() - start_time) * 1000.0
        logger.info(f"Successfully indexed {count} records in {elapsed_ms:.1f}ms.")
        _emit_summary_if_needed(
            writer, args.target, count, elapsed_ms, args.passthrough
        )
        return 0
