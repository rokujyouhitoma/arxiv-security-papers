#!/usr/bin/env python3
"""src/core/settings/metadata.py: Database scope and metadata introspection utilities.

Zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional


def resolve_database_scopes(databases: Dict[str, Dict[str, Any]]) -> Dict[str, str]:
    """Returns mapping of scope name to description for all configured scopes."""
    scopes: Dict[str, str] = {
        "all": "All federated databases and scopes",
    }
    for s_name, cfg in databases.items():
        if s_name != "default":
            scopes[s_name] = str(cfg.get("DESCRIPTION", s_name))
    return scopes


def resolve_all_configured_databases(
    databases: Dict[str, Dict[str, Any]],
) -> List[str]:
    """Returns list of all non-default configured database scope names."""
    return [name for name in databases.keys() if name != "default"]


def resolve_database_metadata(
    scope_name: str,
    databases: Dict[str, Dict[str, Any]],
    default_tz: str = "UTC",
    default_use_tz: bool = True,
    default_display_tz: str = "Asia/Tokyo",
) -> Dict[str, Any]:
    """Returns UI and introspection metadata for a database scope."""
    cfg = databases.get(scope_name, {})
    return {
        "name": scope_name,
        "description": cfg.get("DESCRIPTION", scope_name),
        "icon": cfg.get("ICON", "🗄️"),
        "short_label": cfg.get("SHORT_LABEL", scope_name),
        "display_name": cfg.get("DISPLAY_NAME", scope_name),
        "category": cfg.get("CATEGORY", cfg.get("DESCRIPTION", "Database Store")),
        "engine": cfg.get("ENGINE", "unknown"),
        "location": cfg.get("LOCATION", ""),
        "type": cfg.get("TYPE", "Unknown"),
        "time_zone": cfg.get("TIME_ZONE", default_tz),
        "use_tz": cfg.get("USE_TZ", default_use_tz),
        "display_time_zone": cfg.get("DISPLAY_TIME_ZONE", default_display_tz),
    }


def resolve_table_scope(
    tname: str,
    databases: Dict[str, Dict[str, Any]],
) -> str:
    """Resolves which database scope a table belongs to based on settings."""
    for s_name, cfg in databases.items():
        tables = cfg.get("TABLES", {})
        if tname in tables:
            return s_name
    return "default"


def resolve_table_type(
    tname: str,
    databases: Dict[str, Dict[str, Any]],
) -> Optional[str]:
    """Retrieves declared table type from settings if explicitly configured."""
    for cfg in databases.values():
        tables = cfg.get("TABLES", {})
        if tname in tables:
            val = tables[tname].get("TYPE")
            return str(val) if val else None
    return None
