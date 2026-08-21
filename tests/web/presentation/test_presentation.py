#!/usr/bin/env python3
"""
Unit tests for UI Presentation Layer (template rendering and metadata extraction).
"""

from web.presentation import extract_paper_preview_metadata, render_okf_preview_html

SAMPLE_OKF_MARKDOWN = """---
type: "security-paper"
title: "Zero-Trust Architecture in Quantum Computing Networks"
description: "量子コンピューティング環境におけるゼロトラストセキュリティモデルの検証"
tags: ["cryptography", "zero-trust", "quantum"]
timestamp: "2026-08-15T00:00:00Z"
authors: ["Alice Researcher", "Bob Engineer"]
---

# Zero-Trust Architecture in Quantum Computing Networks

## 概要
量子鍵配送（QKD）とポスト量子暗号（PQC）の統合アーキテクチャ。
"""


def test_extract_paper_preview_metadata():
    meta = extract_paper_preview_metadata(SAMPLE_OKF_MARKDOWN)
    assert meta["title"] == "Zero-Trust Architecture in Quantum Computing Networks"
    assert "Alice Researcher" in meta["authors"]
    assert "cryptography" in meta["tags"]
    assert meta["date"] == "2026-08-15"


def test_extract_paper_preview_metadata_fallback():
    raw = "No frontmatter content here."
    meta = extract_paper_preview_metadata(raw)
    assert meta["title"] == "OKF Paper Preview"
    assert meta["authors"] == ""
    assert meta["tags"] == ""
    assert meta["date"] == ""


def test_render_okf_preview_html():
    html_output = render_okf_preview_html(
        arxiv_id="2608.12345",
        content=SAMPLE_OKF_MARKDOWN,
        raw_md_path="/outputs/okf_papers/2026-08-15/2608.12345.md",
    )

    assert "<!DOCTYPE html>" in html_output
    assert "Zero-Trust Architecture in Quantum Computing Networks" in html_output
    assert "arXiv: 2608.12345" in html_output
    assert "Alice Researcher" in html_output
    assert "Google OKF v0.2" in html_output
    assert "/outputs/okf_papers/2026-08-15/2608.12345.md" in html_output
    assert "window.MarkdownCompiler" in html_output
