#!/usr/bin/env python3
"""src/settings.py: System-wide configuration and centralized database registry (SSOT).

Conforms to DSN-24 and DSN-05 Section 21. Zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

import os
from typing import Any, Dict

BASE_DIR = os.path.realpath(
    os.path.abspath(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)

TIME_ZONE: str = "Asia/Tokyo"
USE_TZ: bool = True
DATABASE_TIME_ZONE: str = "UTC"
DISPLAY_TIME_ZONE: str = TIME_ZONE
DB_TIME_ZONE: str = DATABASE_TIME_ZONE

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
        "DISPLAY_NAME": "ArXiv Security Core DB",
        "SHORT_LABEL": "Virtual Tables",
        "ICON": "🗃️",
        "CATEGORY": "Core arXiv Papers & Plain-text Virtual Tables",
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
        "DISPLAY_NAME": "MITRE ATT&CK & CTI Catalog",
        "SHORT_LABEL": "ATT&CK & CTI",
        "ICON": "🛡️",
        "CATEGORY": "Threat Intelligence & Taxonomy",
        "ENGINE": "multi_vdb",
        "LOCATION": os.path.join(
            BASE_DIR, "outputs", "database", "catalog", "cti_catalog.vdb"
        ),
        "TYPE": "Physical (VDB)",
        "TABLES": {
            "cti_techniques": {"TYPE": "Physical (VDB)"},
            "cisa_kev_vulnerabilities": {"TYPE": "Physical (VDB)"},
            "cti_cwes": {
                "ENGINE": "csv_table",
                "LOCATION": os.path.join(
                    BASE_DIR, "outputs", "database", "catalog", "cti_cwes.csv"
                ),
                "PRIMARY_KEY": "cwe_id",
                "TYPE": "Virtual (CSV)",
            },
            "cti_cwe_relationships": {"TYPE": "Physical (VDB)"},
            "cti_mitigations": {"TYPE": "Physical (VDB)"},
            "cti_relationships": {"TYPE": "Physical (VDB)"},
            "cti_tactics": {"TYPE": "Physical (VDB)"},
        },
    },
    "graph_db": {
        "DESCRIPTION": "Security Knowledge Graph & SKO (MultiTable VDB)",
        "DISPLAY_NAME": "Property Graph & Ontology Store",
        "SHORT_LABEL": "Knowledge Graph & SKO",
        "ICON": "🕸️",
        "CATEGORY": "Security Knowledge Graph & SKO",
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
        "DISPLAY_NAME": "Analytics & Trends Store",
        "SHORT_LABEL": "Telemetry & Trends",
        "ICON": "📊",
        "CATEGORY": "Telemetry, Trends & Strategic KPIs",
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
    "spider_execution_db": {
        "DESCRIPTION": "Spider Crawler Autonomous Execution & Status Logs (MultiTable VDB)",
        "DISPLAY_NAME": "Spider Crawler Execution DB",
        "SHORT_LABEL": "Crawler Execution Logs",
        "ICON": "🕷️",
        "CATEGORY": "Spider Crawlers & Execution Logs",
        "ENGINE": "multi_vdb",
        "LOCATION": os.path.join(
            BASE_DIR, "outputs", "database", "spider_execution.vdb"
        ),
        "TYPE": "Physical (VDB)",
        "TABLES": {
            "spider_execution_logs": {"TYPE": "Physical (VDB)"},
        },
    },
}


__all__ = [
    "BASE_DIR",
    "TIME_ZONE",
    "USE_TZ",
    "DATABASE_TIME_ZONE",
    "DISPLAY_TIME_ZONE",
    "DB_TIME_ZONE",
    "DATABASES",
]
