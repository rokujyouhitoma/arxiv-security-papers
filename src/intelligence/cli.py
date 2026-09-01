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

from intelligence.contracts import IntelligencePhase, PhaseContext, PhaseStatus
from intelligence.engine import ClosedLoopIntelligenceEngine


def _print_banner() -> None:
    banner = """
================================================================================
   UNIVERSAL AUTONOMOUS INTELLIGENCE ORCHESTRATOR (arxiv-security-papers)
   Closed-Loop 6-Phase Intelligence Lifecycle: Planning -> Feedback
================================================================================
"""
    print(banner)


def _seed_intelligence_requirements(
    orchestrator: ClosedLoopIntelligenceEngine, topics: Optional[str]
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


def _print_phase_matrix(context: PhaseContext) -> None:
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
        symbol = "✓" if status_enum == PhaseStatus.COMPLETED else "✗"
        print(f"      [{symbol}] {phase.value:<15} : {status_enum.value}")


def _print_cycle_details(
    context: PhaseContext, cycle_id: str, elapsed_ms: float
) -> None:
    """Prints verbose execution summary for an intelligence cycle."""
    print(f"[+] Cycle {cycle_id} Completed in {elapsed_ms:.2f}ms")
    _print_phase_matrix(context)

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


def _exec_orchestrator_cycle(
    orchestrator: ClosedLoopIntelligenceEngine,
    cycle_id: str,
    args: argparse.Namespace,
) -> PhaseContext:
    if getattr(args, "streaming", False):
        chunk_size = getattr(args, "chunk_size", 20)
        return orchestrator.stream_cycle(cycle_id=cycle_id, chunk_size=chunk_size)
    return orchestrator.run_cycle(cycle_id=cycle_id)


def _run_single_cycle(
    orchestrator: ClosedLoopIntelligenceEngine,
    cycle_id: str,
    args: argparse.Namespace,
) -> Dict[str, Any]:
    """Executes a single cycle and returns summary dict."""
    start_time = time.perf_counter()
    context = _exec_orchestrator_cycle(orchestrator, cycle_id, args)
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
        "streaming_stats": context.state.get("streaming_stats"),
    }


def _format_cycle_id(cycle_id_arg: Optional[str], index: int, total_cycles: int) -> str:
    """Computes cycle ID prefix and indexed name."""
    cycle_prefix = (
        cycle_id_arg
        if cycle_id_arg
        else f"cycle_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"
    )
    return f"{cycle_prefix}_{index+1}" if total_cycles > 1 else cycle_prefix


def _run_all_cycles(
    orchestrator: ClosedLoopIntelligenceEngine, args: argparse.Namespace, cycles_to_run: int
) -> List[Dict[str, Any]]:
    results_summary: List[Dict[str, Any]] = []
    for i in range(cycles_to_run):
        cycle_id = _format_cycle_id(getattr(args, "cycle_id", None), i, cycles_to_run)
        if not args.quiet and not args.json:
            print(f"[*] Starting Intelligence Cycle [{i+1}/{cycles_to_run}]: {cycle_id}")
        cycle_result = _run_single_cycle(orchestrator, cycle_id, args)
        results_summary.append(cycle_result)
    return results_summary


def _init_cycle_orchestrator(args: argparse.Namespace) -> ClosedLoopIntelligenceEngine:
    if not (args.quiet or args.json):
        _print_banner()
    orchestrator = ClosedLoopIntelligenceEngine(workspace_dir=os.path.abspath(args.workdir))
    _seed_intelligence_requirements(orchestrator, getattr(args, "topics", None))
    return orchestrator


def _output_cycle_summary(results_summary: List[Dict[str, Any]], as_json: bool) -> int:
    if as_json:
        print(json.dumps(results_summary, indent=2, ensure_ascii=False))
    return 1 if any(len(r["errors"]) > 0 for r in results_summary) else 0


def run_cycle_command(args: argparse.Namespace) -> int:
    """Executes one or more intelligence cycles."""
    orchestrator = _init_cycle_orchestrator(args)
    cycles_to_run = max(1, getattr(args, "cycles", 1))
    results_summary = _run_all_cycles(orchestrator, args, cycles_to_run)
    return _output_cycle_summary(results_summary, getattr(args, "json", False))


def _run_daemon_step(orchestrator: ClosedLoopIntelligenceEngine, cycle_count: int) -> None:
    print(f"\n[{datetime.now(timezone.utc).isoformat()}] --- Daemon Cycle #{cycle_count} ---")
    ctx = orchestrator.run_cycle(cycle_id=f"daemon_{int(time.time())}_{cycle_count}")
    print(
        f"[+] Completed cycle {ctx.cycle_id}: {len(ctx.processed_records)} records, "
        f"{len(ctx.products)} products"
    )


