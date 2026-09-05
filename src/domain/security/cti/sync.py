#!/usr/bin/env python3
"""
MITRE ATT&CK CTI Synchronization Manager.
Downloads, validates, and populates SQLite CTI Catalog from MITRE/CTI repository.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
import urllib.request
from typing import Any, Dict, Optional

from .parser import STIXCTIParser
from .storage import CTICatalogStorage

logger = logging.getLogger(__name__)


class CTISyncManager:
    """Manages fetching, parsing, and persisting MITRE ATT&CK CTI data."""

    DEFAULT_URL = (
        "https://raw.githubusercontent.com/mitre/cti/master/"
        "enterprise-attack/enterprise-attack.json"
    )

    def __init__(self, storage: Optional[CTICatalogStorage] = None) -> None:
        self.storage = storage or CTICatalogStorage()
        self.parser = STIXCTIParser()

    def sync_from_url(
        self, url: Optional[str] = None, timeout: float = 120.0
    ) -> Dict[str, int]:
        """
        Downloads the STIX bundle JSON from GitHub and ingests into SQLite catalog.
        Uses a temporary file to minimize memory overhead during streaming.
        """
        target_url = url or self.DEFAULT_URL
        logger.info("Starting MITRE CTI download from %s", target_url)

        temp_fd, temp_path = tempfile.mkstemp(prefix="mitre_cti_", suffix=".json")
        os.close(temp_fd)

        try:
            self._download_file(target_url, temp_path, timeout)
            summary = self.sync_from_file(temp_path)
            logger.info("Successfully ingested MITRE CTI: %s", summary)
            return summary
        finally:
            if os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except OSError:
                    pass

    def sync_from_file(self, file_path: str) -> Dict[str, int]:
        """Loads and parses a local STIX JSON file into SQLite catalog."""
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"CTI STIX file not found: {file_path}")

        logger.info("Loading CTI JSON from %s", file_path)
        with open(file_path, "r", encoding="utf-8") as f:
            bundle_data: Dict[str, Any] = json.load(f)

        return self.sync_from_bundle(bundle_data)

    def sync_from_bundle(self, bundle_data: Dict[str, Any]) -> Dict[str, int]:
        """Parses in-memory STIX bundle dictionary and persists to SQLite."""
        tactics, techniques, mitigations, relationships = self.parser.parse_bundle(
            bundle_data
        )

        if tactics:
            self.storage.insert_tactics(tactics)
        if techniques:
            self.storage.insert_techniques(techniques)
        if mitigations:
            self.storage.insert_mitigations(mitigations)
        if relationships:
            self.storage.insert_relationships(relationships)

        return {
            "tactics": len(tactics),
            "techniques": len(techniques),
            "mitigations": len(mitigations),
            "relationships": len(relationships),
        }

    def _download_file(self, url: str, output_path: str, timeout: float) -> None:
        """Streams URL content into output path."""
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "arxiv-security-papers-cti-sync/1.0"},
        )
        with urllib.request.urlopen(req, timeout=timeout) as response:
            with open(output_path, "wb") as out_f:
                while True:
                    chunk = response.read(65536)
                    if not chunk:
                        break
                    out_f.write(chunk)
