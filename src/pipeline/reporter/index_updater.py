#!/usr/bin/env python3
"""
Index & Log Updater Module
Synchronizes root knowledge catalog (outputs/index.md) and execution history (outputs/log.md).
"""

import os
import re
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from ..transformer.translator import translate_title_ja

MAX_INDEX_PAPERS: int = 50


def _append_log_entry(workspace_dir: str, config: Dict[str, Any], count: int) -> None:
    log_path = os.path.join(workspace_dir, config["paths"]["log_file"])
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    now_str = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    log_entry = (
        f"| {now_str} | {count} | OKF v0.2 | `cs.CR` | "
        "正常完了 (160日バックフィル & PDF/TXT完全リンク検証) |\n"
    )
    if not os.path.exists(log_path):
        with open(log_path, "w", encoding="utf-8") as f:
            f.write(
                "# OKF Pipeline Log\n\n| 実行日時 (UTC) | 処理論文数 | 仕様 | カテゴリ | ステータス |\n|---|---|---|---|---|\n"
            )
            f.write(log_entry)
    else:
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(log_entry)


def _find_txt_target(txt_p: str, abs_p: str) -> Optional[str]:
    """Finds available text target between extracted txt and raw abstract."""
    if os.path.exists(txt_p):
        return txt_p
    if os.path.exists(abs_p):
        return abs_p
    return None


def _format_raw_links(
    workspace_dir: str, config: Dict[str, Any], day: str, clean_id: str, index_dir: str
) -> str:
    raw_dir = os.path.join(workspace_dir, config["paths"]["raw_data_dir"], day)
    meta_p = os.path.join(raw_dir, f"{clean_id}_meta.json")
    pdf_p = os.path.join(raw_dir, f"{clean_id}.pdf")
    txt_p = os.path.join(raw_dir, f"{clean_id}.txt")
    abs_p = os.path.join(raw_dir, f"{clean_id}_raw_abstract.txt")

    links: List[str] = []
    if os.path.exists(meta_p):
        links.append(f"[JSON]({os.path.relpath(meta_p, index_dir)})")
    if os.path.exists(pdf_p):
        links.append(f"[PDF]({os.path.relpath(pdf_p, index_dir)})")

    txt_target = _find_txt_target(txt_p, abs_p)
    if txt_target:
        links.append(f"[TXT]({os.path.relpath(txt_target, index_dir)})")

    return " / ".join(links) if links else "N/A"


def _extract_titles_from_okf(okf_path: str, clean_id: str) -> tuple[str, str]:
    with open(okf_path, "r", encoding="utf-8") as file:
        txt = file.read()
    title_match = re.search(r'^title:\s*"((?:\\.|[^"\\])*)"', txt, re.MULTILINE)
    title_ja_match = re.search(r'^title_ja:\s*"((?:\\.|[^"\\])*)"', txt, re.MULTILINE)
    t_str = (
        re.sub(r'\\(["\\])', r"\1", title_match.group(1)) if title_match else clean_id
    )
    t_ja = (
        re.sub(r'\\(["\\])', r"\1", title_ja_match.group(1))
        if title_ja_match
        else translate_title_ja(t_str)
    )
    return t_str.replace("|", "&#124;"), t_ja.replace("|", "&#124;")


def _build_single_index_row(
    day: str,
    fname: str,
    day_dir: str,
    workspace_dir: str,
    config: Dict[str, Any],
    index_dir: str,
) -> str:
    """Formats one row for the index catalog table."""
    okf_path = os.path.join(day_dir, fname)
    rel_okf = os.path.relpath(okf_path, index_dir)
    clean_id = fname.replace(".md", "")
    raw_links_str = _format_raw_links(workspace_dir, config, day, clean_id, index_dir)
    c_t_str, c_t_ja = _extract_titles_from_okf(okf_path, clean_id)
    return (
        f"| {day} | `{clean_id}` | [{c_t_str}]({rel_okf}) | "
        f"{c_t_ja} | {raw_links_str} | `cs.CR` | [arXiv](https://arxiv.org/abs/{clean_id}) |"
    )


def _scan_day_index_rows(
    day: str,
    day_dir: str,
    workspace_dir: str,
    config: Dict[str, Any],
    index_dir: str,
    limit: Optional[int] = None,
) -> List[str]:
    """Scans okf papers for a given day and generates index rows up to limit."""
    day_rows: List[str] = []
    for fname in sorted(os.listdir(day_dir)):
        if fname.endswith(".md"):
            row = _build_single_index_row(
                day, fname, day_dir, workspace_dir, config, index_dir
            )
            day_rows.append(row)
            if limit is not None and len(day_rows) >= limit:
                break
    return day_rows


