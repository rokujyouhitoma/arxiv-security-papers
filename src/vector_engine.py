#!/usr/bin/env python3
"""
Backward-compatible shim for VectorEngine and extended search components.
Re-exports from the modular `search` package.
"""

from search import (
    CitationNetworkIndex,
    FacetedIndex,
    FMIndex,
    KnowledgeGraphIndex,
    QuerySemanticCache,
    RAPTORTreeIndex,
    SynonymExpander,
    VectorEngine,
    extract_abstract_from_okf,
)

__all__ = [
    "CitationNetworkIndex",
    "FacetedIndex",
    "FMIndex",
    "KnowledgeGraphIndex",
    "QuerySemanticCache",
    "RAPTORTreeIndex",
    "SynonymExpander",
    "VectorEngine",
    "extract_abstract_from_okf",
]

if __name__ == "__main__":
    import argparse
    import json

    parser = argparse.ArgumentParser(
        description="Advanced Multi-Engine Hybrid & RAG Search Engine for arXiv Security Papers"
    )
    parser.add_argument(
        "--build",
        action="store_true",
        help="Build or rebuild multi-engine hybrid index",
    )
    parser.add_argument("--query", type=str, help="Search query string")
    parser.add_argument(
        "--top-k", type=int, default=5, help="Number of results to return"
    )
    args = parser.parse_args()

    engine = VectorEngine()
    if args.build:
        count = engine.build_index()
        print(
            f"✅ Multi-Engine Hybrid Index built successfully (v3.2.0). Total documents: {count}"
        )

    if args.query:
        resp = engine.search_hybrid_pipeline(args.query, top_k=args.top_k)
        print(
            f"\n🔍 Multi-Stage Hybrid Search Results for '{args.query}' (Time: {resp['profile']['total_ms']} ms):"
        )
        for i, res in enumerate(resp["papers"], 1):
            print(f"{i}. [{res['score']}] {res['title']} ({res['id']})")
            print(f"   要約: {res['description']}")
            print(f"   事前注釈キーワード: {res.get('annotated_keywords', [])}")
            print(f"   パス: {res['path']}\n")
        if resp["raptor_macro_summaries"]:
            print("📊 RAPTOR 階層要約コンテキスト:")
            for s in resp["raptor_macro_summaries"]:
                print(f" - [{s['domain']}] {s['summary']}")
        print(f"\n⏱️ Performance Breakdown: {json.dumps(resp['profile'], indent=2)}")
