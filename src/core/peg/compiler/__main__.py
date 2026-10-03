#!/usr/bin/env python3
"""Main entry point for running core.peg.compiler as a module."""

import sys

from core.peg.compiler.cli import run_cli

if __name__ == "__main__":
    sys.exit(run_cli())
