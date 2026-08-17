"""
Ingestion package for extracting arXiv metadata, PDFs, and full text.
"""

from .arxiv_client import (
    clean_text,
    fetch_arxiv_papers,
    fetch_arxiv_rss_fallback,
    load_config,
    parse_arxiv_entry,
)
from .pdf_extractor import (
    fetch_single_pdf_and_text,
    get_paper_pub_date_str,
    save_raw_paper_data,
)

__all__ = [
    "load_config",
    "clean_text",
    "parse_arxiv_entry",
    "fetch_arxiv_papers",
    "fetch_arxiv_rss_fallback",
    "get_paper_pub_date_str",
    "fetch_single_pdf_and_text",
    "save_raw_paper_data",
]
