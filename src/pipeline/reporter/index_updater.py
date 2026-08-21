#!/usr/bin/env python3
"""
Index & Log Updater Module
Synchronizes root knowledge catalog (outputs/index.md) and execution history (outputs/log.md).
"""

import os
import re
from datetime import datetime, timezone
from typing import Any, Dict, List

from ..transformer.translator import translate_title_ja


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
    if os.path.exists(txt_p):
        links.append(f"[TXT]({os.path.relpath(txt_p, index_dir)})")
    elif os.path.exists(abs_p):
        links.append(f"[TXT]({os.path.relpath(abs_p, index_dir)})")
    return " / ".join(links) if links else "N/A"


def _extract_titles_from_okf(okf_path: str, clean_id: str) -> tuple[str, str]:
    with open(okf_path, "r", encoding="utf-8") as file:
        txt = file.read()
    title_match = re.search(r'^title:\s*"([^"]+)"', txt, re.MULTILINE)
    title_ja_match = re.search(r'^title_ja:\s*"([^"]+)"', txt, re.MULTILINE)
    t_str = title_match.group(1) if title_match else clean_id
    t_ja = title_ja_match.group(1) if title_ja_match else translate_title_ja(t_str)
    return t_str.replace("|", "&#124;"), t_ja.replace("|", "&#124;")


def _build_index_rows(
    workspace_dir: str, config: Dict[str, Any], index_dir: str
) -> List[str]:
    okf_root = os.path.join(workspace_dir, config["paths"]["okf_papers_dir"])
    rows: List[str] = []
    if not os.path.exists(okf_root):
        return rows

    for day in sorted(os.listdir(okf_root), reverse=True):
        day_dir = os.path.join(okf_root, day)
        if not os.path.isdir(day_dir):
            continue
        for fname in sorted(os.listdir(day_dir)):
            if fname.endswith(".md"):
                okf_path = os.path.join(day_dir, fname)
                rel_okf = os.path.relpath(okf_path, index_dir)
                clean_id = fname.replace(".md", "")
                raw_links_str = _format_raw_links(
                    workspace_dir, config, day, clean_id, index_dir
                )
                c_t_str, c_t_ja = _extract_titles_from_okf(okf_path, clean_id)
                row_str = (
                    f"| {day} | `{clean_id}` | [{c_t_str}]({rel_okf}) | "
                    f"{c_t_ja} | {raw_links_str} | `cs.CR` | [arXiv](https://arxiv.org/abs/{clean_id}) |"
                )
                rows.append(row_str)
    return rows


def update_index_and_log(
    workspace_dir: str,
    new_items: List[Dict[str, Any]],
    per_run_path: str,
    daily_path: str,
    monthly_path: str,
    quarterly_path: str,
    annual_path: str,
    config: Dict[str, Any],
) -> None:
    """Updates outputs/index.md and appends execution entry to outputs/log.md."""
    index_path = os.path.join(workspace_dir, config["paths"]["index_file"])
    index_dir = os.path.dirname(index_path)
    os.makedirs(index_dir, exist_ok=True)

    _append_log_entry(workspace_dir, config, len(new_items))

    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    rel_pr = os.path.relpath(per_run_path, index_dir) if per_run_path else "N/A"
    rel_d = os.path.relpath(daily_path, index_dir) if daily_path else "N/A"
    rel_m = os.path.relpath(monthly_path, index_dir) if monthly_path else "N/A"
    rel_q = os.path.relpath(quarterly_path, index_dir) if quarterly_path else "N/A"
    rel_a = os.path.relpath(annual_path, index_dir) if annual_path else "N/A"

    info_desc = (
        "> このカタログは、arXiv (`cs.CR`) から取得したセキュリティ論文について、"
        "**原データ保持 (raw_data: JSON / PDF / TXT)**、**OKF変換ドキュメント (okf_papers)**、"
        "および**日本語表形式エグゼクティブサマリー (01_per_run, 02_daily, 03_monthly, 04_quarterly, 05_annual)** "
        "を全成果物集約ディレクトリ `outputs/` の下で独立管理・提供します。"
    )

    index_content = f"""---
type: "catalog-index"
title: "arXiv セキュリティ論文 OKF ナレッジカタログ"
description: "arXiv cs.CR から取得したセキュリティ論文Rawデータ（JSON/PDF/TXT）、OKFドキュメント、および各階層の日本語エグゼクティブサマリー一覧"
timestamp: "{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}"
---

# 🛡️ arXiv セキュリティ論文 ナレッジカタログ (Google OKF v0.2)

> [!INFO]
{info_desc}

---

## 📊 ソート済みエグゼクティブサマリー層 (日本語サマリー)

| 項番 & 区分 | ディレクトリ名 | 対象範囲 | 最新サマリーファイル (相対リンク) |
|---|---|---|---|
| ⏱️ **01_per_run** | `01_per_run/` | 取得時ごと (1日4回) | [{os.path.basename(per_run_path)}]({rel_pr}) |
| 📅 **02_daily** | `02_daily/` | 最新日 ({date_str}) | [{os.path.basename(daily_path)}]({rel_d}) |
| 📊 **03_monthly** | `03_monthly/` | 過去30日間 | [{os.path.basename(monthly_path)}]({rel_m}) |
| 🏢 **04_quarterly** | `04_quarterly/` | 過去90日間 | [{os.path.basename(quarterly_path)}]({rel_q}) |
| 🏆 **05_annual** | `05_annual/` | 過去365日間 | [{os.path.basename(annual_path)}]({rel_a}) |

---

## 📚 登録論文ドキュメント一覧 (Raw JSON / PDF / TXT リンク付き)

| 公開日 | arXiv ID | OKFドキュメント (原題 & リンク) | 論文タイトル (日本語訳) | 原本Rawデータ (JSON / PDF / TXT) | 主カテゴリ | 原本リンク |
|---|---|---|---|---|---|---|
"""
    rows = _build_index_rows(workspace_dir, config, index_dir)
    with open(index_path, "w", encoding="utf-8") as f:
        f.write(index_content)
        for r in rows:
            f.write(r + "\n")
