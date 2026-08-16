#!/usr/bin/env python3
"""
Entity Graph & Relationship Index for GraphRAG and Multi-Hop Inference.
"""

from collections import defaultdict
from typing import Any, Dict, List, Set


class KnowledgeGraphIndex:
    """
    Entity Graph & Relationship Index for GraphRAG and Multi-Hop Inference.
    """

    def __init__(self) -> None:
        self.nodes: Dict[str, Dict[str, Any]] = {}
        self.edges: List[Dict[str, Any]] = []
        self.adjacency: Dict[str, List[Dict[str, str]]] = defaultdict(list)
        self.doc_to_entities: Dict[str, Set[str]] = defaultdict(set)

    def add_entity(
        self, entity_id: str, entity_type: str, label: str, doc_id: str
    ) -> None:
        if entity_id not in self.nodes:
            self.nodes[entity_id] = {
                "id": entity_id,
                "type": entity_type,
                "label": label,
                "papers": [doc_id],
            }
        else:
            if doc_id not in self.nodes[entity_id]["papers"]:
                self.nodes[entity_id]["papers"].append(doc_id)
        self.doc_to_entities[doc_id].add(entity_id)

    def add_relationship(
        self, source: str, target: str, relation: str, doc_id: str
    ) -> None:
        edge = {
            "source": source,
            "target": target,
            "relation": relation,
            "doc_id": doc_id,
        }
        self.edges.append(edge)
        self.adjacency[source].append({"target": target, "relation": relation})

    def get_neighbors(self, entity_id: str, max_depth: int = 2) -> Dict[str, Any]:
        visited = set([entity_id])
        queue = [(entity_id, 0)]
        subgraph_nodes = []
        subgraph_edges = []
        related_papers: Set[str] = set()

        while queue:
            curr, depth = queue.pop(0)
            if curr in self.nodes:
                subgraph_nodes.append(self.nodes[curr])
                related_papers.update(self.nodes[curr].get("papers", []))

            if depth < max_depth:
                for neighbor in self.adjacency.get(curr, []):
                    target = neighbor["target"]
                    subgraph_edges.append(
                        {
                            "source": curr,
                            "target": target,
                            "relation": neighbor["relation"],
                        }
                    )
                    if target not in visited:
                        visited.add(target)
                        queue.append((target, depth + 1))

        return {
            "root": entity_id,
            "nodes": subgraph_nodes,
            "edges": subgraph_edges,
            "related_papers": list(related_papers),
        }
