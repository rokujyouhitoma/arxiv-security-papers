#!/usr/bin/env python3
"""Unit tests for Pure-Python W3C Turtle (.ttl) / OWL Ontology Engine."""

import tempfile
from pathlib import Path

from ontology.turtle_engine import (
    URI,
    DatatypeProperty,
    Literal,
    ObjectProperty,
    OntologyClass,
    OntologyInstance,
    OntologyMetadata,
    RawTriple,
    TurtleDocumentBuilder,
    _escape_turtle_string,
    build_sample_enterprise_ontology,
    build_security_cti_ontology,
)


class TestTurtleEngine:
    """Test suite for Turtle and OWL serializer."""

    def test_direct_dataclass_renderers(self) -> None:
        """Tests direct rendering methods on individual ontology dataclasses."""
        meta = OntologyMetadata(
            uri="http://example.org/test",
            label="Test",
            comment="Desc",
            version_info="1.0",
            imports=["http://example.org/core"],
        )
        meta_ttl = meta.to_turtle()
        assert "<http://example.org/test>" in meta_ttl
        assert "owl:imports <http://example.org/core>" in meta_ttl

        cls = OntologyClass(
            uri="ex:Cat",
            label="猫",
            sub_class_of="ex:Animal",
            disjoint_with=["ex:Dog"],
            section_comment="Cat class",
        )
        cls_ttl = cls.to_turtle()
        assert "# Cat class" in cls_ttl
        assert "ex:Cat rdf:type owl:Class ;" in cls_ttl
        assert "ex:Cat owl:disjointWith ex:Dog ." in cls_ttl

        op = ObjectProperty(
            uri="ex:eats",
            label="食べる",
            domain="ex:Animal",
            range_="ex:Food",
            inverse_of="ex:eatenBy",
            is_transitive=True,
            is_symmetric=True,
            section_comment="Eating relationship",
        )
        op_ttl = op.to_turtle()
        assert "owl:TransitiveProperty, owl:SymmetricProperty" in op_ttl
        assert "owl:inverseOf ex:eatenBy" in op_ttl

        dp = DatatypeProperty(
            uri="ex:age",
            label="年齢",
            domain="ex:Animal",
            range_="xsd:integer",
            is_functional=True,
        )
        dp_ttl = dp.to_turtle()
        assert "owl:FunctionalProperty" in dp_ttl

        inst = OntologyInstance(
            uri="ex:tora",
            rdf_types=["ex:Cat"],
            properties=[("ex:age", 3)],
            section_comment="Instance Tora",
        )
        inst_ttl = inst.to_turtle()
        assert "# Instance Tora" in inst_ttl
        assert "ex:tora rdf:type ex:Cat ;" in inst_ttl

        raw_tr = RawTriple("ex:tora", "ex:color", "orange", comment="Color assertion")
        assert "# Color assertion" in raw_tr.to_turtle()
        assert 'ex:tora ex:color "orange" .' in raw_tr.to_turtle()

    def test_escape_turtle_string(self) -> None:
        """Tests character escaping in string literals."""
        raw = 'He said: "Hello\\World"\nNew\tLine'
        escaped = _escape_turtle_string(raw)
        assert '\\"' in escaped
        assert "\\\\" in escaped
        assert "\\n" in escaped
        assert "\\t" in escaped

    def test_literal_types(self) -> None:
        """Tests Literal rendering for various types."""
        # String literal
        lit_str = Literal("Hello")
        assert lit_str.to_turtle() == '"Hello"'

        # Language-tagged literal
        lit_ja = Literal("エージェント", lang="ja")
        assert lit_ja.to_turtle() == '"エージェント"@ja'

        # Typed literal
        lit_dt = Literal("2026-04-10T14:30:00Z", datatype="xsd:dateTime")
        assert lit_dt.to_turtle() == '"2026-04-10T14:30:00Z"^^xsd:dateTime'

        # Full URI typed literal
        lit_full_dt = Literal(
            "123", datatype="http://www.w3.org/2001/XMLSchema#integer"
        )
        assert (
            lit_full_dt.to_turtle()
            == '"123"^^<http://www.w3.org/2001/XMLSchema#integer>'
        )

        # Numeric literal (untyped integer/float)
        lit_int = Literal(8)
        assert lit_int.to_turtle() == "8"

        lit_float = Literal(3.14)
        assert lit_float.to_turtle() == "3.14"

        # Boolean literal
        lit_true = Literal(True)
        assert lit_true.to_turtle() == "true"
        lit_false = Literal(False)
        assert lit_false.to_turtle() == "false"

    def test_uri_rendering(self) -> None:
        """Tests URI rendering for full IRIs and prefixed names."""
        assert URI("ex:Person").to_turtle() == "ex:Person"
        assert URI("a").to_turtle() == "a"
        assert (
            URI("https://example.com/ontology/corp").to_turtle()
            == "<https://example.com/ontology/corp>"
        )
        assert URI("urn:isbn:0451450523").to_turtle() == "<urn:isbn:0451450523>"

    def test_sample_enterprise_ontology_serialization(self) -> None:
        """Tests exact recreation of the user-provided enterprise knowledge ontology sample."""
        builder = build_sample_enterprise_ontology()
        ttl = builder.serialize()

        # Check prefixes
        assert "@prefix ex:    <https://example.com/ontology/corp#> ." in ttl
        assert "@prefix owl:   <http://www.w3.org/2002/07/owl#> ." in ttl
        assert "@prefix rdf:   <http://www.w3.org/1999/02/22-rdf-syntax-ns#> ." in ttl
        assert "@prefix rdfs:  <http://www.w3.org/2000/01/rdf-schema#> ." in ttl
        assert "@prefix xsd:   <http://www.w3.org/2001/XMLSchema#> ." in ttl

        # Check metadata
        assert "<https://example.com/ontology/corp>" in ttl
        assert 'rdfs:label "Enterprise Knowledge Ontology"@ja' in ttl
        assert 'owl:versionInfo "1.0.0"' in ttl

        # Check Classes
        assert "ex:Agent rdf:type owl:Class ;" in ttl
        assert 'rdfs:label "エージェント"@ja ;' in ttl
        assert "ex:Person rdf:type owl:Class ;" in ttl
        assert "rdfs:subClassOf ex:Agent ;" in ttl
        assert "ex:Person owl:disjointWith ex:Organization ." in ttl

        # Check Object Properties
        assert "ex:belongsTo rdf:type owl:ObjectProperty ;" in ttl
        assert "rdfs:domain ex:Person ;" in ttl
        assert "rdfs:range ex:Organization ." in ttl
        assert "owl:inverseOf ex:belongsTo ;" in ttl
        assert (
            "ex:subOrganizationOf rdf:type owl:ObjectProperty, owl:TransitiveProperty ;"
            in ttl
        )

        # Check Datatype Properties
        assert (
            "ex:personId rdf:type owl:DatatypeProperty, owl:FunctionalProperty ;" in ttl
        )
        assert "rdfs:domain owl:Thing ;" in ttl
        assert "rdfs:range xsd:string ." in ttl
        assert "rdfs:range xsd:integer ." in ttl
        assert "rdfs:range xsd:dateTime ." in ttl

        # Check Instances (ABox)
        assert "ex:dept_eng rdf:type ex:Organization ;" in ttl
        assert 'ex:name "技術統括部" .' in ttl
        assert "ex:subOrganizationOf ex:dept_eng ." in ttl
        assert "ex:emp_001 rdf:type ex:Person ;" in ttl
        assert 'ex:personId "EMP-001" ;' in ttl
        assert 'ex:name "田中 太郎" ;' in ttl
        assert "ex:experienceYears 8 ;" in ttl
        assert "ex:belongsTo ex:team_sec ;" in ttl
        assert "ex:hasSkill ex:skill_python ;" in ttl
        assert "ex:hasSkill ex:skill_appsec ." in ttl
        assert 'ex:createdAt "2026-04-10T14:30:00Z"^^xsd:dateTime .' in ttl
        assert "ex:emp_001 ex:createdArtifact ex:doc_sec_spec ." in ttl

    def test_security_cti_ontology_serialization(self) -> None:
        """Tests CTI ontology generation with Security entities and predicates."""
        builder = build_security_cti_ontology()
        ttl = builder.serialize()

        assert (
            "@prefix sec:   <https://arxiv-security-papers.org/ontology/security#> ."
            in ttl
        )
        assert "sec:Paper rdf:type owl:Class ;" in ttl
        assert "sec:ThreatActor rdf:type owl:Class ;" in ttl
        assert "sec:AttackTechnique rdf:type owl:Class ;" in ttl
        assert "sec:Vulnerability rdf:type owl:Class ;" in ttl
        assert "sec:DefenseMechanism rdf:type owl:Class ;" in ttl

        # Predicates
        assert "sec:discloses rdf:type owl:ObjectProperty ;" in ttl
        assert "sec:exploits rdf:type owl:ObjectProperty ;" in ttl
        assert "sec:mitigates rdf:type owl:ObjectProperty ;" in ttl
        assert (
            "sec:paperId rdf:type owl:DatatypeProperty, owl:FunctionalProperty ;" in ttl
        )

    def test_save_to_file(self) -> None:
        """Tests saving ontology to disk."""
        builder = build_sample_enterprise_ontology()
        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "sub" / "ontology.ttl"
            builder.save(file_path)

            assert file_path.exists()
            content = file_path.read_text(encoding="utf-8")
            assert "Enterprise Knowledge Ontology" in content
            assert "ex:emp_001" in content

    def test_custom_triple_and_instance(self) -> None:
        """Tests adding standalone triples and custom instances."""
        builder = TurtleDocumentBuilder()
        builder.add_prefix("test", "http://test.org#")
        builder.add_instance(
            uri="test:Item1",
            rdf_types=["test:CustomItem"],
            properties=[("test:weight", 42)],
        )
        builder.add_triple("test:Item1", "test:relatedTo", URI("test:Item2"))

        ttl = builder.serialize()
        assert "test:Item1 rdf:type test:CustomItem ;" in ttl
        assert "test:weight 42 ." in ttl
        assert "test:Item1 test:relatedTo test:Item2 ." in ttl
