#!/usr/bin/env python3
"""
arXiv Security Papers Multi-Tiered OKF & Executive Summary Pipeline Orchestrator
Coordinates the 3-Tier ETL Architecture (Ingestion -> Transformer -> Reporter).
Maintains 100% backward compatibility with all existing APIs and CLI flags.
"""

import argparse
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

# 1. Ingestion Layer (Extract)
from .ingestion import (
    clean_text,
    fetch_arxiv_papers,
    fetch_arxiv_rss_fallback,
    fetch_single_pdf_and_text,
    get_paper_pub_date_str,
    load_config,
    parse_arxiv_entry,
    save_raw_paper_data,
)

# 3. Reporter Layer (Load & Report)
from .reporter import (
    PAPER_META_CACHE,
    build_summary_table_md,
    generate_all_daily_summaries,
    generate_annual_summary,
    generate_mermaid_mindmap,
    generate_monthly_summary,
    generate_per_run_summary,
    generate_quarterly_summary,
    get_paper_meta_cached,
    update_index_and_log,
)

# 2. Transformer Layer (Transform)
from .transformer import (
    build_okf_from_raw,
    classify_domain,
    determine_security_tags,
    extract_mitre_and_stride,
    generate_japanese_executive_summary,
    load_template,
    translate_title_ja,
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
    "translate_title_ja",
    "classify_domain",
    "determine_security_tags",
    "extract_mitre_and_stride",
    "generate_japanese_executive_summary",
    "load_template",
    "build_okf_from_raw",
    "PAPER_META_CACHE",
    "get_paper_meta_cached",
    "build_summary_table_md",
    "generate_per_run_summary",
    "generate_all_daily_summaries",
    "generate_monthly_summary",
    "generate_quarterly_summary",
    "generate_annual_summary",
    "generate_mermaid_mindmap",
    "update_index_and_log",
    "run_pipeline",
    "main",
]


def run_pipeline(
    workspace_dir: str,
    config: Dict[str, Any],
    query: str = "cat:cs.CR",
    max_results: int = 3500,
    start_dt: Optional[datetime] = None,
    end_dt: Optional[datetime] = None,
    force: bool = False,
    max_workers: int = 15,
) -> List[Dict[str, Any]]:
    """Executes the full 3-tier ETL pipeline:

    1. Extract: Fetches papers from arXiv and downloads PDFs.
    2. Transform: Generates OKF v0.2 markdown files.
    3. Report: Builds 5-tier summaries and index catalog.
    """
    state_path = os.path.join(workspace_dir, config["paths"]["state_file"])
    processed_state: Dict[str, Any] = {}
    if os.path.exists(state_path):
        try:
            with open(state_path, "r", encoding="utf-8") as f:
                processed_state = json.load(f)
        except Exception:
            processed_state = {}

    print(
        f"[{datetime.now().isoformat()}] [ETL:Ingestion] Fetching papers from arXiv (query={query}, max_results={max_results})..."
    )
    papers = fetch_arxiv_papers(query=query, max_results=max_results)
    if not papers:
        papers = fetch_arxiv_rss_fallback(max_results=min(max_results, 50))

    if not papers:
        print("[ETL:Ingestion] No papers fetched.")
        return []

    pdf_fetch_tasks = []

    # Step 1: Save metadata JSON and raw abstract TXT
    for paper in papers:
        arxiv_id = paper["arxiv_id"]

        pub_str = paper.get("published")
        if pub_str and len(pub_str) >= 10:
            try:
                pub_dt = datetime.strptime(pub_str[:10], "%Y-%m-%d").replace(
                    tzinfo=timezone.utc
                )
                if start_dt and pub_dt < start_dt:
                    continue
                if end_dt and pub_dt > end_dt:
                    continue
            except Exception:
                pass

        if arxiv_id in processed_state and not force:
            continue

        raw_meta_path = save_raw_paper_data(paper, workspace_dir, config)
        date_str = get_paper_pub_date_str(paper)
        raw_dir = os.path.join(workspace_dir, config["paths"]["raw_data_dir"], date_str)
        pdf_fetch_tasks.append((paper, raw_dir, raw_meta_path))

    # Step 2: Download PDFs & extract TXT in parallel
    print(
        f"[{datetime.now().isoformat()}] [ETL:Ingestion] Downloading PDFs & pdftotext "
        f"for {len(pdf_fetch_tasks)} papers with {max_workers} parallel threads..."
    )
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [
            executor.submit(fetch_single_pdf_and_text, p, r_dir)
            for p, r_dir, _ in pdf_fetch_tasks
        ]
        for _ in as_completed(futures):
            pass

    # Step 3: Transform & Build OKF files
    print(
        f"[{datetime.now().isoformat()}] [ETL:Transformer] Serializing Google OKF v0.2 documents..."
    )
    processed_items = []
    for paper, raw_dir, raw_meta_path in pdf_fetch_tasks:
        item = build_okf_from_raw(raw_meta_path, workspace_dir, config)
        processed_items.append(item)

        processed_state[paper["arxiv_id"]] = {
            "processed_at": datetime.now(timezone.utc).isoformat(),
            "published": paper.get("published"),
            "title": paper["title"],
            "title_ja": item["title_ja"],
            "raw_meta_path": os.path.relpath(raw_meta_path, workspace_dir),
            "okf_path": item["rel_okf_path"],
        }

    with open(state_path, "w", encoding="utf-8") as f:
        json.dump(processed_state, f, ensure_ascii=False, indent=2)

    # Step 4: Report & Generate 5-tier summaries
    print(
        f"[{datetime.now().isoformat()}] [ETL:Reporter] Generating 5-tier executive summaries and updating index catalog..."
    )
    if processed_items:
        per_run_path = generate_per_run_summary(processed_items, workspace_dir, config)
    else:
        now_dt = datetime.now(timezone.utc)
        date_str = now_dt.strftime("%Y-%m-%d")
        time_str = now_dt.strftime("%H%M")
        run_dir = os.path.join(workspace_dir, config["paths"]["per_run_dir"], date_str)
        os.makedirs(run_dir, exist_ok=True)
        per_run_path = os.path.join(run_dir, f"run_{time_str}.md")
        with open(per_run_path, "w", encoding="utf-8") as f:
            f.write(
                f"# Run Summary ({date_str} {time_str} UTC)\nNo new papers processed in this run.\n"
            )

    daily_path = generate_all_daily_summaries(workspace_dir, config)
    monthly_path = generate_monthly_summary(workspace_dir, config)
    quarterly_path = generate_quarterly_summary(workspace_dir, config)
    annual_path = generate_annual_summary(workspace_dir, config)

    update_index_and_log(
        workspace_dir,
        processed_items,
        per_run_path,
        daily_path,
        monthly_path,
        quarterly_path,
        annual_path,
        config,
    )

    print(
        f"[{datetime.now().isoformat()}] [ETL:Pipeline] Complete! Processed {len(processed_items)} papers."
    )
    return processed_items


