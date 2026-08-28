#!/usr/bin/env python3
"""
Apache TinkerPop 3.5.0 Gremlin-compatible GraphTraversal Query DSL.
Based on the design principles of rokujyouhitoma/gremlin.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import heapq
import random
from typing import (
    TYPE_CHECKING,
    Any,
    Callable,
    Dict,
    List,
    Optional,
    Set,
    Tuple,
    Union,
)

from .structures import Edge, Path, Vertex

if TYPE_CHECKING:
    from .engine import PropertyGraphEngine


class GraphTraversal:
    """
    Fluent Graph Traversal DSL supporting TinkerPop Gremlin 3.5.0 operations.
    Maintains a list of current traversers with their history paths and step labels.
    """

    def __init__(
        self,
        engine: "PropertyGraphEngine",
        current_objects: Optional[List[Any]] = None,
        paths: Optional[List[Path]] = None,
    ) -> None:
        self.engine = engine
        self._current: List[Any] = (
            current_objects if current_objects is not None else []
        )
        self._paths: List[Path] = (
            paths
            if paths is not None
            else [Path(objects=[obj]) for obj in self._current]
        )
        self._side_effects: Dict[str, Any] = {}
        self._as_labels: Dict[str, List[Any]] = {}

    def _clone(
        self, new_objects: List[Any], new_paths: Optional[List[Path]] = None
    ) -> "GraphTraversal":
        """Creates a new GraphTraversal instance preserving engine reference."""
        t = GraphTraversal(
            engine=self.engine,
            current_objects=new_objects,
            paths=new_paths
            if new_paths is not None
            else [Path(objects=[obj]) for obj in new_objects],
        )
        t._side_effects = dict(self._side_effects)
        t._as_labels = {k: list(v) for k, v in self._as_labels.items()}
        return t

    # -------------------------------------------------------------------------
    # 1. Navigation Steps (V, E, out, in_, both, outE, inE, bothE, outV, inV...)
    # -------------------------------------------------------------------------

    def V(self, *vertex_ids: str) -> "GraphTraversal":
        """Starts traversal at all vertices or specified vertex IDs."""
        if vertex_ids:
            vertices = [
                self.engine.get_vertex(vid)
                for vid in vertex_ids
                if self.engine.get_vertex(vid) is not None
            ]
        else:
            vertices = list(self.engine._vertices.values())
        return self._clone(vertices)

    def E(self, *edge_ids: str) -> "GraphTraversal":
        """Starts traversal at all edges or specified edge IDs."""
        if edge_ids:
            edges = [
                self.engine.get_edge(eid)
                for eid in edge_ids
                if self.engine.get_edge(eid) is not None
            ]
        else:
            edges = list(self.engine._edges.values())
        return self._clone(edges)

    def out(self, *labels: str) -> "GraphTraversal":
        """Moves to the outgoing adjacent vertices."""
        new_objs: List[Vertex] = []
        new_paths: List[Path] = []
        for i, obj in enumerate(self._current):
            if isinstance(obj, Vertex):
                edges = self.engine.get_out_edges(obj.id, *labels)
                for e in edges:
                    dst = self.engine.get_vertex(e.dst_id)
                    if dst is not None:
                        new_objs.append(dst)
                        curr_path = (
                            self._paths[i] if i < len(self._paths) else Path()
                        )
                        new_paths.append(curr_path.extend(dst))
        return self._clone(new_objs, new_paths)

    def in_(self, *labels: str) -> "GraphTraversal":
        """Moves to the incoming adjacent vertices."""
        new_objs: List[Vertex] = []
        new_paths: List[Path] = []
        for i, obj in enumerate(self._current):
            if isinstance(obj, Vertex):
                edges = self.engine.get_in_edges(obj.id, *labels)
                for e in edges:
                    src = self.engine.get_vertex(e.src_id)
                    if src is not None:
                        new_objs.append(src)
                        curr_path = (
                            self._paths[i] if i < len(self._paths) else Path()
                        )
                        new_paths.append(curr_path.extend(src))
        return self._clone(new_objs, new_paths)

    def both(self, *labels: str) -> "GraphTraversal":
        """Moves to adjacent vertices in both incoming and outgoing directions."""
        new_objs: List[Vertex] = []
        new_paths: List[Path] = []
        for i, obj in enumerate(self._current):
            if isinstance(obj, Vertex):
                curr_path = self._paths[i] if i < len(self._paths) else Path()
                for e in self.engine.get_out_edges(obj.id, *labels):
                    dst = self.engine.get_vertex(e.dst_id)
                    if dst is not None:
                        new_objs.append(dst)
                        new_paths.append(curr_path.extend(dst))
                for e in self.engine.get_in_edges(obj.id, *labels):
                    src = self.engine.get_vertex(e.src_id)
                    if src is not None:
                        new_objs.append(src)
                        new_paths.append(curr_path.extend(src))
        return self._clone(new_objs, new_paths)

    def outE(self, *labels: str) -> "GraphTraversal":
        """Moves from vertices to outgoing edges."""
        new_objs: List[Edge] = []
        new_paths: List[Path] = []
        for i, obj in enumerate(self._current):
            if isinstance(obj, Vertex):
                curr_path = self._paths[i] if i < len(self._paths) else Path()
                for e in self.engine.get_out_edges(obj.id, *labels):
                    new_objs.append(e)
                    new_paths.append(curr_path.extend(e))
        return self._clone(new_objs, new_paths)

    def inE(self, *labels: str) -> "GraphTraversal":
        """Moves from vertices to incoming edges."""
        new_objs: List[Edge] = []
        new_paths: List[Path] = []
        for i, obj in enumerate(self._current):
            if isinstance(obj, Vertex):
                curr_path = self._paths[i] if i < len(self._paths) else Path()
                for e in self.engine.get_in_edges(obj.id, *labels):
                    new_objs.append(e)
                    new_paths.append(curr_path.extend(e))
        return self._clone(new_objs, new_paths)

    def bothE(self, *labels: str) -> "GraphTraversal":
        """Moves from vertices to both incoming and outgoing edges."""
        new_objs: List[Edge] = []
        new_paths: List[Path] = []
        for i, obj in enumerate(self._current):
            if isinstance(obj, Vertex):
                curr_path = self._paths[i] if i < len(self._paths) else Path()
                for e in self.engine.get_both_edges(obj.id, *labels):
                    new_objs.append(e)
                    new_paths.append(curr_path.extend(e))
        return self._clone(new_objs, new_paths)

    def outV(self) -> "GraphTraversal":
        """Moves from edges to their source vertices."""
        new_objs: List[Vertex] = []
        new_paths: List[Path] = []
        for i, obj in enumerate(self._current):
            if isinstance(obj, Edge):
                src = self.engine.get_vertex(obj.src_id)
                if src is not None:
                    new_objs.append(src)
                    curr_path = (
                        self._paths[i] if i < len(self._paths) else Path()
                    )
                    new_paths.append(curr_path.extend(src))
        return self._clone(new_objs, new_paths)

    def inV(self) -> "GraphTraversal":
        """Moves from edges to their destination vertices."""
        new_objs: List[Vertex] = []
        new_paths: List[Path] = []
        for i, obj in enumerate(self._current):
            if isinstance(obj, Edge):
                dst = self.engine.get_vertex(obj.dst_id)
                if dst is not None:
                    new_objs.append(dst)
                    curr_path = (
                        self._paths[i] if i < len(self._paths) else Path()
                    )
                    new_paths.append(curr_path.extend(dst))
        return self._clone(new_objs, new_paths)

    def otherV(self) -> "GraphTraversal":
        """Moves from edges to the other vertex in the traversal history."""
        new_objs: List[Vertex] = []
        new_paths: List[Path] = []
        for i, obj in enumerate(self._current):
            if isinstance(obj, Edge):
                curr_path = self._paths[i] if i < len(self._paths) else Path()
                prev_v_id = (
                    curr_path.objects[-2].id
                    if len(curr_path.objects) >= 2
                    else None
                )
                other_id = (
                    obj.dst_id if obj.src_id == prev_v_id else obj.src_id
                )
                v = self.engine.get_vertex(other_id)
                if v is not None:
                    new_objs.append(v)
                    new_paths.append(curr_path.extend(v))
        return self._clone(new_objs, new_paths)

    # -------------------------------------------------------------------------
    # 2. Filter & Predicate Steps (has, hasLabel, hasId, filter, and_, or_...)
    # -------------------------------------------------------------------------

    def has(self, key: str, value: Any = None) -> "GraphTraversal":
        """Filters objects by property key/value or existence."""
        new_objs: List[Any] = []
        new_paths: List[Path] = []
        for i, obj in enumerate(self._current):
            props = getattr(obj, "properties", {})
            if value is None:
                if key in props or getattr(obj, key, None) is not None:
                    new_objs.append(obj)
                    new_paths.append(self._paths[i])
            else:
                if (
                    props.get(key) == value
                    or getattr(obj, key, None) == value
                    or (key == "id" and getattr(obj, "id", None) == value)
                ):
                    new_objs.append(obj)
                    new_paths.append(self._paths[i])
        return self._clone(new_objs, new_paths)

    def hasLabel(self, *labels: str) -> "GraphTraversal":
        """Filters vertices/edges by label."""
        target_labels = set(labels)
        new_objs = [
            obj
            for obj in self._current
            if getattr(obj, "label", None) in target_labels
        ]
        new_paths = [
            self._paths[i]
            for i, obj in enumerate(self._current)
            if getattr(obj, "label", None) in target_labels
        ]
        return self._clone(new_objs, new_paths)

    def hasId(self, *ids: str) -> "GraphTraversal":
        """Filters vertices/edges by ID."""
        target_ids = set(ids)
        new_objs = [
            obj
            for obj in self._current
            if getattr(obj, "id", None) in target_ids
        ]
        new_paths = [
            self._paths[i]
            for i, obj in enumerate(self._current)
            if getattr(obj, "id", None) in target_ids
        ]
        return self._clone(new_objs, new_paths)

    def hasNot(self, key: str) -> "GraphTraversal":
        """Filters out objects that have the specified property key."""
        new_objs = [
            obj
            for obj in self._current
            if key not in getattr(obj, "properties", {})
            and getattr(obj, key, None) is None
        ]
        new_paths = [
            self._paths[i]
            for i, obj in enumerate(self._current)
            if key not in getattr(obj, "properties", {})
            and getattr(obj, key, None) is None
        ]
        return self._clone(new_objs, new_paths)

    def filter(
        self, predicate_fn: Union[Callable[[Any], bool], "GraphTraversal"]
    ) -> "GraphTraversal":
        """Filters elements using a predicate function or sub-traversal."""
        new_objs: List[Any] = []
        new_paths: List[Path] = []
        for i, obj in enumerate(self._current):
            if callable(predicate_fn):
                if predicate_fn(obj):
                    new_objs.append(obj)
                    new_paths.append(self._paths[i])
            elif isinstance(predicate_fn, GraphTraversal):
                sub = self.engine.V(getattr(obj, "id", ""))._clone([obj])
                if len(sub._current) > 0:
                    new_objs.append(obj)
                    new_paths.append(self._paths[i])
        return self._clone(new_objs, new_paths)

    def dedup(self) -> "GraphTraversal":
        """Deduplicates current elements preserving order."""
        seen: Set[str] = set()
        new_objs: List[Any] = []
        new_paths: List[Path] = []
        for i, obj in enumerate(self._current):
            oid = getattr(obj, "id", str(obj))
            if oid not in seen:
                seen.add(oid)
                new_objs.append(obj)
                new_paths.append(self._paths[i])
        return self._clone(new_objs, new_paths)

    def limit(self, n: int) -> "GraphTraversal":
        """Limits the traversal stream to n elements."""
        return self._clone(self._current[:n], self._paths[:n])

    def skip(self, n: int) -> "GraphTraversal":
        """Skips the first n elements in the traversal stream."""
        return self._clone(self._current[n:], self._paths[n:])

    def range(self, start: int, end: int) -> "GraphTraversal":
        """Slices the traversal stream from start to end index."""
        return self._clone(self._current[start:end], self._paths[start:end])

    def coin(self, probability: float) -> "GraphTraversal":
        """Probabilistically samples elements with probability p (0.0 - 1.0)."""
        new_objs = [
            obj for obj in self._current if random.random() <= probability
        ]
        return self._clone(new_objs)

    def simplePath(self) -> "GraphTraversal":
        """Filters out paths that contain cycles (repeated vertices)."""
        new_objs: List[Any] = []
        new_paths: List[Path] = []
        for i, p in enumerate(self._paths):
            v_ids = [
                getattr(o, "id", str(o))
                for o in p.objects
                if isinstance(o, Vertex)
            ]
            if len(v_ids) == len(set(v_ids)):
                new_objs.append(self._current[i])
                new_paths.append(p)
        return self._clone(new_objs, new_paths)

    # -------------------------------------------------------------------------
    # 3. Projection & Aggregation Steps (values, valueMap, count, group...)
    # -------------------------------------------------------------------------

    def values(self, *keys: str) -> "GraphTraversal":
        """Extracts property values from current vertices/edges."""
        new_objs: List[Any] = []
        for obj in self._current:
            props = getattr(obj, "properties", {})
            for k in keys:
                if k in props:
                    new_objs.append(props[k])
                elif hasattr(obj, k):
                    new_objs.append(getattr(obj, k))
        return self._clone(new_objs)

    def valueMap(self, *keys: str) -> "GraphTraversal":
        """Extracts property maps as dictionaries."""
        new_objs: List[Dict[str, Any]] = []
        for obj in self._current:
            props = dict(getattr(obj, "properties", {}))
            if keys:
                props = {k: v for k, v in props.items() if k in keys}
            new_objs.append(props)
        return self._clone(new_objs)

    def id(self) -> "GraphTraversal":
        """Extracts IDs of elements."""
        return self._clone([getattr(obj, "id", str(obj)) for obj in self._current])

    def label(self) -> "GraphTraversal":
        """Extracts labels of elements."""
        return self._clone(
            [getattr(obj, "label", "Unknown") for obj in self._current]
        )

    def count(self) -> "GraphTraversal":
        """Counts the total number of elements in the traversal."""
        return self._clone([len(self._current)])

    def sum(self) -> "GraphTraversal":
        """Sums numeric elements in the stream."""
        total = sum(float(x) for x in self._current if isinstance(x, (int, float)))
        return self._clone([total])

    def mean(self) -> "GraphTraversal":
        """Calculates arithmetic mean of numeric elements."""
        nums = [float(x) for x in self._current if isinstance(x, (int, float))]
        avg = (sum(nums) / len(nums)) if nums else 0.0
        return self._clone([avg])

    def groupCount(self) -> "GraphTraversal":
        """Computes frequency distribution of elements."""
        counts: Dict[str, int] = {}
        for obj in self._current:
            key = getattr(obj, "label", getattr(obj, "id", str(obj)))
            counts[key] = counts.get(key, 0) + 1
        return self._clone([counts])

    def fold(self) -> "GraphTraversal":
        """Folds entire stream into a single list element."""
        return self._clone([list(self._current)])

    def unfold(self) -> "GraphTraversal":
        """Unfolds nested list elements into a flat stream."""
        flat: List[Any] = []
        for item in self._current:
            if isinstance(item, (list, set, tuple)):
                flat.extend(list(item))
            else:
                flat.append(item)
        return self._clone(flat)

    # -------------------------------------------------------------------------
    # 4. Advanced Graph Control & Algorithms (repeat, times, shortestPath, pageRank)
    # -------------------------------------------------------------------------

    def as_(self, step_label: str) -> "GraphTraversal":
        """Labels the current step elements for later reference via select()."""
        self._as_labels[step_label] = list(self._current)
        return self

    def select(self, step_label: str) -> "GraphTraversal":
        """Retrieves elements previously labeled with as_()."""
        return self._clone(self._as_labels.get(step_label, []))

    def path(self) -> "GraphTraversal":
        """Returns the full historical paths taken by traversers."""
        return self._clone([p.to_list() for p in self._paths])

    def repeat(
        self, traversal_step_fn: Callable[["GraphTraversal"], "GraphTraversal"]
    ) -> "_RepeatHelper":
        """Applies a repeated sub-traversal step."""
        return _RepeatHelper(parent=self, step_fn=traversal_step_fn)

    def shortestPath(self, target_id: str) -> List[Vertex]:
        """Calculates shortest weighted path (Dijkstra) from current vertex to target_id."""
        if not self._current or not isinstance(self._current[0], Vertex):
            return []
        start_v = self._current[0]
        if start_v.id == target_id:
            return [start_v]

        dist: Dict[str, float] = {start_v.id: 0.0}
        prev: Dict[str, Optional[str]] = {start_v.id: None}
        pq: List[Tuple[float, str]] = [(0.0, start_v.id)]
        visited: Set[str] = set()

        while pq:
            d, u = heapq.heappop(pq)
            if u in visited:
                continue
            visited.add(u)
            if u == target_id:
                break

            for edge in self.engine.get_out_edges(u):
                v = edge.dst_id
                weight = max(0.01, float(edge.weight))
                if dist.get(v, float("inf")) > d + weight:
                    dist[v] = d + weight
                    prev[v] = u
                    heapq.heappush(pq, (dist[v], v))

        if target_id not in dist:
            return []

        # Reconstruct path
        path_ids: List[str] = []
        curr: Optional[str] = target_id
        while curr is not None:
            path_ids.append(curr)
            curr = prev.get(curr)
        path_ids.reverse()

        result: List[Vertex] = []
        for vid in path_ids:
            v_obj = self.engine.get_vertex(vid)
            if v_obj is not None:
                result.append(v_obj)
        return result

    def pageRank(
        self, damping: float = 0.85, iterations: int = 20
    ) -> Dict[str, float]:
        """Calculates PageRank centrality for all vertices in the graph."""
        vertices = list(self.engine._vertices.keys())
        N = len(vertices)
        if N == 0:
            return {}

        ranks: Dict[str, float] = {v: 1.0 / N for v in vertices}
        for _ in range(iterations):
            new_ranks: Dict[str, float] = {
                v: (1.0 - damping) / N for v in vertices
            }
            for u in vertices:
                out_edges = self.engine.get_out_edges(u)
                out_deg = len(out_edges)
                if out_deg > 0:
                    share = (damping * ranks[u]) / out_deg
                    for e in out_edges:
                        new_ranks[e.dst_id] = new_ranks.get(e.dst_id, 0.0) + share
                else:
                    share = (damping * ranks[u]) / N
                    for v in vertices:
                        new_ranks[v] += share
            ranks = new_ranks

        return ranks

    # -------------------------------------------------------------------------
    # 5. Terminal Steps (toList, toSet, next, iterate, to_triples)
    # -------------------------------------------------------------------------

    def toList(self) -> List[Any]:
        """Terminates traversal and returns all elements as a list."""
        return list(self._current)

    def toSet(self) -> Set[Any]:
        """Terminates traversal and returns all elements as a set."""
        return set(self._current)

    def next(self, amount: int = 1) -> Any:
        """Returns the next element or first n elements."""
        if amount == 1:
            return self._current[0] if self._current else None
        return self._current[:amount]

    def iterate(self) -> "GraphTraversal":
        """Executes all traversal side effects and returns self."""
        return self

    def to_triples(self) -> List[Dict[str, Any]]:
        """Converts matched paths into semantic triples for GraphRAG."""
        triples: List[Dict[str, Any]] = []
        for p in self._paths:
            for i in range(len(p.objects) - 1):
                src = p.objects[i]
                dst = p.objects[i + 1]
                if isinstance(src, Vertex) and isinstance(dst, Vertex):
                    # Find connecting edge
                    edges = self.engine.get_out_edges(src.id)
                    for e in edges:
                        if e.dst_id == dst.id:
                            triples.append(
                                {
                                    "subject": src.id,
                                    "predicate": e.label,
                                    "object": dst.id,
                                    "weight": e.weight,
                                }
                            )
        return triples


class _RepeatHelper:
    """Helper class implementing .repeat(...).times(n) or .until(...) loop construct."""

    def __init__(
        self,
        parent: GraphTraversal,
        step_fn: Callable[[GraphTraversal], GraphTraversal],
    ) -> None:
        self.parent = parent
        self.step_fn = step_fn

    def times(self, n: int) -> GraphTraversal:
        """Repeats the step function exactly n times."""
        curr = self.parent
        for _ in range(n):
            curr = self.step_fn(curr)
        return curr

    def until(
        self,
        condition_fn: Callable[[GraphTraversal], bool],
        max_depth: int = 5,
        emit: bool = False,
    ) -> GraphTraversal:
        """Repeats step function until condition is met (up to max_depth)."""
        curr = self.parent
        emitted_objs: List[Any] = []
        for _ in range(max_depth):
            if emit:
                emitted_objs.extend(curr._current)
            if condition_fn(curr):
                break
            curr = self.step_fn(curr)
        if emit:
            emitted_objs.extend(curr._current)
            return curr._clone(emitted_objs)
        return curr
