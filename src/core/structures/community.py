#!/usr/bin/env python3
"""
Pure-Python Louvain Modularity Optimization Community Detection Engine.
Enables fast, hierarchical clustering of cyber threat intelligence (CTI) graphs
without external scientific libraries.
"""

from __future__ import annotations

import random
from typing import Dict, Iterable, List, Optional, Set, Tuple


def _accumulate_meta_edge(
    meta_adj: Dict[str, Dict[str, float]], c_u: str, c_v: str, w: float
) -> None:
    if c_v not in meta_adj[c_u]:
        meta_adj[c_u][c_v] = 0.0
    meta_adj[c_u][c_v] += w


def _populate_meta_edges(
    adj: Dict[str, Dict[str, float]],
    partition: Dict[str, int],
    meta_adj: Dict[str, Dict[str, float]],
) -> None:
    for u, neighbors in adj.items():
        c_u = str(partition[u])
        for v, w in neighbors.items():
            c_v = str(partition[v])
            _accumulate_meta_edge(meta_adj, c_u, c_v, w)


def _build_meta_graph(
    adj: Dict[str, Dict[str, float]], partition: Dict[str, int], num_comms: int
) -> Dict[str, Dict[str, float]]:
    meta_adj: Dict[str, Dict[str, float]] = {str(i): {} for i in range(num_comms)}
    _populate_meta_edges(adj, partition, meta_adj)
    return meta_adj


def _compress_partition_ids(partition: Dict[str, int]) -> Tuple[Dict[str, int], int]:
    comm_map: Dict[int, int] = {}
    compressed: Dict[str, int] = {}
    for node, comm in partition.items():
        if comm not in comm_map:
            comm_map[comm] = len(comm_map)
        compressed[node] = comm_map[comm]
    return compressed, len(comm_map)


def _compute_node_weight_to_comm(
    adj: Dict[str, Dict[str, float]],
    u: str,
    target_comm: int,
    node_comm: Dict[str, int],
) -> float:
    weight = 0.0
    for neighbor, w in adj.get(u, {}).items():
        if node_comm.get(neighbor) == target_comm and neighbor != u:
            weight += w
    return weight


def _eval_comm_gain(
    k_in: float,
    sigma_tot: float,
    k_u: float,
    weight_2m: float,
    resolution: float,
) -> float:
    return k_in - resolution * (sigma_tot * k_u) / weight_2m


def _evaluate_best_community(
    candidates: Iterable[int],
    adj: Dict[str, Dict[str, float]],
    u: str,
    curr_comm: int,
    comm_tot: Dict[int, float],
    node_comm: Dict[str, int],
    k_u: float,
    weight_2m: float,
    resolution: float,
) -> Tuple[int, float]:
    best_comm = curr_comm
    base_k_in = _compute_node_weight_to_comm(adj, u, curr_comm, node_comm)
    base_gain = _eval_comm_gain(
        base_k_in, comm_tot.get(curr_comm, 0.0), k_u, weight_2m, resolution
    )
    best_gain = base_gain

    for cand in candidates:
        if cand == curr_comm:
            continue
        cand_k_in = _compute_node_weight_to_comm(adj, u, cand, node_comm)
        cand_gain = _eval_comm_gain(
            cand_k_in, comm_tot.get(cand, 0.0), k_u, weight_2m, resolution
        )
        if cand_gain > best_gain:
            best_gain = cand_gain
            best_comm = cand

    return best_comm, best_gain - base_gain


def _move_single_node(
    u: str,
    adj: Dict[str, Dict[str, float]],
    node_comm: Dict[str, int],
    comm_tot: Dict[int, float],
    k_u: float,
    weight_2m: float,
    resolution: float,
    min_gain: float,
) -> float:
    curr_comm = node_comm[u]
    comm_tot[curr_comm] -= k_u
    candidates: Set[int] = {node_comm[nb] for nb in adj.get(u, {}) if nb in node_comm}
    candidates.add(curr_comm)

    best_comm, net_gain = _evaluate_best_community(
        candidates,
        adj,
        u,
        curr_comm,
        comm_tot,
        node_comm,
        k_u,
        weight_2m,
        resolution,
    )

    if net_gain > min_gain:
        node_comm[u] = best_comm
        comm_tot[best_comm] = comm_tot.get(best_comm, 0.0) + k_u
        return net_gain

    comm_tot[curr_comm] += k_u
    return 0.0


