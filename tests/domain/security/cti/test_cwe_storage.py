#!/usr/bin/env python3
"""Unit tests for CTICatalogStorage CWE tables and hybrid taxonomy resolution."""

from __future__ import annotations

from domain.security.cti.storage import CTICatalogStorage
from domain.security.taxonomy.cwe import get_cwe_definition


def test_cwe_storage_crud_and_search() -> None:
    """Verifies CRUD, Top 25 filtering, and keyword search on cti_cwes table."""
    storage = CTICatalogStorage(":memory:")

    # Initial count is zero
    assert storage.get_cwe_count() == 0

    # 1. Insert single entry
    storage.insert_cwe(
        {
            "cwe_id": "79",
            "name": "Cross-site Scripting",
            "abstraction": "Class",
            "description": "Improper input neutralization during web page generation",
            "top25_rank": 2,
            "is_top25": True,
            "status": "Incomplete",
            "mitigations": [
                {
                    "phase": "Implementation",
                    "strategy": "Output Encoding",
                    "description": "Context-aware HTML escaping",
                }
            ],
            "extended_meta": {"likelihood": "High"},
        }
    )

    assert storage.get_cwe_count() == 1
    cwe79 = storage.get_cwe("CWE-79")
    assert cwe79 is not None
    assert cwe79["cwe_id"] == "CWE-79"
    assert cwe79["name"] == "Cross-site Scripting"
    assert cwe79["is_top25"] is True
    assert cwe79["top25_rank"] == 2
    assert len(cwe79["mitigations"]) == 1

    # Also retrievable via numeric ID "79"
    assert storage.get_cwe("79") is not None

    # 2. Bulk insert
    more_cwes = [
        {
            "cwe_id": "CWE-89",
            "name": "SQL Injection",
            "abstraction": "Class",
            "description": "Improper neutralization in SQL command",
            "top25_rank": 3,
            "is_top25": True,
        },
        {
            "cwe_id": "CWE-999",
            "name": "Non-critical Weakness",
            "abstraction": "Variant",
            "description": "Edge case flaw",
            "is_top25": False,
        },
    ]
    inserted = storage.bulk_insert_cwes(more_cwes)
    assert inserted == 2
    assert storage.get_cwe_count() == 3

    # 3. Top 25 filter
    top25_list = storage.get_all_cwes(top25_only=True)
    assert len(top25_list) == 2
    top25_ids = [c["cwe_id"] for c in top25_list]
    assert "CWE-79" in top25_ids
    assert "CWE-89" in top25_ids
    assert "CWE-999" not in top25_ids

    # 4. Search
    search_sql = storage.search_cwes("SQL")
    assert len(search_sql) == 1
    assert search_sql[0]["cwe_id"] == "CWE-89"

    search_all = storage.search_cwes("CWE")
    assert len(search_all) == 3


def test_cwe_relationships_hierarchy() -> None:
    """Verifies parent/child hierarchy traversal via cti_cwe_relationships."""
    storage = CTICatalogStorage(":memory:")

    # 79 (XSS) is ChildOf 74 (Injection)
    # 89 (SQLi) is ChildOf 74 (Injection)
    relationships = [
        ("CWE-79", "CWE-74", "ChildOf"),
        ("CWE-89", "CWE-74", "ChildOf"),
        ("CWE-80", "CWE-79", "ChildOf"),  # Basic XSS is ChildOf XSS
    ]
    storage.bulk_insert_cwe_relationships(relationships)

    # Children of CWE-74
    children_74 = storage.get_cwe_children("CWE-74")
    assert len(children_74) == 2
    assert "CWE-79" in children_74
    assert "CWE-89" in children_74

    # Children of CWE-79
    children_79 = storage.get_cwe_children("79")
    assert children_79 == ["CWE-80"]

    # Parents of CWE-79
    parents_79 = storage.get_cwe_parents("CWE-79")
    assert parents_79 == ["CWE-74"]

    # Count summary verification
    counts = storage.count_summary()
    assert counts["cwes"] == 0
    assert counts["cwe_relationships"] == 3


def test_hybrid_cwe_definition_resolver() -> None:
    """Verifies get_cwe_definition prioritizes static recipes and falls back to storage."""
    storage = CTICatalogStorage(":memory:")

    # 1. Static high-fidelity recipe (e.g. CWE-89 has Semgrep pattern in CWE_DEFENSE_MAP)
    def_89 = get_cwe_definition("CWE-89", storage=storage)
    assert def_89 is not None
    assert def_89["name"] == "SQL Injection"
    assert "semgrep_pattern" in def_89
    assert len(def_89["semgrep_pattern"]) > 0

    # 2. Unknown in static, but present in CTICatalogStorage
    storage.insert_cwe(
        {
            "cwe_id": "CWE-1234",
            "name": "Custom Firmware Weakness",
            "description": "Hardware glitching flaw",
            "abstraction": "Base",
            "mitigations": [{"description": "Use hardware fault detection shielding."}],
        }
    )
    def_1234 = get_cwe_definition("CWE-1234", storage=storage)
    assert def_1234 is not None
    assert def_1234["name"] == "Custom Firmware Weakness"
    assert def_1234["secure_alternative"] == "Use hardware fault detection shielding."

    # 3. Non-existent anywhere
    assert get_cwe_definition("CWE-99999", storage=storage) is None