def _daemon_loop(
    orchestrator: ClosedLoopIntelligenceEngine, interval: int, max_cycles: int
) -> None:
    cycle_count = 0
    while True:
        cycle_count += 1
        _run_daemon_step(orchestrator, cycle_count)
        if max_cycles > 0 and cycle_count >= max_cycles:
            print(f"[*] Reached max cycles ({max_cycles}). Exiting daemon.")
            break
        print(f"[*] Sleeping for {interval} seconds until next cycle...")
        time.sleep(interval)


def run_daemon_command(args: argparse.Namespace) -> int:
    """Runs recurring intelligence cycles in daemon mode."""
    _print_banner()
    interval = max(5, args.interval)
    max_cycles = args.max_cycles
    orchestrator = ClosedLoopIntelligenceEngine(workspace_dir=os.path.abspath(args.workdir))

    max_cycles_label = "Infinite" if max_cycles == 0 else str(max_cycles)
    print(f"[*] Starting Autonomous Orchestrator Daemon (Interval: {interval}s, Max Cycles: {max_cycles_label})")

    try:
        _daemon_loop(orchestrator, interval, max_cycles)
    except KeyboardInterrupt:
        print("\n[*] Daemon interrupted by user. Shutting down gracefully.")
    return 0


def _parse_pir_horizon(raw_horizon: str) -> Any:
    from intelligence.pir.models import PIRHorizon
    try:
        return PIRHorizon(raw_horizon.lower())
    except ValueError:
        return PIRHorizon.OPERATIONAL


def _validate_pir_args(args: argparse.Namespace) -> bool:
    return bool(args.id and args.title and args.topics)


def _add_pir_requirement(
    orchestrator: ClosedLoopIntelligenceEngine, args: argparse.Namespace
) -> int:
    """Handles adding a new PIR."""
    if not _validate_pir_args(args):
        print("[ERROR] --id, --title, and --topics are required to add a PIR.")
        return 1

    topics = [t.strip() for t in args.topics.split(",") if t.strip()]
    horizon_val = _parse_pir_horizon(getattr(args, "horizon", "operational"))

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
    orchestrator: ClosedLoopIntelligenceEngine, args: argparse.Namespace
) -> int:
    """Handles dynamically escalating an existing PIR."""
    if not args.id:
        print("[ERROR] --id is required to escalate a PIR.")
        return 1

    reason = getattr(args, "reason", "Manual operator escalation") or "Manual operator escalation"
    target_h = _parse_pir_horizon(getattr(args, "horizon", "tactical"))

    success = orchestrator.escalate_pir(
        req_id=args.id, reason=reason, target_horizon=target_h
    )
    if not success:
        print(f"[ERROR] Failed to escalate PIR [{args.id}]. Not found or reached max level.")
        return 1

    req = orchestrator.pir_manager.get_requirement(args.id)
    assert req is not None
    print(f"[+] Successfully escalated PIR [{req.req_id}] to {req.horizon.value.upper()}")
    print(f"    Escalation Level: {req.escalation_level}")
    print(f"    New Priority Score: {req.priority_score:.2f}")
    print(f"    Reason: {reason}")
    return 0


def _print_active_pir(r: Any) -> None:
    horizon_tag = f"[{r.horizon.value.upper()}]"
    escalation_tag = f" (Escalation Lvl: {r.escalation_level})" if r.escalation_level > 0 else ""
    print(f"  {horizon_tag} [{r.req_id}] {r.title} (Priority: {r.priority_score}){escalation_tag}")
    print(f"    Topics: {', '.join(r.target_topics)}")
    if r.description:
        print(f"    Desc:   {r.description}")
    print()


def _print_topic_weights(weights: Dict[str, float]) -> None:
    print("--- Current Topic Priority Distribution ---")
    if not weights:
        print("  (No topic weights calculated yet)")
        return
    for topic, weight in sorted(weights.items(), key=lambda x: x[1], reverse=True):
        bar = "#" * int(weight * 30)
        print(f"  {topic:<25} : {weight:.4f} | {bar}")


