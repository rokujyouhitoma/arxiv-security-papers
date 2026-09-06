#!/usr/bin/env python3
"""Pure-Python W3C Turtle (.ttl) / OWL Ontology Generation Engine.

Provides an intuitive, type-safe DSL and builder for constructing W3C RDF 1.1 Turtle
and OWL 2 ontology definitions (TBox) and instance data assertions (ABox).
Zero external dependencies.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple, Union


@dataclass(frozen=True)
class RDFTerm:
    """Base class for all RDF terms in Turtle serialization."""

    def to_turtle(self) -> str:
        raise NotImplementedError


@dataclass(frozen=True)
class URI(RDFTerm):
    """URI or Prefixed Name (CURIE) RDF Term."""

    value: str

    def to_turtle(self) -> str:
        if self.value == "a":
            return "a"
        if self.value.startswith(("http://", "https://", "urn:")):
            return f"<{self.value}>"
        return self.value


def _escape_turtle_string(text: str) -> str:
    """Escapes special characters for Turtle string literals."""
    return (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )


def _format_typed_literal(escaped_str: str, datatype: str) -> str:
    """Formats a typed literal string."""
    dt = datatype
    if dt.startswith(("http://", "https://", "urn:")):
        dt = f"<{dt}>"
    return f'"{escaped_str}"^^{dt}'


def _resolve_object_term(obj: Union[RDFTerm, Any]) -> str:
    """Resolves arbitrary Python object or RDFTerm into a Turtle term string."""
    if isinstance(obj, RDFTerm):
        return obj.to_turtle()
    if isinstance(obj, str):
        if ":" in obj or obj.startswith("http"):
            return URI(obj).to_turtle()
        return Literal(obj).to_turtle()
    return Literal(obj).to_turtle()


def _format_number(val: Any) -> Optional[str]:
    """Formats numeric value to str if int or float."""
    return str(val) if isinstance(val, (int, float)) else None


def _format_primitive_value(
    val: Any, lang: Optional[str], datatype: Optional[str]
) -> Optional[str]:
    """Formats primitive unquoted values if eligible."""
    if isinstance(val, bool):
        return "true" if val else "false"
    if lang or datatype:
        return None
    return _format_number(val)


@dataclass(frozen=True)
class Literal(RDFTerm):
    """RDF Literal with optional datatype URI or language tag."""

    value: Any
    lang: Optional[str] = None
    datatype: Optional[str] = None

    def to_turtle(self) -> str:
        prim = _format_primitive_value(self.value, self.lang, self.datatype)
        if prim is not None:
            return prim

        escaped = _escape_turtle_string(str(self.value))
        if self.lang:
            return f'"{escaped}"@{self.lang}'
        if self.datatype:
            return _format_typed_literal(escaped, self.datatype)
        return f'"{escaped}"'


def _append_annotations(
    pred_objs: List[str],
    label: Optional[str],
    label_lang: Optional[str],
    comment: Optional[str],
    comment_lang: Optional[str],
) -> None:
    """Appends rdfs:label and rdfs:comment to predicate-object list."""
    if label:
        lit_label = Literal(label, lang=label_lang).to_turtle()
        pred_objs.append(f"    rdfs:label {lit_label}")
    if comment:
        lit_comment = Literal(comment, lang=comment_lang).to_turtle()
        pred_objs.append(f"    rdfs:comment {lit_comment}")


@dataclass
class OntologyMetadata:
    """Represents owl:Ontology metadata header."""

    uri: str
    label: Optional[str] = None
    label_lang: Optional[str] = "ja"
    comment: Optional[str] = None
    comment_lang: Optional[str] = "ja"
    version_info: Optional[str] = None
    imports: List[str] = field(default_factory=list)

    def to_turtle(self) -> str:
        subj = URI(self.uri).to_turtle()
        pred_objs: List[str] = ["    rdf:type owl:Ontology"]
        _append_annotations(
            pred_objs, self.label, self.label_lang, self.comment, self.comment_lang
        )
        if self.version_info:
            lit_ver = Literal(self.version_info).to_turtle()
            pred_objs.append(f"    owl:versionInfo {lit_ver}")
        for imp in self.imports:
            pred_objs.append(f"    owl:imports {URI(imp).to_turtle()}")

        return f"{subj}\n" + " ;\n".join(pred_objs) + " ."


@dataclass
class OntologyClass:
    """Represents an owl:Class definition."""

    uri: str
    label: Optional[str] = None
    label_lang: Optional[str] = "ja"
    comment: Optional[str] = None
    comment_lang: Optional[str] = "ja"
    sub_class_of: Optional[str] = None
    disjoint_with: List[str] = field(default_factory=list)
    section_comment: Optional[str] = None

    def to_turtle(self) -> str:
        lines: List[str] = []
        if self.section_comment:
            lines.append(f"# {self.section_comment}")

        subj = URI(self.uri).to_turtle()
        pred_objs: List[str] = [f"{subj} rdf:type owl:Class"]
        if self.sub_class_of:
            parent = URI(self.sub_class_of).to_turtle()
            pred_objs.append(f"    rdfs:subClassOf {parent}")

        _append_annotations(
            pred_objs, self.label, self.label_lang, self.comment, self.comment_lang
        )
        lines.append(" ;\n".join(pred_objs) + " .")

        for dj in self.disjoint_with:
            lines.append(f"{subj} owl:disjointWith {URI(dj).to_turtle()} .")

        return "\n".join(lines)


def _build_object_property_types(is_transitive: bool, is_symmetric: bool) -> str:
    """Builds comma-separated owl property types."""
    types = ["owl:ObjectProperty"]
    if is_transitive:
        types.append("owl:TransitiveProperty")
    if is_symmetric:
        types.append("owl:SymmetricProperty")
    return ", ".join(types)


def _append_sub_properties(
    pred_objs: List[str], sub_property_of: Optional[Union[str, Sequence[str]]]
) -> None:
    """Appends rdfs:subPropertyOf predicates."""
    if not sub_property_of:
        return
    subs = [sub_property_of] if isinstance(sub_property_of, str) else sub_property_of
    for sp in subs:
        pred_objs.append(f"    rdfs:subPropertyOf {URI(sp).to_turtle()}")


def _append_domain_range(
    pred_objs: List[str], domain: Optional[str], range_: Optional[str]
) -> None:
    """Appends rdfs:domain and rdfs:range predicates."""
    if domain:
        pred_objs.append(f"    rdfs:domain {URI(domain).to_turtle()}")
    if range_:
        pred_objs.append(f"    rdfs:range {URI(range_).to_turtle()}")


def _build_op_pred_objs(
    uri: str,
    label: Optional[str],
    label_lang: Optional[str],
    comment: Optional[str],
    comment_lang: Optional[str],
    domain: Optional[str],
    range_: Optional[str],
    inverse_of: Optional[str],
    is_transitive: bool,
    is_symmetric: bool,
    sub_property_of: Optional[Union[str, Sequence[str]]] = None,
) -> List[str]:
    """Constructs predicate-object lines for ObjectProperty."""
    subj = URI(uri).to_turtle()
    types_str = _build_object_property_types(is_transitive, is_symmetric)
    pred_objs: List[str] = [f"{subj} rdf:type {types_str}"]
    if inverse_of:
        pred_objs.append(f"    owl:inverseOf {URI(inverse_of).to_turtle()}")
    _append_sub_properties(pred_objs, sub_property_of)
    _append_annotations(pred_objs, label, label_lang, comment, comment_lang)
    _append_domain_range(pred_objs, domain, range_)
    return pred_objs


@dataclass
class ObjectProperty:
    """Represents an owl:ObjectProperty definition."""

    uri: str
    label: Optional[str] = None
    label_lang: Optional[str] = "ja"
    comment: Optional[str] = None
    comment_lang: Optional[str] = "ja"
    domain: Optional[str] = None
    range_: Optional[str] = None
    inverse_of: Optional[str] = None
    is_transitive: bool = False
    is_symmetric: bool = False
    sub_property_of: Optional[Union[str, Sequence[str]]] = None
    section_comment: Optional[str] = None

    def to_turtle(self) -> str:
        lines: List[str] = []
        if self.section_comment:
            lines.append(f"# {self.section_comment}")

        pred_objs = _build_op_pred_objs(
            self.uri,
            self.label,
            self.label_lang,
            self.comment,
            self.comment_lang,
            self.domain,
            self.range_,
            self.inverse_of,
            self.is_transitive,
            self.is_symmetric,
            self.sub_property_of,
        )
        lines.append(" ;\n".join(pred_objs) + " .")
        return "\n".join(lines)


def _build_dp_pred_objs(
    uri: str,
    label: Optional[str],
    label_lang: Optional[str],
    comment: Optional[str],
    comment_lang: Optional[str],
    domain: Optional[str],
    range_: Optional[str],
    is_functional: bool,
    sub_property_of: Optional[Union[str, Sequence[str]]] = None,
) -> List[str]:
    """Constructs predicate-object lines for DatatypeProperty."""
    subj = URI(uri).to_turtle()
    types_str = (
        "owl:DatatypeProperty, owl:FunctionalProperty"
        if is_functional
        else "owl:DatatypeProperty"
    )
    pred_objs: List[str] = [f"{subj} rdf:type {types_str}"]
    _append_sub_properties(pred_objs, sub_property_of)
    _append_annotations(pred_objs, label, label_lang, comment, comment_lang)
    _append_domain_range(pred_objs, domain, range_)
    return pred_objs


@dataclass
class DatatypeProperty:
    """Represents an owl:DatatypeProperty definition."""

    uri: str
    label: Optional[str] = None
    label_lang: Optional[str] = "ja"
    comment: Optional[str] = None
    comment_lang: Optional[str] = "ja"
    domain: Optional[str] = None
    range_: Optional[str] = None
    is_functional: bool = False
    sub_property_of: Optional[Union[str, Sequence[str]]] = None
    section_comment: Optional[str] = None

    def to_turtle(self) -> str:
        lines: List[str] = []
        if self.section_comment:
            lines.append(f"# {self.section_comment}")

        pred_objs = _build_dp_pred_objs(
            self.uri,
            self.label,
            self.label_lang,
            self.comment,
            self.comment_lang,
            self.domain,
            self.range_,
            self.is_functional,
            self.sub_property_of,
        )
        lines.append(" ;\n".join(pred_objs) + " .")
        return "\n".join(lines)


@dataclass
class DatatypeDefinition:
    """Represents an rdfs:Datatype definition with owl:withRestrictions pattern constraint."""

    uri: str
    base_datatype: str = "xsd:string"
    pattern: Optional[str] = None
    label: Optional[str] = None
    label_lang: Optional[str] = "ja"
    comment: Optional[str] = None
    comment_lang: Optional[str] = "ja"
    section_comment: Optional[str] = None

    def to_turtle(self) -> str:
        lines: List[str] = []
        if self.section_comment:
            lines.append(f"# {self.section_comment}")

        subj = URI(self.uri).to_turtle()
        pred_objs = [f"{subj} rdf:type rdfs:Datatype"]
        if self.base_datatype:
            pred_objs.append(
                f"    owl:onDatatype {URI(self.base_datatype).to_turtle()}"
            )
        if self.pattern:
            pred_objs.append(
                f'    owl:withRestrictions (\n        [ xsd:pattern "{self.pattern}" ]\n    )'
            )
        _append_annotations(
            pred_objs, self.label, self.label_lang, self.comment, self.comment_lang
        )
        lines.append(" ;\n".join(pred_objs) + " .")
        return "\n".join(lines)


def _format_property_line(pred: str, obj: Union[RDFTerm, Any]) -> str:
    """Formats single predicate-object line."""
    p_term = URI(pred).to_turtle()
    o_term = _resolve_object_term(obj)
    return f"    {p_term} {o_term}"


def _build_typeless_instance(
    subj: str, properties: List[Tuple[str, Union[RDFTerm, Any]]]
) -> str:
    """Builds instance triples without explicit rdf:type."""
    first_p, first_o = properties[0]
    p0 = URI(first_p).to_turtle()
    o0 = _resolve_object_term(first_o)
    pred_objs = [f"{subj} {p0} {o0}"]
    for p, o in properties[1:]:
        pred_objs.append(_format_property_line(p, o))
    return " ;\n".join(pred_objs) + " ."


def _format_instance_header(subj: str, rdf_types: List[str]) -> str:
    """Formats instance type assertion header."""
    if not rdf_types:
        return subj
    types_str = ", ".join(URI(t).to_turtle() for t in rdf_types)
    return f"{subj} rdf:type {types_str}"


def _build_instance_triples(
    subj: str,
    rdf_types: List[str],
    properties: List[Tuple[str, Union[RDFTerm, Any]]],
) -> str:
    """Builds predicate-object body for an instance."""
    if not rdf_types and properties:
        return _build_typeless_instance(subj, properties)

    header = _format_instance_header(subj, rdf_types)
    lines = [header] + [_format_property_line(p, o) for p, o in properties]
    return " ;\n".join(lines) + " ."


@dataclass
class OntologyInstance:
    """Represents an ABox instance with type assertions and property values."""

    uri: str
    rdf_types: List[str] = field(default_factory=list)
    properties: List[Tuple[str, Union[RDFTerm, Any]]] = field(default_factory=list)
    section_comment: Optional[str] = None

    def to_turtle(self) -> str:
        lines: List[str] = []
        if self.section_comment:
            lines.append(f"# {self.section_comment}")

        subj = URI(self.uri).to_turtle()
        lines.append(_build_instance_triples(subj, self.rdf_types, self.properties))
        return "\n".join(lines)


@dataclass
class RawTriple:
    """Represents a standalone subject-predicate-object assertion."""

    subject: str
    predicate: str
    object_: Union[RDFTerm, Any]
    comment: Optional[str] = None

    def to_turtle(self) -> str:
        lines: List[str] = []
        if self.comment:
            lines.append(f"# {self.comment}")
        s = URI(self.subject).to_turtle()
        p = URI(self.predicate).to_turtle()
        o = _resolve_object_term(self.object_)
        lines.append(f"{s} {p} {o} .")
        return "\n".join(lines)


class TurtleDocumentBuilder:
    """Fluent Builder for generating W3C Turtle (.ttl) and OWL ontology files."""

    DEFAULT_PREFIXES: Dict[str, str] = {
        "owl": "http://www.w3.org/2002/07/owl#",
        "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
        "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
        "xsd": "http://www.w3.org/2001/XMLSchema#",
    }

    def __init__(self) -> None:
        self.prefixes: Dict[str, str] = dict(self.DEFAULT_PREFIXES)
        self.ontology_meta: Optional[OntologyMetadata] = None
        self.classes: List[OntologyClass] = []
        self.object_properties: List[ObjectProperty] = []
        self.datatype_properties: List[DatatypeProperty] = []
        self.datatypes: List[DatatypeDefinition] = []
        self.instances: List[OntologyInstance] = []
        self.standalone_triples: List[RawTriple] = []

    def add_prefix(self, prefix: str, uri: str) -> "TurtleDocumentBuilder":
        """Adds a namespace prefix mapping."""
        self.prefixes[prefix] = uri
        return self

    def set_ontology(
        self,
        uri: str,
        label: Optional[str] = None,
        label_lang: Optional[str] = "ja",
        comment: Optional[str] = None,
        comment_lang: Optional[str] = "ja",
        version_info: Optional[str] = None,
        imports: Optional[Sequence[str]] = None,
    ) -> "TurtleDocumentBuilder":
        """Sets the owl:Ontology metadata header."""
        self.ontology_meta = OntologyMetadata(
            uri=uri,
            label=label,
            label_lang=label_lang,
            comment=comment,
            comment_lang=comment_lang,
            version_info=version_info,
            imports=list(imports or []),
        )
        return self

    def add_class(
        self,
        uri: str,
        label: Optional[str] = None,
        label_lang: Optional[str] = "ja",
        comment: Optional[str] = None,
        comment_lang: Optional[str] = "ja",
        sub_class_of: Optional[str] = None,
        disjoint_with: Optional[Sequence[str]] = None,
        section_comment: Optional[str] = None,
    ) -> "TurtleDocumentBuilder":
        """Adds an owl:Class definition."""
        self.classes.append(
            OntologyClass(
                uri=uri,
                label=label,
                label_lang=label_lang,
                comment=comment,
                comment_lang=comment_lang,
                sub_class_of=sub_class_of,
                disjoint_with=list(disjoint_with or []),
                section_comment=section_comment,
            )
        )
        return self

    def add_object_property(
        self,
        uri: str,
        label: Optional[str] = None,
        label_lang: Optional[str] = "ja",
        comment: Optional[str] = None,
        comment_lang: Optional[str] = "ja",
        domain: Optional[str] = None,
        range_: Optional[str] = None,
        inverse_of: Optional[str] = None,
        is_transitive: bool = False,
        is_symmetric: bool = False,
        sub_property_of: Optional[Union[str, Sequence[str]]] = None,
        section_comment: Optional[str] = None,
    ) -> "TurtleDocumentBuilder":
        """Adds an owl:ObjectProperty definition."""
        self.object_properties.append(
            ObjectProperty(
                uri=uri,
                label=label,
                label_lang=label_lang,
                comment=comment,
                comment_lang=comment_lang,
                domain=domain,
                range_=range_,
                inverse_of=inverse_of,
                is_transitive=is_transitive,
                is_symmetric=is_symmetric,
                sub_property_of=sub_property_of,
                section_comment=section_comment,
            )
        )
        return self

    def add_datatype_property(
        self,
        uri: str,
        label: Optional[str] = None,
        label_lang: Optional[str] = "ja",
        comment: Optional[str] = None,
        comment_lang: Optional[str] = "ja",
        domain: Optional[str] = None,
        range_: Optional[str] = None,
        is_functional: bool = False,
        sub_property_of: Optional[Union[str, Sequence[str]]] = None,
        section_comment: Optional[str] = None,
    ) -> "TurtleDocumentBuilder":
        """Adds an owl:DatatypeProperty definition."""
        self.datatype_properties.append(
            DatatypeProperty(
                uri=uri,
                label=label,
                label_lang=label_lang,
                comment=comment,
                comment_lang=comment_lang,
                domain=domain,
                range_=range_,
                is_functional=is_functional,
                sub_property_of=sub_property_of,
                section_comment=section_comment,
            )
        )
        return self

    def add_datatype(
        self,
        uri: str,
        base_datatype: str = "xsd:string",
        pattern: Optional[str] = None,
        label: Optional[str] = None,
        label_lang: Optional[str] = "ja",
        comment: Optional[str] = None,
        comment_lang: Optional[str] = "ja",
        section_comment: Optional[str] = None,
    ) -> "TurtleDocumentBuilder":
        """Adds an rdfs:Datatype definition with pattern constraint."""
        self.datatypes.append(
            DatatypeDefinition(
                uri=uri,
                base_datatype=base_datatype,
                pattern=pattern,
                label=label,
                label_lang=label_lang,
                comment=comment,
                comment_lang=comment_lang,
                section_comment=section_comment,
            )
        )
        return self

    def add_instance(
        self,
        uri: str,
        rdf_types: Optional[Sequence[str]] = None,
        properties: Optional[Sequence[Tuple[str, Union[RDFTerm, Any]]]] = None,
        section_comment: Optional[str] = None,
    ) -> "TurtleDocumentBuilder":
        """Adds an ABox instance assertion."""
        self.instances.append(
            OntologyInstance(
                uri=uri,
                rdf_types=list(rdf_types or []),
                properties=list(properties or []),
                section_comment=section_comment,
            )
        )
        return self

    def add_triple(
        self,
        subject: str,
        predicate: str,
        object_: Union[RDFTerm, Any],
        comment: Optional[str] = None,
    ) -> "TurtleDocumentBuilder":
        """Adds a standalone RDF triple assertion."""
        self.standalone_triples.append(
            RawTriple(
                subject=subject, predicate=predicate, object_=object_, comment=comment
            )
        )
        return self

    def _render_prefixes(self) -> str:
        """Renders prefix declarations."""
        return "\n".join(
            f"@prefix {pfx + ':':<6} <{uri}> ."
            for pfx, uri in sorted(self.prefixes.items())
        )

    def _render_metadata(self) -> Optional[str]:
        """Renders ontology metadata section if configured."""
        if not self.ontology_meta:
            return None
        return (
            "### --------------------------------------------------\n"
            "### オントロジー メタデータ\n"
            "### --------------------------------------------------\n"
            f"{self.ontology_meta.to_turtle()}"
        )

    def _render_classes(self) -> Optional[str]:
        """Renders classes section if any defined."""
        if not self.classes:
            return None
        return (
            "### --------------------------------------------------\n"
            "### 1. クラス（概念）の定義\n"
            "### --------------------------------------------------\n"
            + "\n\n".join(c.to_turtle() for c in self.classes)
        )

    def _render_object_properties(self) -> Optional[str]:
        """Renders object properties section if any defined."""
        if not self.object_properties:
            return None
        return (
            "### --------------------------------------------------\n"
            "### 2. オブジェクトプロパティ（エンティティ間の関係）\n"
            "### --------------------------------------------------\n"
            + "\n\n".join(op.to_turtle() for op in self.object_properties)
        )

    def _render_datatype_properties(self) -> Optional[str]:
        """Renders datatype properties section if any defined."""
        if not self.datatype_properties:
            return None
        return (
            "### --------------------------------------------------\n"
            "### 3. データプロパティ（属性値・リテラル）\n"
            "### --------------------------------------------------\n"
            + "\n\n".join(dp.to_turtle() for dp in self.datatype_properties)
        )

    def _render_datatypes(self) -> Optional[str]:
        """Renders rdfs:Datatype definitions with pattern constraints."""
        if not self.datatypes:
            return None
        return (
            "### --------------------------------------------------\n"
            "### 4. データ型（正規表現・制約定義）\n"
            "### --------------------------------------------------\n"
            + "\n\n".join(dt.to_turtle() for dt in self.datatypes)
        )

    def _render_abox(self) -> Optional[str]:
        """Renders ABox instances and standalone triples."""
        if not self.instances and not self.standalone_triples:
            return None
        items = [inst.to_turtle() for inst in self.instances]
        items.extend(tr.to_turtle() for tr in self.standalone_triples)
        return (
            "### --------------------------------------------------\n"
            "### 5. インスタンス例（ABox: 実データ）\n"
            "### --------------------------------------------------\n"
            + "\n\n".join(items)
        )

    def serialize(self) -> str:
        """Serializes the entire ontology model into W3C Turtle (.ttl) text."""
        parts: List[str] = [self._render_prefixes()]

        for section in (
            self._render_metadata(),
            self._render_classes(),
            self._render_object_properties(),
            self._render_datatype_properties(),
            self._render_datatypes(),
            self._render_abox(),
        ):
            if section:
                parts.append(section)

        return "\n\n".join(parts) + "\n"

    def save(self, file_path: Union[str, Path]) -> None:
        """Saves the serialized Turtle text to the given path."""
        p = Path(file_path)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(self.serialize(), encoding="utf-8")


def _add_sample_classes(builder: TurtleDocumentBuilder) -> None:
    """Populates classes for the sample enterprise ontology."""
    builder.add_class(
        uri="ex:Agent",
        label="エージェント",
        label_lang="ja",
        comment="行動の主体となる概念（人間または組織）",
        comment_lang="ja",
        section_comment="基底クラス: 実体",
    )
    builder.add_class(
        uri="ex:Person",
        sub_class_of="ex:Agent",
        label="人物",
        label_lang="ja",
        disjoint_with=["ex:Organization"],
        section_comment="Agentのサブクラス",
    )
    builder.add_class(
        uri="ex:Organization",
        sub_class_of="ex:Agent",
        label="組織",
        label_lang="ja",
    )
    builder.add_class(
        uri="ex:Project",
        label="プロジェクト",
        label_lang="ja",
        section_comment="プロジェクト",
    )
    builder.add_class(
        uri="ex:Skill",
        label="スキル",
        label_lang="ja",
        section_comment="スキル / 技術要素",
    )
    builder.add_class(
        uri="ex:Artifact",
        label="成果物",
        label_lang="ja",
        section_comment="成果物 / ドキュメント",
    )


def _add_sample_object_properties(builder: TurtleDocumentBuilder) -> None:
    """Populates object properties for sample ontology."""
    builder.add_object_property(
        uri="ex:belongsTo",
        label="所属する",
        label_lang="ja",
        domain="ex:Person",
        range_="ex:Organization",
        section_comment="所属関係（Person -> Organization）",
    )
    builder.add_object_property(
        uri="ex:hasMember",
        inverse_of="ex:belongsTo",
        label="メンバーを有する",
        label_lang="ja",
        section_comment="逆関係の定義（Organization hasMember Person）",
    )
    builder.add_object_property(
        uri="ex:subOrganizationOf",
        label="上位組織である",
        label_lang="ja",
        domain="ex:Organization",
        range_="ex:Organization",
        is_transitive=True,
        section_comment="組織の階層関係（部分全体関係 / 推移律を付与）",
    )
    builder.add_object_property(
        uri="ex:assignedTo",
        label="アサインされている",
        label_lang="ja",
        domain="ex:Person",
        range_="ex:Project",
        section_comment="プロジェクトへのアサイン（Person -> Project）",
    )
    builder.add_object_property(
        uri="ex:hasSkill",
        label="スキルを保有する",
        label_lang="ja",
        domain="ex:Person",
        range_="ex:Skill",
        section_comment="スキルの保有（Person -> Skill）",
    )
    builder.add_object_property(
        uri="ex:createdArtifact",
        label="成果物を作成した",
        label_lang="ja",
        domain="ex:Person",
        range_="ex:Artifact",
        section_comment="成果物の作成者（Artifact -> Person）",
    )


def _add_sample_datatype_properties(builder: TurtleDocumentBuilder) -> None:
    """Populates datatype properties for sample ontology."""
    builder.add_datatype_property(
        uri="ex:personId",
        label="社員ID",
        label_lang="ja",
        domain="ex:Person",
        range_="xsd:string",
        is_functional=True,
    )
    builder.add_datatype_property(
        uri="ex:name",
        label="名称",
        label_lang="ja",
        domain="owl:Thing",
        range_="xsd:string",
    )
    builder.add_datatype_property(
        uri="ex:experienceYears",
        label="経験年数",
        label_lang="ja",
        domain="ex:Person",
        range_="xsd:integer",
    )
    builder.add_datatype_property(
        uri="ex:createdAt",
        label="作成日時",
        label_lang="ja",
        domain="ex:Artifact",
        range_="xsd:dateTime",
    )


def _add_sample_instances(builder: TurtleDocumentBuilder) -> None:
    """Populates ABox sample instances."""
    builder.add_instance(
        uri="ex:dept_eng",
        rdf_types=["ex:Organization"],
        properties=[("ex:name", Literal("技術統括部"))],
        section_comment="組織構造",
    )
    builder.add_instance(
        uri="ex:team_sec",
        rdf_types=["ex:Organization"],
        properties=[
            ("ex:name", Literal("セキュリティ技術チーム")),
            ("ex:subOrganizationOf", URI("ex:dept_eng")),
        ],
    )
    builder.add_instance(
        uri="ex:skill_python",
        rdf_types=["ex:Skill"],
        properties=[("ex:name", Literal("Python"))],
        section_comment="スキル",
    )
    builder.add_instance(
        uri="ex:skill_appsec",
        rdf_types=["ex:Skill"],
        properties=[("ex:name", Literal("Application Security"))],
    )
    builder.add_instance(
        uri="ex:emp_001",
        rdf_types=["ex:Person"],
        properties=[
            ("ex:personId", Literal("EMP-001")),
            ("ex:name", Literal("田中 太郎")),
            ("ex:experienceYears", Literal(8)),
            ("ex:belongsTo", URI("ex:team_sec")),
            ("ex:hasSkill", URI("ex:skill_python")),
            ("ex:hasSkill", URI("ex:skill_appsec")),
        ],
        section_comment="人物",
    )
    builder.add_instance(
        uri="ex:doc_sec_spec",
        rdf_types=["ex:Artifact"],
        properties=[
            ("ex:name", Literal("認証認可基盤 脅威分析仕様書")),
            ("ex:createdAt", Literal("2026-04-10T14:30:00Z", datatype="xsd:dateTime")),
        ],
        section_comment="成果物",
    )
    builder.add_triple("ex:emp_001", "ex:createdArtifact", "ex:doc_sec_spec")


def build_sample_enterprise_ontology() -> TurtleDocumentBuilder:
    """Builds the exact sample Enterprise Knowledge Ontology provided by user."""
    builder = TurtleDocumentBuilder()
    builder.add_prefix("ex", "https://example.com/ontology/corp#")
    builder.set_ontology(
        uri="https://example.com/ontology/corp",
        label="Enterprise Knowledge Ontology",
        label_lang="ja",
        comment="組織、プロジェクト、スキル、成果物を管理・推論するためのオントロジーモデル",
        comment_lang="ja",
        version_info="1.0.0",
    )
    _add_sample_classes(builder)
    _add_sample_object_properties(builder)
    _add_sample_datatype_properties(builder)
    _add_sample_instances(builder)
    return builder


def _add_security_classes(builder: TurtleDocumentBuilder) -> None:
    """Populates core classes for security ontology."""
    builder.add_class(
        uri="sec:Paper",
        label="セキュリティ論文",
        label_lang="ja",
        comment="arXiv または IACR 等で公開された学術セキュリティ論文",
        comment_lang="ja",
        section_comment="学術知見実体",
    )
    builder.add_class(
        uri="sec:ThreatActor",
        label="脅威アクター",
        label_lang="ja",
        comment="サイバー攻撃を仕掛ける国家主導組織、APTグループ、または脅威主体",
        comment_lang="ja",
        section_comment="脅威・インテリジェンス実体",
    )
    builder.add_class(
        uri="sec:AttackTechnique",
        label="攻撃手法",
        label_lang="ja",
        comment="MITRE ATT&CK または学術知見で定義される戦術・技術・手順 (TTP)",
        comment_lang="ja",
    )
    builder.add_class(
        uri="sec:Vulnerability",
        label="脆弱性",
        label_lang="ja",
        comment="CWE または CVE で特定されるソフトウェア/システムの弱点およびセキュリティ欠陥",
        comment_lang="ja",
    )
    builder.add_class(
        uri="sec:TargetAsset",
        label="対象資産",
        label_lang="ja",
        comment="攻撃の標的となるシステム、プロトコル、ハードウェア、またはAIモデル",
        comment_lang="ja",
    )
    builder.add_class(
        uri="sec:DefenseMechanism",
        label="防御メカニズム",
        label_lang="ja",
        comment="論文で提案される防御機構、緩和策、またはセキュアシグネチャ",
        comment_lang="ja",
    )
    builder.add_class(
        uri="sec:BenchmarkMetric",
        label="評価ベンチマーク指標",
        label_lang="ja",
        comment="防御性能や攻撃成功率を測定するための客観的メトリクス",
        comment_lang="ja",
    )


def _add_security_object_properties(builder: TurtleDocumentBuilder) -> None:
    """Populates core object properties for security ontology with owl:inverseOf and alignments."""
    builder.add_object_property(
        uri="sec:discloses",
        inverse_of="sec:disclosedIn",
        label="脆弱性を公開・開示する",
        label_lang="ja",
        domain="sec:Paper",
        range_="sec:Vulnerability",
        section_comment="論文と脆弱性の関係",
    )
    builder.add_object_property(
        uri="sec:disclosedIn",
        inverse_of="sec:discloses",
        label="論文で公開・開示された",
        label_lang="ja",
        domain="sec:Vulnerability",
        range_="sec:Paper",
    )
    builder.add_object_property(
        uri="sec:exploits",
        inverse_of="sec:exploitedBy",
        label="脆弱性を悪用する",
        label_lang="ja",
        domain="sec:AttackTechnique",
        range_="sec:Vulnerability",
        section_comment="攻撃手法と脆弱性の関係",
    )
    builder.add_object_property(
        uri="sec:exploitedBy",
        inverse_of="sec:exploits",
        label="攻撃手法により悪用される",
        label_lang="ja",
        domain="sec:Vulnerability",
        range_="sec:AttackTechnique",
    )
    builder.add_object_property(
        uri="sec:analyzes",
        inverse_of="sec:analyzedIn",
        label="攻撃手法を分析する",
        label_lang="ja",
        domain="sec:Paper",
        range_="sec:AttackTechnique",
        section_comment="論文と攻撃手法の関係",
    )
    builder.add_object_property(
        uri="sec:analyzedIn",
        inverse_of="sec:analyzes",
        label="論文で分析・解明された",
        label_lang="ja",
        domain="sec:AttackTechnique",
        range_="sec:Paper",
    )
    builder.add_object_property(
        uri="sec:targets",
        inverse_of="sec:targetedBy",
        label="資産を標的とする",
        label_lang="ja",
        domain="sec:AttackTechnique",
        range_="sec:TargetAsset",
        section_comment="攻撃手法と対象資産の関係",
    )
    builder.add_object_property(
        uri="sec:targetedBy",
        inverse_of="sec:targets",
        label="攻撃手法の標的となる",
        label_lang="ja",
        domain="sec:TargetAsset",
        range_="sec:AttackTechnique",
    )
    builder.add_object_property(
        uri="sec:proposes",
        inverse_of="sec:proposedIn",
        label="防御策を提案する",
        label_lang="ja",
        domain="sec:Paper",
        range_="sec:DefenseMechanism",
        section_comment="論文と防御メカニズムの関係",
    )
    builder.add_object_property(
        uri="sec:proposedIn",
        inverse_of="sec:proposes",
        label="論文で提案された",
        label_lang="ja",
        domain="sec:DefenseMechanism",
        range_="sec:Paper",
    )
    builder.add_object_property(
        uri="sec:mitigates",
        inverse_of="sec:mitigatedBy",
        label="攻撃手法を緩和・防御する",
        label_lang="ja",
        domain="sec:DefenseMechanism",
        range_="sec:AttackTechnique",
        section_comment="防御策と攻撃手法の関係",
    )
    builder.add_object_property(
        uri="sec:mitigatedBy",
        inverse_of="sec:mitigates",
        label="攻撃手法が緩和・防御される",
        label_lang="ja",
        domain="sec:AttackTechnique",
        range_="sec:DefenseMechanism",
    )
    builder.add_object_property(
        uri="sec:patches",
        inverse_of="sec:patchedBy",
        label="脆弱性を改修・修復する",
        label_lang="ja",
        domain="sec:DefenseMechanism",
        range_="sec:Vulnerability",
        section_comment="防御策と脆弱性の関係",
    )
    builder.add_object_property(
        uri="sec:patchedBy",
        inverse_of="sec:patches",
        label="脆弱性が改修・修復される",
        label_lang="ja",
        domain="sec:Vulnerability",
        range_="sec:DefenseMechanism",
    )
    builder.add_object_property(
        uri="sec:evaluates",
        inverse_of="sec:evaluatedIn",
        label="評価指標で測定する",
        label_lang="ja",
        domain="sec:Paper",
        range_="sec:BenchmarkMetric",
        section_comment="論文と評価指標の関係",
    )
    builder.add_object_property(
        uri="sec:evaluatedIn",
        inverse_of="sec:evaluates",
        label="論文で評価・測定された",
        label_lang="ja",
        domain="sec:BenchmarkMetric",
        range_="sec:Paper",
    )
    builder.add_object_property(
        uri="sec:attributedTo",
        inverse_of="sec:actorAttributedTechnique",
        label="脅威アクターに帰属する",
        label_lang="ja",
        domain="sec:AttackTechnique",
        range_="sec:ThreatActor",
        section_comment="攻撃手法と脅威アクターの関係",
    )
    builder.add_object_property(
        uri="sec:actorAttributedTechnique",
        inverse_of="sec:attributedTo",
        label="脅威アクターが使用する攻撃手法",
        label_lang="ja",
        domain="sec:ThreatActor",
        range_="sec:AttackTechnique",
    )
    builder.add_object_property(
        uri="sec:cites",
        label="先行研究を引用する",
        label_lang="ja",
        domain="sec:Paper",
        range_="sec:Paper",
        is_transitive=False,
        sub_property_of="cito:cites",
        section_comment="論文間の引用関係（CiTOアライメント・直接引用）",
    )


def _add_security_datatype_properties(builder: TurtleDocumentBuilder) -> None:
    """Populates core datatype properties for security ontology with standards alignment."""
    builder.add_datatype_property(
        uri="sec:paperId",
        label="論文ID",
        label_lang="ja",
        domain="sec:Paper",
        range_="xsd:string",
        is_functional=True,
    )
    builder.add_datatype_property(
        uri="sec:title",
        label="論文タイトル",
        label_lang="ja",
        domain="sec:Paper",
        range_="xsd:string",
        sub_property_of="dcterms:title",
    )
    builder.add_datatype_property(
        uri="sec:publishedDate",
        label="公開日",
        label_lang="ja",
        domain="sec:Paper",
        range_="xsd:date",
        sub_property_of="dcterms:date",
    )
    builder.add_datatype_property(
        uri="sec:cveId",
        label="CVE番号",
        label_lang="ja",
        domain="sec:Vulnerability",
        range_="xsd:string",
    )
    builder.add_datatype_property(
        uri="sec:techniqueId",
        label="ATT&CK テクニックID",
        label_lang="ja",
        domain="sec:AttackTechnique",
        range_="xsd:string",
    )


def build_security_cti_ontology() -> TurtleDocumentBuilder:
    """Builds the standard Security Knowledge Ontology (SKO) in W3C Turtle / OWL format."""
    builder = TurtleDocumentBuilder()
    builder.add_prefix("sec", "https://arxiv-security-papers.org/ontology/security#")
    builder.add_prefix("dcterms", "http://purl.org/dc/terms/")
    builder.add_prefix("cito", "http://purl.org/spar/cito/")
    builder.add_prefix("stix", "http://docs.oasis-open.org/cti/ns/stix#")
    builder.set_ontology(
        uri="https://arxiv-security-papers.org/ontology/security",
        label="arXiv Security Papers CTI Knowledge Ontology",
        label_lang="ja",
        comment="セキュリティ学術論文、サイバー脅威、攻撃手法、脆弱性、および防御策を推論・連携するための知識オントロジーモデル",
        comment_lang="ja",
        version_info="2.0.0",
    )
    _add_security_classes(builder)
    _add_security_object_properties(builder)
    _add_security_datatype_properties(builder)
    return builder


def _add_extended_classes_part1(builder: TurtleDocumentBuilder) -> None:
    """Adds Incident, DetectionRule, and PoCArtifact classes."""
    builder.add_class(
        uri="sec:Incident",
        label="実世界インシデント",
        label_lang="ja",
        comment="観測された実世界での侵害事例およびセキュリティインシデント",
        section_comment="実世界脅威事象",
    )
    builder.add_class(
        uri="sec:DetectionRule",
        label="検知・防御ルール",
        label_lang="ja",
        comment="Semgrep, Sigma, YARA などの機械可読な防御シグネチャコード",
        section_comment="即応防御成果物",
    )
    builder.add_class(
        uri="sec:PoCArtifact",
        label="PoCソフトウェア成果物",
        label_lang="ja",
        comment="GitHub リポジトリや Dockerfile などの実証ソフトウェアコード",
    )


def _add_extended_classes_part2(builder: TurtleDocumentBuilder) -> None:
    """Adds Precondition, ResearchGap, ResidualRisk, PublicationVenue, and Impact classes."""
    builder.add_class(
        uri="sec:Precondition",
        label="成立前提条件・脅威モデル",
        label_lang="ja",
        comment="攻撃や防御が成立するために必要なアクセス権限や知識モデル要件",
        section_comment="成立前提・制約境界",
    )
    builder.add_class(
        uri="sec:Impact",
        label="被害影響・影響度",
        label_lang="ja",
        comment="攻撃成立により発生する機密性/完全性/可用性の侵害または権限昇格等の結果事象 (STRIDE/CIA侵害)",
        section_comment="脅威被害・結果影響",
    )
    builder.add_class(
        uri="sec:ResearchGap",
        label="未解決研究課題",
        label_lang="ja",
        comment="学術的・技術的に未解決の限界および将来の探究テーマ",
        section_comment="研究限界・未解決課題",
    )
    builder.add_class(
        uri="sec:ResidualRisk",
        label="残余リスク・死角",
        label_lang="ja",
        comment="防御策適用後もなお残存するバイパス手法や潜在的脅威",
    )
    builder.add_class(
        uri="sec:PublicationVenue",
        label="採択会議・出版媒体",
        label_lang="ja",
        comment="IEEE S&P, USENIX, CCS, NDSS などの学術トップカンファレンス",
        section_comment="学術来歴・信頼性",
    )


def _add_extended_object_properties_part1(builder: TurtleDocumentBuilder) -> None:
    """Adds Incident coupling, blocks, generatesRule, and requiresPrecondition properties."""
    # 孤立クラス sec:Incident の結合（インシデントと攻撃手法、脆弱性、アクター、資産）
    builder.add_object_property(
        uri="sec:exploitedIn",
        inverse_of="sec:incidentObservedTechnique",
        label="インシデントで悪用が観測された",
        label_lang="ja",
        domain="sec:AttackTechnique",
        range_="sec:Incident",
        section_comment="攻撃手法とインシデントの関係",
    )
    builder.add_object_property(
        uri="sec:incidentObservedTechnique",
        inverse_of="sec:exploitedIn",
        label="インシデントで観測された攻撃手法",
        label_lang="ja",
        domain="sec:Incident",
        range_="sec:AttackTechnique",
    )
    builder.add_object_property(
        uri="sec:leveragedVulnerability",
        inverse_of="sec:vulnerabilityLeveragedIn",
        label="インシデントで悪用された脆弱性",
        label_lang="ja",
        domain="sec:Incident",
        range_="sec:Vulnerability",
        section_comment="インシデントと脆弱性の関係",
    )
    builder.add_object_property(
        uri="sec:vulnerabilityLeveragedIn",
        inverse_of="sec:leveragedVulnerability",
        label="脆弱性が悪用されたインシデント",
        label_lang="ja",
        domain="sec:Vulnerability",
        range_="sec:Incident",
    )
    builder.add_object_property(
        uri="sec:attributedToActor",
        inverse_of="sec:actorAttributedIncident",
        label="インシデントの関与アクター",
        label_lang="ja",
        domain="sec:Incident",
        range_="sec:ThreatActor",
        section_comment="インシデントと脅威アクターの関係",
    )
    builder.add_object_property(
        uri="sec:actorAttributedIncident",
        inverse_of="sec:attributedToActor",
        label="アクターが関与したインシデント",
        label_lang="ja",
        domain="sec:ThreatActor",
        range_="sec:Incident",
    )
    builder.add_object_property(
        uri="sec:targetsAsset",
        inverse_of="sec:assetTargetedInIncident",
        label="インシデントの標的資産",
        label_lang="ja",
        domain="sec:Incident",
        range_="sec:TargetAsset",
        section_comment="インシデントと標的資産の関係",
    )
    builder.add_object_property(
        uri="sec:assetTargetedInIncident",
        inverse_of="sec:targetsAsset",
        label="インシデントで標的とされた資産",
        label_lang="ja",
        domain="sec:TargetAsset",
        range_="sec:Incident",
    )

    # 検知ルールおよび前提条件
    builder.add_object_property(
        uri="sec:blocks",
        inverse_of="sec:blockedBy",
        label="攻撃手法を検知・遮断する",
        label_lang="ja",
        domain="sec:DetectionRule",
        range_="sec:AttackTechnique",
        section_comment="検知ルールと攻撃手法の関係",
    )
    builder.add_object_property(
        uri="sec:blockedBy",
        inverse_of="sec:blocks",
        label="検知ルールにより検知・遮断される",
        label_lang="ja",
        domain="sec:AttackTechnique",
        range_="sec:DetectionRule",
    )
    builder.add_object_property(
        uri="sec:generatesRule",
        inverse_of="sec:ruleGeneratedBy",
        label="防御シグネチャを生成する",
        label_lang="ja",
        domain="sec:DefenseMechanism",
        range_="sec:DetectionRule",
        section_comment="防御策と検知ルールの関係",
    )
    builder.add_object_property(
        uri="sec:ruleGeneratedBy",
        inverse_of="sec:generatesRule",
        label="防御策から生成されたシグネチャ",
        label_lang="ja",
        domain="sec:DetectionRule",
        range_="sec:DefenseMechanism",
    )
    builder.add_object_property(
        uri="sec:requiresPrecondition",
        inverse_of="sec:preconditionRequiredBy",
        label="成立前提条件を要求する",
        label_lang="ja",
        domain="sec:AttackTechnique",
        range_="sec:Precondition",
        section_comment="攻撃手法と前提条件の関係",
    )
    builder.add_object_property(
        uri="sec:preconditionRequiredBy",
        inverse_of="sec:requiresPrecondition",
        label="前提条件を要求する攻撃手法",
        label_lang="ja",
        domain="sec:Precondition",
        range_="sec:AttackTechnique",
    )
    builder.add_object_property(
        uri="sec:hasImpact",
        inverse_of="sec:impactCausedBy",
        label="被害影響をもたらす",
        label_lang="ja",
        domain="sec:AttackTechnique",
        range_="sec:Impact",
        section_comment="攻撃手法と被害影響（STRIDE/CIA侵害）の因果関係",
    )
    builder.add_object_property(
        uri="sec:impactCausedBy",
        inverse_of="sec:hasImpact",
        label="被害影響をもたらした攻撃手法",
        label_lang="ja",
        domain="sec:Impact",
        range_="sec:AttackTechnique",
    )
    builder.add_object_property(
        uri="sec:neutralizesPrecondition",
        inverse_of="sec:preconditionNeutralizedBy",
        label="攻撃前提条件を無力化・打破する",
        label_lang="ja",
        domain="sec:DefenseMechanism",
        range_="sec:Precondition",
        section_comment="防御策による攻撃成立前提条件の無力化因果関係",
    )
    builder.add_object_property(
        uri="sec:preconditionNeutralizedBy",
        inverse_of="sec:neutralizesPrecondition",
        label="防御策により無力化される前提条件",
        label_lang="ja",
        domain="sec:Precondition",
        range_="sec:DefenseMechanism",
    )


def _add_extended_object_properties_part2(builder: TurtleDocumentBuilder) -> None:
    """Adds leavesUnaddressed, identifiesGap, presentedAt, verifiesCVE, and hasPoC with inverseOf."""
    builder.add_object_property(
        uri="sec:leavesUnaddressed",
        inverse_of="sec:unaddressedBy",
        label="残余リスクを未対処とする",
        label_lang="ja",
        domain="sec:DefenseMechanism",
        range_="sec:ResidualRisk",
        section_comment="防御策と残余リスクの関係",
    )
    builder.add_object_property(
        uri="sec:unaddressedBy",
        inverse_of="sec:leavesUnaddressed",
        label="防御策で未対処として残存する",
        label_lang="ja",
        domain="sec:ResidualRisk",
        range_="sec:DefenseMechanism",
    )
    builder.add_object_property(
        uri="sec:identifiesGap",
        inverse_of="sec:gapIdentifiedBy",
        label="未解決課題を提起・特定する",
        label_lang="ja",
        domain="sec:Paper",
        range_="sec:ResearchGap",
        section_comment="論文と研究ギャップの関係",
    )
    builder.add_object_property(
        uri="sec:gapIdentifiedBy",
        inverse_of="sec:identifiesGap",
        label="論文により特定された未解決課題",
        label_lang="ja",
        domain="sec:ResearchGap",
        range_="sec:Paper",
    )
    builder.add_object_property(
        uri="sec:presentedAt",
        inverse_of="sec:venuePresentedPaper",
        label="採択・発表される",
        label_lang="ja",
        domain="sec:Paper",
        range_="sec:PublicationVenue",
        section_comment="論文と発表媒体の関係",
    )
    builder.add_object_property(
        uri="sec:venuePresentedPaper",
        inverse_of="sec:presentedAt",
        label="採択・発表された論文",
        label_lang="ja",
        domain="sec:PublicationVenue",
        range_="sec:Paper",
    )
    builder.add_object_property(
        uri="sec:verifiesCVE",
        inverse_of="sec:cveVerifiedBy",
        label="既知脆弱性を検証・悪用実証する",
        label_lang="ja",
        domain="sec:Paper",
        range_="sec:Vulnerability",
        section_comment="論文と既知脆弱性の実証関係",
    )
    builder.add_object_property(
        uri="sec:cveVerifiedBy",
        inverse_of="sec:verifiesCVE",
        label="論文により悪用実証された脆弱性",
        label_lang="ja",
        domain="sec:Vulnerability",
        range_="sec:Paper",
    )
    builder.add_object_property(
        uri="sec:hasPoC",
        inverse_of="sec:pocOfPaper",
        label="PoC成果物を有する",
        label_lang="ja",
        domain="sec:Paper",
        range_="sec:PoCArtifact",
        section_comment="論文とPoCコードの関係",
    )
    builder.add_object_property(
        uri="sec:pocOfPaper",
        inverse_of="sec:hasPoC",
        label="論文のPoC成果物",
        label_lang="ja",
        domain="sec:PoCArtifact",
        range_="sec:Paper",
    )


def _add_extended_datatype_properties(builder: TurtleDocumentBuilder) -> None:
    """Adds datatype properties for full-spectrum ontology."""
    builder.add_datatype_property(
        uri="sec:ruleFormat",
        label="ルール形式",
        label_lang="ja",
        domain="sec:DetectionRule",
        range_="xsd:string",
        section_comment="防御ルール属性",
    )
    builder.add_datatype_property(
        uri="sec:ruleContent",
        label="ルール本文",
        label_lang="ja",
        domain="sec:DetectionRule",
        range_="xsd:string",
    )
    builder.add_datatype_property(
        uri="sec:accessLevel",
        label="要求アクセス権限",
        label_lang="ja",
        domain="sec:Precondition",
        range_="xsd:string",
        section_comment="前提条件属性",
    )
    builder.add_datatype_property(
        uri="sec:assumedKnowledge",
        label="前提知識モデル",
        label_lang="ja",
        domain="sec:Precondition",
        range_="xsd:string",
    )
    builder.add_datatype_property(
        uri="sec:reproducibilityTier",
        label="再現性ランク",
        label_lang="ja",
        domain="sec:Paper",
        range_="xsd:string",
        section_comment="論文再現性ランク (Tier-1〜3)",
    )
    builder.add_datatype_property(
        uri="sec:repoUrl",
        label="リポジトリURL",
        label_lang="ja",
        domain="sec:PoCArtifact",
        range_="xsd:anyURI",
    )
    builder.add_datatype_property(
        uri="sec:venueTier",
        label="会議ティア",
        label_lang="ja",
        domain="sec:PublicationVenue",
        range_="xsd:string",
    )
    builder.add_datatype_property(
        uri="sec:strideCategory",
        label="STRIDE脅威分類",
        label_lang="ja",
        domain="sec:Impact",
        range_="xsd:string",
        section_comment="被害影響属性",
    )
    builder.add_datatype_property(
        uri="sec:impactSeverity",
        label="影響深刻度",
        label_lang="ja",
        domain="sec:Impact",
        range_="xsd:string",
    )


def _add_reification_and_data_constraints(builder: TurtleDocumentBuilder) -> None:
    """Adds Claim-Evidence reification model and regex-constrained datatypes (Issue #186)."""
    # 1. 主張・実証評価クラス (Reification Classes)
    builder.add_class(
        uri="sec:Claim",
        label="学術的主張・命題",
        label_lang="ja",
        comment="論文著者が提唱・主張する防御性能や緩和効果の命題",
        section_comment="学術的主張（著者主張）",
    )
    builder.add_class(
        uri="sec:EvaluationResult",
        label="実証評価イベント・検証事実",
        label_lang="ja",
        comment="独立した第三者や実験環境における客観的ベンチマーク・再現性評価イベント（関係性の具現化ノード）",
        section_comment="実証事実・エッジ属性保持実体",
    )

    # 2. 具現化オブジェクトプロパティ (Reification Object Properties)
    builder.add_object_property(
        uri="sec:assertsClaim",
        inverse_of="sec:claimAssertedBy",
        label="命題を主張する",
        label_lang="ja",
        domain="sec:Paper",
        range_="sec:Claim",
        section_comment="論文と主張の関係",
    )
    builder.add_object_property(
        uri="sec:claimAssertedBy",
        inverse_of="sec:assertsClaim",
        label="命題を主張した論文",
        label_lang="ja",
        domain="sec:Claim",
        range_="sec:Paper",
    )
    builder.add_object_property(
        uri="sec:evaluatesClaim",
        inverse_of="sec:claimEvaluatedIn",
        label="主張を実証・評価する",
        label_lang="ja",
        domain="sec:EvaluationResult",
        range_="sec:Claim",
        section_comment="評価イベントと主張の関係",
    )
    builder.add_object_property(
        uri="sec:claimEvaluatedIn",
        inverse_of="sec:evaluatesClaim",
        label="主張の実証評価イベント",
        label_lang="ja",
        domain="sec:Claim",
        range_="sec:EvaluationResult",
    )
    builder.add_object_property(
        uri="sec:evaluatesTechnique",
        inverse_of="sec:techniqueEvaluatedIn",
        label="評価対象の攻撃手法",
        label_lang="ja",
        domain="sec:EvaluationResult",
        range_="sec:AttackTechnique",
        section_comment="評価イベントと攻撃手法の関係",
    )
    builder.add_object_property(
        uri="sec:techniqueEvaluatedIn",
        inverse_of="sec:evaluatesTechnique",
        label="攻撃手法が検証された評価イベント",
        label_lang="ja",
        domain="sec:AttackTechnique",
        range_="sec:EvaluationResult",
    )

    # 3. エッジ属性データプロパティ (Reification Datatype Properties)
    builder.add_datatype_property(
        uri="sec:successRate",
        label="実測成功率・緩和率",
        label_lang="ja",
        domain="sec:EvaluationResult",
        range_="xsd:decimal",
        section_comment="実証エッジ属性",
    )
    builder.add_datatype_property(
        uri="sec:targetEnvironment",
        label="検証対象環境・OS",
        label_lang="ja",
        domain="sec:EvaluationResult",
        range_="xsd:string",
    )
    builder.add_datatype_property(
        uri="sec:empiricalEvidenceLevel",
        label="実証エビデンス信頼水準",
        label_lang="ja",
        domain="sec:EvaluationResult",
        range_="xsd:string",
    )

    # 4. 正規表現パターン付きカスタムDatatype (rdfs:Datatype with owl:withRestrictions)
    builder.add_datatype(
        uri="sec:CVEIdentifier",
        base_datatype="xsd:string",
        pattern=r"[cC][vV][eE]-[0-9]{4}-[0-9]{4,}",
        label="CVE番号識別子",
        label_lang="ja",
        comment="正規表現に準拠するCVE番号フォーマット制約 (CVE-YYYY-NNNN+)",
        section_comment="識別子正規表現制約",
    )
    builder.add_datatype(
        uri="sec:CWEIdentifier",
        base_datatype="xsd:string",
        pattern=r"[cC][wW][eE]-[0-9]+",
        label="CWE番号識別子",
        label_lang="ja",
        comment="正規表現に準拠するCWE番号フォーマット制約 (CWE-NNN+)",
    )
    builder.add_datatype(
        uri="sec:AttackTechniqueIdentifier",
        base_datatype="xsd:string",
        pattern=r"T[0-9]{4}(\.[0-9]{3})?",
        label="ATT&CKテクニックID識別子",
        label_lang="ja",
        comment="正規表現に準拠するMITRE ATT&CKテクニックIDフォーマット制約 (TNNNNまたはTNNNN.NNN)",
    )


def build_full_spectrum_security_ontology() -> TurtleDocumentBuilder:
    """Builds the Full-Spectrum Security Knowledge Ontology (Issue #179, #184, #185, #186).

    Integrates:
    1. Core Entities & Predicates (Paper, ThreatActor, AttackTechnique, Vulnerability, etc.)
    2. Real-world Threat Entities (Incident, verifiesCVE, Incident coupling)
    3. Actionable Defense Artifacts (DetectionRule: Semgrep/Sigma, PoCArtifact, blocks)
    4. Preconditions & Threat Models (Precondition, accessLevel, requiresPrecondition)
    5. Research Gaps & Residual Risks (ResearchGap, ResidualRisk, leavesUnaddressed)
    6. Provenance & Trust Tiers (PublicationVenue, reproducibilityTier, presentedAt)
    7. Threat Model Causality & Impact (Impact, hasImpact, neutralizesPrecondition, strideCategory)
    8. Claim-Evidence Reification & Data Constraints (Claim, EvaluationResult, CVE/ATT&CK Datatypes)
    """
    builder = build_security_cti_ontology()
    _add_extended_classes_part1(builder)
    _add_extended_classes_part2(builder)
    _add_extended_object_properties_part1(builder)
    _add_extended_object_properties_part2(builder)
    _add_extended_datatype_properties(builder)
    _add_reification_and_data_constraints(builder)
    return builder


def main(argv: Optional[Sequence[str]] = None) -> int:
    """CLI entrypoint for generating Full-Spectrum Security Ontology W3C Turtle document."""
    import argparse
    import sys
    from pathlib import Path

    parser = argparse.ArgumentParser(
        prog="python -m ontology.turtle_engine",
        description="Generate W3C RDF/OWL 2.0 Full-Spectrum Security Knowledge Ontology Turtle (.ttl) document.",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=str,
        default="outputs/ontology/security_ontology_v2.ttl",
        help="Path to write Turtle (.ttl) output file (default: outputs/ontology/security_ontology_v2.ttl)",
    )
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="Print generated Turtle (.ttl) directly to stdout",
    )
    args = parser.parse_args(argv)

    doc = build_full_spectrum_security_ontology()
    ttl_content = doc.serialize()

    if args.stdout:
        sys.stdout.write(ttl_content)
        return 0

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(ttl_content, encoding="utf-8")
    print(
        f"✨ Successfully generated W3C Turtle ontology ({len(ttl_content)} bytes) -> {out_path}"
    )
    return 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
