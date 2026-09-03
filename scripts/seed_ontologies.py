#!/usr/bin/env python3
"""
Seed Ontologies CLI Script.
Seeds MITRE ATT&CK (Enterprise & ATLAS) and CWE Master Data into PropertyGraphEngine.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import argparse
import os
import sys

# Ensure repository root src is on sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

from graph.engine import PropertyGraphEngine  # noqa: E402
from ontology.seeder import ingest_okf_papers, seed_ontology_graph  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Seed MITRE ATT&CK & CWE Master Ontologies into PropertyGraphEngine"
    )
    parser.add_argument(
        "--db-path",
        default=None,
        help="Path to target graph.db file (defaults to outputs/database/graph.db)",
    )
    parser.add_argument(
        "--ingest-papers",
        action="store_true",
        help="Ingest real OKF papers from outputs/okf_papers/",
    )
    parser.add_argument(
        "--limit-papers",
        type=int,
        default=100,
        help="Maximum papers to ingest (default: 100)",
    )
    args = parser.parse_args()

    engine = PropertyGraphEngine(storage_path=args.db_path)
    v_count, e_count = seed_ontology_graph(engine)

    if args.ingest_papers:
        p_ents, p_trips = ingest_okf_papers(engine, limit=args.limit_papers)
        print(f"Ingested {args.limit_papers} papers ({p_ents} entities, {p_trips} triples)")

    engine.save()

    print(f"Successfully seeded {v_count} ontology vertices and {e_count} causal edges into {engine.storage_path}")
    print(f"Total Graph Size: {engine.vertex_count} vertices, {engine.edge_count} edges")
    return 0


if __name__ == "__main__":
    sys.exit(main())
