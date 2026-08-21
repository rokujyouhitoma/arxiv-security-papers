#!/usr/bin/env python3
"""
PDF Extractor & Raw Asset Storage Module
Handles downloading PDFs from arXiv, pdftotext extraction, and raw metadata saving.
"""

import json
import os
import subprocess
import urllib.request
from datetime import datetime, timezone
from typing import Any, Dict


def get_paper_pub_date_str(paper: Dict[str, Any]) -> str:
    """Extracts YYYY-MM-DD publication date string from paper dict."""
    pub = paper.get("published")
    if pub and isinstance(pub, str) and len(pub) >= 10 and pub[:4].isdigit():
        return str(pub[:10])
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def fetch_single_pdf_and_text(paper: Dict[str, Any], raw_dir: str) -> None:
    """Downloads PDF and extracts full text via pdftotext."""
    clean_id = paper["clean_id"]
    pdf_path = os.path.join(raw_dir, f"{clean_id}.pdf")
    txt_path = os.path.join(raw_dir, f"{clean_id}.txt")

    if not os.path.exists(pdf_path):
        pdf_url = (
            paper.get("pdf_url") or f"https://arxiv.org/pdf/{paper['arxiv_id']}.pdf"
        )
        try:
            req = urllib.request.Request(
                pdf_url,
                headers={
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ArXivSecurityOKFBot/1.0"
                },
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                pdf_data = resp.read()
                with open(pdf_path, "wb") as f:
                    f.write(pdf_data)
        except Exception:
            pass

    if os.path.exists(pdf_path) and not os.path.exists(txt_path):
        try:
            subprocess.run(
                ["pdftotext", pdf_path, txt_path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=10,
            )
        except Exception:
            pass


def save_raw_paper_data(
    paper: Dict[str, Any], workspace_dir: str, config: Dict[str, Any]
) -> str:
    """Persists raw metadata JSON and abstract TXT under outputs/raw_data/YYYY-MM-DD/."""
    date_str = get_paper_pub_date_str(paper)
    raw_dir = os.path.join(workspace_dir, config["paths"]["raw_data_dir"], date_str)
    os.makedirs(raw_dir, exist_ok=True)

    clean_id = paper["clean_id"]
    raw_meta_path = os.path.join(raw_dir, f"{clean_id}_meta.json")
    with open(raw_meta_path, "w", encoding="utf-8") as f:
        json.dump(paper, f, ensure_ascii=False, indent=2)

    raw_abs_path = os.path.join(raw_dir, f"{clean_id}_raw_abstract.txt")
    with open(raw_abs_path, "w", encoding="utf-8") as f:
        f.write(f"Title (EN): {paper['title']}\n")
        f.write(f"Title (JA): {paper.get('title_ja', '')}\n")
        f.write(f"arXiv ID: {paper['arxiv_id']}\n")
        f.write(f"Published: {paper['published']}\n")
        f.write(f"Authors: {', '.join(paper.get('authors', []))}\n")
        f.write(f"Abstract:\n{paper.get('summary', '')}\n")

    return raw_meta_path