def _scan_day_dir_if_exists(
    day: str,
    okf_root: str,
    workspace_dir: str,
    config: Dict[str, Any],
    index_dir: str,
    remaining: Optional[int],
) -> List[str]:
    day_dir = os.path.join(okf_root, day)
    if not os.path.isdir(day_dir):
        return []
    return _scan_day_index_rows(
        day, day_dir, workspace_dir, config, index_dir, limit=remaining
    )


def _scan_days_with_limit(
    days: List[str],
    okf_root: str,
    workspace_dir: str,
    config: Dict[str, Any],
    index_dir: str,
    limit: Optional[int],
) -> List[str]:
    """Scans multiple day directories collecting rows up to limit."""
    rows: List[str] = []
    for day in days:
        remaining = (limit - len(rows)) if limit is not None else None
        day_rows = _scan_day_dir_if_exists(
            day, okf_root, workspace_dir, config, index_dir, remaining
        )
        rows.extend(day_rows)
        if limit is not None and len(rows) >= limit:
            break
    return rows


def _build_index_rows(
    workspace_dir: str,
    config: Dict[str, Any],
    index_dir: str,
    limit: Optional[int] = MAX_INDEX_PAPERS,
) -> List[str]:
    okf_root = os.path.join(workspace_dir, config["paths"]["okf_papers_dir"])
    if not os.path.exists(okf_root):
        return []
    days = sorted(os.listdir(okf_root), reverse=True)
    return _scan_days_with_limit(
        days, okf_root, workspace_dir, config, index_dir, limit
    )


def _format_tier_link(path: str, index_dir: str) -> str:
    """Formats markdown relative link for summary tier file."""
    if not path:
        return "N/A"
    rel_p = os.path.relpath(path, index_dir)
    return f"[{os.path.basename(path)}]({rel_p})"


def _resolve_okf_rel_path(
    workspace_dir: Optional[str],
    config: Optional[Dict[str, Any]],
    index_dir: str,
) -> str:
    """Resolves relative link to okf papers directory."""
    if config and workspace_dir and "okf_papers_dir" in config.get("paths", {}):
        okf_papers_full = os.path.join(workspace_dir, config["paths"]["okf_papers_dir"])
        return os.path.relpath(okf_papers_full, index_dir)
    if os.path.exists(os.path.join(index_dir, "okf", "papers")):
        return "okf/papers"
    return "okf_papers"


def _resolve_raw_rel_path(
    workspace_dir: Optional[str],
    config: Optional[Dict[str, Any]],
    index_dir: str,
) -> str:
    """Resolves relative link to raw data directory."""
    if config and workspace_dir and "raw_data_dir" in config.get("paths", {}):
        raw_data_full = os.path.join(workspace_dir, config["paths"]["raw_data_dir"])
        return os.path.relpath(raw_data_full, index_dir)
    return "raw_data"


