#!/usr/bin/env python3
"""
Citation Network Linker.
Extracts arXiv identifiers and cross-references from paper text/metadata
and builds directed [:CITES] edges in the PropertyGraphEngine.
"""

from __future__ import annotations

import re
from typing import TYPE_CHECKING, List, Set

if TYPE_CHECKING:
    from .engine import PropertyGraphEngine

ARXIV_ID_RE = re.compile(
    r"(?:arXiv:\s*|arxiv\.org/(?:abs|pdf)/)?(\d{4}\.\d{4,5}(?:v\d+)?)",
    re.IGNORECASE,
)


class CitationLinker:
    """Extracts and establishes citation edges between paper vertices."""

    @classmethod
    def extract_cited_arxiv_ids(cls, text: str, self_id: str = "") -> List[str]:
        """
        Extracts valid, unique arXiv IDs cited within the text,
        excluding the paper's own ID.
        """
        matches: Set[str] = set()
        clean_self = self_id.replace("Paper:", "").strip()
        for match in ARXIV_ID_RE.finditer(text):
            found_id = match.group(1).split("v")[0]  # strip version suffix
            if found_id != clean_self:
                matches.add(found_id)
        return sorted(list(matches))

    @classmethod
    def link_paper_citations(
        cls,
        graph_engine: "PropertyGraphEngine",
        source_paper_id: str,
        text_or_references: str,
    ) -> int:
        """
        Extracts cited papers from text and inserts [:CITES] edges into graph_engine
        if the target papers exist as vertices. Returns number of edges created.
        """
        src_canonical = (
            source_paper_id
            if source_paper_id.startswith("Paper:")
            else f"Paper:{source_paper_id}"
        )
        if graph_engine.get_vertex(src_canonical) is None:
            return 0

        cited_ids = cls.extract_cited_arxiv_ids(
            text_or_references, self_id=source_paper_id
        )
        added_count = 0

        for cited_id in cited_ids:
            dst_canonical = f"Paper:{cited_id}"
            if graph_engine.get_vertex(dst_canonical) is not None:
                edge_id = f"cites:{src_canonical}->{dst_canonical}"
                graph_engine.add_edge(
                    src_id=src_canonical,
                    dst_id=dst_canonical,
                    label="CITES",
                    properties={"edge_id": edge_id},
                    weight=1.0,
                )
                added_count += 1

        return added_count
