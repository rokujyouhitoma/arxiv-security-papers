#!/usr/bin/env python3
"""
Google OKF v0.2 Serializer & Japanese Executive Summary Generator Module
Converts raw paper metadata and extracted text into OKF Markdown documents.
"""

import json
import os
import re
from datetime import datetime, timezone
from typing import Any, Dict, Tuple

from .keyword_extractor import extract_keyphrases
from .structured_summarizer import generate_structured_summary
from .tagger import determine_security_tags
from .translator import translate_title_ja


def generate_japanese_executive_summary(paper: Dict[str, Any]) -> Dict[str, Any]:
    """Generates structured 3-point Japanese executive summary and section blocks."""
    title = paper["title"]
    title_ja = paper.get("title_ja", translate_title_ja(title))
    abstract = paper.get("summary", "")
    arxiv_id = paper.get("arxiv_id", "")
    clean_id = paper.get("clean_id", arxiv_id)

    # 1. 3-Point Structured Summary & Cohesive One-Liner
    sum_data = generate_structured_summary(
        title=title,
        abstract=abstract,
        clean_id=clean_id,
        japanese_title=title_ja,
    )

    # 2. Keyphrase Extraction
    full_text = f"{title} {abstract}"
    keyphrases = extract_keyphrases(full_text, top_k=4)
    keyphrases_str = (
        ", ".join(keyphrases) if keyphrases else "セキュリティ分析, 脆弱性検証"
    )

    overview_desc = (
        f"本論文「{title_ja}」（原題: {title} / arXiv: {arxiv_id}）は、"
        f"{paper.get('primary_category', 'cs.CR')} 分野における最新セキュリティ研究成果を取り扱っています。"
    )

    background_text = (
        f"【課題・脅威】{sum_data['threat']}\n" f"(主要キーワード: {keyphrases_str})"
    )
    tech_text = f"【提案技術】{sum_data['proposal']}"
    impact_text = f"【実証・影響】{sum_data['impact']}"

    return {
        "one_liner": sum_data["executive_summary"],
        "overview": f"{overview_desc}\n\n**概要**: {sum_data['executive_summary']}",
        "background": background_text,
        "technical_approach": tech_text,
        "results_impact": impact_text,
        "keyphrases": keyphrases,
        "keyphrases_str": keyphrases_str,
        "threat": sum_data["threat"],
        "proposal": sum_data["proposal"],
        "impact": sum_data["impact"],
        "executive_recommendations": [
            "組織のセキュリティ設計およびリスク評価基準への影響確認",
            "技術チームによる検証実験および対策パッチ/設定の展開検討",
            "関連する暗号プロトコル・認証ロジックの脆弱性監査の実施",
        ],
    }


def load_template(
    template_name: str,
    default_content: str,
    workspace_dir: str,
    config: Dict[str, Any],
) -> str:
    """Loads markdown template or returns default fallback content."""
    templates_dir = config.get("paths", {}).get("templates_dir", "templates")
    template_path = os.path.join(workspace_dir, templates_dir, template_name)
    if os.path.exists(template_path):
        try:
            with open(template_path, "r", encoding="utf-8") as f:
                return f.read()
        except Exception:
            pass
    return default_content


def get_paper_pub_date_str(paper: Dict[str, Any]) -> str:
    """Extracts YYYY-MM-DD publication date string from paper dict."""
    pub = paper.get("published")
    if pub and isinstance(pub, str) and len(pub) >= 10 and pub[:4].isdigit():
        return str(pub[:10])
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def is_sensitive_path(path: str) -> bool:
    """Checks if a path references sensitive files."""
    norm = os.path.normpath(path).lower()
    sensitive_markers = [
        ".ssh",
        ".aws",
        ".env",
        "passwd",
        "id_rsa",
        "id_ed25519",
        ".bashrc",
        ".profile",
    ]
    return any(marker in norm for marker in sensitive_markers)


