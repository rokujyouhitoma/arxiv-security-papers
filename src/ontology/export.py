#!/usr/bin/env python3
"""Multi-Format Knowledge Graph Serializer (W3C Turtle / JSON-LD / STIX 2.1).

Pure-Python zero-dependency exporter that converts the PropertyGraphEngine
vertex/edge data into three international standard serialization formats:

  - W3C RDF 1.1 Turtle  (.ttl)
  - W3C JSON-LD 1.1     (.jsonld)
  - OASIS STIX 2.1 Bundle (.json)

Usage::

    from ontology.export import GraphExporter
    from graph.engine import PropertyGraphEngine

    engine = PropertyGraphEngine()
    exporter = GraphExporter(engine)

    ttl_str    = exporter.to_turtle()
    jsonld_str = exporter.to_jsonld()
    stix_str   = exporter.to_stix()

"""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Any, Dict, List, Optional, Tuple

if TYPE_CHECKING:
    from graph.engine import PropertyGraphEngine
    from graph.structures import Edge, Vertex

# ---------------------------------------------------------------------------
# RDF Namespace / Prefix constants
# ---------------------------------------------------------------------------

_PREFIXES: List[Tuple[str, str]] = [
    ("rdf", "http://www.w3.org/1999/02/22-rdf-syntax-ns#"),
    ("rdfs", "http://www.w3.org/2000/01/rdf-schema#"),
    ("owl", "http://www.w3.org/2002/07/owl#"),
    ("xsd", "http://www.w3.org/2001/XMLSchema#"),
    ("sec", "https://arxiv-security-papers.example.org/ontology#"),
    ("paper", "https://arxiv-security-papers.example.org/paper/"),
    ("dcterms", "http://purl.org/dc/terms/"),
    ("schema", "https://schema.org/"),
]

_BASE_URI = "https://arxiv-security-papers.example.org/ontology#"
_PAPER_NS = "https://arxiv-security-papers.example.org/paper/"

# STIX 2.1 spec version constant
_STIX_SPEC_VERSION = "2.1"


# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------


def _sanitize_local_name(raw: str) -> str:
    """Converts an arbitrary string to a valid Turtle local name."""
    # Replace any character that is not alphanumeric or _ with _
    cleaned = re.sub(r"[^A-Za-z0-9_]", "_", raw)
    # Must not start with a digit
    if cleaned and cleaned[0].isdigit():
        cleaned = "_" + cleaned
    return cleaned or "_unknown"


def _escape_turtle_literal(value: str) -> str:
    """Escapes special characters inside a Turtle string literal."""
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )


def _vertex_to_uri(vertex: "Vertex") -> str:
    """Produces the Turtle prefixed-name or full URI for a vertex."""
    vid = vertex.id
    # If the vertex ID looks like an arXiv ID, use paper: namespace
    if re.match(r"^\d{4}\.\d+", vid):
        return f"paper:{_sanitize_local_name(vid)}"
    label_local = _sanitize_local_name(vertex.label)
    return f"sec:{label_local}_{_sanitize_local_name(vid)}"


def _edge_predicate_uri(edge: "Edge") -> str:
    """Maps edge label to a Turtle prefixed predicate."""
    pred = _sanitize_local_name(edge.label.lower())
    return f"sec:{pred}"


def _literal(value: Any) -> str:
    """Renders a Python value as a Turtle literal."""
    if isinstance(value, bool):
        return f'"{str(value).lower()}"^^xsd:boolean'
    if isinstance(value, int):
        return f'"{value}"^^xsd:integer'
    if isinstance(value, float):
        return f'"{value}"^^xsd:decimal'
    escaped = _escape_turtle_literal(str(value))
    return f'"{escaped}"'


# ---------------------------------------------------------------------------
# Turtle Serializer
# ---------------------------------------------------------------------------


