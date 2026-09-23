#!/usr/bin/env python3
"""src/cli.py

Direct execution CLI entrypoint located under src/.
Delegates command resolution to CommandDispatcher conforming to DSN-24 and DSN-30.
"""

from __future__ import annotations

import os
import sys

current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

workspace_root = os.path.dirname(current_dir)

from cli.dispatcher import CommandDispatcher  # noqa: E402


def main() -> int:
    dispatcher = CommandDispatcher(workspace_dir=workspace_root)
    return dispatcher.run()


if __name__ == "__main__":
    sys.exit(main())