def _list_pir_requirements(
    orchestrator: ClosedLoopIntelligenceEngine,
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
            _print_active_pir(r)

    _print_topic_weights(weights)
    return 0


def run_pir_command(args: argparse.Namespace) -> int:
    """Manages Priority Intelligence Requirements (PIRs)."""
    orchestrator = ClosedLoopIntelligenceEngine(
        workspace_dir=os.path.abspath(args.workdir)
    )
    if args.pir_action == "add":
        return _add_pir_requirement(orchestrator, args)
    elif args.pir_action == "escalate":
        return _escalate_pir_requirement(orchestrator, args)
    return _list_pir_requirements(orchestrator)


def _list_hypotheses(
    orchestrator: ClosedLoopIntelligenceEngine,
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


def _validate_hypothesis_args(args: argparse.Namespace) -> bool:
    return bool(args.id and args.statement and args.topics)


def _add_hypothesis(
    orchestrator: ClosedLoopIntelligenceEngine, args: argparse.Namespace
) -> int:
    """Registers a manual hypothesis proposition."""
    if not _validate_hypothesis_args(args):
        print("[ERROR] --id, --statement, and --topics are required to add a hypothesis.")
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
    orchestrator: ClosedLoopIntelligenceEngine, args: argparse.Namespace
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
    orchestrator = ClosedLoopIntelligenceEngine(
        workspace_dir=os.path.abspath(args.workdir)
    )
    if getattr(args, "hypo_action", None) == "add":
        return _add_hypothesis(orchestrator, args)
    elif getattr(args, "hypo_action", None) == "report":
        return _report_hypothesis(orchestrator, args)
    return _list_hypotheses(orchestrator)


def run_credibility_command(args: argparse.Namespace) -> int:
    """Manages NATO STANAG 2022 Admiralty Credibility Scoring."""
    from intelligence.processing.credibility import AdmiraltyEngine

    engine = AdmiraltyEngine()
    if getattr(args, "cred_action", None) == "rate":
        text = getattr(args, "text", "")
        source = getattr(args, "source", "arxiv")
        if not text:
            print("[ERROR] --text is required for credibility assessment.")
            return 1
        dummy_rec = {"title": text[:80], "summary": text, "source": source}
        rating = engine.rate_record(dummy_rec)
        print("=================================================================")
        print("   NATO STANAG 2022 ADMIRALTY CREDIBILITY ASSESSMENT")
        print("=================================================================")
        print(f"  Source Type       : {source}")
        print(f"  Admiralty Code    : [{rating.code}]")
        print(f"  Compound Score    : {rating.score:.3f} / 1.000")
        print(f"  Assessment Details: {rating.justification}")
        return 0

    print(engine.generate_matrix_markdown())
    return 0


def _list_recoverable_cycles(orchestrator: ClosedLoopIntelligenceEngine) -> int:
    cycles = orchestrator.wal.list_active_cycles()
    print("=================================================================")
    print("   EVENT SOURCING WAL & CRASH RECOVERY CYCLES")
    print("=================================================================")
    if not cycles:
        print("  (No WAL cycles found in outputs/wal/)")
        return 0
    for c in cycles:
        status_icon = (
            "✓"
            if c["status"] == "completed"
            else ("✗" if c["status"] == "failed" else "⏳")
        )
        print(
            f"  [{status_icon}] {c['cycle_id']:<30} | Status: {c['status']:<11} | "
            f"Events: {c['total_events']:<3} | Started: {c['started_at']}"
        )
    return 0


def run_recover_command(args: argparse.Namespace) -> int:
    """Manages WAL state replay and cycle crash recovery."""
    workspace_dir = os.path.abspath(args.workdir)
    orchestrator = ClosedLoopIntelligenceEngine(workspace_dir=workspace_dir)

    if getattr(args, "list", False):
        return _list_recoverable_cycles(orchestrator)

    cycle_id = getattr(args, "cycle_id", None)
    if not cycle_id:
        print("[ERROR] Please specify --cycle-id <ID> or use --list.")
        return 1

    print(f"[*] Replaying and resuming cycle [{cycle_id}] from WAL...")
    ctx = orchestrator.resume_cycle(cycle_id)
    print(
        f"[+] Recovery complete! Processed {len(ctx.processed_records)} records, "
        f"{len(ctx.products)} products produced."
    )
    return 0 if not ctx.errors else 1


def run_harvest_command(args: argparse.Namespace) -> int:
    """Manages adaptive harvesting routes and circuit breaker tests."""
    workspace_dir = os.path.abspath(args.workdir)
    orchestrator = ClosedLoopIntelligenceEngine(workspace_dir=workspace_dir)
    coordinator = orchestrator.harvest_coordinator

    if getattr(args, "harvest_action", None) == "test":
        topic = getattr(args, "topic", "cryptography")
        quota = getattr(args, "quota", 5)
        records, used_route, log = coordinator.router.harvest_topic(topic, quota)
        print("=================================================================")
        print("   ADAPTIVE HARVEST ROUTE MUTATION TEST")
        print("=================================================================")
        print(f"Target Topic     : {topic}")
        print(f"Requested Quota  : {quota}")
        print(f"Route Selected   : {used_route}")
        print(f"Collected Records: {len(records)}")
        print("\n[Mutation Trace Log]")
        for entry in log:
            print(f"  - Route: {entry.get('route_id')}, Action: {entry.get('action')}")
        return 0

    # Default: status markdown
    print(coordinator.router.generate_status_markdown())
    return 0


def _count_okf_papers(workspace_dir: str) -> int:
    okf_dir = os.path.join(workspace_dir, "outputs", "okf_papers")
    if not os.path.exists(okf_dir):
        return 0
    return sum(
        sum(1 for f in files if f.endswith(".md"))
        for _, _, files in os.walk(okf_dir)
    )


def _print_summary_status(workspace_dir: str) -> None:
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


def run_status_command(args: argparse.Namespace) -> int:
    """Displays comprehensive repository and intelligence status."""
    workspace_dir = os.path.abspath(args.workdir)
    print("=================================================================")
    print("   ARXIV SECURITY PAPERS & INTELLIGENCE PLATFORM STATUS")
    print("=================================================================")
    print(f"Workspace Directory : {workspace_dir}")
    print(f"OKF Papers Ingested : {_count_okf_papers(workspace_dir):,} documents")

    vector_db_path = os.path.join(workspace_dir, "outputs", "vector_db", "index.json")
    if os.path.exists(vector_db_path):
        size_mb = os.path.getsize(vector_db_path) / (1024 * 1024)
        print(f"Vector Search Index : Active ({size_mb:.1f} MB in outputs/vector_db/index.json)")
    else:
        print("Vector Search Index : Not built (Run 'make build_vector_db')")

    _print_summary_status(workspace_dir)

    orchestrator = ClosedLoopIntelligenceEngine(workspace_dir=workspace_dir)
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
        "--streaming",
        action="store_true",
        help="Execute intelligence pipeline using Streaming DAG with reactive backpressure",
    )
    cycle_parser.add_argument(
        "--chunk-size",
        type=int,
        default=20,
        help="Chunk size for streaming execution (default: 20)",
    )
    cycle_parser.add_argument(
        "--quiet", action="store_true", help="Suppress visual banners and headers"
    )
    cycle_parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable detailed verbose diagnostic output",
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

    # Command: credibility
    cred_parser = subparsers.add_parser(
        "credibility", help="NATO STANAG 2022 Admiralty Credibility Scoring"
    )
    cred_subparsers = cred_parser.add_subparsers(
        dest="cred_action", help="Credibility action to perform"
    )
    cred_subparsers.add_parser(
        "matrix", help="Display NATO STANAG 2022 Admiralty Matrix table (default)"
    )
    rate_cred_parser = cred_subparsers.add_parser(
        "rate", help="Assess Admiralty credibility rating for given text"
    )
    rate_cred_parser.add_argument(
        "--text", type=str, required=True, help="Content text to evaluate"
    )
    rate_cred_parser.add_argument(
        "--source",
        type=str,
        default="arxiv",
        help="Source type / venue (default: arxiv)",
    )

    # Command: recover
    recover_parser = subparsers.add_parser(
        "recover", help="Event Sourcing WAL Crash Recovery and Cycle Resume"
    )
    recover_parser.add_argument(
        "--cycle-id", type=str, default=None, help="Target cycle ID to resume"
    )
    recover_parser.add_argument(
        "--list", action="store_true", help="List all recoverable cycles from WAL"
    )

    # Command: harvest
    harvest_parser = subparsers.add_parser(
        "harvest", help="Adaptive multi-source harvesting and route circuit status"
    )
    harvest_subparsers = harvest_parser.add_subparsers(
        dest="harvest_action", help="Harvest action to perform"
    )
    harvest_subparsers.add_parser(
        "status", help="Show all harvest routes and circuit breaker health (default)"
    )
    test_harvest_parser = harvest_subparsers.add_parser(
        "test", help="Test adaptive route mutation for a specific topic"
    )
    test_harvest_parser.add_argument(
        "--topic", type=str, default="cryptography", help="Topic to harvest"
    )
    test_harvest_parser.add_argument(
        "--quota", type=int, default=5, help="Number of records to fetch"
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


def _ensure_cycle_defaults(args: argparse.Namespace) -> None:
    defaults = {
        "cycles": 1,
        "cycle_id": None,
        "topics": "",
        "quota": 20,
        "json": False,
        "quiet": False,
    }
    for k, v in defaults.items():
        if not hasattr(args, k):
            setattr(args, k, v)


def _handle_cycle_cli(args: argparse.Namespace) -> int:
    """Dispatches to cycle command with default attributes."""
    _ensure_cycle_defaults(args)
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
        "credibility": run_credibility_command,
        "recover": run_recover_command,
        "harvest": run_harvest_command,
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