def _one_pass_local_move(
    nodes: List[str],
    adj: Dict[str, Dict[str, float]],
    node_comm: Dict[str, int],
    comm_tot: Dict[int, float],
    degrees: Dict[str, float],
    weight_2m: float,
    resolution: float,
    min_gain: float,
) -> float:
    total_gain = 0.0
    for u in nodes:
        gain = _move_single_node(
            u,
            adj,
            node_comm,
            comm_tot,
            degrees[u],
            weight_2m,
            resolution,
            min_gain,
        )
        total_gain += gain
    return total_gain


def _exec_local_iteration(
    iter_nodes: List[str],
    adj: Dict[str, Dict[str, float]],
    node_comm: Dict[str, int],
    comm_tot: Dict[int, float],
    degrees: Dict[str, float],
    weight_2m: float,
    resolution: float,
    min_gain: float,
    random_state: Optional[random.Random],
) -> float:
    if random_state:
        random_state.shuffle(iter_nodes)
    return _one_pass_local_move(
        iter_nodes,
        adj,
        node_comm,
        comm_tot,
        degrees,
        weight_2m,
        resolution,
        min_gain,
    )


def _accumulate_node_comm_weights(
    adj: Dict[str, Dict[str, float]],
    u: str,
    c_u: int,
    partition: Dict[str, int],
    comm_in: Dict[int, float],
) -> None:
    for v, w in adj.get(u, {}).items():
        if partition.get(v, -2) == c_u:
            comm_in[c_u] = comm_in.get(c_u, 0.0) + w


def _compute_community_weights(
    adj: Dict[str, Dict[str, float]],
    nodes: List[str],
    partition: Dict[str, int],
    degrees: Dict[str, float],
) -> Tuple[Dict[int, float], Dict[int, float]]:
    comm_in: Dict[int, float] = {}
    comm_tot: Dict[int, float] = {}
    for u in nodes:
        c_u = partition.get(u, -1)
        comm_tot[c_u] = comm_tot.get(c_u, 0.0) + degrees[u]
        _accumulate_node_comm_weights(adj, u, c_u, partition, comm_in)
    return comm_in, comm_tot


def _sort_and_renumber_communities(partition: Dict[str, int]) -> Dict[str, int]:
    counts: Dict[int, int] = {}
    for comm in partition.values():
        counts[comm] = counts.get(comm, 0) + 1
    sorted_comms = sorted(counts.keys(), key=lambda c: (-counts[c], c))
    mapping = {c: idx for idx, c in enumerate(sorted_comms)}
    return {node: mapping[comm] for node, comm in partition.items()}


def _parse_edge_tuple(
    edge: Tuple[str, str, float] | Tuple[str, str],
) -> Tuple[str, str, float]:
    w = float(edge[2]) if len(edge) > 2 else 1.0
    return edge[0], edge[1], w


def _add_edge_to_adj(
    adj: Dict[str, Dict[str, float]],
    edge: Tuple[str, str, float] | Tuple[str, str],
) -> None:
    u, v, w = _parse_edge_tuple(edge)
    adj.setdefault(u, {})[v] = adj.setdefault(u, {}).get(v, 0.0) + w
    if u != v:
        adj.setdefault(v, {})[u] = adj.setdefault(v, {}).get(u, 0.0) + w


def _merge_partitions(
    final_partition: Dict[str, int],
    compressed: Dict[str, int],
    pass_idx: int,
) -> Dict[str, int]:
    if pass_idx == 0:
        return compressed
    return {orig: compressed[str(cur_c)] for orig, cur_c in final_partition.items()}