def _resolve_raw_links(
    paper: Dict[str, Any],
    raw_dir: str,
    safe_clean_id: str,
    okf_file_dir: str,
    rel_raw_meta: str,
) -> tuple[str, str]:
    pdf_file_path = os.path.join(raw_dir, f"{safe_clean_id}.pdf")
    txt_file_path = os.path.join(raw_dir, f"{safe_clean_id}.txt")
    abs_txt_file_path = os.path.join(raw_dir, f"{safe_clean_id}_raw_abstract.txt")

    if os.path.exists(pdf_file_path):
        rel_pdf = os.path.relpath(pdf_file_path, okf_file_dir)
        pdf_link_str = f"[`PDF`]({rel_pdf})"
    else:
        pdf_link_str = f"[`PDF (arXiv)`]({paper['pdf_url']})"

    if os.path.exists(txt_file_path):
        rel_txt = os.path.relpath(txt_file_path, okf_file_dir)
        txt_link_str = f"[`TXT`]({rel_txt})"
    elif os.path.exists(abs_txt_file_path):
        rel_abs = os.path.relpath(abs_txt_file_path, okf_file_dir)
        txt_link_str = f"[`TXT`]({rel_abs})"
    else:
        txt_link_str = f"[`TXT`]({rel_raw_meta})"

    return pdf_link_str, txt_link_str


def _load_raw_paper_meta(raw_meta_path: str) -> Dict[str, Any]:
    """Loads and validates raw paper JSON metadata."""
    resolved_meta = os.path.realpath(os.path.abspath(raw_meta_path))
    if is_sensitive_path(resolved_meta):
        raise PermissionError(f"Access to sensitive path blocked: {resolved_meta}")
    with open(resolved_meta, "r", encoding="utf-8") as f:
        return cast(Dict[str, Any], json.load(f))


def _render_okf_markdown(
    raw_template: str,
    paper: Dict[str, Any],
    title_ja: str,
    exec_summary: Dict[str, Any],
    tags_yaml: str,
    authors_yaml: str,
    now_iso: str,
    pub_date: str,
    rel_raw_meta: str,
    raw_meta_path: str,
    pdf_link_str: str,
    txt_link_str: str,
    rec_list: str,
) -> str:
    """Renders formatted OKF markdown content string."""
    return raw_template.format(
        title=paper["title"].replace('"', '\\"'),
        title_ja=title_ja.replace('"', '\\"'),
        description=exec_summary["one_liner"].replace('"', '\\"'),
        resource=paper["abs_url"],
        tags_yaml=tags_yaml,
        timestamp=now_iso,
        rel_raw_meta_from_okf=rel_raw_meta,
        published_date=pub_date,
        authors_yaml=authors_yaml,
        arxiv_id=paper["arxiv_id"],
        raw_meta_basename=os.path.basename(raw_meta_path),
        overview=exec_summary["overview"],
        background=exec_summary["background"],
        technical_approach=exec_summary["technical_approach"],
        results_impact=exec_summary["results_impact"],
        rec_list=rec_list,
        pdf_url=paper["pdf_url"],
        authors_str=", ".join(paper.get("authors", [])),
        categories_str=", ".join(paper.get("categories", [])),
        pdf_link_str=pdf_link_str,
        txt_link_str=txt_link_str,
        summary=paper.get("summary", ""),
    )


def _build_okf_template_vars(
    paper: Dict[str, Any], config: Dict[str, Any]
) -> Tuple[str, Dict[str, Any], str, str, str, str, str]:
    """Prepares structured metadata variables for OKF template injection."""
    title_ja = paper.get("title_ja", translate_title_ja(paper["title"]))
    exec_summary = generate_japanese_executive_summary(paper)
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    pub_date = str(paper.get("published") or now_iso)

    authors_yaml = "\n".join([f'    - "{a}"' for a in paper.get("authors", [])])
    default_tags = config.get("okf", {}).get("default_tags", ["cs.CR", "security"])
    tags = list(set(default_tags + determine_security_tags(paper)))
    tags_yaml = "\n".join([f'  - "{t}"' for t in sorted(tags)])
    rec_list = "\n".join([f"- {r}" for r in exec_summary["executive_recommendations"]])
    return title_ja, exec_summary, now_iso, pub_date, authors_yaml, tags_yaml, rec_list


def _write_validated_okf_file(
    okf_file_path: str, workspace_dir: str, content: str
) -> str:
    """Validates path boundary within workspace and writes OKF content."""
    resolved_ws = os.path.realpath(os.path.abspath(workspace_dir))
    resolved_target = os.path.realpath(os.path.abspath(okf_file_path))
    if not resolved_target.startswith(resolved_ws):
        raise ValueError(
            f"Security: Target OKF path {resolved_target} is outside workspace {resolved_ws}"
        )
    with open(resolved_target, "w", encoding="utf-8") as f:
        f.write(content)
    return os.path.relpath(resolved_target, resolved_ws)


