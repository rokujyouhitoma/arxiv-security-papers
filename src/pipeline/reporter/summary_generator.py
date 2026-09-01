#!/usr/bin/env python3
"""Executive Summary Generator Module.

Generates 5-tier Japanese executive summaries (01_per_run ~ 05_annual)
with NLP keyphrases, 3-point structured summaries, and thematic trends.
"""

import os
import re
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple, cast

from ..transformer.keyword_extractor import extract_keyphrases
from ..transformer.okf_serializer import load_template
from ..transformer.structured_summarizer import generate_structured_summary
from ..transformer.thematic_synthesizer import synthesize_thematic_trends
from ..transformer.translator import translate_title_ja

PAPER_META_CACHE: Dict[str, Any] = {}


def _extract_frontmatter_field(text: str, field_name: str) -> Optional[str]:
    """Safely extracts and unescapes a YAML frontmatter field value."""
    pattern = rf'^{field_name}:\s*"((?:\\.|[^"\\])*)"'
    match = re.search(pattern, text, re.MULTILINE)
    if match:
        val = match.group(1)
        return re.sub(r'\\(["\\])', r"\1", val)
    fallback_match = re.search(rf"^{field_name}:\s*([^\n\r]+)", text, re.MULTILINE)
    if fallback_match:
        return fallback_match.group(1).strip().strip("'\"")
    return None


def _resolve_one_liner(
    text: str, title: str, title_ja: str, extracted_desc: Optional[str]
) -> str:
    """Resolves or generates structured one-liner summary."""
    is_legacy = (
        not extracted_desc
        or "課題分析と防御モデルの検証" in extracted_desc
        or extracted_desc == "unknown"
    )
    if is_legacy:
        sum_data = generate_structured_summary(
            title=title,
            abstract=text[:1500],
            clean_id="unknown",
            japanese_title=title_ja,
        )
        return sum_data["executive_summary"]
    return extracted_desc or ""


def _resolve_threat_category(extracted_tags: str) -> str:
    """Extracts first valid threat category tag."""
    if not extracted_tags:
        return "cs.CR"
    cat = extracted_tags.split(",")[0].strip("[] '\"")
    return cat if cat else "cs.CR"


def _format_keyphrases_str(text: str, title: str) -> str:
    """Extracts and formats markdown inline keyphrases."""
    keyphrases = extract_keyphrases(f"{title} {text[:1500]}", top_k=3)
    return ", ".join([f"`{k}`" for k in keyphrases]) if keyphrases else "`Security`"


def _resolve_paper_title_and_desc(
    text: str,
) -> Tuple[str, str, str, str, str]:
    """Resolves title, japanese title, description, keyphrases, and threat category."""
    extracted_title = _extract_frontmatter_field(text, "title") or "unknown"
    extracted_title_ja = _extract_frontmatter_field(
        text, "title_ja"
    ) or translate_title_ja(extracted_title)
    extracted_desc = _extract_frontmatter_field(text, "description")
    extracted_tags = _extract_frontmatter_field(text, "tags") or ""

    one_liner = _resolve_one_liner(
        text, extracted_title, extracted_title_ja, extracted_desc
    )
    keyphrases_str = _format_keyphrases_str(text, extracted_title)
    threat_cat = _resolve_threat_category(extracted_tags)

    return extracted_title, extracted_title_ja, one_liner, keyphrases_str, threat_cat


def _parse_paper_meta_fields(
    text: str, pf: str
) -> Tuple[str, str, str, str, str, str, str]:
    """Parses frontmatter fields and regex matches from OKF text."""
    (
        t_str,
        t_ja,
        one_liner,
        keyphrases_str,
        threat_cat,
    ) = _resolve_paper_title_and_desc(text)
    arxiv_match = re.search(r"arXiv ID = \[`([^`]+)`\]", text)
    extracted_date = _extract_frontmatter_field(text, "published_date") or "N/A"
    ar_id = (
        arxiv_match.group(1) if arxiv_match else os.path.basename(pf).replace(".md", "")
    )
    return (
        t_str,
        t_ja,
        one_liner,
        ar_id,
        extracted_date,
        keyphrases_str,
        threat_cat,
    )


