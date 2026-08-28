#!/usr/bin/env python3
"""
Analytics CLI Command Line Interface.
Provides entrypoint to run batch metrics pre-aggregation.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import List, Optional

from .aggregator import AnalyticsAggregator
from .storage import AnalyticsStorage


def build_parser() -> argparse.ArgumentParser:
    """Builds argument parser for Analytics CLI."""
    parser = argparse.ArgumentParser(
        prog="analytics",
        description="Pre-Aggregated Analytics Engine & High-Speed Storage CLI",
    )
    subparsers = parser.add_subparsers(dest="command", help="Sub-commands")

    # Command: aggregate
    agg_parser = subparsers.add_parser(
        "aggregate", help="Run full batch pre-calculation of strategic KPIs"
    )
    agg_parser.add_argument(
        "--workspace-dir",
        type=str,
        default=None,
        help="Path to workspace root directory",
    )

    # Command: show
    show_parser = subparsers.add_parser(
        "show", help="Display current pre-aggregated snapshot metrics"
    )
    show_parser.add_argument(
        "--workspace-dir",
        type=str,
        default=None,
        help="Path to workspace root directory",
    )

    return parser


def main(args: Optional[List[str]] = None) -> int:
    """Main CLI entrypoint."""
    parser = build_parser()
    parsed = parser.parse_args(args)

    if not parsed.command or parsed.command == "aggregate":
        aggregator = AnalyticsAggregator(workspace_dir=getattr(parsed, "workspace_dir", None))
        metrics = aggregator.aggregate_all()
        print("✅ Batch pre-aggregation completed.")
        print(json.dumps(metrics, indent=2, ensure_ascii=False))
        return 0
    elif parsed.command == "show":
        storage = AnalyticsStorage(workspace_dir=getattr(parsed, "workspace_dir", None))
        loaded_metrics = storage.load_latest_metrics()
        if loaded_metrics is None:
            print("⚠️ No analytics snapshot found. Run 'aggregate' first.")
            return 1
        print(json.dumps(loaded_metrics, indent=2, ensure_ascii=False))
        return 0
    else:
        parser.print_help()
        return 1


if __name__ == "__main__":
    sys.exit(main())
