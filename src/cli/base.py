#!/usr/bin/env python3
"""src/cli/base.py

Abstract base class for management CLI commands conforming to DSN-24 Section 3.2.
Pure Python, zero external dependencies.
"""

from __future__ import annotations

import abc
import argparse
from typing import Optional


class BaseCommand(abc.ABC):
    """Abstract base class for all management CLI commands."""

    name: str = ""
    help_text: str = ""

    def __init__(self, workspace_dir: Optional[str] = None) -> None:
        self.workspace_dir = workspace_dir

    @abc.abstractmethod
    def add_arguments(self, parser: argparse.ArgumentParser) -> None:
        """Configures command-specific CLI flags and positional arguments."""
        pass

    def create_parser(self) -> argparse.ArgumentParser:
        """Creates an ArgumentParser preconfigured with this command's arguments."""
        parser = argparse.ArgumentParser(
            prog=f"manage.py {self.name}", description=self.help_text
        )
        self.add_arguments(parser)
        return parser

    @abc.abstractmethod
    def handle(self, args: argparse.Namespace) -> int:
        """Executes the command logic.

        Returns exit code (0 for success).
        """
        pass
