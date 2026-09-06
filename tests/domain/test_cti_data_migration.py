#!/usr/bin/env python3
"""
Unit tests for MITRE ATT&CK CTI data migration and dataset export/import.
Verifies zero-data-loss portable migration between storage backends powered by src/database.
"""

import os
import tempfile
from typing import Generator

import pytest

from domain.security.cti.storage import CTICatalogStorage


@pytest.fixture
def temp_cti_db_paths() -> Generator[tuple[str, str], None, None]:
    with tempfile.TemporaryDirectory() as tmpdir:
        src_path = os.path.join(tmpdir, "source_cti.db")
        dst_path = os.path.join(tmpdir, "dest_cti.db")
        yield src_path, dst_path


def test_cti_data_export_and_import_migration(
    temp_cti_db_paths: tuple[str, str],
) -> None:
    src_path, dst_path = temp_cti_db_paths

    # 1. Initialize source and populate with test CTI entities
    src_storage = CTICatalogStorage(db_path=src_path)
    src_storage.insert_tactics(
        [
            {
                "tactic_id": "TA0001",
                "shortname": "initial-access",
                "name": "Initial Access",
                "description": "The adversary is trying to get into your network.",
                "external_url": "https://attack.mitre.org/tactics/TA0001",
            }
        ]
    )
    src_storage.insert_techniques(
        [
            {
                "technique_id": "T1190",
                "name": "Exploit Public-Facing Application",
                "description": "Adversaries may attempt to exploit vulnerabilities.",
                "tactics": ["initial-access"],
                "stix_id": "attack-pattern--1190",
            }
        ]
    )
    src_storage.insert_mitigations(
        [
            {
                "mitigation_id": "M1018",
                "name": "User Account Management",
                "description": "Manage the creation, modification, and deletion of user accounts.",
                "external_url": "https://attack.mitre.org/mitigations/M1018",
                "stix_id": "course-of-action--1018",
            }
        ]
    )
    src_storage.insert_relationships([("M1018", "T1190", "mitigates")])

    src_counts = src_storage.count_summary()
    assert src_counts["tactics"] == 1
    assert src_counts["techniques"] == 1
    assert src_counts["mitigations"] == 1
    assert src_counts["relationships"] == 1

    # 2. Export dataset into portable structured dictionary
    dataset = src_storage.export_catalog_dataset()
    assert "cti_tactics" in dataset
    assert "cti_techniques" in dataset
    assert "cti_mitigations" in dataset
    assert "cti_relationships" in dataset
    assert len(dataset["cti_tactics"]) == 1
    assert dataset["cti_tactics"][0]["tactic_id"] == "TA0001"

    # 3. Import dataset into clean destination storage
    dst_storage = CTICatalogStorage(db_path=dst_path)
    restored_count = dst_storage.import_catalog_dataset(dataset)
    assert restored_count >= 4

    dst_counts = dst_storage.count_summary()
    assert dst_counts == src_counts

    # 4. Verify FTS5 full-text index was rebuilt automatically
    search_hits = dst_storage.search_techniques("vulnerabilities", limit=5)
    assert len(search_hits) == 1
    assert search_hits[0]["technique_id"] == "T1190"
    assert search_hits[0]["name"] == "Exploit Public-Facing Application"
