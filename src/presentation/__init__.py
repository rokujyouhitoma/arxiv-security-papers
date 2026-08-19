#!/usr/bin/env python3
"""
UI Presentation Layer for arXiv Security Papers.
Provides standalone HTML template rendering, Markdown compilation hooks, and UI component generation.
"""

from .template import extract_paper_preview_metadata, render_okf_preview_html

__all__ = [
    "render_okf_preview_html",
    "extract_paper_preview_metadata",
]
