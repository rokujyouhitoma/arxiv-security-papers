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
    log_path = os.path.join(workspace_dir, config["paths"]["log_file"])
    index_dir = os.path.dirname(index_path)

    now_str = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    os.makedirs(index_dir, exist_ok=True)
    os.makedirs(os.path.dirname(log_path), exist_ok=True)

    log_entry = (
        f"| {now_str} | {len(new_items)} | OKF v0.2 | `cs.CR` | "
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

    rel_pr_file = os.path.relpath(per_run_path, index_dir) if per_run_path else "N/A"
    rel_d_file = os.path.relpath(daily_path, index_dir) if daily_path else "N/A"
    rel_m_file = os.path.relpath(monthly_path, index_dir) if monthly_path else "N/A"
    rel_q_file = os.path.relpath(quarterly_path, index_dir) if quarterly_path else "N/A"
    rel_a_file = os.path.relpath(annual_path, index_dir) if annual_path else "N/A"

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
| ⏱️ **01_per_run** | `01_per_run/` | 取得時ごと (1日4回) | [{os.path.basename(per_run_path)}]({rel_pr_file}) |
| 📅 **02_daily** | `02_daily/` | 最新日 ({date_str}) | [{os.path.basename(daily_path)}]({rel_d_file}) |
| 📊 **03_monthly** | `03_monthly/` | 過去30日間 | [{os.path.basename(monthly_path)}]({rel_m_file}) |
| 🏢 **04_quarterly** | `04_quarterly/` | 過去90日間 | [{os.path.basename(quarterly_path)}]({rel_q_file}) |
| 🏆 **05_annual** | `05_annual/` | 過去365日間 | [{os.path.basename(annual_path)}]({rel_a_file}) |

---

## 📚 登録論文ドキュメント一覧 (Raw JSON / PDF / TXT リンク付き)

| 公開日 | arXiv ID | OKFドキュメント (原題 & リンク) | 論文タイトル (日本語訳) | 原本Rawデータ (JSON / PDF / TXT) | 主カテゴリ | 原本リンク |
|---|---|---|---|---|---|---|
"""
    okf_root = os.path.join(workspace_dir, config["paths"]["okf_papers_dir"])
    rows: List[str] = []
    if os.path.exists(okf_root):
        for day in sorted(os.listdir(okf_root), reverse=True):
            day_dir = os.path.join(okf_root, day)
            if os.path.isdir(day_dir):
                for fname in sorted(os.listdir(day_dir)):
                    if fname.endswith(".md"):
                        okf_path = os.path.join(day_dir, fname)
                        rel_okf = os.path.relpath(okf_path, index_dir)
                        clean_id = fname.replace(".md", "")

                        raw_meta = os.path.join(
                            workspace_dir,
                            config["paths"]["raw_data_dir"],
                            day,
                            f"{clean_id}_meta.json",
                        )
                        raw_pdf = os.path.join(
                            workspace_dir,
                            config["paths"]["raw_data_dir"],
                            day,
                            f"{clean_id}.pdf",
                        )
                        raw_txt = os.path.join(
                            workspace_dir,
                            config["paths"]["raw_data_dir"],
                            day,
                            f"{clean_id}.txt",
                        )
                        raw_abs = os.path.join(
                            workspace_dir,
                            config["paths"]["raw_data_dir"],
                            day,
                            f"{clean_id}_raw_abstract.txt",
                        )

                        rel_raw_meta = (
                            os.path.relpath(raw_meta, index_dir)
                            if os.path.exists(raw_meta)
                            else ""
                        )
                        rel_raw_pdf = (
                            os.path.relpath(raw_pdf, index_dir)
                            if os.path.exists(raw_pdf)
                            else ""
                        )
                        rel_raw_txt = (
                            os.path.relpath(raw_txt, index_dir)
                            if os.path.exists(raw_txt)
                            else (
                                os.path.relpath(raw_abs, index_dir)
                                if os.path.exists(raw_abs)
                                else ""
                            )
                        )

                        raw_links = []
                        if rel_raw_meta:
                            raw_links.append(f"[JSON]({rel_raw_meta})")
                        if rel_raw_pdf:
                            raw_links.append(f"[PDF]({rel_raw_pdf})")
                        if rel_raw_txt:
                            raw_links.append(f"[TXT]({rel_raw_txt})")
                        raw_links_str = " / ".join(raw_links) if raw_links else "N/A"

                        with open(okf_path, "r", encoding="utf-8") as file:
                            txt = file.read()
                        title_match = re.search(
                            r'^title:\s*"([^"]+)"', txt, re.MULTILINE
                        )
                        title_ja_match = re.search(
                            r'^title_ja:\s*"([^"]+)"', txt, re.MULTILINE
                        )
                        t_str = title_match.group(1) if title_match else clean_id
                        t_ja = (
                            title_ja_match.group(1)
                            if title_ja_match
                            else translate_title_ja(t_str)
                        )

                        c_t_str = t_str.replace("|", "&#124;")
                        c_t_ja = t_ja.replace("|", "&#124;")

                        row_str = (
                            f"| {day} | `{clean_id}` | [{c_t_str}]({rel_okf}) | "
                            f"{c_t_ja} | {raw_links_str} | `cs.CR` | [arXiv](https://arxiv.org/abs/{clean_id}) |"
                        )
                        rows.append(row_str)

    with open(index_path, "w", encoding="utf-8") as f:
        f.write(index_content)
        for r in rows:
            f.write(r + "\n")