class TurtleSerializer:
    """Serializes PropertyGraphEngine data to W3C RDF 1.1 Turtle format."""

    def __init__(self, engine: "PropertyGraphEngine") -> None:
        self._engine = engine

    def serialize(self) -> str:
        """Returns the complete Turtle document as a string."""
        lines: List[str] = []
        # Prefix declarations
        for prefix, uri in _PREFIXES:
            lines.append(f"@prefix {prefix}: <{uri}> .")
        lines.append(f"@base <{_BASE_URI}> .")
        lines.append("")
        # Ontology header
        lines.append("# =============================")
        lines.append("# arXiv Security Papers Graph")
        ts = datetime.now(timezone.utc).isoformat()
        lines.append(f"# Generated: {ts}")
        lines.append("# =============================")
        lines.append("")

        # Vertex triples
        for vertex in self._engine.get_all_vertices():
            lines.extend(self._vertex_triples(vertex))
            lines.append("")

        # Edge triples (property assertions)
        for edge in self._engine.get_all_edges():
            lines.extend(self._edge_triples(edge))

        return "\n".join(lines)

    def _vertex_triples(self, vertex: "Vertex") -> List[str]:
        uri = _vertex_to_uri(vertex)
        label_local = _sanitize_local_name(vertex.label)
        triples: List[str] = [
            f"{uri}",
            f"    a sec:{label_local} ;",
            f"    rdfs:label {_literal(vertex.id)} ;",
        ]
        for key, val in vertex.properties.items():
            if val is None:
                continue
            pred = f"sec:{_sanitize_local_name(key)}"
            if isinstance(val, (dict, list)):
                val_str = json.dumps(val, ensure_ascii=False)
                triples.append(f"    {pred} {_literal(val_str)} ;")
            else:
                triples.append(f"    {pred} {_literal(val)} ;")
        # Close subject block
        if triples[-1].endswith(";"):
            triples[-1] = triples[-1][:-1] + "."
        else:
            triples.append(".")
        return triples

    def _edge_triples(self, edge: "Edge") -> List[str]:
        """Generates RDF triples for a directed edge using object property."""
        # Determine source and destination URIs
        src_v = self._engine._vertices.get(edge.src_id)
        dst_v = self._engine._vertices.get(edge.dst_id)
        if src_v is None or dst_v is None:
            return []
        src_uri = _vertex_to_uri(src_v)
        dst_uri = _vertex_to_uri(dst_v)
        pred = _edge_predicate_uri(edge)
        lines: List[str] = [f"{src_uri} {pred} {dst_uri} ."]
        # Weight as annotation property if set
        weight = edge.properties.get("weight")
        if weight is not None:
            lines.append(f"{src_uri} sec:edgeWeight {_literal(float(weight))} .")
        return lines


# ---------------------------------------------------------------------------
# JSON-LD Serializer
# ---------------------------------------------------------------------------


class JSONLDSerializer:
    """Serializes PropertyGraphEngine data to W3C JSON-LD 1.1 format."""

    def __init__(self, engine: "PropertyGraphEngine") -> None:
        self._engine = engine

    def _build_context(self) -> Dict[str, Any]:
        ctx: Dict[str, Any] = {}
        for prefix, uri in _PREFIXES:
            ctx[prefix] = uri
        ctx["@vocab"] = _BASE_URI
        ctx["id"] = "@id"
        ctx["type"] = "@type"
        ctx["label"] = "rdfs:label"
        return ctx

    def _vertex_to_node(self, vertex: "Vertex") -> Dict[str, Any]:
        node: Dict[str, Any] = {
            "@id": _vertex_to_uri(vertex),
            "@type": f"sec:{_sanitize_local_name(vertex.label)}",
            "rdfs:label": vertex.id,
        }
        for key, val in vertex.properties.items():
            if val is None:
                continue
            pred = f"sec:{_sanitize_local_name(key)}"
            if isinstance(val, (dict, list)):
                node[pred] = val
            else:
                node[pred] = val
        return node

    def _edge_to_link(self, edge: "Edge") -> Optional[Dict[str, Any]]:
        src_v = self._engine._vertices.get(edge.src_id)
        dst_v = self._engine._vertices.get(edge.dst_id)
        if src_v is None or dst_v is None:
            return None
        link: Dict[str, Any] = {
            "@type": "rdf:Statement",
            "rdf:subject": {"@id": _vertex_to_uri(src_v)},
            "rdf:predicate": {"@id": _edge_predicate_uri(edge)},
            "rdf:object": {"@id": _vertex_to_uri(dst_v)},
        }
        weight = edge.properties.get("weight")
        if weight is not None:
            link["sec:edgeWeight"] = float(weight)
        return link

    def serialize(self) -> str:
        """Returns the complete JSON-LD document as a formatted string."""
        graph_nodes: List[Dict[str, Any]] = []
        for vertex in self._engine.get_all_vertices():
            graph_nodes.append(self._vertex_to_node(vertex))
        for edge in self._engine.get_all_edges():
            link = self._edge_to_link(edge)
            if link:
                graph_nodes.append(link)

        document: Dict[str, Any] = {
            "@context": self._build_context(),
            "@id": _BASE_URI,
            "@type": "owl:Ontology",
            "dcterms:title": "arXiv Security Papers Knowledge Graph",
            "dcterms:created": datetime.now(timezone.utc).isoformat(),
            "@graph": graph_nodes,
        }
        return json.dumps(document, indent=2, ensure_ascii=False)


