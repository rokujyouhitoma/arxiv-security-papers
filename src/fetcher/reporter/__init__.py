"""
Reporter package for 5-tier executive summaries, Mermaid diagrams, and catalog indexing.
"""

from .diagram_generator import generate_mermaid_mindmap
from .index_updater import update_index_and_log
from .summary_generator import (
    PAPER_META_CACHE,
    build_summary_table_md,
    generate_all_daily_summaries,
    generate_annual_summary,
    generate_monthly_summary,
    generate_per_run_summary,
    generate_quarterly_summary,
    get_paper_meta_cached,
)

__all__ = [
    "PAPER_META_CACHE",
    "get_paper_meta_cached",
    "build_summary_table_md",
    "generate_per_run_summary",
    "generate_all_daily_summaries",
    "generate_monthly_summary",
    "generate_quarterly_summary",
    "generate_annual_summary",
    "generate_mermaid_mindmap",
    "update_index_and_log",
]
