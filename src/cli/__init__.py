"""src/cli/__init__.py

Universal Management CLI framework conforming to DSN-24.
Pure Python, zero external dependencies.
"""

from __future__ import annotations

from .base import BaseCommand
from .dispatcher import CommandDispatcher

__all__ = ["BaseCommand", "CommandDispatcher"]
