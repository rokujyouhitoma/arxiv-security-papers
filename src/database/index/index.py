#!/usr/bin/env python3
"""
Pure Python Hierarchical Navigable Small World (HNSW) Approximate Nearest Neighbor (ANN) Index.
Provides sub-10ms high-dimensional vector search using only Python standard library
(math, random, heapq, json).
"""

import heapq
import json
import math
import os
import random
from typing import Any, Callable, Dict, List, Optional, Sequence, Set, Tuple


class HNSWIndex:
    """
    Pure Python implementation of Hierarchical Navigable Small World (HNSW) graph index.
    """

    def __init__(
        self,
        dim: int = 128,
        distance_metric: str = "cosine",
        M: int = 16,
        ef_construction: int = 64,
        ef_search: int = 32,
        seed: int = 42,
    ) -> None:
        self.dim = dim
        self.metric = distance_metric.lower()
        self.M = M
        self.M0 = 2 * M  # Max connections at bottom layer (layer 0)
        self.ef_construction = ef_construction
        self.ef_search = ef_search
        self.mL = 1.0 / math.log(max(M, 2))

        self.rng = random.Random(seed)
        self.vectors: Dict[int, Tuple[float, ...]] = {}
        self.node_levels: Dict[int, int] = {}
        self.layers: List[Dict[int, List[int]]] = []
        self.enter_point: Optional[int] = None
        self.max_level: int = -1

    def _distance(self, v1: Sequence[float], v2: Sequence[float]) -> float:
        """Computes distance between two vectors (lower = closer)."""
        if self.metric in ("cosine", "dot_product"):
            dot = sum(x * y for x, y in zip(v1, v2))
            return max(0.0, 1.0 - dot)
        else:
            return sum((x - y) ** 2 for x, y in zip(v1, v2))

    def _similarity_from_distance(self, dist: float) -> float:
        """Converts distance back to a 0.0 ~ 1.0 similarity score."""
        if self.metric in ("cosine", "dot_product"):
            return max(0.0, min(1.0, 1.0 - dist))
        else:
            return 1.0 / (1.0 + math.sqrt(dist))

    def _random_level(self) -> int:
        """Generates random level with exponential decay."""
        unif = max(1e-9, self.rng.random())
        return int(-math.log(unif) * self.mL)

    def _should_add_to_results(self, n_dist: float, w_results: list, ef: int) -> bool:
        return n_dist < -w_results[0][0] or len(w_results) < ef

    def _init_search_queues(
        self, query: Sequence[float], enter_points: Sequence[int]
    ) -> Tuple[List[Tuple[float, int]], List[Tuple[float, int]]]:
        candidates: List[Tuple[float, int]] = []
        w_results: List[Tuple[float, int]] = []
        for ep in enter_points:
            dist = self._distance(query, self.vectors[ep])
            heapq.heappush(candidates, (dist, ep))
            heapq.heappush(w_results, (-dist, ep))
        return candidates, w_results

    def _evaluate_neighbor(
        self,
        query: Sequence[float],
        neighbor: int,
        visited: Set[int],
        candidates: List[Tuple[float, int]],
        w_results: List[Tuple[float, int]],
        ef: int,
    ) -> None:
        if neighbor in visited:
            return
        visited.add(neighbor)
        n_dist = self._distance(query, self.vectors[neighbor])
        if self._should_add_to_results(n_dist, w_results, ef):
            heapq.heappush(candidates, (n_dist, neighbor))
            heapq.heappush(w_results, (-n_dist, neighbor))
            if len(w_results) > ef:
                heapq.heappop(w_results)

    def _search_layer(
        self,
        query: Sequence[float],
        enter_points: Sequence[int],
        ef: int,
        level: int,
    ) -> List[Tuple[float, int]]:
        """Greedy beam search with priority queues within a specific graph level."""
        visited: Set[int] = set(enter_points)
        candidates, w_results = self._init_search_queues(query, enter_points)
        layer_graph = self.layers[level]
        while candidates:
            c_dist, c_node = heapq.heappop(candidates)
            if c_dist > -w_results[0][0]:
                break
            for neighbor in layer_graph.get(c_node, []):
                self._evaluate_neighbor(
                    query, neighbor, visited, candidates, w_results, ef
                )
        res = [(-neg_d, node) for neg_d, node in w_results]
        res.sort(key=lambda x: x[0])
        return res

    def _select_neighbors(
        self,
        query: Sequence[float],
        candidates: List[Tuple[float, int]],
        max_m: int,
    ) -> List[int]:
        """Heuristic selection of closest neighbors."""
        sorted_candidates = sorted(candidates, key=lambda x: x[0])
        return [node for _, node in sorted_candidates[:max_m]]

    def insert(self, node_id: int, vector: Sequence[float]) -> None:
        """Alias for add_item for standard index API consistency."""
        self.add_item(node_id, vector)

    def _greedy_traverse_level(
        self, vec: Tuple[float, ...], curr_obj: int, curr_dist: float, lc: int
    ) -> Tuple[int, float]:
        """Traverses one level greedily, returning new (curr_obj, curr_dist)."""
        changed = True
        while changed:
            changed = False
            for neighbor in self.layers[lc].get(curr_obj, []):
                d = self._distance(vec, self.vectors[neighbor])
                if d < curr_dist:
                    curr_dist = d
                    curr_obj = neighbor
                    changed = True
        return curr_obj, curr_dist

    def _traverse_upper_layers(self, vec: Tuple[float, ...], insert_level: int) -> int:
        curr_obj = self.enter_point
        if curr_obj is None:
            return 0
        curr_dist = self._distance(vec, self.vectors[curr_obj])
        for lc in range(self.max_level, insert_level, -1):
            curr_obj, curr_dist = self._greedy_traverse_level(
                vec, curr_obj, curr_dist, lc
            )
        return curr_obj

    def _update_neighbor_links(
        self, node_id: int, n: int, lc: int, max_conn: int
    ) -> None:
        n_neighbors = self.layers[lc].setdefault(n, [])
        n_neighbors.append(node_id)
        if len(n_neighbors) > max_conn:
            candidates = [
                (self._distance(self.vectors[n], self.vectors[c]), c)
                for c in n_neighbors
            ]
            self.layers[lc][n] = self._select_neighbors(
                self.vectors[n], candidates, max_conn
            )

    def _insert_lower_layers(
        self, node_id: int, vec: Tuple[float, ...], curr_obj: int, insert_level: int
    ) -> None:
        enter_points = [curr_obj]
        for lc in range(min(self.max_level, insert_level), -1, -1):
            w = self._search_layer(vec, enter_points, self.ef_construction, lc)
            max_conn = self.M0 if lc == 0 else self.M
            neighbors = self._select_neighbors(vec, w, max_conn)
            self.layers[lc][node_id] = neighbors
            for n in neighbors:
                self._update_neighbor_links(node_id, n, lc, max_conn)
            enter_points = [node for _, node in w]

    def _init_first_node(self, node_id: int, insert_level: int) -> None:
        self.enter_point = node_id
        self.max_level = insert_level
        for lc in range(insert_level + 1):
            self.layers[lc][node_id] = []

    def add_item(self, node_id: int, vector: Sequence[float]) -> None:
        """Inserts a vector into the HNSW index."""
        if len(vector) != self.dim:
            raise ValueError(f"Vector dimension {len(vector)} != expected {self.dim}")
        vec_tuple = tuple(vector)
        self.vectors[node_id] = vec_tuple
        insert_level = self._random_level()
        self.node_levels[node_id] = insert_level
        while len(self.layers) <= insert_level:
            self.layers.append({})
        if self.enter_point is None:
            self._init_first_node(node_id, insert_level)
            return
        curr_obj = self._traverse_upper_layers(vec_tuple, insert_level)
        self._insert_lower_layers(node_id, vec_tuple, curr_obj, insert_level)
        if insert_level > self.max_level:
            self.max_level = insert_level
            self.enter_point = node_id

    def build_from_storage(
        self,
        vectors: Sequence[Sequence[float]],
        progress_callback: Optional[Callable[[int, int], None]] = None,
    ) -> None:
        """Builds index from a sequence of vectors."""
        total = len(vectors)
        for idx, vec in enumerate(vectors):
            self.add_item(idx, vec)
            if progress_callback and (idx % 100 == 0 or idx == total - 1):
                progress_callback(idx + 1, total)

    def _get_entry_point(self) -> Optional[int]:
        if self.enter_point is None:
            return None
        if not self.vectors:
            return None
        return self.enter_point

    def search(
        self,
        query: Sequence[float],
        top_k: int = 10,
        ef_search: Optional[int] = None,
    ) -> List[Tuple[int, float]]:
        """Searches Top-K nearest neighbors. Returns list of (node_id, similarity_score)."""
        curr_obj = self._get_entry_point()
        if curr_obj is None:
            return []
        ef = ef_search or max(self.ef_search, top_k)
        curr_dist = self._distance(query, self.vectors[curr_obj])
        for lc in range(self.max_level, 0, -1):
            curr_obj, curr_dist = self._greedy_traverse_level(
                query, curr_obj, curr_dist, lc
            )
        w = self._search_layer(query, [curr_obj], ef, 0)
        return [(node, self._similarity_from_distance(d)) for d, node in w[:top_k]]

    def save(self, file_path: str) -> None:
        """Serializes graph index state to JSON file."""
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        data: Dict[str, Any] = {
            "dim": self.dim,
            "metric": self.metric,
            "M": self.M,
            "M0": self.M0,
            "ef_construction": self.ef_construction,
            "ef_search": self.ef_search,
            "enter_point": self.enter_point,
            "max_level": self.max_level,
            "node_levels": self.node_levels,
            "layers": self.layers,
        }
        with open(file_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)

    @classmethod
    def _load_layers(cls, data: Dict[str, Any]) -> list:
        return [
            {int(k): [int(x) for x in v] for k, v in layer.items()}
            for layer in data["layers"]
        ]

    @classmethod
    def load(
        cls, file_path: str, vectors: Optional[Dict[int, Tuple[float, ...]]] = None
    ) -> "HNSWIndex":
        """Loads index graph structure from file."""
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        idx = cls(
            dim=data["dim"],
            distance_metric=data["metric"],
            M=data["M"],
            ef_construction=data["ef_construction"],
            ef_search=data["ef_search"],
        )
        idx.enter_point = data["enter_point"]
        idx.max_level = data["max_level"]
        idx.node_levels = {int(k): v for k, v in data["node_levels"].items()}
        idx.layers = cls._load_layers(data)
        if vectors:
            idx.vectors = vectors
        return idx