def build_okf_from_raw(
    raw_meta_path: str, workspace_dir: str, config: Dict[str, Any]
) -> Dict[str, Any]:
    """Builds and serializes a Google OKF v0.2 Markdown document from raw metadata JSON."""
    paper = _load_raw_paper_meta(raw_meta_path)
    resolved_meta = os.path.realpath(os.path.abspath(raw_meta_path))

    date_str = get_paper_pub_date_str(paper)
    safe_clean_id = re.sub(r"[^a-zA-Z0-9._-]", "", paper.get("clean_id", "unknown"))
    okf_dir = os.path.join(workspace_dir, config["paths"]["okf_papers_dir"], date_str)
    raw_dir = os.path.join(workspace_dir, config["paths"]["raw_data_dir"], date_str)
    os.makedirs(okf_dir, exist_ok=True)

    okf_file_path = os.path.join(okf_dir, f"{safe_clean_id}.md")
    if is_sensitive_path(okf_file_path):
        raise PermissionError(f"Target path blocked: {okf_file_path}")

    okf_file_dir = os.path.dirname(okf_file_path)
    rel_raw_meta = os.path.relpath(resolved_meta, okf_file_dir)
    pdf_link_str, txt_link_str = _resolve_raw_links(
        paper, raw_dir, safe_clean_id, okf_file_dir, rel_raw_meta
    )

    title_ja, exec_summary, now_iso, pub_date, authors_yaml, tags_yaml, rec_list = (
        _build_okf_template_vars(paper, config)
    )

    raw_template = load_template(
        "okf_paper.md.template",
        """---
type: "security-paper"
title: "{title}"
title_ja: "{title_ja}"
description: "{description}"
resource: "{resource}"
tags:
{tags_yaml}
timestamp: "{timestamp}"
provenance:
  source: "arxiv.org"
  raw_meta_file: "{rel_raw_meta_from_okf}"
  published_date: "{published_date}"
  authors:
{authors_yaml}
trust:
  attestation: "processed_by: arxiv-security-agent"
  confidence: "high"
---

# {title}
### (日本語題名: {title_ja})

> [!NOTE]
> **OKF Metadata**: Type = `security-paper` | arXiv ID = [`{arxiv_id}`]({resource})
> Raw Meta = [`{raw_meta_basename}`]({rel_raw_meta_from_okf})

## エグゼクティブサマリー (Executive Summary)

### 1. 概要 (Overview & Key Finding)
{overview}

### 2. 背景とセキュリティ上の課題 (Background & Problem)
{background}

### 3. 提案アプローチ・技術革新 (Technical Innovation)
{technical_approach}

### 4. セキュリティ影響と実験結果 (Results & Impact)
{results_impact}

### 5. 経営層・セキュリティ管理者向け推奨アクション (Executive Recommendations)
{rec_list}

---

## 原論文情報 (Original Paper Metadata & Raw Data)

- **arXiv ID**: `{arxiv_id}`
- **論文URL**: [{resource}]({resource})
- **PDFリンク**: [{pdf_url}]({pdf_url})
- **著者**: {authors_str}
- **公開日時**: `{published_date}`
- **カテゴリ**: `{categories_str}`
- **保存済みRawデータ**: [`JSON`]({rel_raw_meta_from_okf}) | {pdf_link_str} | {txt_link_str}

### Abstract (原文)
> {summary}
""",
        workspace_dir,
        config,
    )

    okf_content = _render_okf_markdown(
        raw_template,
        paper,
        title_ja,
        exec_summary,
        tags_yaml,
        authors_yaml,
        now_iso,
        pub_date,
        rel_raw_meta,
        raw_meta_path,
        pdf_link_str,
        txt_link_str,
        rec_list,
    )

    rel_okf_path = _write_validated_okf_file(okf_file_path, workspace_dir, okf_content)
    resolved_target = os.path.realpath(os.path.abspath(okf_file_path))

    return {
        "paper": paper,
        "okf_path": resolved_target,
        "rel_okf_path": rel_okf_path,
        "exec_summary": exec_summary,
        "title_ja": title_ja,
        "date_str": date_str,
    }
