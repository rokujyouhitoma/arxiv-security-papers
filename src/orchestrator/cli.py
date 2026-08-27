#!/usr/bin/env python3
"""Universal Intelligence Orchestrator Unified CLI Entry Point.

Serves as the central application entry point for arxiv-security-papers,
orchestrating the 6-phase intelligence lifecycle while providing subcommands
for executing individual tools (pipeline, spider, search, web, mcp, status).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional

from orchestrator.contracts import IntelligencePhase, PhaseContext, PhaseStatus
from orchestrator.engine import UniversalIntelligenceOrchestrator


def _print_banner() -> None:
    banner = """
================================================================================
   UNIVERSAL AUTONOMOUS INTELLIGENCE ORCHESTRATOR (arxiv-security-papers)
   Closed-Loop 6-Phase Intelligence Lifecycle: Planning -> Feedback
================================================================================
"""
    print(banner)


def _seed_intelligence_requirements(
    orchestrator: UniversalIntelligenceOrchestrator, topics: Optional[str]
) -> None:
    """Seeds default or custom priority intelligence requirements."""
    if topics:
        custom_topics = [t.strip() for t in topics.split(",") if t.strip()]
        orchestrator.register_pir(
            req_id=f"pir_cli_{int(time.time())}",
            title="CLI Requested Priority Requirement",
            description="Dynamically injected PIR from CLI execution",
            target_topics=custom_topics,
            priority_score=1.0,
        )
        return

    if not orchestrator.pir_manager.list_active_requirements():
        orchestrator.register_pir(
            req_id="pir_llm_sec",
            title="LLM & AI Safety Threats",
            description="Monitor prompt injection, jailbreaking, and foundation model security",
            target_topics=[
                "LLM・AIセキュリティ",
                "脱獄攻撃",
                "プロンプトインジェクション",
            ],
            priority_score=0.9,
        )
        orchestrator.register_pir(
            req_id="pir_vuln_fuzz",
            title="Vulnerability Research & Penetration Testing",
            description="Monitor automated fuzzing, exploit payloads, and binary analysis",
            target_topics=[
                "ファジング・脆弱性調査",
                "ペネトレーションテスト・脆弱性検証",
            ],
            priority_score=0.85,
        )
        orchestrator.register_pir(
            req_id="pir_crypto_priv",
            title="Cryptography & Privacy Engineering",
            description="Monitor post-quantum crypto, zero-knowledge proofs, and side-channel defenses",
            target_topics=["暗号・プライバシー技術", "耐量子暗号", "ゼロ知識証明"],
            priority_score=0.8,
        )


def _print_cycle_details(
    context: PhaseContext, cycle_id: str, elapsed_ms: float
) -> None:
    """Prints verbose execution summary for an intelligence cycle."""
    print(f"[+] Cycle {cycle_id} Completed in {elapsed_ms:.2f}ms")
    print("    Phase Execution Matrix:")
    for phase in [
        IntelligencePhase.PLANNING,
        IntelligencePhase.COLLECTION,
        IntelligencePhase.PROCESSING,
        IntelligencePhase.ANALYSIS,
        IntelligencePhase.DISSEMINATION,
        IntelligencePhase.EVALUATION,
    ]:
        status_enum = context.phase_statuses.get(phase, PhaseStatus.PENDING)
        status = status_enum.value
        symbol = "✓" if status_enum == PhaseStatus.COMPLETED else "✗"
        print(f"      [{symbol}] {phase.value:<15} : {status}")

    print(
        f"    Records Collected: {len(context.raw_records)} | "
        f"Processed: {len(context.processed_records)} | "
        f"Products: {len(context.products)}"
    )
    if context.products:
        print("    Published Intelligence Products:")
        for prod in context.products:
            print(f"      - [{prod.tier}] {prod.title} (sources: {prod.source_count})")

    if context.errors:
        print(f"    [!] Warnings/Errors encountered: {len(context.errors)}")

    print("-" * 80)


def _run_single_cycle(
    orchestrator: UniversalIntelligenceOrchestrator,
    cycle_id: str,
    args: argparse.Namespace,
) -> Dict[str, Any]:
    """Executes a single cycle and returns summary dict."""
    start_time = time.perf_counter()
    context: PhaseContext = orchestrator.run_cycle(cycle_id=cycle_id)
    elapsed_ms = (time.perf_counter() - start_time) * 1000.0

    if not args.quiet and not args.json:
        _print_cycle_details(context, cycle_id, elapsed_ms)

    return {
        "cycle_id": context.cycle_id,
        "elapsed_ms": round(elapsed_ms, 2),
        "statuses": {p.value: s.value for p, s in context.phase_statuses.items()},
        "target_topics": (context.directive.target_topics if context.directive else []),
        "raw_records_count": len(context.raw_records),
        "processed_records_count": len(context.processed_records),
        "products_count": len(context.products),
        "errors": context.errors,
        "topic_weights": orchestrator.get_current_topic_weights(),
    }


def _format_cycle_id(cycle_id_arg: Optional[str], index: int, total_cycles: int) -> str:
    """Computes cycle ID prefix and indexed name."""
    cycle_prefix = (
        cycle_id_arg
        if cycle_id_arg
        else f"cycle_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"
    )
    return f"{cycle_prefix}_{index+1}" if total_cycles > 1 else cycle_prefix


def run_cycle_command(args: argparse.Namespace) -> int:
    """Executes one or more intelligence cycles."""
    if not args.quiet and not args.json:
        _print_banner()

    workspace_dir = os.path.abspath(args.workdir)
    orchestrator = UniversalIntelligenceOrchestrator(workspace_dir=workspace_dir)
    _seed_intelligence_requirements(orchestrator, getattr(args, "topics", None))

    cycles_to_run = max(1, getattr(args, "cycles", 1))
    results_summary: List[Dict[str, Any]] = []

    for i in range(cycles_to_run):
        cycle_id = _format_cycle_id(getattr(args, "cycle_id", None), i, cycles_to_run)
        if not args.quiet and not args.json:
            print(
                f"[*] Starting Intelligence Cycle [{i+1}/{cycles_to_run}]: {cycle_id}"
            )
        cycle_result = _run_single_cycle(orchestrator, cycle_id, args)
        results_summary.append(cycle_result)

    if getattr(args, "json", False):
        print(json.dumps(results_summary, indent=2, ensure_ascii=False))

    return 1 if any(len(r["errors"]) > 0 for r in results_summary) else 0


def run_daemon_command(args: argparse.Namespace) -> int:
    """Runs recurring intelligence cycles in daemon mode."""
    _print_banner()
    interval = max(5, args.interval)
    max_cycles = args.max_cycles
    workspace_dir = os.path.abspath(args.workdir)
    orchestrator = UniversalIntelligenceOrchestrator(workspace_dir=workspace_dir)

    max_cycles_label = "Infinite" if max_cycles == 0 else str(max_cycles)
    print(
        f"[*] Starting Autonomous Orchestrator Daemon (Interval: {interval}s, Max Cycles: {max_cycles_label})"
    )

    cycle_count = 0
    try:
        while True:
            cycle_count += 1
            print(
                f"\n[{datetime.now(timezone.utc).isoformat()}] --- Daemon Cycle #{cycle_count} ---"
            )
            ctx = orchestrator.run_cycle(
                cycle_id=f"daemon_{int(time.time())}_{cycle_count}"
            )
            print(
                f"[+] Completed cycle {ctx.cycle_id}: {len(ctx.processed_records)} records, "
                f"{len(ctx.products)} products"
            )

            if max_cycles > 0 and cycle_count >= max_cycles:
                print(f"[*] Reached max cycles ({max_cycles}). Exiting daemon.")
                break

            print(f"[*] Sleeping for {interval} seconds until next cycle...")
            time.sleep(interval)
    except KeyboardInterrupt:
        print("\n[*] Daemon interrupted by user. Shutting down gracefully.")

    return 0


def _add_pir_requirement(
    orchestrator: UniversalIntelligenceOrchestrator, args: argparse.Namespace
) -> int:
    """Handles adding a new PIR."""
    if not args.id or not args.title or not args.topics:
        print("[ERROR] --id, --title, and --topics are required to add a PIR.")
        return 1
    from orchestrator.pir.models import PIRHorizon

    topics = [t.strip() for t in args.topics.split(",") if t.strip()]
    raw_horizon = getattr(args, "horizon", "operational").lower()
    try:
        horizon_val = PIRHorizon(raw_horizon)
    except ValueError:
        horizon_val = PIRHorizon.OPERATIONAL

    req = orchestrator.register_pir(
        req_id=args.id,
        title=args.title,
        description=args.description or "",
        target_topics=topics,
        priority_score=args.priority,
        horizon=horizon_val,
    )
    print(f"[+] Successfully registered PIR: [{req.req_id}] {req.title}")
    print(f"    Horizon: {req.horizon.value.upper()}")
    print(f"    Topics: {req.target_topics}")
    print(f"    Priority Score: {req.priority_score}")
    return 0


def _escalate_pir_requirement(
    orchestrator: UniversalIntelligenceOrchestrator, args: argparse.Namespace
) -> int:
    """Handles dynamically escalating an existing PIR."""
    if not args.id:
        print("[ERROR] --id is required to escalate a PIR.")
        return 1
    from orchestrator.pir.models import PIRHorizon

    reason = (
        getattr(args, "reason", "Manual operator escalation")
        or "Manual operator escalation"
    )
    raw_horizon = getattr(args, "horizon", "tactical").lower()
    try:
        target_h = PIRHorizon(raw_horizon)
    except ValueError:
        target_h = PIRHorizon.TACTICAL

    success = orchestrator.escalate_pir(
        req_id=args.id, reason=reason, target_horizon=target_h
    )
    if success:
        req = orchestrator.pir_manager.get_requirement(args.id)
        assert req is not None
        print(
            f"[+] Successfully escalated PIR [{req.req_id}] to {req.horizon.value.upper()}"
        )
        print(f"    Escalation Level: {req.escalation_level}")
        print(f"    New Priority Score: {req.priority_score:.2f}")
        print(f"    Reason: {reason}")
        return 0
    else:
        print(
            f"[ERROR] Failed to escalate PIR [{args.id}]. Not found or reached max level."
        )
        return 1


def _list_pir_requirements(
    orchestrator: UniversalIntelligenceOrchestrator,
) -> int:
    """Lists registered PIRs and topic distribution across 3 temporal horizons."""
    active_reqs = orchestrator.pir_manager.list_active_requirements()
    weights = orchestrator.get_current_topic_weights()

    print("=================================================================")
    print("   ACTIVE PRIORITY INTELLIGENCE REQUIREMENTS (PIRs)")
    print("=================================================================")
    if not active_reqs:
        print("  (No custom PIRs currently registered. Built-in defaults active.)")
    else:
        for r in active_reqs:
            horizon_tag = f"[{r.horizon.value.upper()}]"
            escalation_tag = (
                f" (Escalation Lvl: {r.escalation_level})"
                if r.escalation_level > 0
                else ""
            )
            print(
                f"  {horizon_tag} [{r.req_id}] {r.title} (Priority: {r.priority_score}){escalation_tag}"
            )
            print(f"    Topics: {', '.join(r.target_topics)}")
            if r.description:
                print(f"    Desc:   {r.description}")
            print()

    print("--- Current Topic Priority Distribution ---")
    if not weights:
        print("  (No topic weights calculated yet)")
    else:
        for topic, weight in sorted(weights.items(), key=lambda x: x[1], reverse=True):
            bar = "#" * int(weight * 30)
            print(f"  {topic:<25} : {weight:.4f} | {bar}")

    return 0


def run_pir_command(args: argparse.Namespace) -> int:
    """Manages Priority Intelligence Requirements (PIRs)."""
    orchestrator = UniversalIntelligenceOrchestrator(
        workspace_dir=os.path.abspath(args.workdir)
    )
    if args.pir_action == "add":
        return _add_pir_requirement(orchestrator, args)
    elif args.pir_action == "escalate":
        return _escalate_pir_requirement(orchestrator, args)
    return _list_pir_requirements(orchestrator)


def _list_hypotheses(
    orchestrator: UniversalIntelligenceOrchestrator,
) -> int:
    """Lists tracked intelligence hypotheses and their verification status."""
    hypotheses = orchestrator.list_hypotheses()
    print("=================================================================")
    print("   AUTONOMOUS SECURITY HYPOTHESES & VERIFICATION STATUS")
    print("=================================================================")
    if not hypotheses:
        print("  (No hypotheses formulated or evaluated yet.)")
    else:
        for h in hypotheses:
            status_str = h.status.value.upper()
            supp_n = len(h.supporting_evidence)
            ref_n = len(h.refuting_evidence)
            print(
                f"  [{status_str}] [{h.hypo_id}] (Confidence: {h.confidence_score*100:.1f}%)"
            )
            print(f"    Statement: {h.statement}")
            print(f"    Topics:    {', '.join(h.target_topics)}")
            print(f"    Evidence:  {supp_n} Supporting | {ref_n} Refuting")
            print()
    return 0


def _add_hypothesis(
    orchestrator: UniversalIntelligenceOrchestrator, args: argparse.Namespace
) -> int:
    """Registers a manual hypothesis proposition."""
    if not args.id or not args.statement or not args.topics:
        print(
            "[ERROR] --id, --statement, and --topics are required to add a hypothesis."
        )
        return 1
    topics = [t.strip() for t in args.topics.split(",") if t.strip()]
    hypo = orchestrator.register_hypothesis(
        hypo_id=args.id, statement=args.statement, target_topics=topics
    )
    print(f"[+] Successfully registered hypothesis: [{hypo.hypo_id}]")
    print(f"    Statement: {hypo.statement}")
    print(f"    Topics: {hypo.target_topics}")
    return 0


def _report_hypothesis(
    orchestrator: UniversalIntelligenceOrchestrator, args: argparse.Namespace
) -> int:
    """Displays detailed markdown investigation report for a hypothesis."""
    if not args.id:
        print("[ERROR] --id is required to view a hypothesis report.")
        return 1
    hypo = orchestrator.hypothesis_engine.get_hypothesis(args.id)
    if not hypo:
        print(f"[ERROR] Hypothesis [{args.id}] not found.")
        return 1
    report = orchestrator.hypothesis_engine.synthesize_hypothesis_report(hypo)
    print(report)
    return 0


def run_hypothesis_command(args: argparse.Namespace) -> int:
    """Manages hypothesis-driven autonomous investigation."""
    orchestrator = UniversalIntelligenceOrchestrator(
        workspace_dir=os.path.abspath(args.workdir)
    )
    if getattr(args, "hypo_action", None) == "add":
        return _add_hypothesis(orchestrator, args)
    elif getattr(args, "hypo_action", None) == "report":
        return _report_hypothesis(orchestrator, args)
    return _list_hypotheses(orchestrator)


def run_status_command(args: argparse.Namespace) -> int:
    """Displays comprehensive repository and intelligence status."""
    workspace_dir = os.path.abspath(args.workdir)
    print("=================================================================")
    print("   ARXIV SECURITY PAPERS & INTELLIGENCE PLATFORM STATUS")
    print("=================================================================")
    print(f"Workspace Directory : {workspace_dir}")

    # 1. OKF Papers Count
    okf_dir = os.path.join(workspace_dir, "outputs", "okf_papers")
    paper_count = 0
    if os.path.exists(okf_dir):
        for _, _, files in os.walk(okf_dir):
            paper_count += sum(1 for f in files if f.endswith(".md"))
    print(f"OKF Papers Ingested : {paper_count:,} documents")

    # 2. Vector DB Status
    vector_db_path = os.path.join(workspace_dir, "outputs", "vector_db", "index.json")
    if os.path.exists(vector_db_path):
        size_mb = os.path.getsize(vector_db_path) / (1024 * 1024)
        print(
            f"Vector Search Index : Active ({size_mb:.1f} MB in outputs/vector_db/index.json)"
        )
    else:
        print("Vector Search Index : Not built (Run 'make build_vector_db')")

    # 3. Executive Summaries Status
    summaries_dir = os.path.join(workspace_dir, "outputs", "executive_summaries")
    tiers = ["01_per_run", "02_daily", "03_monthly", "04_quarterly", "05_annual"]
    print("Executive Summaries :")
    for tier in tiers:
        tier_path = os.path.join(summaries_dir, tier)
        count = (
            len([f for f in os.listdir(tier_path) if f.endswith(".md")])
            if os.path.exists(tier_path)
            else 0
        )
        print(f"  - {tier:<15} : {count} summaries")

    # 4. Active PIRs
    orchestrator = UniversalIntelligenceOrchestrator(workspace_dir=workspace_dir)
    active_pirs = orchestrator.pir_manager.list_active_requirements()
    print(f"Active PIRs         : {len(active_pirs)} requirements active")

    return 0


def build_parser() -> argparse.ArgumentParser:
    """Builds the comprehensive CLI argument parser."""
    parser = argparse.ArgumentParser(
        prog="orchestrator",
        description="Universal Autonomous Intelligence Lifecycle Orchestrator for arxiv-security-papers",
    )
    parser.add_argument(
        "--workdir",
        "-w",
        default=".",
        help="Path to workspace root directory (default: .)",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable detailed verbose diagnostic output",
    )

    subparsers = parser.add_subparsers(dest="command", help="Available subcommands")

    # Command: cycle (Default Orchestrator cycle)
    cycle_parser = subparsers.add_parser(
        "cycle",
        help="Execute 6-phase closed-loop autonomous intelligence cycle (Default)",
    )
    cycle_parser.add_argument(
        "--cycles",
        "-c",
        type=int,
        default=1,
        help="Number of intelligence cycles to execute sequentially (default: 1)",
    )
    cycle_parser.add_argument(
        "--cycle-id",
        type=str,
        default=None,
        help="Custom identifier for the intelligence cycle",
    )
    cycle_parser.add_argument(
        "--topics",
        "-t",
        type=str,
        default="",
        help="Comma-separated target topics to prioritize for collection and synthesis",
    )
    cycle_parser.add_argument(
        "--quota",
        "-q",
        type=int,
        default=20,
        help="Base collection crawl quota per topic (default: 20)",
    )
    cycle_parser.add_argument(
        "--json", action="store_true", help="Output results formatted as JSON"
    )
    cycle_parser.add_argument(
        "--quiet", action="store_true", help="Suppress visual banners and headers"
    )

    # Command: daemon
    daemon_parser = subparsers.add_parser(
        "daemon", help="Run recurring intelligence cycles in autonomous daemon mode"
    )
    daemon_parser.add_argument(
        "--interval",
        "-i",
        type=int,
        default=3600,
        help="Cycle interval in seconds (default: 3600)",
    )
    daemon_parser.add_argument(
        "--max-cycles",
        type=int,
        default=0,
        help="Maximum cycles before terminating (0 = infinite, default: 0)",
    )

    # Command: pir
    pir_parser = subparsers.add_parser(
        "pir", help="Inspect and manage Priority Intelligence Requirements (PIRs)"
    )
    pir_subparsers = pir_parser.add_subparsers(
        dest="pir_action", help="PIR action to perform"
    )
    pir_subparsers.add_parser(
        "list", help="List active PIR requirements and topic weights (default)"
    )
    add_pir_parser = pir_subparsers.add_parser(
        "add", help="Register a new Priority Intelligence Requirement"
    )
    add_pir_parser.add_argument(
        "--id", type=str, required=True, help="Unique PIR Requirement ID"
    )
    add_pir_parser.add_argument(
        "--title", type=str, required=True, help="Human-readable title"
    )
    add_pir_parser.add_argument(
        "--description", type=str, default="", help="Detailed description"
    )
    add_pir_parser.add_argument(
        "--topics",
        type=str,
        required=True,
        help="Comma-separated list of target domain topics",
    )
    add_pir_parser.add_argument(
        "--priority",
        type=float,
        default=1.0,
        help="Priority score (0.0 - 1.0, default: 1.0)",
    )
    add_pir_parser.add_argument(
        "--horizon",
        type=str,
        default="operational",
        choices=["tactical", "operational", "strategic"],
        help="Temporal horizon (tactical, operational, strategic, default: operational)",
    )

    escalate_pir_parser = pir_subparsers.add_parser(
        "escalate", help="Dynamically escalate a Priority Intelligence Requirement"
    )
    escalate_pir_parser.add_argument(
        "--id", type=str, required=True, help="PIR Requirement ID to escalate"
    )
    escalate_pir_parser.add_argument(
        "--reason", type=str, default="", help="Reason for dynamic escalation"
    )
    escalate_pir_parser.add_argument(
        "--horizon",
        type=str,
        default="tactical",
        choices=["tactical", "operational", "strategic"],
        help="Target horizon (default: tactical)",
    )

    # Command: hypothesis
    hypo_parser = subparsers.add_parser(
        "hypothesis", help="Inspect and manage autonomous security hypotheses"
    )
    hypo_subparsers = hypo_parser.add_subparsers(
        dest="hypo_action", help="Hypothesis action to perform"
    )
    hypo_subparsers.add_parser(
        "list", help="List tracked hypotheses and verification statuses (default)"
    )
    add_hypo_parser = hypo_subparsers.add_parser(
        "add", help="Register a manual security hypothesis proposition"
    )
    add_hypo_parser.add_argument(
        "--id", type=str, required=True, help="Unique Hypothesis ID"
    )
    add_hypo_parser.add_argument(
        "--statement", type=str, required=True, help="Hypothesis proposition statement"
    )
    add_hypo_parser.add_argument(
        "--topics",
        type=str,
        required=True,
        help="Comma-separated list of target domain topics",
    )

    report_hypo_parser = hypo_subparsers.add_parser(
        "report", help="Display detailed markdown investigation report for a hypothesis"
    )
    report_hypo_parser.add_argument(
        "--id", type=str, required=True, help="Hypothesis ID to report"
    )

    # Command: status
    subparsers.add_parser(
        "status", help="Show system-wide intelligence and data status"
    )

    # Command: pipeline (Direct tool runner)
    pipeline_parser = subparsers.add_parser(
        "pipeline", help="Run arXiv / multi-theme ETL ingestion pipeline directly"
    )
    pipeline_parser.add_argument(
        "--theme",
        type=str,
        default="security",
        help="Theme ID to run (security, cryptography, ai_safety, all)",
    )
    pipeline_parser.add_argument(
        "--days", type=int, default=1, help="Number of historical days to backfill"
    )
    pipeline_parser.add_argument(
        "--max-results", type=int, default=50, help="Maximum results per query"
    )

    # Command: spider (Direct tool runner)
    spider_parser = subparsers.add_parser(
        "spider", help="Run distributed crawler & spider platform directly"
    )
    spider_parser.add_argument(
        "--spider-name",
        type=str,
        default="arxiv",
        help="Spider to execute (arxiv, iacr, advisory)",
    )
    spider_parser.add_argument(
        "--depth", type=int, default=2, help="Maximum crawl depth"
    )

    # Command: search (Direct tool runner)
    search_parser = subparsers.add_parser(
        "search", help="Execute semantic vector & hybrid search directly"
    )
    search_parser.add_argument(
        "--query", "-q", type=str, default="", help="Search query string"
    )
    search_parser.add_argument(
        "--build", action="store_true", help="Build or rebuild the vector index"
    )
    search_parser.add_argument(
        "--top-k", "-k", type=int, default=10, help="Number of results (default: 10)"
    )

    # Command: web (Direct tool runner)
    web_parser = subparsers.add_parser(
        "web", help="Launch Glassmorphic Web Search UI and API Server"
    )
    web_parser.add_argument(
        "--port", "-p", type=int, default=8000, help="Port to bind (default: 8000)"
    )
    web_parser.add_argument(
        "--host", type=str, default="0.0.0.0", help="Host interface to bind"
    )

    # Command: mcp (Direct tool runner)
    mcp_parser = subparsers.add_parser(
        "mcp", help="Launch Model Context Protocol JSON-RPC servers"
    )
    mcp_parser.add_argument(
        "--server-type",
        type=str,
        default="papers",
        choices=["papers", "observability", "threat_defense", "tech_radar"],
        help="MCP server type to launch",
    )

    return parser


def _handle_cycle_cli(args: argparse.Namespace) -> int:
    """Dispatches to cycle command with default attributes."""
    if not hasattr(args, "cycles"):
        args.cycles = 1
    if not hasattr(args, "cycle_id"):
        args.cycle_id = None
    if not hasattr(args, "topics"):
        args.topics = ""
    if not hasattr(args, "quota"):
        args.quota = 20
    if not hasattr(args, "json"):
        args.json = False
    if not hasattr(args, "quiet"):
        args.quiet = False
    return run_cycle_command(args)


def _handle_pipeline_cli(args: argparse.Namespace) -> int:
    """Dispatches to pipeline ingestion engine."""
    import pipeline.arxiv_okf_fetcher as pipe_mod

    print(f"[*] Delegating to Pipeline Ingestion Engine (Theme: {args.theme})...")
    pipe_mod.run_theme_pipeline(
        theme_id=args.theme,
        workspace_dir=os.path.abspath(args.workdir),
        max_results=getattr(args, "max_results", None),
    )
    return 0


def _handle_spider_cli(args: argparse.Namespace) -> int:
    """Dispatches to spider runner."""
    import spider.runner as sp_mod

    print(f"[*] Delegating to Spider Runner ({args.spider_name})...")
    runner = sp_mod.SpiderRunner(workspace_dir=os.path.abspath(args.workdir))
    stats = runner.run_spider(args.spider_name, max_depth=args.depth)
    print(f"[+] Spider execution complete: {stats}")
    return 0


def _handle_search_cli(args: argparse.Namespace) -> int:
    """Dispatches to vector search engine."""
    import search.vector_engine as se_mod

    engine = se_mod.VectorEngine(workspace_dir=os.path.abspath(args.workdir))
    if args.build:
        print("[*] Rebuilding Vector Search Index from OKF papers...")
        count = engine.build_index()
        print(f"[+] Successfully indexed {count} documents.")
        return 0
    if args.query:
        results, profile = engine.search_with_profile(args.query, top_k=args.top_k)
        print(
            f"[+] Found {len(results)} matches for '{args.query}' in {profile.get('total_ms', 0):.2f}ms:"
        )
        for i, doc in enumerate(results, 1):
            print(
                f"  {i}. [{doc.get('id')}] {doc.get('title')} (score: {doc.get('score', 0):.4f})"
            )
        return 0
    print("[ERROR] Please specify --query '<query>' or --build.")
    return 1


def _handle_web_cli(args: argparse.Namespace) -> int:
    """Dispatches to web server."""
    import web.server as ws_mod

    print(f"[*] Launching WSGI Web Server on {args.host}:{args.port}...")
    ws_mod.run_server(host=args.host, port=args.port)
    return 0


def _handle_mcp_cli(args: argparse.Namespace) -> int:
    """Dispatches to standard MCP server."""
    if args.server_type == "observability":
        import mcp.observability_server as obs_server

        obs_server.main()
    elif args.server_type == "threat_defense":
        import mcp.threat_defense_server as td_server

        td_server.main()
    elif args.server_type == "tech_radar":
        import mcp.tech_radar_server as tr_server

        tr_server.main()
    else:
        import mcp.papers_server as p_server

        p_server.main()
    return 0


def _dispatch_command(
    cmd: Optional[str],
    args: argparse.Namespace,
    parser: argparse.ArgumentParser,
) -> int:
    """Dispatches parsed CLI command to appropriate handler."""
    dispatch_table: Dict[str, Callable[[argparse.Namespace], int]] = {
        "cycle": _handle_cycle_cli,
        "daemon": run_daemon_command,
        "pir": run_pir_command,
        "hypothesis": run_hypothesis_command,
        "status": run_status_command,
        "pipeline": _handle_pipeline_cli,
        "spider": _handle_spider_cli,
        "search": _handle_search_cli,
        "web": _handle_web_cli,
        "mcp": _handle_mcp_cli,
    }
    if not cmd or cmd == "cycle":
        return _handle_cycle_cli(args)
    handler = dispatch_table.get(cmd)
    if handler:
        return handler(args)
    parser.print_help()
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    """Main entry point dispatching to orchestrator cycle or individual tools."""
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit:
        return 1
    return _dispatch_command(args.command, args, parser)


if __name__ == "__main__":
    sys.exit(main())
