#!/usr/bin/env python3
"""src/cli/dispatcher.py

Universal management CLI argument parser and command dispatcher.
Conforms to DSN-24 Section 3.1, pure Python, zero external dependencies.
"""

from __future__ import annotations

import argparse
import sys
from typing import List, Optional, Tuple

from .registry import get_command_class, list_available_commands


def _create_main_parser() -> argparse.ArgumentParser:
    """Builds top-level parser with global options."""
    parser = argparse.ArgumentParser(
        prog="manage.py",
        description="Unified Management CLI for arXiv Security Papers Platform (DSN-24).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--workspace-dir",
        dest="workspace_dir",
        default=None,
        help="Custom project workspace root directory.",
    )
    parser.add_argument(
        "subcommand",
        nargs="?",
        help="Command to run: " + ", ".join(list_available_commands()),
    )
    return parser


def _dispatch_subcommand(
    cmd_name: str, cmd_args: List[str], workspace_dir: Optional[str]
) -> int:
    """Instantiates and executes a registered subcommand."""
    cmd_cls = get_command_class(cmd_name)
    if not cmd_cls:
        available = ", ".join(list_available_commands())
        sys.stderr.write(f"Unknown command: '{cmd_name}'. Available: [{available}]\n")
        return 1

    command = cmd_cls(workspace_dir=workspace_dir)
    parser = argparse.ArgumentParser(
        prog=f"manage.py {cmd_name}",
        description=command.help_text,
    )
    command.add_arguments(parser)
    parsed = parser.parse_args(cmd_args)
    return command.handle(parsed)


def _extract_subcommand_args(
    args_list: List[str], default_ws: Optional[str]
) -> Tuple[str, List[str], Optional[str]]:
    cmd_name = args_list[0]
    cmd_args = args_list[1:]
    ws_dir = default_ws
    if cmd_name == "--workspace-dir" and len(cmd_args) >= 2:
        ws_dir = cmd_args[0]
        cmd_name = cmd_args[1]
        cmd_args = cmd_args[2:]
    return cmd_name, cmd_args, ws_dir


class CommandDispatcher:
    """Dispatches command-line arguments to registered subcommand handlers."""

    def __init__(self, workspace_dir: Optional[str] = None) -> None:
        self.workspace_dir = workspace_dir

    def run(self, argv: Optional[List[str]] = None) -> int:
        """Parses argv and routes to the appropriate subcommand."""
        args_list = argv if argv is not None else sys.argv[1:]

        if not args_list or args_list[0] in ("-h", "--help"):
            _create_main_parser().print_help()
            return 0

        cmd_name, cmd_args, ws_dir = _extract_subcommand_args(
            args_list, self.workspace_dir
        )
        return _dispatch_subcommand(cmd_name, cmd_args, ws_dir)
