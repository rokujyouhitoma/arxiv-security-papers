#!/usr/bin/env python3
"""src/cli/registry.py

Subcommand registry for universal management CLI conforming to DSN-24.
Pure Python, zero external dependencies, lazy import.
"""

from __future__ import annotations

from typing import Callable, Dict, List, Optional, Type

from .base import BaseCommand

_COMMAND_LOADERS: Dict[str, Callable[[], Type[BaseCommand]]] = {}


def register_command(name: str, loader: Callable[[], Type[BaseCommand]]) -> None:
    """Registers a subcommand loader function."""
    _COMMAND_LOADERS[name] = loader


def get_command_class(name: str) -> Optional[Type[BaseCommand]]:
    """Retrieves the command class by name, invoking lazy loader."""
    _ensure_builtins()
    loader = _COMMAND_LOADERS.get(name)
    return loader() if loader else None


def list_available_commands() -> List[str]:
    """Returns sorted list of all registered subcommand names."""
    _ensure_builtins()
    return sorted(_COMMAND_LOADERS.keys())


def _load_dbshell() -> Type[BaseCommand]:
    from .commands.dbshell import DatabaseShellCommand

    return DatabaseShellCommand


def _load_tables() -> Type[BaseCommand]:
    from .commands.tables import ShowTablesCommand

    return ShowTablesCommand


def _load_inspect() -> Type[BaseCommand]:
    from .commands.inspect import InspectTableCommand

    return InspectTableCommand


def _load_dbsync() -> Type[BaseCommand]:
    from .commands.dbsync import DatabaseSyncCommand

    return DatabaseSyncCommand


_BUILTINS_REGISTERED = False


def _ensure_builtins() -> None:
    global _BUILTINS_REGISTERED
    if _BUILTINS_REGISTERED:
        return
    _COMMAND_LOADERS["dbshell"] = _load_dbshell
    _COMMAND_LOADERS["tables"] = _load_tables
    _COMMAND_LOADERS["inspect"] = _load_inspect
    _COMMAND_LOADERS["dbsync"] = _load_dbsync
    _BUILTINS_REGISTERED = True
