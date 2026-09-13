#!/usr/bin/env python3
"""
CTI Knowledge Graph Query DSL Parser powered by Packrat PEG.
Provides Cypher-style path queries (e.g. APT29 -> [USES] -> Malware -> [EXPLOITS] -> CWE-79)
and structured composite filter queries (e.g. community:0 AND label:ThreatActor).
Conforms to DSN-25 Phase 1 / DSN-18 specifications.
"""

from typing import Any, List, Optional, Set, Tuple, cast

from core.structures.peg import (
    Lit,
    OneOrMore,
    Opt,
    Parser,
    PEGSyntaxError,
    Reg,
    Seq,
    ZeroOrMore,
)
from graph.structures import Edge, Vertex


class NodePattern:
    """Represents a node expression in a graph path query."""

    def __init__(
        self,
        name_or_id: Optional[str] = None,
        label: Optional[str] = None,
        alias: Optional[str] = None,
    ) -> None:
        self.name_or_id = name_or_id
        self.label = label
        self.alias = alias

    def __repr__(self) -> str:
        return f"NodePattern(id={self.name_or_id!r}, label={self.label!r}, alias={self.alias!r})"


class EdgePattern:
    """Represents an edge expression in a graph path query."""

    def __init__(
        self,
        label: Optional[str] = None,
        direction: str = "out",
        min_hops: int = 1,
        max_hops: int = 1,
    ) -> None:
        self.label = label
        self.direction = direction  # "out", "in", "both"
        self.min_hops = min_hops
        self.max_hops = max_hops

    def __repr__(self) -> str:
        return f"EdgePattern(label={self.label!r}, dir={self.direction!r}, hops={self.min_hops}..{self.max_hops})"


class PathPattern:
    """Represents a multi-hop graph path pattern."""

    def __init__(
        self,
        nodes: List[NodePattern],
        edges: List[EdgePattern],
    ) -> None:
        self.nodes = nodes
        self.edges = edges

    def __repr__(self) -> str:
        return f"PathPattern(nodes={self.nodes!r}, edges={self.edges!r})"


class FilterCondition:
    """Represents a key:value filter condition."""

    def __init__(self, key: str, value: str) -> None:
        self.key = key
        self.value = value

    def __repr__(self) -> str:
        return f"FilterCondition({self.key}:{self.value})"


class FilterQuery:
    """Represents a composite filter expression."""

    def __init__(self, conditions: List[FilterCondition], op: str = "AND") -> None:
        self.conditions = conditions
        self.op = op

    def __repr__(self) -> str:
        return f"FilterQuery({self.op}, conds={self.conditions!r})"


class GraphDSLQuery:
    """Unified container for parsed graph queries."""

    def __init__(
        self,
        kind: str,
        path: Optional[PathPattern] = None,
        filter_q: Optional[FilterQuery] = None,
    ) -> None:
        self.kind = kind  # "path" or "filter"
        self.path = path
        self.filter = filter_q

    def __repr__(self) -> str:
        if self.kind == "path":
            return f"GraphDSLQuery(path={self.path!r})"
        return f"GraphDSLQuery(filter={self.filter!r})"


# =========================================================================
# PEG Grammar Construction for Graph Query DSL
# =========================================================================


def _extract_paren_node(body: Any) -> NodePattern:
    if body is None:
        return NodePattern()
    alias_str, label_part = body
    lbl = label_part[1] if label_part else None
    name = alias_str if alias_str and not lbl else None
    return NodePattern(name_or_id=name, label=lbl, alias=alias_str)


def _make_node_pattern(val: Any) -> NodePattern:
    if isinstance(val, str):
        return NodePattern(name_or_id=val)
    return _extract_paren_node(val[2])


def _build_node_parser() -> Parser[NodePattern]:
    opt_ws = Opt(Reg(r"\s+"))
    ident = Reg(r"[a-zA-Z0-9_\-]+")
    label_part = Seq(Lit(":"), ident)
    node_body = Seq(Opt(ident), Opt(label_part))
    paren_node = Seq(Lit("("), opt_ws, Opt(node_body), opt_ws, Lit(")"))
    simple_node = ident
    return (paren_node / simple_node).map(_make_node_pattern)


def _parse_arrow_bracket_arrow(val: Any) -> EdgePattern:
    b_content = val[2]
    colon_part = b_content[2]
    lbl = colon_part[1] if (colon_part and len(colon_part) > 1) else None
    return EdgePattern(label=lbl, direction="out")


def _parse_bracket_edge(val: Any) -> EdgePattern:
    prefix, _, lbl_part, _, suffix = val
    lbl = lbl_part[1] if (lbl_part and len(lbl_part) > 1) else None
    if str(prefix).startswith("<-"):
        direction = "in"
    elif str(suffix).endswith("->"):
        direction = "out"
    else:
        direction = "both"
    return EdgePattern(label=lbl, direction=direction)


