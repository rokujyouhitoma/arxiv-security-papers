#!/usr/bin/env python3
"""manage.py

Unified management CLI entrypoint for arXiv Security Papers platform.
Conforms to DSN-24, Django-style subcommand dispatcher, pure Python.
"""

from __future__ import annotations

import os
import sys

# Ensure src/ is on Python search path
current_dir = os.path.dirname(os.path.abspath(__file__))
src_dir = os.path.join(current_dir, "src")
if src_dir not in sys.path:
    sys.path.insert(0, src_dir)

from cli.dispatcher import CommandDispatcher  # noqa: E402


def main() -> int:
    dispatcher = CommandDispatcher(workspace_dir=current_dir)
    return dispatcher.run()


if __name__ == "__main__":
    sys.exit(main())
