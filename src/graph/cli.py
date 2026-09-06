#!/usr/bin/env python3
"""
CLI entrypoint for Property Graph Database Engine and Ontology Knowledge Graph Builder.
"""

from __future__ import annotations

import argparse
import glob
import logging
import os
import sys
import time
from typing import Any, Dict, List, Optional

from ontology.extractor import OntologyExtractor

try:
    from .engine import PropertyGraphEngine
except ImportError:
    from graph.engine import PropertyGraphEngine

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger("graph.cli")


def _index_single_paper(fpath: str, engine: PropertyGraphEngine) -> int:
    """Indexes entities and triples from a single OKF paper file into the graph engine."""
    fname = os.path.basename(fpath)
    clean_id = fname.replace(".md", "")
    try:
        with open(fpath, "r", encoding="utf-8") as pf:
            content = pf.read()
        entities, triples = OntologyExtractor.extract_from_okf(clean_id, content)

        for ent in entities:
            engine.add_vertex(
                vertex_id=ent.id,
                label=ent.entity_type.value,
                properties=ent.properties or {"name": ent.name},
            )

        for t in triples:
            engine.add_edge(
                src_id=t.subject_id,
                dst_id=t.object_id,
                label=t.predicate.value,
                weight=t.weight,
                properties=t.properties,
            )
        return len(triples)
    except Exception as ex:
        logger.warning("Failed to extract ontology from %s: %s", fpath, ex)
        return 0


def _resolve_graph_path(workspace_dir: str, explicit_path: Optional[str] = None) -> str:
    if explicit_path:
        return explicit_path
    new_path = os.path.join(workspace_dir, "outputs", "database", "graph", "graph.db")
    legacy_path = os.path.join(workspace_dir, "outputs", "database", "graph.db")
    if os.path.exists(legacy_path) and not os.path.exists(new_path):
        return legacy_path
    return new_path


def build_knowledge_graph(workspace_dir: str, output_path: Optional[str] = None) -> int:
    """Scans all OKF markdown files and constructs the persistent Security Knowledge Graph."""
    graph_path = _resolve_graph_path(workspace_dir, output_path)
    engine = PropertyGraphEngine(storage_path=graph_path)

    okf_pattern = os.path.join(workspace_dir, "outputs", "okf_papers", "*", "*.md")
    files = sorted(glob.glob(okf_pattern))
    logger.info(
        "Found %d OKF markdown papers to index into Knowledge Graph", len(files)
    )

    start_time = time.perf_counter()
    extracted_triples_count = sum(_index_single_paper(fpath, engine) for fpath in files)

    engine.save()
    elapsed_ms = (time.perf_counter() - start_time) * 1000.0
    st = engine.stats()

    logger.info("=" * 60)
    logger.info(
        "✨ Knowledge Graph Build Complete in %.2f ms (Indexed Triples: %d)",
        elapsed_ms,
        extracted_triples_count,
    )
    logger.info("  • Total Vertices: %d", st["vertex_count"])
    logger.info("  • Total Edges:    %d", st["edge_count"])
    logger.info("  • Vertex Types:   %s", st["vertex_labels"])
    logger.info("  • Edge Types:     %s", st["edge_predicates"])
    logger.info("  • Persistent DB:  %s", graph_path)
    logger.info("=" * 60)
    return 0


def show_graph_stats(workspace_dir: str, graph_path: Optional[str] = None) -> int:
    """Displays topological statistics of the Security Knowledge Graph."""
    target_path = _resolve_graph_path(workspace_dir, graph_path)
    if not os.path.exists(target_path):
        print(f"[!] Graph database not found at {target_path}. Run build first.")
        return 1

    engine = PropertyGraphEngine(storage_path=target_path)
    st = engine.stats()
    print("\n📊 [Security Knowledge Graph Statistics]")
    print(f"  • Total Vertices: {st['vertex_count']}")
    print(f"  • Total Edges:    {st['edge_count']}")
    print("  • Vertex Distribution:")
    for lbl, cnt in sorted(
        st["vertex_labels"].items(), key=lambda x: x[1], reverse=True
    ):
        print(f"    - {lbl:20s}: {cnt:4d}")
    print("  • Edge Predicates Distribution:")
    for pred, cnt in sorted(
        st["edge_predicates"].items(), key=lambda x: x[1], reverse=True
    ):
        print(f"    - {pred:20s}: {cnt:4d}")
    print()
    return 0


def _print_top_nodes(nodes: List[Dict[str, Any]]) -> None:
    """Prints formatted top matched nodes."""
    print("\n  [Top Matched Nodes]")
    for n in nodes[:15]:
        n_id = n.get("id", "")
        n_lbl = n.get("label", "")
        n_props = n.get("properties", {})
        n_name = n_props.get("name") or n_props.get("title") or n_id
        print(f"    - [{n_lbl}] {n_id}: {n_name}")

    if len(nodes) > 15:
        print(f"    ... and {len(nodes) - 15} more nodes.")


