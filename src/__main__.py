#!/usr/bin/env python3
"""Unified Application Entry Point for arxiv-security-papers.

Executing `python -m src` or running `python src/__main__.py` launches the
Universal Autonomous Intelligence Lifecycle Orchestrator by default, while
supporting subcommands for individual tools (pipeline, spider, search, web, mcp).
"""

import sys

from orchestrator.cli import main

if __name__ == "__main__":
    sys.exit(main())