def get_paper_meta_extended(
    pf: str,
) -> Tuple[str, str, str, str, str, str, str]:
    """Retrieves or caches extended paper metadata extracted from OKF markdown file."""
    mtime = os.path.getmtime(pf) if os.path.exists(pf) else 0
    if pf in PAPER_META_CACHE and PAPER_META_CACHE[pf]["mtime"] == mtime:
        return cast(
            Tuple[str, str, str, str, str, str, str],
            PAPER_META_CACHE[pf]["data"],
        )

    with open(pf, "r", encoding="utf-8") as f:
        text = f.read()

    res = _parse_paper_meta_fields(text, pf)
    PAPER_META_CACHE[pf] = {"mtime": mtime, "data": res}
    return res


def get_paper_meta_cached(pf: str) -> Tuple[str, str, str, str, str]:
    """Retrieves standard 5-tuple paper metadata for backward compatibility."""
    res = get_paper_meta_extended(pf)
    return res[0], res[1], res[2], res[3], res[4]


def build_summary_table_md(paper_files: List[str], base_summary_path: str) -> str:
    """Builds a structured markdown table with NLP keyphrases and 3-point summaries."""
    if not paper_files:
        return "論文データはありません。\n"

    rows: List[str] = [
        "| No | arXiv ID | 論文タイトル (日本語訳) | 重要キーワード | 構造化エグゼクティブ要約 (背景・提案・影響) | 脅威分類 | 詳細リンク |",
        "|---|---|---|---|---|---|---|",
    ]

    for idx, pf in enumerate(paper_files, 1):
        (
            t_str,
            t_ja,
            one_liner,
            ar_id,
            p_date,
            keyphrases_str,
            threat_cat,
        ) = get_paper_meta_extended(pf)
        rel_okf = os.path.relpath(pf, os.path.dirname(base_summary_path))

        c_t_ja = t_ja.replace("|", "&#124;").replace("\n", " ").strip()
        c_one_liner = one_liner.replace("|", "&#124;").replace("\n", " ").strip()

        row_str = (
            f"| {idx} | `{ar_id}` | [{c_t_ja}]({rel_okf}) | {keyphrases_str} | "
            f"{c_one_liner} | `{threat_cat}` | [arXiv](https://arxiv.org/abs/{ar_id}) &#124; [OKF]({rel_okf}) |"
        )
        rows.append(row_str)

    return "\n".join(rows) + "\n"


