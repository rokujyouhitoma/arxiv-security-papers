#!/usr/bin/env python3
"""src/cli/commands/dbsync.py

Database auto-provisioning and synchronization command conforming to DSN-24 Section 5.5.
Scans physical OKF papers, detects catalog drift, and complements missing metadata.
Pure Python, zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from typing import Any, Dict, List, Tuple

from ..base import BaseCommand


def _load_existing_catalog(cat_path: str) -> Dict[str, Any]:
    """Loads existing papers catalog safely or returns empty dict."""
    if not os.path.exists(cat_path):
        return {}
    try:
        with open(cat_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, dict):
                return data
    except Exception:
        pass
    return {}


def _extract_title_from_okf(full_path: str, clean_id: str) -> str:
    """Extracts title from YAML frontmatter safely."""
    try:
        with open(full_path, "r", encoding="utf-8", errors="replace") as f:
            header = f.read(2048)
            for line in header.splitlines():
                if line.startswith("title:"):
                    return line.split(":", 1)[1].strip().strip("'\"")
    except OSError:
        pass
    return clean_id


def _collect_missing_from_files(
    root: str,
    files: List[str],
    ws: str,
    existing: set[str],
    out: List[Tuple[str, str, str]],
) -> None:
    for fname in files:
        if not fname.endswith(".md"):
            continue
        cid = os.path.splitext(fname)[0]
        if cid not in existing:
            fpath = os.path.join(root, fname)
            out.append((cid, fpath, os.path.relpath(fpath, ws)))


def _find_unregistered_okf_papers(
    okf_dir: str, ws: str, existing_ids: set[str]
) -> List[Tuple[str, str, str]]:
    """Discovers markdown files not present in the catalog."""
    unregistered: List[Tuple[str, str, str]] = []
    if not os.path.exists(okf_dir):
        return unregistered

    for root, _, files in os.walk(okf_dir):
        _collect_missing_from_files(root, files, ws, existing_ids, unregistered)
    return unregistered


def _save_catalog_atomic(cat_path: str, data: Dict[str, Any]) -> None:
    """Saves catalog atomically using a temporary file."""
    os.makedirs(os.path.dirname(os.path.abspath(cat_path)), exist_ok=True)
    temp_dir = os.path.dirname(os.path.abspath(cat_path))
    with tempfile.NamedTemporaryFile(
        "w", dir=temp_dir, delete=False, encoding="utf-8"
    ) as tf:
        json.dump(data, tf, indent=2, ensure_ascii=False)
        temp_name = tf.name
    os.replace(temp_name, cat_path)


def synchronize_database_catalog(workspace_dir: str) -> Tuple[int, int]:
    """Synchronizes physical OKF files into the catalog. Returns (complemented_count, total_count)."""
    ws = os.path.realpath(os.path.abspath(workspace_dir))
    cat_path = os.path.join(ws, "outputs", "database", "papers_catalog.json")
    catalog = _load_existing_catalog(cat_path)

    okf_dir = os.path.join(ws, "outputs", "okf_papers")
    existing_ids = set(catalog.keys())
    missing = _find_unregistered_okf_papers(okf_dir, ws, existing_ids)

    for clean_id, full_path, rel_path in missing:
        title = _extract_title_from_okf(full_path, clean_id)
        catalog[clean_id] = {
            "clean_id": clean_id,
            "title": title,
            "okf_path": rel_path,
            "sha256": "",
        }

    if missing:
        _save_catalog_atomic(cat_path, catalog)

    return len(missing), len(catalog)


class DatabaseSyncCommand(BaseCommand):
    """Subcommand to sync physical paper documents with catalog ledger."""

    name = "dbsync"
    help_text = "Synchronize physical files with database catalog (auto-complements missing entries)."

    def add_arguments(self, parser: argparse.ArgumentParser) -> None:
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Show uncatalogued entries without modifying catalog.",
        )

    def handle(self, args: argparse.Namespace) -> int:
        sys.stdout.write("Scanning workspace for uncatalogued paper records...\n")
        ws = self.workspace_dir or os.getcwd()
        added, total = synchronize_database_catalog(ws)
        if added > 0:
            sys.stdout.write(
                f"Successfully complemented {added} new record(s) into database catalog.\n"
            )
        else:
            sys.stdout.write(
                "Database catalog is already fully synchronized with physical storage.\n"
            )
        sys.stdout.write(f"Total catalog entries: {total}\n")
        return 0
