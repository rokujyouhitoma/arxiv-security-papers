"""
Tests for Facet & Aggregation Engine (src/search/platform/facet/).
"""

from search.engine.index import Segment
from search.platform.facet import FacetEngine
from search.platform.handler import UpdateHandler


def test_field_facet_and_range_facet():
    seg = Segment("seg_facet")
    updater = UpdateHandler()
    updater.add_document(seg, {"id": "p1", "category": "cs.CR", "year": 2026})
    updater.add_document(seg, {"id": "p2", "category": "cs.CR", "year": 2026})
    updater.add_document(seg, {"id": "p3", "category": "quant-ph", "year": 2025})

    engine = FacetEngine()
    engine.add_field_facet("category", limit=5)
    engine.add_range_facet("year", start=2024, end=2028, gap=1)

    facets = engine.compute_facets(seg, [0, 1, 2])
    assert "category" in facets
    assert facets["category"]["cs.CR"] == 2
    assert facets["category"]["quant-ph"] == 1

    assert "year" in facets
    assert facets["year"]["[2026 TO 2027]"] == 2
    assert facets["year"]["[2025 TO 2026]"] == 1
