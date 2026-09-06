#!/usr/bin/env python3
"""Source resolution helper for multi-repository paper datasets (arXiv, IACR ePrint)."""

import re
from typing import Dict


def resolve_paper_source_info(paper_id: str) -> Dict[str, str]:
    """Resolves source repository, display label, abstract URL, and PDF URL for a given paper ID.

    Examples:
        - "iacr-2026-386" ->
            source: "iacr"
            source_name: "IACR ePrint"
            label: "IACR: 2026/386"
            abs_url: "https://eprint.iacr.org/2026/386"
            pdf_url: "https://eprint.iacr.org/2026/386.pdf"
        - "2505.12345" ->
            source: "arxiv"
            source_name: "arXiv"
            label: "arXiv: 2505.12345"
            abs_url: "https://arxiv.org/abs/2505.12345"
            pdf_url: "https://arxiv.org/pdf/2505.12345.pdf"
    """
    clean_id = (paper_id or "").strip()
    if clean_id.startswith("Paper:"):
        clean_id = clean_id[6:]

    if clean_id.lower().startswith("iacr-"):
        match = re.match(r"^iacr-(\d{4})-(\d+)$", clean_id, re.IGNORECASE)
        if match:
            year, num = match.group(1), match.group(2)
            canonical_path = f"{year}/{num}"
            return {
                "source": "iacr",
                "source_name": "IACR ePrint",
                "label": f"IACR: {canonical_path}",
                "clean_id": clean_id,
                "abs_url": f"https://eprint.iacr.org/{canonical_path}",
                "pdf_url": f"https://eprint.iacr.org/{canonical_path}.pdf",
            }
        suffix = clean_id[5:]
        return {
            "source": "iacr",
            "source_name": "IACR ePrint",
            "label": f"IACR: {suffix}",
            "clean_id": clean_id,
            "abs_url": f"https://eprint.iacr.org/{suffix}",
            "pdf_url": f"https://eprint.iacr.org/{suffix}.pdf",
        }

    canonical_id = re.sub(r"v\d+$", "", clean_id)
    return {
        "source": "arxiv",
        "source_name": "arXiv",
        "label": f"arXiv: {clean_id}",
        "clean_id": clean_id,
        "abs_url": f"https://arxiv.org/abs/{canonical_id}",
        "pdf_url": f"https://arxiv.org/pdf/{clean_id}.pdf",
    }
