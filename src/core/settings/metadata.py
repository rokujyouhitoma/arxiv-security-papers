#!/usr/bin/env python3
"""src/core/settings/metadata.py: Database scope and metadata introspection utilities.

Zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

import settings


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


def get_database_scopes(
    databases: Optional[Dict[str, Dict[str, Any]]] = None,
) -> Dict[str, str]:
    """Returns mapping of scope name to description for all configured scopes."""
    target_dbs = databases if databases is not None else settings.DATABASES
    return resolve_database_scopes(target_dbs)


def get_all_configured_databases(
    databases: Optional[Dict[str, Dict[str, Any]]] = None,
) -> List[str]:
    """Returns list of all non-default configured database scope names."""
    target_dbs = databases if databases is not None else settings.DATABASES
    return resolve_all_configured_databases(target_dbs)


def get_database_metadata(
    scope_name: str,
    databases: Optional[Dict[str, Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """Returns UI and introspection metadata for a database scope."""
    target_dbs = databases if databases is not None else settings.DATABASES
    return resolve_database_metadata(
        scope_name=scope_name,
        databases=target_dbs,
        default_tz=settings.DATABASE_TIME_ZONE,
        default_use_tz=settings.USE_TZ,
        default_display_tz=settings.DISPLAY_TIME_ZONE,
    )


def get_table_scope_from_settings(
    tname: str,
    databases: Optional[Dict[str, Dict[str, Any]]] = None,
) -> str:
    """Resolves which database scope a table belongs to based on settings."""
    target_dbs = databases if databases is not None else settings.DATABASES
    return resolve_table_scope(tname=tname, databases=target_dbs)


def get_table_type_from_settings(
    tname: str,
    databases: Optional[Dict[str, Dict[str, Any]]] = None,
) -> Optional[str]:
    """Retrieves declared table type from settings if explicitly configured."""
    target_dbs = databases if databases is not None else settings.DATABASES
    return resolve_table_type(tname=tname, databases=target_dbs)


__all__ = [
    "resolve_database_scopes",
    "resolve_all_configured_databases",
    "resolve_database_metadata",
    "resolve_table_scope",
    "resolve_table_type",
    "get_database_scopes",
    "get_all_configured_databases",
    "get_database_metadata",
    "get_table_scope_from_settings",
    "get_table_type_from_settings",
]