def main() -> None:
    """CLI Entrypoint for arXiv Security Papers ETL Pipeline."""
    parser = argparse.ArgumentParser(
        description="arXiv Security Papers OKF & Summary Generator (ETL 3-Tier)"
    )
    parser.add_argument("--start-date", type=str, help="Start date (YYYY-MM-DD)")
    parser.add_argument("--end-date", type=str, help="End date (YYYY-MM-DD)")
    parser.add_argument("--max-results", type=int, help="Max results to fetch")
    parser.add_argument(
        "--force", action="store_true", help="Force reprocessing existing papers"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Run without network operations"
    )
    args, _ = parser.parse_known_args()

    current_dir = os.path.dirname(os.path.abspath(__file__))
    if os.path.exists(os.path.join(current_dir, "..", "config.json")):
        workspace_dir = os.path.abspath(os.path.join(current_dir, ".."))
    elif os.path.exists(os.path.join(current_dir, "..", "..", "config.json")):
        workspace_dir = os.path.abspath(os.path.join(current_dir, "..", ".."))
    else:
        workspace_dir = current_dir

    config = load_config()
    query = config.get("arxiv", {}).get("query", "cat:cs.CR")
    start_dt = None
    end_dt = None

    if args.start_date:
        start_dt = datetime.strptime(args.start_date, "%Y-%m-%d").replace(
            tzinfo=timezone.utc
        )
        if args.end_date:
            end_dt = datetime.strptime(args.end_date, "%Y-%m-%d").replace(
                hour=23, minute=59, second=59, tzinfo=timezone.utc
            )
        else:
            end_dt = datetime.now(timezone.utc)
        start_str = args.start_date.replace("-", "")
        end_str = (
            args.end_date or datetime.now(timezone.utc).strftime("%Y-%m-%d")
        ).replace("-", "")
        query = f"cat:cs.CR AND submittedDate:[{start_str}0000 TO {end_str}2359]"
    else:
        days_back = config.get("arxiv", {}).get("days_back", 160)
        start_dt = datetime.now(timezone.utc) - timedelta(days=days_back)

    max_results = (
        args.max_results
        if args.max_results is not None
        else config.get("arxiv", {}).get("max_results_per_run", 3500)
    )

    if args.dry_run:
        print("[DRY-RUN] Dry run mode enabled. Validating local templates and index...")
        daily_path = generate_all_daily_summaries(workspace_dir, config)
        monthly_path = generate_monthly_summary(workspace_dir, config)
        quarterly_path = generate_quarterly_summary(workspace_dir, config)
        annual_path = generate_annual_summary(workspace_dir, config)
        update_index_and_log(
            workspace_dir,
            [],
            "",
            daily_path,
            monthly_path,
            quarterly_path,
            annual_path,
            config,
        )
        print("[DRY-RUN] Dry run validation completed successfully.")
        return

    run_pipeline(
        workspace_dir=workspace_dir,
        config=config,
        query=query,
        max_results=max_results,
        start_dt=start_dt,
        end_dt=end_dt,
        force=args.force or "--force" in sys.argv,
    )


if __name__ == "__main__":
    main()