# ---------------------------------------------------------------------------
# STIX 2.1 Serializer
# ---------------------------------------------------------------------------


class STIXSerializer:
    """Serializes PropertyGraphEngine data to OASIS STIX 2.1 Bundle JSON.

    Vertex labels are mapped to STIX Domain Object (SDO) types:
      - Paper / Article     -> report
      - AttackTechnique     -> attack-pattern
      - Vulnerability / CVE -> vulnerability
      - DefenseMechanism    -> course-of-action
      - ThreatActor         -> threat-actor
      - everything else     -> x-custom-node (custom extension)

    Edges are mapped to STIX Relationship SROs.
    """

    _LABEL_TO_STIX_TYPE: Dict[str, str] = {
        "Paper": "report",
        "Article": "report",
        "AttackTechnique": "attack-pattern",
        "Vulnerability": "vulnerability",
        "CVE": "vulnerability",
        "DefenseMechanism": "course-of-action",
        "ThreatActor": "threat-actor",
        "Identity": "identity",
        "CourseOfAction": "course-of-action",
        "Malware": "malware",
        "Tool": "tool",
        "Campaign": "campaign",
        "Indicator": "indicator",
        "Infrastructure": "infrastructure",
        "IntrusionSet": "intrusion-set",
        "Location": "location",
        "Note": "note",
        "ObservedData": "observed-data",
        "Opinion": "opinion",
    }

    def __init__(self, engine: "PropertyGraphEngine") -> None:
        self._engine = engine
        # Map vertex id -> STIX id
        self._stix_id_map: Dict[str, str] = {}

    def _stix_type_for(self, label: str) -> str:
        return self._LABEL_TO_STIX_TYPE.get(label, "x-custom-node")

    def _make_stix_id(self, stix_type: str, vertex_id: str) -> str:
        import uuid

        uid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"{stix_type}:{vertex_id}"))
        return f"{stix_type}--{uid}"

    def _now_ts(self) -> str:
        return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")

    def _apply_description(self, sdo: Dict[str, Any], props: Dict[str, Any]) -> None:
        """Copies description or abstract into the SDO dict."""
        desc = props.get("description") or props.get("abstract")
        if desc:
            sdo["description"] = str(desc)

    def _apply_report_fields(
        self, sdo: Dict[str, Any], props: Dict[str, Any], vertex_id: str, ts: str
    ) -> None:
        """Adds arXiv external_references and published field for report SDOs."""
        arxiv_id = props.get("arxiv_id") or vertex_id
        sdo["external_references"] = [
            {
                "source_name": "arXiv",
                "url": f"https://arxiv.org/abs/{arxiv_id}",
                "external_id": str(arxiv_id),
            }
        ]
        sdo["published"] = str(props.get("published", ts))

    def _apply_labels(self, sdo: Dict[str, Any], props: Dict[str, Any]) -> None:
        """Maps tags property to STIX labels list."""
        tags = props.get("tags")
        if isinstance(tags, list):
            sdo["labels"] = [str(t) for t in tags]
        elif isinstance(tags, str):
            sdo["labels"] = [tags]

    def _apply_confidence(self, sdo: Dict[str, Any], props: Dict[str, Any]) -> None:
        """Copies confidence property into SDO if present and parseable."""
        confidence = props.get("confidence")
        if confidence is None:
            return
        try:
            sdo["confidence"] = int(float(confidence))
        except (ValueError, TypeError):
            pass

    _RESERVED_PROP_KEYS = frozenset(
        {
            "name",
            "title",
            "description",
            "abstract",
            "arxiv_id",
            "published",
            "tags",
            "confidence",
        }
    )

    def _apply_custom_props(self, sdo: Dict[str, Any], props: Dict[str, Any]) -> None:
        """Carries over non-reserved properties as x_arxiv_extended extension."""
        custom_props = {
            k: v
            for k, v in props.items()
            if k not in self._RESERVED_PROP_KEYS and v is not None
        }
        if custom_props:
            sdo["x_arxiv_extended"] = custom_props

    def _vertex_to_sdo(self, vertex: "Vertex", ts: str) -> Dict[str, Any]:
        stix_type = self._stix_type_for(vertex.label)
        sid = self._make_stix_id(stix_type, vertex.id)
        self._stix_id_map[vertex.id] = sid
        props = vertex.properties

        sdo: Dict[str, Any] = {
            "type": stix_type,
            "id": sid,
            "spec_version": _STIX_SPEC_VERSION,
            "created": ts,
            "modified": ts,
            "name": str(props.get("name") or props.get("title") or vertex.id),
        }
        self._apply_description(sdo, props)
        if stix_type == "report":
            self._apply_report_fields(sdo, props, vertex.id, ts)
        self._apply_labels(sdo, props)
        self._apply_confidence(sdo, props)
        self._apply_custom_props(sdo, props)
        return sdo

    def _edge_to_sro(self, edge: "Edge", ts: str) -> Optional[Dict[str, Any]]:
        src_stix_id = self._stix_id_map.get(edge.src_id)
        dst_stix_id = self._stix_id_map.get(edge.dst_id)
        if src_stix_id is None or dst_stix_id is None:
            return None
        import uuid

        rel_id = "relationship--" + str(
            uuid.uuid5(uuid.NAMESPACE_DNS, f"{src_stix_id}{edge.label}{dst_stix_id}")
        )
        sro: Dict[str, Any] = {
            "type": "relationship",
            "id": rel_id,
            "spec_version": _STIX_SPEC_VERSION,
            "created": ts,
            "modified": ts,
            "relationship_type": edge.label.lower().replace(" ", "-"),
            "source_ref": src_stix_id,
            "target_ref": dst_stix_id,
        }
        weight = edge.properties.get("weight")
        if weight is not None:
            try:
                sro["confidence"] = min(100, max(0, int(float(weight) * 100)))
            except (ValueError, TypeError):
                pass
        return sro

    def serialize(self) -> str:
        """Returns the OASIS STIX 2.1 Bundle as a formatted JSON string."""
        import uuid

        ts = self._now_ts()
        objects: List[Dict[str, Any]] = []

        # SDOs from vertices
        for vertex in self._engine.get_all_vertices():
            objects.append(self._vertex_to_sdo(vertex, ts))

        # SROs from edges (must come after SDOs so _stix_id_map is populated)
        for edge in self._engine.get_all_edges():
            sro = self._edge_to_sro(edge, ts)
            if sro:
                objects.append(sro)

        bundle_id = "bundle--" + str(uuid.uuid4())
        bundle: Dict[str, Any] = {
            "type": "bundle",
            "id": bundle_id,
            "objects": objects,
        }
        return json.dumps(bundle, indent=2, ensure_ascii=False)