def _print_sample_edges(edges: List[Dict[str, Any]]) -> None:
    """Prints formatted sample edges."""
    print("\n  [Sample Traversed Relationships]")
    for e in edges[:10]:
        print(f"    - ({e.get('source')}) --[{e.get('label')}]--> ({e.get('target')})")

    if len(edges) > 10:
        print(f"    ... and {len(edges) - 10} more edges.")
    print()


def query_knowledge_graph(
    workspace_dir: str,
    query_str: str,
    limit: int = 50,
    graph_path: Optional[str] = None,
) -> int:
    """Executes a domain graph query and displays formatted results."""
    target_path = _resolve_graph_path(workspace_dir, graph_path)
    if not os.path.exists(target_path):
        print(f"[!] Graph database not found at {target_path}. Run build first.")
        return 1

    engine = PropertyGraphEngine(storage_path=target_path)
    res = engine.execute_graph_query(query=query_str, limit=limit)
    nodes = res.get("nodes", [])
    edges = res.get("edges", [])

    print(f'\n🔍 [Security Knowledge Graph Query]: "{query_str}"')
    print(f"  • Matched Seeds / Count: {res.get('match_count', len(nodes))}")
    print(f"  • Returned Vertices:     {len(nodes)}")
    print(f"  • Returned Edges:        {len(edges)}")
    _print_top_nodes(nodes)
    _print_sample_edges(edges)
    return 0


def _create_arg_parser() -> argparse.ArgumentParser:
    """Constructs the CLI argument parser with subparsers."""
    parser = argparse.ArgumentParser(
        prog="graph.cli",
        description="CLI tool for Property Graph Database Engine & Security Knowledge Graph",
    )
    parser.add_argument(
        "--backfill",
        action="store_true",
        help="Alias for 'build': scan all OKF papers and backfill knowledge graph",
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Alias for 'show': show topological statistics of graph database",
    )
    parser.add_argument(
        "--query",
        "-q",
        type=str,
        default=None,
        help="Execute a graph query directly (e.g. 'causal:T1059', 'ego:CWE-79', 'cwe:79', 'gap')",
    )

    subparsers = parser.add_subparsers(dest="command")

    build_p = subparsers.add_parser(
        "build", help="Extract ontology and build knowledge graph from OKF papers"
    )
    build_p.add_argument(
        "--output", "-o", type=str, default=None, help="Output graph database path"
    )
    build_p.add_argument(
        "--backfill",
        action="store_true",
        help="Perform full backfill from all OKF papers",
    )

    show_p = subparsers.add_parser(
        "show", help="Show topological statistics of graph database"
    )
    show_p.add_argument(
        "--input", "-i", type=str, default=None, help="Input graph database path"
    )
    show_p.add_argument(
        "--stats",
        action="store_true",
        help="Display graph topological statistics",
    )

    query_p = subparsers.add_parser(
        "query", help="Execute domain graph query (causal, ego, cwe, path, gap, match)"
    )
    query_p.add_argument(
        "expression",
        type=str,
        help="Query expression (e.g. 'causal:T1059', 'ego:CWE-79 2', 'cwe:79', 'path:A->B', 'gap')",
    )
    query_p.add_argument(
        "--limit", "-l", type=int, default=50, help="Maximum nodes/edges to retrieve"
    )
    query_p.add_argument(
        "--input", "-i", type=str, default=None, help="Input graph database path"
    )
    return parser


def _dispatch_flags(args: argparse.Namespace, workspace_dir: str) -> Optional[int]:
    """Handles top-level flag shortcuts."""
    if args.query:
        return query_knowledge_graph(workspace_dir, args.query)
    if args.backfill:
        return build_knowledge_graph(workspace_dir)
    if args.stats:
        return show_graph_stats(workspace_dir)
    return None


def _dispatch_command(args: argparse.Namespace, workspace_dir: str) -> int:
    """Dispatches subcommand to appropriate handler function."""
    flag_res = _dispatch_flags(args, workspace_dir)
    if flag_res is not None:
        return flag_res

    cmd = args.command or "build"
    if cmd == "build":
        return build_knowledge_graph(workspace_dir, getattr(args, "output", None))
    if cmd == "show":
        return show_graph_stats(workspace_dir, getattr(args, "input", None))
    return query_knowledge_graph(
        workspace_dir,
        getattr(args, "expression", ""),
        getattr(args, "limit", 50),
        getattr(args, "input", None),
    )


def main(argv: Optional[List[str]] = None) -> int:
    parser = _create_arg_parser()
    args = parser.parse_args(argv)
    workspace_dir = os.path.abspath(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    )
    return _dispatch_command(args, workspace_dir)


if __name__ == "__main__":
    sys.exit(main())