def generate_per_run_summary(
    new_items: List[Dict[str, Any]], workspace_dir: str, config: Dict[str, Any]
) -> str:
    """Generates 01_per_run summary report for the current batch execution."""
    now_dt = datetime.now(timezone.utc)
    date_str = now_dt.strftime("%Y-%m-%d")
    time_str = now_dt.strftime("%H%M")
    run_dir = os.path.join(workspace_dir, config["paths"]["per_run_dir"], date_str)
    os.makedirs(run_dir, exist_ok=True)

    filepath = os.path.join(run_dir, f"run_{time_str}.md")
    rows: List[str] = [
        "| No | arXiv ID | 論文タイトル (日本語訳) | 重要キーワード | 構造化エグゼクティブ要約 (背景・提案・影響) | 脅威分類 | 詳細リンク |",
        "|---|---|---|---|---|---|---|",
    ]
    raw_papers: List[Dict[str, Any]] = []

    for idx, item in enumerate(new_items, 1):
        paper = item["paper"]
        exec_sum = item.get("exec_summary", {})
        one_liner = exec_sum.get("one_liner", item.get("description", ""))
        rel_okf = os.path.relpath(item["okf_path"], os.path.dirname(filepath))
        t_ja = item.get("title_ja", translate_title_ja(paper["title"]))
        c_t_ja = t_ja.replace("|", "&#124;").replace("\n", " ").strip()
        c_one_liner = one_liner.replace("|", "&#124;").replace("\n", " ").strip()

        kws = exec_sum.get("keyphrases") or extract_keyphrases(
            f"{paper['title']} {paper.get('summary', '')}", top_k=3
        )
        kw_str = ", ".join([f"`{k}`" for k in kws]) if kws else "`Security`"
        threat_tag = paper.get("primary_category", "cs.CR")

        row_str = (
            f"| {idx} | `{paper['arxiv_id']}` | [{c_t_ja}]({rel_okf}) | {kw_str} | "
            f"{c_one_liner} | `{threat_tag}` | [arXiv]({paper['abs_url']}) &#124; [OKF]({rel_okf}) |"
        )
        rows.append(row_str)
        raw_papers.append(
            {
                "title": paper["title"],
                "title_ja": t_ja,
                "abstract": paper.get("summary", ""),
                "tags": paper.get("tags", ["cs.CR"]),
            }
        )

    table_md = "\n".join(rows) + "\n"
    trends = synthesize_thematic_trends(raw_papers, date_str)

    raw_template = load_template(
        "01_per_run.md.template",
        """---
type: "executive-summary-run"
title: "arXiv セキュリティ 取得時エグゼクティブサマリー ({date_str} {time_str} UTC)"
description: "取得バッチ実行における新着セキュリティ論文 {count} 件のエグゼクティブサマリー"
timestamp: "{timestamp}"
---

# ⏱️ 01_per_run: 取得時エグゼクティブサマリー報告書 ({date_str} {time_str} UTC)

**実行日時**: {datetime_utc}
**新着論文数**: {count} 件

---

## 💡 エグゼクティブサマリー (Executive Summary)

{macro_insights}

---

## 📌 新着セキュリティ論文一覧 (日本語表形式)

{table_md}
""",
        workspace_dir,
        config,
    )

    content = raw_template.format(
        date_str=date_str,
        time_str=time_str,
        count=len(new_items),
        timestamp=now_dt.strftime("%Y-%m-%dT%H:%M:%SZ"),
        datetime_utc=now_dt.strftime("%Y-%m-%d %H:%M:%S UTC"),
        macro_insights=trends["macro_insights"],
        table_md=table_md,
    )

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content)

    return filepath


def _collect_window_papers(
    okf_root: str, ref_dt: datetime, window_days: int
) -> List[str]:
    papers: List[str] = []
    for i in range(window_days):
        target_day = (ref_dt - timedelta(days=i)).strftime("%Y-%m-%d")
        target_dir = os.path.join(okf_root, target_day)
        if os.path.exists(target_dir):
            for fname in sorted(os.listdir(target_dir)):
                if fname.endswith(".md"):
                    papers.append(os.path.join(target_dir, fname))
    return papers


def _build_paper_dicts_from_files(
    paper_files: List[str],
) -> List[Dict[str, Any]]:
    """Converts OKF files to raw paper dictionaries for thematic synthesis."""
    results: List[Dict[str, Any]] = []
    for pf in paper_files:
        (
            t_str,
            t_ja,
            one_liner,
            ar_id,
            p_date,
            keyphrases_str,
            threat_cat,
        ) = get_paper_meta_extended(pf)
        results.append(
            {
                "title": t_str,
                "title_ja": t_ja,
                "abstract": one_liner,
                "tags": [threat_cat],
            }
        )
    return results


def _write_single_daily_summary(
    day: str, day_dir: str, daily_dir: str, workspace_dir: str, config: Dict[str, Any]
) -> str:
    """Renders and writes daily summary markdown for one day with trends."""
    paper_files = [
        os.path.join(day_dir, fname)
        for fname in sorted(os.listdir(day_dir))
        if fname.endswith(".md")
    ]
    filepath = os.path.join(daily_dir, f"{day}.md")
    table_md = build_summary_table_md(paper_files, filepath)
    paper_dicts = _build_paper_dicts_from_files(paper_files)
    trends = synthesize_thematic_trends(paper_dicts, day)
    now_str = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    raw_template = load_template(
        "02_daily.md.template",
        """---
type: "executive-summary-daily"
title: "arXiv セキュリティ 日次エグゼクティブサマリー ({date_str})"
description: "{date_str} に公開・収集されたセキュリティ論文 {count} 件の日次集計レポート"
timestamp: "{timestamp}"
---

# 📅 02_daily: 日次エグゼクティブサマリー報告書 ({date_str})

**集計日時**: {datetime_utc}
**対象日付**: {date_str}
**本日収集論文数**: {count} 件

---

## 💡 主要セキュリティ動向・脅威インサイト (Executive Insights)

{macro_insights}

### 🗺️ 技術・脅威トピックマインドマップ
{mermaid_mindmap}

---

## 📌 日次セキュリティ論文一覧 (日本語表形式)

{table_md}
""",
        workspace_dir,
        config,
    )

    content = raw_template.format(
        day=day,
        date_str=day,
        count=len(paper_files),
        timestamp=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        datetime_utc=now_str,
        macro_insights=trends["macro_insights"],
        mermaid_mindmap=trends["mermaid_mindmap"],
        table_md=table_md,
    )

    with open(filepath, "w", encoding="utf-8") as out_f:
        out_f.write(content)
    return filepath