def _make_edge_pattern(val: Any) -> EdgePattern:
    if val in ("->", "<-", "--"):
        dir_map = {"->": "out", "<-": "in", "--": "both"}
        return EdgePattern(direction=dir_map[val])
    if isinstance(val, (list, tuple)) and len(val) == 5:
        if val[0] == "->":
            return _parse_arrow_bracket_arrow(val)
        return _parse_bracket_edge(val)
    return EdgePattern(direction="out")


def _build_edge_parser() -> Parser[EdgePattern]:
    opt_ws = Opt(Reg(r"\s+"))
    ident = Reg(r"[a-zA-Z0-9_\-]+")
    colon_ident = Seq(Opt(Lit(":")), ident).map(lambda val: (None, val[1]))

    bracket_content = Seq(Lit("["), opt_ws, Opt(colon_ident), opt_ws, Lit("]"))
    arrow_bracket_arrow = Seq(Lit("->"), opt_ws, bracket_content, opt_ws, Lit("->"))
    bracket_out = Seq(Lit("-["), opt_ws, Opt(colon_ident), opt_ws, Lit("]->"))
    bracket_in = Seq(Lit("<-["), opt_ws, Opt(colon_ident), opt_ws, Lit("]-"))
    bracket_both = Seq(Lit("-["), opt_ws, Opt(colon_ident), opt_ws, Lit("]-"))

    edge_tokens = (
        arrow_bracket_arrow
        / bracket_out
        / bracket_in
        / bracket_both
        / Lit("->")
        / Lit("<-")
        / Lit("--")
    )
    return edge_tokens.map(_make_edge_pattern)


def _fold_path(val: Any) -> PathPattern:
    start_node, rest = val
    nodes = [start_node]
    edges = []
    for item in rest:
        # item is [opt_ws, edge, opt_ws, node]
        edges.append(item[1])
        nodes.append(item[3])
    return PathPattern(nodes=nodes, edges=edges)


def _build_path_parser(
    node_p: Parser[NodePattern], edge_p: Parser[EdgePattern]
) -> Parser[PathPattern]:
    opt_ws = Opt(Reg(r"\s+"))
    hop = Seq(opt_ws, edge_p, opt_ws, node_p)
    return Seq(node_p, OneOrMore(hop)).map(_fold_path)


def _fold_filter(val: Any) -> FilterQuery:
    first, rest = val
    conds = [first]
    for item in rest:
        conds.append(item[3])
    return FilterQuery(conditions=conds, op="AND")


def _build_filter_parser() -> Parser[FilterQuery]:
    opt_ws = Opt(Reg(r"\s+"))
    ident = Reg(r"[a-zA-Z0-9_\-]+")
    filter_item = Seq(ident, Lit(":"), ident).map(
        lambda v: FilterCondition(key=v[0], value=v[2])
    )
    and_kw = Reg(r"(?i)\bAND\b")
    rest_filter = Seq(opt_ws, and_kw, opt_ws, filter_item)
    return Seq(filter_item, ZeroOrMore(rest_filter)).map(_fold_filter)


def _build_graph_dsl_grammar() -> Parser[GraphDSLQuery]:
    node_p = _build_node_parser()
    edge_p = _build_edge_parser()
    path_p = _build_path_parser(node_p, edge_p).map(
        lambda p: GraphDSLQuery(kind="path", path=p)
    )
    filter_p = _build_filter_parser().map(
        lambda f: GraphDSLQuery(kind="filter", filter_q=f)
    )

    opt_ws = Opt(Reg(r"\s+"))
    return Seq(opt_ws, (path_p / filter_p), opt_ws).map(
        lambda val: cast(GraphDSLQuery, val[1])
    )


class GraphQueryDSLParser:
    """Packrat PEG Parser for Graph Query DSL."""

    def __init__(self) -> None:
        self._grammar = _build_graph_dsl_grammar()

    def parse(self, query_str: str) -> GraphDSLQuery:
        """Parses a graph query DSL string into a GraphDSLQuery AST."""
        clean = query_str.strip()
        if not clean:
            raise PEGSyntaxError(
                "Empty graph DSL query",
                pos=0,
                line=1,
                col=1,
                expected_tokens={"node", "filter"},
                snippet="",
            )
        return self._grammar.parse(clean)


# =========================================================================
# DSL Query Executor integration
# =========================================================================


def _filter_community(engine: Any, val: str) -> Set[str]:
    comms = engine.detect_communities()
    target_cid = int(val) if val.isdigit() else 0
    return {vid for vid, cid in comms.items() if cid == target_cid}


def _filter_ego(engine: Any, val: str) -> Set[str]:
    target_id = engine._resolve_ego_node_id(val)
    if not target_id:
        return set()
    ego_sub = engine.get_ego_network(target_id, radius=1)
    return {v.id for v in ego_sub.get("nodes", [])}


def _execute_filter_condition(engine: Any, cond: FilterCondition) -> Set[str]:
    k = cond.key.lower()
    if k == "community":
        return _filter_community(engine, cond.value)
    if k == "label":
        lbl_nodes = engine.get_vertices_by_label(cond.value)
        return {v.id for v in lbl_nodes}
    if k in ("ego", "id"):
        return _filter_ego(engine, cond.value)
    return set()


