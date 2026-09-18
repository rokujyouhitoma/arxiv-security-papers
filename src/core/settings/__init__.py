#!/usr/bin/env python3
"""src/core/settings: Settings and metadata introspection utility package.

Zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

from core.settings.metadata import (
    get_all_configured_databases,
    get_database_metadata,
    get_database_scopes,
    get_table_scope_from_settings,
    get_table_type_from_settings,
    resolve_all_configured_databases,
    resolve_database_metadata,
    resolve_database_scopes,
    resolve_table_scope,
    resolve_table_type,
)

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
