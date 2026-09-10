#!/usr/bin/env python3
"""src/settings.py: System-wide configuration and centralized database registry (SSOT).

Conforms to DSN-24 and DSN-05 Section 21. Zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

import os
from typing import Any, Dict, Optional

BASE_DIR = os.path.realpath(
    os.path.abspath(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)

DATABASES: Dict[str, Dict[str, Any]] = {
    "default": {
        "ENGINE": "binary_vdb",
        "LOCATION": ":memory:",
        "TYPE": "In-Memory",
        "DESCRIPTION": "Default scratchpad in-memory database",
        "TABLES": {
            "main": {"TYPE": "In-Memory"},
        },
    },
    "arxiv_security_db": {
        "DESCRIPTION": "Core arXiv Papers & Plain-text Virtual Tables",
        "TABLES": {
            "okf_papers": {
                "ENGINE": "file_plain_text",
                "LOCATION": os.path.join(BASE_DIR, "outputs", "okf_papers"),
                "PATTERNS": ["*.md"],
                "TYPE": "Virtual (Markdown)",
                "PRIMARY_KEY": "clean_id",
            },
            "processed_papers": {
                "ENGINE": "json_table",
                "LOCATION": os.path.join(BASE_DIR, "processed_papers.json"),
                "TYPE": "Virtual (JSON)",
                "PRIMARY_KEY": "clean_id",
            },
            "raw_papers": {
                "ENGINE": "file_plain_text",
                "LOCATION": os.path.join(BASE_DIR, "outputs", "raw_data"),
                "PATTERNS": ["*.txt"],
                "TYPE": "Virtual (Text)",
                "PRIMARY_KEY": "clean_id",
            },
        },
    },
    "cti_catalog_db": {
        "DESCRIPTION": "MITRE ATT&CK & CTI Catalog (MultiTable VDB)",
        "ENGINE": "multi_vdb",
        "LOCATION": os.path.join(
            BASE_DIR, "outputs", "database", "catalog", "cti_catalog.vdb"
        ),
        "TYPE": "Physical (VDB)",
        "TABLES": {
            "cti_techniques": {"TYPE": "Physical (VDB)"},
            "cisa_kev_vulnerabilities": {"TYPE": "Physical (VDB)"},
            "cti_mitigations": {"TYPE": "Physical (VDB)"},
            "cti_relationships": {"TYPE": "Physical (VDB)"},
            "cti_tactics": {"TYPE": "Physical (VDB)"},
        },
    },
    "graph_db": {
        "DESCRIPTION": "Security Knowledge Graph & SKO (MultiTable VDB)",
        "ENGINE": "multi_vdb",
        "LOCATION": os.path.join(
            BASE_DIR, "outputs", "database", "knowledge_graph.vdb"
        ),
        "TYPE": "Physical (VDB)",
        "TABLES": {
            "vertices": {"TYPE": "Physical (VDB)"},
            "edges": {"TYPE": "Physical (VDB)"},
        },
    },
    "analytics_db": {
        "DESCRIPTION": "Telemetry, Trends & Strategic KPIs (MultiTable VDB)",
        "ENGINE": "multi_vdb",
        "LOCATION": os.path.join(
            BASE_DIR, "outputs", "database", "analytics", "analytics.vdb"
        ),
        "TYPE": "Physical (VDB)",
        "TABLES": {
            "threat_trends": {"TYPE": "Physical (VDB)"},
            "strategic_kpis": {"TYPE": "Physical (VDB)"},
            "metrics_history": {"TYPE": "Physical (VDB)"},
            "latest_snapshot": {"TYPE": "Physical (VDB)"},
            "papers": {"TYPE": "Physical (VDB)"},
        },
    },
}


def get_database_scopes() -> Dict[str, str]:
    """Returns mapping of scope name to description for all configured scopes."""
    scopes: Dict[str, str] = {
        "all": "All federated databases and scopes",
    }
    for s_name, cfg in DATABASES.items():
        if s_name != "default":
            scopes[s_name] = str(cfg.get("DESCRIPTION", s_name))
    return scopes


def get_table_scope_from_settings(tname: str) -> str:
    """Resolves which database scope a table belongs to based on settings."""
    for s_name, cfg in DATABASES.items():
        tables = cfg.get("TABLES", {})
        if tname in tables:
            return s_name
    return "default"


def get_table_type_from_settings(tname: str) -> Optional[str]:
    """Retrieves declared table type from settings if explicitly configured."""
    for cfg in DATABASES.values():
        tables = cfg.get("TABLES", {})
        if tname in tables:
            val = tables[tname].get("TYPE")
            return str(val) if val else None
    return None