# ---------------------------------------------------------------------------
# Public Facade
# ---------------------------------------------------------------------------


class GraphExporter:
    """Unified facade for multi-format graph serialization.

    Args:
        engine: A ``PropertyGraphEngine`` instance populated with vertices/edges.
    """

    def __init__(self, engine: "PropertyGraphEngine") -> None:
        self._engine = engine
        self._turtle = TurtleSerializer(engine)
        self._jsonld = JSONLDSerializer(engine)
        self._stix = STIXSerializer(engine)

    def to_turtle(self) -> str:
        """Serializes graph to W3C RDF 1.1 Turtle (.ttl) format."""
        return self._turtle.serialize()

    def to_jsonld(self) -> str:
        """Serializes graph to W3C JSON-LD 1.1 format."""
        return self._jsonld.serialize()

    def to_stix(self) -> str:
        """Serializes graph to OASIS STIX 2.1 Bundle JSON format."""
        return self._stix.serialize()

    def export(self, fmt: str) -> Tuple[str, str, str]:
        """Exports graph in the requested format.

        Args:
            fmt: One of ``"turtle"``, ``"jsonld"``, or ``"stix"``.

        Returns:
            Tuple of (content, content_type, filename).

        Raises:
            ValueError: If fmt is not a supported format.
        """
        fmt = fmt.lower().strip()
        if fmt in ("turtle", "ttl"):
            return (
                self.to_turtle(),
                "text/turtle; charset=utf-8",
                "graph.ttl",
            )
        if fmt in ("jsonld", "json-ld", "json_ld"):
            return (
                self.to_jsonld(),
                "application/ld+json; charset=utf-8",
                "graph.jsonld",
            )
        if fmt in ("stix", "stix2", "stix21"):
            return (
                self.to_stix(),
                "application/json; charset=utf-8",
                "graph_stix_bundle.json",
            )
        raise ValueError(
            f"Unsupported export format: '{fmt}'. "
            "Valid values: 'turtle', 'jsonld', 'stix'."
        )