class LouvainCommunityDetector:
    """
    Pure-Python Louvain Modularity Optimization Community Detection.
    Partitions graphs into densely connected clusters by maximizing modularity Q.
    """

    def _compute_degrees_and_total_weight(
        self, adj: Dict[str, Dict[str, float]], nodes: List[str]
    ) -> Tuple[Dict[str, float], float]:
        degrees: Dict[str, float] = {}
        total_weight_2m = 0.0
        for u in nodes:
            deg = 0.0
            for v, w in adj.get(u, {}).items():
                deg += w
                total_weight_2m += w
            degrees[u] = deg
        return degrees, total_weight_2m

    def _init_louvain_state(
        self, adj: Dict[str, Dict[str, float]]
    ) -> Tuple[List[str], Dict[str, float], float]:
        nodes = sorted(adj.keys())
        degrees, weight_2m = self._compute_degrees_and_total_weight(adj, nodes)
        return nodes, degrees, weight_2m

    def _run_local_optimization(
        self,
        nodes: List[str],
        adj: Dict[str, Dict[str, float]],
        degrees: Dict[str, float],
        weight_2m: float,
        resolution: float,
        max_iter: int,
        min_gain: float,
        random_state: Optional[random.Random] = None,
    ) -> Dict[str, int]:
        node_comm = {n: idx for idx, n in enumerate(nodes)}
        comm_tot = {idx: degrees[n] for idx, n in enumerate(nodes)}
        iter_nodes = list(nodes)

        for _ in range(max_iter):
            gain = _exec_local_iteration(
                iter_nodes,
                adj,
                node_comm,
                comm_tot,
                degrees,
                weight_2m,
                resolution,
                min_gain,
                random_state,
            )
            if gain <= min_gain:
                break

        return node_comm

    def _execute_pass(
        self,
        current_nodes: List[str],
        current_adj: Dict[str, Dict[str, float]],
        resolution: float,
        rnd: Optional[random.Random],
        max_iter: int,
        min_gain: float,
    ) -> Tuple[Dict[str, int], int]:
        deg, w2m = self._compute_degrees_and_total_weight(current_adj, current_nodes)
        level_comm = self._run_local_optimization(
            current_nodes,
            current_adj,
            deg,
            w2m,
            resolution,
            max_iter,
            min_gain,
            rnd,
        )
        return _compress_partition_ids(level_comm)

    def _hierarchical_louvain_passes(
        self,
        nodes: List[str],
        adj: Dict[str, Dict[str, float]],
        resolution: float,
        rnd: Optional[random.Random],
        max_passes: int,
        max_iter: int,
        min_gain: float,
    ) -> Dict[str, int]:
        current_adj = adj
        current_nodes = nodes
        final_partition: Dict[str, int] = {}

        for pass_idx in range(max_passes):
            compressed, num_comms = self._execute_pass(
                current_nodes, current_adj, resolution, rnd, max_iter, min_gain
            )
            final_partition = _merge_partitions(final_partition, compressed, pass_idx)
            if num_comms >= len(current_nodes):
                break
            current_adj = _build_meta_graph(current_adj, compressed, num_comms)
            current_nodes = [str(i) for i in range(num_comms)]

        return _sort_and_renumber_communities(final_partition)

    def detect(
        self,
        adj: Dict[str, Dict[str, float]],
        resolution: float = 1.0,
        seed: Optional[int] = None,
        max_passes: int = 20,
        max_iter_per_pass: int = 50,
        min_gain: float = 1e-7,
    ) -> Dict[str, int]:
        """
        Executes multi-level Louvain community detection on given adjacency dictionary.
        Returns a mapping from node ID to community ID (0-indexed, ordered by size descending).
        """
        nodes, _, weight_2m = self._init_louvain_state(adj)
        if not nodes or weight_2m <= 0.0:
            return {node: idx for idx, node in enumerate(nodes)}

        rnd = random.Random(seed) if seed is not None else None
        return self._hierarchical_louvain_passes(
            nodes,
            adj,
            resolution,
            rnd,
            max_passes,
            max_iter_per_pass,
            min_gain,
        )

    def modularity(
        self,
        adj: Dict[str, Dict[str, float]],
        partition: Dict[str, int],
        resolution: float = 1.0,
    ) -> float:
        """
        Calculates Newman-Girvan modularity Q in [-0.5, 1.0] for a given graph partition.
        """
        nodes, degrees, weight_2m = self._init_louvain_state(adj)
        if not nodes or weight_2m <= 0.0:
            return 0.0

        comm_in, comm_tot = _compute_community_weights(adj, nodes, partition, degrees)
        q = 0.0
        for c, tot in comm_tot.items():
            internal_w = comm_in.get(c, 0.0)
            expected_w = resolution * (tot**2) / weight_2m
            q += internal_w - expected_w

        return q / weight_2m


def detect_louvain_communities(
    nodes: Iterable[str],
    edges: Iterable[Tuple[str, str, float] | Tuple[str, str]],
    resolution: float = 1.0,
    seed: Optional[int] = None,
) -> Dict[str, int]:
    """
    Convenience wrapper converting node and edge tuples into adjacency dict and detecting communities.
    """
    adj: Dict[str, Dict[str, float]] = {n: {} for n in nodes}
    for e in edges:
        _add_edge_to_adj(adj, e)

    detector = LouvainCommunityDetector()
    return detector.detect(adj, resolution=resolution, seed=seed)
