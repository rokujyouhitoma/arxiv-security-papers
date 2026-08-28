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
from typing import List, Optional

from ontology.extractor import OntologyExtractor

from .engine import PropertyGraphEngine

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger("graph.cli")


def build_knowledge_graph(workspace_dir: str, output_path: Optional[str] = None) -> int:
    """Scans all OKF markdown files and constructs the persistent Security Knowledge Graph."""
    graph_path = output_path or os.path.join(
        workspace_dir, "outputs", "database", "graph.db"
    )
    engine = PropertyGraphEngine(storage_path=graph_path)

    okf_pattern = os.path.join(workspace_dir, "outputs", "okf_papers", "*", "*.md")
    files = sorted(glob.glob(okf_pattern))
    logger.info(
        "Found %d OKF markdown papers to index into Knowledge Graph", len(files)
    )

    start_time = time.perf_counter()
    extracted_triples_count = 0

    for fpath in files:
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
                extracted_triples_count += 1
        except Exception as ex:
            logger.warning("Failed to extract ontology from %s: %s", fpath, ex)

    engine.save()
    elapsed_ms = (time.perf_counter() - start_time) * 1000.0
    st = engine.stats()

    logger.info("=" * 60)
    logger.info("✨ Knowledge Graph Build Complete in %.2f ms", elapsed_ms)
    logger.info("  • Total Vertices: %d", st["vertex_count"])
    logger.info("  • Total Edges:    %d", st["edge_count"])
    logger.info("  • Vertex Types:   %s", st["vertex_labels"])
    logger.info("  • Edge Types:     %s", st["edge_predicates"])
    logger.info("  • Persistent DB:  %s", graph_path)
    logger.info("=" * 60)
    return 0


def show_graph_stats(workspace_dir: str, graph_path: Optional[str] = None) -> int:
    """Displays topological statistics of the Security Knowledge Graph."""
    target_path = graph_path or os.path.join(
        workspace_dir, "outputs", "database", "graph.db"
    )
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


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="graph.cli",
        description="CLI tool for Property Graph Database Engine & Security Knowledge Graph",
    )
    subparsers = parser.add_subparsers(dest="command")

    build_p = subparsers.add_parser(
        "build", help="Extract ontology and build knowledge graph from OKF papers"
    )
    build_p.add_argument(
        "--output", "-o", type=str, default=None, help="Output graph database path"
    )

    show_p = subparsers.add_parser(
        "show", help="Show topological statistics of graph database"
    )
    show_p.add_argument(
        "--input", "-i", type=str, default=None, help="Input graph database path"
    )

    args = parser.parse_args(argv)
    workspace_dir = os.path.abspath(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    )

    if args.command == "build" or not args.command:
        return build_knowledge_graph(workspace_dir, getattr(args, "output", None))
    if args.command == "show":
        return show_graph_stats(workspace_dir, getattr(args, "input", None))

    parser.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