def _execute_filter_dsl(
    engine: Any, fq: FilterQuery, limit: int
) -> Tuple[List[Vertex], List[Edge], int]:
    """Executes composite filter DSL query and returns induced subgraph."""
    matching_sets: List[Set[str]] = []
    for cond in fq.conditions:
        matching_sets.append(_execute_filter_condition(engine, cond))

    if not matching_sets:
        return [], [], 0

    result_ids = matching_sets[0]
    for s in matching_sets[1:]:
        result_ids = result_ids & s

    nodes = engine._collect_vertices(result_ids)
    edges = engine._collect_induced_edges(result_ids, limit=limit)
    return nodes, edges, len(nodes)


def _matches_name_or_id(v: Vertex, name_or_id: str) -> bool:
    target = name_or_id.lower()
    id_match = target in v.id.lower()
    name_prop = str(v.properties.get("name", "")).lower()
    return id_match or (target in name_prop)


def _matches_label(v: Vertex, label: Optional[str]) -> bool:
    if not label:
        return True
    return v.label == label


def _matches_name_constraint(v: Vertex, name_or_id: Optional[str]) -> bool:
    if not name_or_id:
        return True
    return _matches_name_or_id(v, name_or_id)


def _matches_node_pattern(v: Optional[Vertex], pat: NodePattern) -> bool:
    if not v:
        return False
    return _matches_label(v, pat.label) and _matches_name_constraint(v, pat.name_or_id)


def _collect_peer_edges(engine: Any, cid: str, edge_pat: EdgePattern) -> List[Edge]:
    out_e = engine.get_out_edges(cid) if edge_pat.direction in ("out", "both") else []
    in_e = engine.get_in_edges(cid) if edge_pat.direction in ("in", "both") else []
    return cast(List[Edge], out_e + in_e)


def _check_edge_peer(
    engine: Any,
    cid: str,
    e: Edge,
    edge_pat: EdgePattern,
    next_node_pat: NodePattern,
) -> Optional[str]:
    if edge_pat.label and e.label != edge_pat.label:
        return None
    peer: str = e.dst_id if e.src_id == cid else e.src_id
    v = engine.get_vertex(peer)
    if _matches_node_pattern(v, next_node_pat):
        return peer
    return None


def _step_match_nodes(
    engine: Any,
    current_ids: Set[str],
    edge_pat: EdgePattern,
    next_node_pat: NodePattern,
) -> Tuple[Set[str], List[Edge]]:
    """Traverses one step along edge pattern and matches next node constraints."""
    next_ids: Set[str] = set()
    matched_edges: List[Edge] = []
    for cid in current_ids:
        for e in _collect_peer_edges(engine, cid, edge_pat):
            peer = _check_edge_peer(engine, cid, e, edge_pat, next_node_pat)
            if peer is not None:
                next_ids.add(peer)
                matched_edges.append(e)
    return next_ids, matched_edges


def _resolve_start_ids(engine: Any, first_node: NodePattern) -> Set[str]:
    if first_node.name_or_id:
        src_id = engine._resolve_ego_node_id(first_node.name_or_id)
        if src_id:
            return {src_id}
    if first_node.label:
        return {v.id for v in engine.get_vertices_by_label(first_node.label)}
    return set()


def _execute_path_dsl(
    engine: Any, path: PathPattern, limit: int
) -> Tuple[List[Vertex], List[Edge], int]:
    """Executes multi-hop path pattern query."""
    if len(path.nodes) < 2:
        return [], [], 0

    current_ids = _resolve_start_ids(engine, path.nodes[0])
    if not current_ids:
        return [], [], 0

    accum_nodes: Set[str] = set(current_ids)
    accum_edges: List[Edge] = []

    for edge_pat, next_node_pat in zip(path.edges, path.nodes[1:]):
        next_ids, step_edges = _step_match_nodes(
            engine, current_ids, edge_pat, next_node_pat
        )
        if not next_ids:
            return [], [], 0
        current_ids = next_ids
        accum_nodes.update(next_ids)
        accum_edges.extend(step_edges)

    nodes = engine._collect_vertices(accum_nodes)
    return nodes, accum_edges, len(nodes)


def _dispatch_dsl_ast(
    engine: Any, dsl: GraphDSLQuery, limit: int
) -> Optional[Tuple[List[Vertex], List[Edge], int]]:
    if dsl.kind == "path" and dsl.path:
        return _execute_path_dsl(engine, dsl.path, limit)
    if dsl.kind == "filter" and dsl.filter:
        return _execute_filter_dsl(engine, dsl.filter, limit)
    return None


def execute_dsl_query(
    engine: Any, query_str: str, limit: int = 50
) -> Optional[Tuple[List[Vertex], List[Edge], int]]:
    """Attempts to parse and execute query_str using the Graph DSL parser."""
    parser = GraphQueryDSLParser()
    try:
        dsl = parser.parse(query_str)
        return _dispatch_dsl_ast(engine, dsl, limit)
    except PEGSyntaxError:
        return None
