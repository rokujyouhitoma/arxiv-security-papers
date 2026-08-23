#!/usr/bin/env python3
"""Main entry point when executing `python -m orchestrator`."""

import sys

from orchestrator.cli import main

if __name__ == "__main__":
    sys.exit(main())
