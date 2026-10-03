#!/usr/bin/env python3
"""Backward-compatibility main entry point for core.structures.peg_compiler."""

import sys

from core.peg.compiler.cli import run_cli

if __name__ == "__main__":
    sys.exit(run_cli())
