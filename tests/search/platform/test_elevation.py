"""
Tests for Query Elevation Component / Fixed Placement (src/search/platform/elevation/).
"""

from search.engine.search import ScoreDoc, TopDocs
from search.platform.elevation import QueryElevationComponent


def test_query_elevation_rule_promotion():
    elevation = QueryElevationComponent()
    elevation.add_elevation_rule(
        query_phrase="cve-2026-critical",
        elevated_ids=["emergency_advisory_01", "hotfix_guide_02"],
        excluded_ids=["legacy_doc_99"],
    )

    top_docs = TopDocs(
        total_hits=3,
        score_docs=[
            ScoreDoc(0, 10.0, {"id": "normal_doc_1", "title": "Normal Paper"}),
            ScoreDoc(
                1, 8.0, {"id": "emergency_advisory_01", "title": "Emergency Advisory"}
            ),
            ScoreDoc(2, 5.0, {"id": "legacy_doc_99", "title": "Legacy CVE"}),
        ],
    )

    elevated_docs = elevation.elevate("cve-2026-critical", top_docs, id_field="id")
    assert elevated_docs.total_hits == 2
    # Promoted ID must be at index 0
    assert elevated_docs.score_docs[0].fields["id"] == "emergency_advisory_01"
    assert elevated_docs.score_docs[0].score >= 1000.0

    # Excluded ID must not be in list
    res_ids = [d.fields["id"] for d in elevated_docs.score_docs]
    assert "legacy_doc_99" not in res_ids
    assert "normal_doc_1" in res_ids


def test_query_elevation_no_rule_match():
    elevation = QueryElevationComponent()
    top_docs = TopDocs(
        total_hits=1,
        score_docs=[ScoreDoc(0, 5.0, {"id": "doc1", "title": "General Paper"})],
    )
    res = elevation.elevate("unrelated_query", top_docs, id_field="id")
    assert res.total_hits == 1
    assert res.score_docs[0].fields["id"] == "doc1"