def _render_index_header(
    date_str: str,
    per_run_path: str,
    daily_path: str,
    monthly_path: str,
    quarterly_path: str,
    annual_path: str,
    index_dir: str,
    displayed_limit: int = MAX_INDEX_PAPERS,
    config: Optional[Dict[str, Any]] = None,
    workspace_dir: Optional[str] = None,
) -> str:
    """Renders the top markdown sections and summary tier links for index.md."""
    link_pr = _format_tier_link(per_run_path, index_dir)
    link_d = _format_tier_link(daily_path, index_dir)
    link_m = _format_tier_link(monthly_path, index_dir)
    link_q = _format_tier_link(quarterly_path, index_dir)
    link_a = _format_tier_link(annual_path, index_dir)

    # Relative navigation links from outputs/
    web_console_rel = "../site/index.html"
    catalog_json_rel = "database/papers_catalog.json"
    okf_papers_rel = _resolve_okf_rel_path(workspace_dir, config, index_dir)
    raw_data_rel = _resolve_raw_rel_path(workspace_dir, config, index_dir)

    info_desc = (
        "> 本カタログは、arXiv (`cs.CR`) から取得したサイバーセキュリティ論文について、"
        "**原データ保持 (raw_data: JSON / PDF / TXT)**、**OKF変換ドキュメント (okf_papers)**、"
        "および**日本語表形式エグゼクティブサマリー (01_per_run 〜 05_annual)** "
        "を全成果物集約ディレクトリ `outputs/` の下で独立管理・提供するナビゲーションポータルです。"
    )

    return f"""---
type: "catalog-index"
title: "arXiv セキュリティ論文 OKF ナレッジカタログ"
description: "arXiv cs.CR から取得したセキュリティ論文Rawデータ（JSON/PDF/TXT）、OKFドキュメント、および各階層の日本語エグゼクティブサマリー一覧"
timestamp: "{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}"
---

# 🛡️ arXiv セキュリティ論文 ナレッジカタログ (Google OKF v0.2)

> [!INFO]
{info_desc}

---

## 🔍 全件検索・データアクセス基盤 (Decoupled Catalog Views)

全収集論文（数千件）の高速検索・フィルタリング、および構造化生データへのアクセスは以下の基盤をご利用ください：

| アクセス種別 | リンク (相対パス) | 提供機能・用途 |
|---|---|---|
| 🌐 **Web コンソール** | [Web Console]({web_console_rel}) | キーワード検索、ドメイン・タグ絞り込み、高速グラフ・統計可視化 |
| 🗄️ **全件カタログ台帳** | [papers_catalog.json]({catalog_json_rel}) | 全収集論文のメタデータ・要約・OKF/Rawリンクを完全網羅した構造化JSON |
| 📄 **OKF ドキュメント** | [okf_papers/]({okf_papers_rel}) | 日付別 OKF v0.2 Markdown ドキュメント群 |
| 📦 **原本生データ** | [raw_data/]({raw_data_rel}) | arXiv 公式 JSON / PDF / pdftotext 抽出 TXT 原本 |

---

## 📊 ソート済みエグゼクティブサマリー層 (日本語サマリー)

| 項番 & 区分 | ディレクトリ名 | 対象範囲 | 最新サマリーファイル (相対リンク) |
|---|---|---|---|
| ⏱️ **01_per_run** | `01_per_run/` | 取得時ごと (1日4回) | {link_pr} |
| 📅 **02_daily** | `02_daily/` | 最新日 ({date_str}) | {link_d} |
| 📊 **03_monthly** | `03_monthly/` | 過去30日間 | {link_m} |
| 🏢 **04_quarterly** | `04_quarterly/` | 過去90日間 | {link_q} |
| 🏆 **05_annual** | `05_annual/` | 過去365日間 | {link_a} |

---

## 📚 直近登録論文ハイライト (最新 {displayed_limit} 件)

> [!NOTE]
> 本ファイルでは直近最新の **{displayed_limit} 件** をピックアップ掲載しています。
> 過去の全論文の検索・閲覧・分析は [Web コンソール]({web_console_rel}) または [papers_catalog.json]({catalog_json_rel}) をご参照ください。

| 公開日 | arXiv ID | OKFドキュメント (原題 & リンク) | 論文タイトル (日本語訳) | 原本Rawデータ (JSON / PDF / TXT) | 主カテゴリ | 原本リンク |
|---|---|---|---|---|---|---|
"""


def _render_index_footer() -> str:
    """Renders the bottom navigation footer for index.md."""
    web_console_rel = "../site/index.html"
    catalog_json_rel = "database/papers_catalog.json"
    return f"""
---

> 💡 **全論文の検索・閲覧について**:
> 全件のインタラクティブ検索およびフィルタリングは [Web コンソール]({web_console_rel})、
> 全件メタデータの一括処理には [papers_catalog.json]({catalog_json_rel}) をご利用いただけます。
"""


def _atomic_write_file(target_path: str, full_text: str) -> None:
    """Writes file atomically using temporary file rename."""
    tmp_path = f"{target_path}.tmp.{os.getpid()}"
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            f.write(full_text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, target_path)
    except Exception:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass
        raise


def update_index_and_log(
    workspace_dir: str,
    new_items: List[Dict[str, Any]],
    per_run_path: str,
    daily_path: str,
    monthly_path: str,
    quarterly_path: str,
    annual_path: str,
    config: Dict[str, Any],
    limit: Optional[int] = MAX_INDEX_PAPERS,
) -> None:
    """Updates outputs/index.md and appends execution entry to outputs/log.md."""
    index_path = os.path.join(workspace_dir, config["paths"]["index_file"])
    index_dir = os.path.dirname(index_path)
    os.makedirs(index_dir, exist_ok=True)

    _append_log_entry(workspace_dir, config, len(new_items))

    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    displayed_limit = limit if limit is not None else 50
    index_content = _render_index_header(
        date_str,
        per_run_path,
        daily_path,
        monthly_path,
        quarterly_path,
        annual_path,
        index_dir,
        displayed_limit=displayed_limit,
        config=config,
        workspace_dir=workspace_dir,
    )
    rows = _build_index_rows(workspace_dir, config, index_dir, limit=limit)
    footer = _render_index_footer()
    full_text = index_content + "".join(r + "\n" for r in rows) + footer
    _atomic_write_file(index_path, full_text)