def generate_all_daily_summaries(workspace_dir: str, config: Dict[str, Any]) -> str:
    """Generates 02_daily aggregated summary reports for each day in okf_papers."""
    okf_root = os.path.join(workspace_dir, config["paths"]["okf_papers_dir"])
    daily_dir = os.path.join(workspace_dir, config["paths"]["daily_dir"])
    os.makedirs(daily_dir, exist_ok=True)

    last_daily_path = ""
    if not os.path.exists(okf_root):
        return last_daily_path

    for day in sorted(os.listdir(okf_root)):
        day_dir = os.path.join(okf_root, day)
        if os.path.isdir(day_dir):
            last_daily_path = _write_single_daily_summary(
                day, day_dir, daily_dir, workspace_dir, config
            )

    return last_daily_path


def _parse_summary_ref_date(day_str: str) -> Optional[datetime]:
    """Parses date string safely for periodic summary generation."""
    try:
        return datetime.strptime(day_str, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except Exception:
        return None


def _get_sorted_okf_days(okf_root: str) -> List[str]:
    """Returns sorted list of daily directories in okf_papers."""
    if not os.path.exists(okf_root):
        return []
    return sorted(
        [d for d in os.listdir(okf_root) if os.path.isdir(os.path.join(okf_root, d))]
    )


def _write_single_monthly_summary(
    day_str: str,
    ref_dt: datetime,
    okf_root: str,
    monthly_dir: str,
    workspace_dir: str,
    config: Dict[str, Any],
) -> str:
    """Renders and writes 03_monthly summary file with macro trends."""
    monthly_papers = _collect_window_papers(okf_root, ref_dt, 30)
    filepath = os.path.join(monthly_dir, f"monthly_{day_str}.md")
    table_md = build_summary_table_md(monthly_papers, filepath)
    paper_dicts = _build_paper_dicts_from_files(monthly_papers)
    trends = synthesize_thematic_trends(paper_dicts, f"月次: {day_str}")

    raw_template = load_template(
        "03_monthly.md.template",
        """---
type: "executive-summary-monthly"
title: "arXiv セキュリティ 月次エグゼクティブサマリー ({date_str})"
description: "過去30日間に収集されたセキュリティ論文 {count} 件の月次包括レポート"
timestamp: "{timestamp}"
---

# 📊 03_monthly: 月次エグゼクティブサマリー報告書 (直近30日間: {date_str})

**集計日時**: {datetime_utc}
**直近30日間の総論文数**: {count} 件

---

## 💡 マクロ脅威動向 & 戦略的リスク評価 (Strategic Executive Insights)

{macro_insights}

### 🗺️ 月次セキュリティ技術レーダー (Technology Radar)
{mermaid_mindmap}

---

## 📌 月次セキュリティ論文一覧 (日本語表形式)

{table_md}
""",
        workspace_dir,
        config,
    )

    content = raw_template.format(
        date_str=day_str,
        count=len(monthly_papers),
        timestamp=ref_dt.strftime("%Y-%m-%dT%H:%M:%SZ"),
        datetime_utc=ref_dt.strftime("%Y-%m-%d %H:%M:%S UTC"),
        macro_insights=trends["macro_insights"],
        mermaid_mindmap=trends["mermaid_mindmap"],
        table_md=(
            table_md if monthly_papers else "過去30日間の論文データはありません。"
        ),
    )
    with open(filepath, "w", encoding="utf-8") as out_f:
        out_f.write(content)
    return filepath


def _is_monthly_summary_day(day_str: str, max_day: str) -> Optional[datetime]:
    """Checks if day is eligible for monthly summary and returns datetime."""
    ref_dt = _parse_summary_ref_date(day_str)
    if ref_dt is None:
        return None
    if (ref_dt + timedelta(days=1)).day == 1 or day_str == max_day:
        return ref_dt
    return None


def generate_monthly_summary(workspace_dir: str, config: Dict[str, Any]) -> str:
    """Generates 03_monthly 30-day aggregated summary reports."""
    okf_root = os.path.join(workspace_dir, config["paths"]["okf_papers_dir"])
    monthly_dir = os.path.join(workspace_dir, config["paths"]["monthly_dir"])
    os.makedirs(monthly_dir, exist_ok=True)

    all_days = _get_sorted_okf_days(okf_root)
    if not all_days:
        return ""
    max_day = all_days[-1]
    last_filepath = ""

    for day_str in all_days:
        ref_dt = _is_monthly_summary_day(day_str, max_day)
        if ref_dt is not None:
            last_filepath = _write_single_monthly_summary(
                day_str, ref_dt, okf_root, monthly_dir, workspace_dir, config
            )

    return last_filepath


def _write_single_quarterly_summary(
    day_str: str,
    ref_dt: datetime,
    okf_root: str,
    q_dir: str,
    workspace_dir: str,
    config: Dict[str, Any],
) -> str:
    """Renders and writes 04_quarterly summary file."""
    quarterly_papers = _collect_window_papers(okf_root, ref_dt, 90)
    filepath = os.path.join(q_dir, f"quarterly_{day_str}.md")
    table_md = build_summary_table_md(quarterly_papers, filepath)
    paper_dicts = _build_paper_dicts_from_files(quarterly_papers)
    trends = synthesize_thematic_trends(paper_dicts, f"四半期: {day_str}")

    raw_template = load_template(
        "04_quarterly.md.template",
        """---
type: "executive-summary-quarterly"
title: "arXiv セキュリティ 四半期エグゼクティブサマリー ({date_str})"
description: "過去90日間に収集されたセキュリティ論文 {count} 件の四半期包括レポート"
timestamp: "{timestamp}"
---

# 🏢 04_quarterly: 四半期エグゼクティブサマリー報告書 (直近90日間: {date_str})

**集計日時**: {datetime_utc}
**直近90日間の総論文数**: {count} 件

---

## 💡 四半期セキュリティ動向と研究ロードマップ評価

{macro_insights}

### 🗺️ 四半期脅威ランドスケープ
{mermaid_mindmap}

---

## 📌 四半期セキュリティ論文一覧 (日本語表形式)

{table_md}
""",
        workspace_dir,
        config,
    )

    content = raw_template.format(
        date_str=day_str,
        count=len(quarterly_papers),
        timestamp=ref_dt.strftime("%Y-%m-%dT%H:%M:%SZ"),
        datetime_utc=ref_dt.strftime("%Y-%m-%d %H:%M:%S UTC"),
        macro_insights=trends["macro_insights"],
        mermaid_mindmap=trends["mermaid_mindmap"],
        table_md=(
            table_md if quarterly_papers else "過去90日間の論文データはありません。"
        ),
    )
    with open(filepath, "w", encoding="utf-8") as out_f:
        out_f.write(content)
    return filepath


def _is_quarterly_summary_day(day_str: str, max_day: str) -> Optional[datetime]:
    """Checks if day is eligible for quarterly summary and returns datetime."""
    ref_dt = _parse_summary_ref_date(day_str)
    if ref_dt is None:
        return None
    quarter_ends = {"03-31", "06-30", "09-30", "12-31"}
    if ref_dt.strftime("%m-%d") in quarter_ends or day_str == max_day:
        return ref_dt
    return None


def generate_quarterly_summary(workspace_dir: str, config: Dict[str, Any]) -> str:
    """Generates 04_quarterly 90-day aggregated summary reports."""
    okf_root = os.path.join(workspace_dir, config["paths"]["okf_papers_dir"])
    q_dir = os.path.join(workspace_dir, config["paths"]["quarterly_dir"])
    os.makedirs(q_dir, exist_ok=True)

    all_days = _get_sorted_okf_days(okf_root)
    if not all_days:
        return ""
    max_day = all_days[-1]
    last_filepath = ""

    for day_str in all_days:
        ref_dt = _is_quarterly_summary_day(day_str, max_day)
        if ref_dt is not None:
            last_filepath = _write_single_quarterly_summary(
                day_str, ref_dt, okf_root, q_dir, workspace_dir, config
            )

    return last_filepath


def _write_single_annual_summary(
    day_str: str,
    ref_dt: datetime,
    okf_root: str,
    annual_dir: str,
    workspace_dir: str,
    config: Dict[str, Any],
) -> str:
    """Renders and writes 05_annual summary file."""
    annual_papers = _collect_window_papers(okf_root, ref_dt, 365)
    filepath = os.path.join(annual_dir, f"annual_{day_str}.md")
    table_md = build_summary_table_md(annual_papers, filepath)
    paper_dicts = _build_paper_dicts_from_files(annual_papers)
    trends = synthesize_thematic_trends(paper_dicts, f"年次: {day_str}")

    raw_template = load_template(
        "05_annual.md.template",
        """---
type: "executive-summary-annual"
title: "arXiv セキュリティ 年次エグゼクティブサマリー ({date_str})"
description: "過去365日間に収集されたセキュリティ論文 {count} 件の年次包括レポート"
timestamp: "{timestamp}"
---

# 🌐 05_annual: 年次エグゼクティブサマリー報告書 (通期365日間: {date_str})

**集計日時**: {datetime_utc}
**通期365日間の総論文数**: {count} 件

---

## 💡 年次セキュリティ技術トレンド総括 (Annual Strategic Synthesis)

{macro_insights}

### 🗺️ 年次セキュリティ脅威マインドマップ
{mermaid_mindmap}

---

## 📌 年次セキュリティ論文一覧 (日本語表形式)

{table_md}
""",
        workspace_dir,
        config,
    )

    content = raw_template.format(
        date_str=day_str,
        count=len(annual_papers),
        timestamp=ref_dt.strftime("%Y-%m-%dT%H:%M:%SZ"),
        datetime_utc=ref_dt.strftime("%Y-%m-%d %H:%M:%S UTC"),
        macro_insights=trends["macro_insights"],
        mermaid_mindmap=trends["mermaid_mindmap"],
        table_md=(
            table_md if annual_papers else "過去365日間の論文データはありません。"
        ),
    )
    with open(filepath, "w", encoding="utf-8") as out_f:
        out_f.write(content)
    return filepath


def _is_annual_summary_day(day_str: str, max_day: str) -> Optional[datetime]:
    """Checks if day is eligible for annual summary and returns datetime."""
    ref_dt = _parse_summary_ref_date(day_str)
    if ref_dt is None:
        return None
    if ref_dt.strftime("%m-%d") == "12-31" or day_str == max_day:
        return ref_dt
    return None


def generate_annual_summary(workspace_dir: str, config: Dict[str, Any]) -> str:
    """Generates 05_annual 365-day aggregated summary reports."""
    okf_root = os.path.join(workspace_dir, config["paths"]["okf_papers_dir"])
    annual_dir = os.path.join(workspace_dir, config["paths"]["annual_dir"])
    os.makedirs(annual_dir, exist_ok=True)

    all_days = _get_sorted_okf_days(okf_root)
    if not all_days:
        return ""
    max_day = all_days[-1]
    last_filepath = ""

    for day_str in all_days:
        ref_dt = _is_annual_summary_day(day_str, max_day)
        if ref_dt is not None:
            last_filepath = _write_single_annual_summary(
                day_str, ref_dt, okf_root, annual_dir, workspace_dir, config
            )

    return last_filepath
