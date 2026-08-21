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
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

# 1. Ingestion Layer (Extract)
try:
    from .ingestion import (
        ArxivSourceAdapter,
        BaseSourceAdapter,
        FeedSourceAdapter,
        IacrEprintSourceAdapter,
        RawItem,
        SourceRegistry,
        clean_text,
        fetch_arxiv_papers,
        fetch_arxiv_rss_fallback,
        fetch_single_pdf_and_text,
        get_paper_pub_date_str,
        get_source_registry,
        load_config,
        parse_arxiv_entry,
        save_raw_paper_data,
    )
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
    from .transformer import (
        SourceConfig,
        ThemeConfig,
        ThemeManager,
        build_okf_from_raw,
        classify_domain,
        determine_security_tags,
        extract_mitre_and_stride,
        generate_japanese_executive_summary,
        get_theme_manager,
        load_template,
        translate_title_ja,
    )
except ImportError:
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    from fetcher.ingestion import (
        ArxivSourceAdapter,
        BaseSourceAdapter,
        FeedSourceAdapter,
        IacrEprintSourceAdapter,
        RawItem,
        SourceRegistry,
        clean_text,
        fetch_arxiv_papers,
        fetch_arxiv_rss_fallback,
        fetch_single_pdf_and_text,
        get_paper_pub_date_str,
        get_source_registry,
        load_config,
        parse_arxiv_entry,
        save_raw_paper_data,
    )
    from fetcher.reporter import (
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
    from fetcher.transformer import (
        SourceConfig,
        ThemeConfig,
        ThemeManager,
        build_okf_from_raw,
        classify_domain,
        determine_security_tags,
        extract_mitre_and_stride,
        generate_japanese_executive_summary,
        get_theme_manager,
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
    "run_theme_pipeline",
    "BaseSourceAdapter",
    "RawItem",
    "ArxivSourceAdapter",
    "IacrEprintSourceAdapter",
    "FeedSourceAdapter",
    "SourceRegistry",
    "get_source_registry",
    "SourceConfig",
    "ThemeConfig",
    "ThemeManager",
    "get_theme_manager",
    "main",
]


def _load_state(state_path: str) -> Dict[str, Any]:
    if os.path.exists(state_path):
        try:
            with open(state_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data if isinstance(data, dict) else {}
        except Exception:
            return {}
    return {}


def _is_date_in_range(
    pub_str: Optional[str], start_dt: Optional[datetime], end_dt: Optional[datetime]
) -> bool:
    if pub_str and len(pub_str) >= 10:
        try:
            pub_dt = datetime.strptime(pub_str[:10], "%Y-%m-%d").replace(
                tzinfo=timezone.utc
            )
            if start_dt and pub_dt < start_dt:
                return False
            if end_dt and pub_dt > end_dt:
                return False
        except Exception:
            pass
    return True


def _filter_and_stage_papers(
    papers: List[Dict[str, Any]],
    workspace_dir: str,
    config: Dict[str, Any],
    processed_state: Dict[str, Any],
    start_dt: Optional[datetime],
    end_dt: Optional[datetime],
    force: bool,
) -> List[tuple[Dict[str, Any], str, str]]:
    tasks = []
    for paper in papers:
        arxiv_id = paper["arxiv_id"]
        if not _is_date_in_range(paper.get("published"), start_dt, end_dt):
            continue
        if arxiv_id in processed_state and not force:
            continue
        raw_meta_path = save_raw_paper_data(paper, workspace_dir, config)
        date_str = get_paper_pub_date_str(paper)
        raw_dir = os.path.join(workspace_dir, config["paths"]["raw_data_dir"], date_str)
        tasks.append((paper, raw_dir, raw_meta_path))
    return tasks


def _transform_and_save_okf(
    pdf_fetch_tasks: List[tuple[Dict[str, Any], str, str]],
    workspace_dir: str,
    config: Dict[str, Any],
    processed_state: Dict[str, Any],
    state_path: str,
) -> List[Dict[str, Any]]:
    processed_items = []
    for paper, _, raw_meta_path in pdf_fetch_tasks:
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
    return processed_items


def _generate_summaries_and_index(
    workspace_dir: str,
    config: Dict[str, Any],
    processed_items: List[Dict[str, Any]],
) -> None:
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
    """Executes the full 3-tier ETL pipeline."""
    state_path = os.path.join(workspace_dir, config["paths"]["state_file"])
    processed_state = _load_state(state_path)

    papers = fetch_arxiv_papers(
        query=query, max_results=max_results
    ) or fetch_arxiv_rss_fallback(max_results=min(max_results, 50))
    if not papers:
        print("[ETL:Ingestion] No papers fetched.")
        return []

    pdf_fetch_tasks = _filter_and_stage_papers(
        papers, workspace_dir, config, processed_state, start_dt, end_dt, force
    )

    now_str = datetime.now().isoformat()
    print(
        f"[{now_str}] [ETL:Ingestion] Downloading PDFs & pdftotext for {len(pdf_fetch_tasks)} papers..."
    )
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [
            executor.submit(fetch_single_pdf_and_text, p, r_dir)
            for p, r_dir, _ in pdf_fetch_tasks
        ]
        for _ in as_completed(futures):
            pass

    processed_items = _transform_and_save_okf(
        pdf_fetch_tasks, workspace_dir, config, processed_state, state_path
    )
    _generate_summaries_and_index(workspace_dir, config, processed_items)
    return processed_items


def _fetch_theme_raw_items(
    theme: ThemeConfig,
    max_results: Optional[int],
    start_dt: Optional[datetime],
    end_dt: Optional[datetime],
) -> List[RawItem]:
    registry = get_source_registry()
    all_raw_items: List[RawItem] = []
    for src_cfg in theme.sources:
        adapter = registry.get(src_cfg.adapter)
        if not adapter:
            print(f"[WARN] No adapter found for {src_cfg.adapter}, skipping.")
            continue
        target_max = max_results if max_results is not None else src_cfg.max_results
        items = adapter.fetch_items(
            query=src_cfg.query,
            max_results=target_max,
            start_date=start_dt,
            end_date=end_dt,
            category=src_cfg.category,
            feed_url=src_cfg.feed_url,
            **src_cfg.extra_params,
        )
        all_raw_items.extend(items)
    return all_raw_items


def _ensure_config_paths(config: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    cfg = config.copy() if config else load_config()
    if "paths" not in cfg:
        cfg["paths"] = {
            "raw_data_dir": "outputs/raw_data",
            "okf_papers_dir": "outputs/okf_papers",
            "per_run_dir": "outputs/executive_summaries/01_per_run",
            "daily_dir": "outputs/executive_summaries/02_daily",
            "monthly_dir": "outputs/executive_summaries/03_monthly",
            "quarterly_dir": "outputs/executive_summaries/04_quarterly",
            "annual_dir": "outputs/executive_summaries/05_annual",
            "state_file": "processed_papers.json",
        }
    return cfg


def run_theme_pipeline(
    theme_id: str = "security",
    workspace_dir: str = "",
    config: Optional[Dict[str, Any]] = None,
    max_results: Optional[int] = None,
    start_dt: Optional[datetime] = None,
    end_dt: Optional[datetime] = None,
    force: bool = False,
    max_workers: int = 8,
) -> List[Dict[str, Any]]:
    """Executes ingestion and reporting for a specific intelligence theme."""
    if not workspace_dir:
        workspace_dir = os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..")
        )
    cfg = _ensure_config_paths(config)

    theme_mgr = get_theme_manager()
    theme = theme_mgr.get(theme_id)
    if not theme:
        print(
            f"[ERROR] Unknown theme ID: {theme_id}. Available themes: {theme_mgr.list_theme_ids()}"
        )
        return []

    print(f"=== [Theme Pipeline] Running theme '{theme.name}' ({theme.theme_id}) ===")
    all_raw_items = _fetch_theme_raw_items(theme, max_results, start_dt, end_dt)
    print(
        f"[Theme: {theme_id}] Fetched {len(all_raw_items)} items from {len(theme.sources)} sources."
    )

    papers_data = [item.to_dict() for item in all_raw_items]
    state_filename = (
        "processed_papers.json"
        if theme_id == "security"
        else f"processed_papers_{theme_id}.json"
    )
    state_path = os.path.join(workspace_dir, state_filename)
    processed_state = _load_state(state_path)

    pdf_fetch_tasks = _filter_and_stage_papers(
        papers_data, workspace_dir, cfg, processed_state, start_dt, end_dt, force
    )

    if not pdf_fetch_tasks:
        print(f"[Theme: {theme_id}] No new papers to stage.")
        return []

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [
            executor.submit(fetch_single_pdf_and_text, p, r_dir)
            for p, r_dir, _ in pdf_fetch_tasks
        ]
        for _ in as_completed(futures):
            pass

    processed_items = _transform_and_save_okf(
        pdf_fetch_tasks, workspace_dir, cfg, processed_state, state_path
    )
    _generate_summaries_and_index(workspace_dir, cfg, processed_items)
    return processed_items


def _parse_cli_date_range(
    args: argparse.Namespace,
) -> tuple[Optional[datetime], Optional[datetime]]:
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
    return start_dt, end_dt


def _detect_workspace_dir() -> str:
    current_dir = os.path.dirname(os.path.abspath(__file__))
    for rel_path in ["..", "..", "."]:
        cand = os.path.abspath(os.path.join(current_dir, rel_path))
        if os.path.exists(os.path.join(cand, "config.json")):
            return cand
    return current_dir


def _execute_dry_run_validation(workspace_dir: str, config: Dict[str, Any]) -> None:
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


def main() -> None:
    """CLI Entrypoint for Multi-Theme Papers ETL Pipeline."""
    parser = argparse.ArgumentParser(
        description="Multi-Theme Intelligence Papers OKF & Summary Generator (ETL 3-Tier)"
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
    parser.add_argument("--theme", type=str, default="security", help="Target theme")
    parser.add_argument(
        "--all-themes", action="store_true", help="Execute across all themes"
    )
    parser.add_argument(
        "--custom-theme-file", type=str, help="Path to custom theme JSON file"
    )
    args, _ = parser.parse_known_args()

    workspace_dir = _detect_workspace_dir()
    config = load_config()
    theme_mgr = get_theme_manager()

    if args.custom_theme_file:
        custom_theme = theme_mgr.load_from_json_file(args.custom_theme_file)
        if custom_theme:
            print(
                f"[Theme] Loaded custom theme: {custom_theme.name} ({custom_theme.theme_id})"
            )

    if args.dry_run:
        _execute_dry_run_validation(workspace_dir, config)
        return

    start_dt, end_dt = _parse_cli_date_range(args)
    force = args.force or "--force" in sys.argv

    theme_ids = theme_mgr.list_theme_ids() if args.all_themes else [args.theme]
    for tid in theme_ids:
        run_theme_pipeline(
            theme_id=tid,
            workspace_dir=workspace_dir,
            config=config,
            max_results=args.max_results,
            start_dt=start_dt,
            end_dt=end_dt,
            force=force,
        )


if __name__ == "__main__":
    main()
