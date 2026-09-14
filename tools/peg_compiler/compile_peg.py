#!/usr/bin/env python3
"""
CLI wrapper executable for DSN-25 Packrat PEG Ahead-of-Time Compiler.
Usage: python tools/peg_compiler/compile_peg.py grammar.peg -o generated_parser.py
"""

import sys
from pathlib import Path

# Add src to sys.path
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SRC_DIR = REPO_ROOT / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from core.structures.peg_compiler.cli import run_cli

if __name__ == "__main__":
    sys.exit(run_cli())
