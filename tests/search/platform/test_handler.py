"""
Tests for Search Platform SelectHandler and UpdateHandler (src/search/platform/handler/).
"""

from search.engine.index import Segment
from search.platform.elevation import QueryElevationComponent
from search.platform.handler import SelectHandler, UpdateHandler


def test_update_and_select_handler_pipeline():
    seg = Segment("seg_handler_e2e")
    updater = UpdateHandler()

    doc1 = {
        "id": "paper_01",
        "title": "Ransomware Defense Strategies",
        "category": "cs.CR",
        "year": 2026,
    }
    doc2 = {
        "id": "paper_02",
        "title": "Quantum Key Distribution",
        "category": "quant-ph",
        "year": 2025,
    }
    doc3 = {
        "id": "paper_03",
        "title": "Zero-Day Kernel Vulnerability",
        "category": "cs.CR",
        "year": 2026,
    }

    updater.add_document(seg, doc1)
    updater.add_document(seg, doc2)
    updater.add_document(seg, doc3)

    handler = SelectHandler()
    handler.facet_engine.add_field_facet("category")

    # 1. Search with query and pagination
    res = handler.handle_request(
        seg, {"q": "ransomware", "rows": 10, "facet": True, "hl": True}
    )
    assert res["response"]["numFound"] == 1
    assert res["response"]["docs"][0]["id"] == "paper_01"
    assert "highlighting" in res

    # 2. Filter query (fq)
    res_fq = handler.handle_request(seg, {"q": "*:*", "fq": "cs.CR"})
    assert res_fq["response"]["numFound"] == 2

    # 3. Query Elevation (Fixed Placement)
    elevation = QueryElevationComponent()
    elevation.add_elevation_rule("urgent-cve", ["paper_03"])
    handler_elev = SelectHandler(elevation=elevation)
    res_elev = handler_elev.handle_request(seg, {"q": "urgent-cve"})
    assert res_elev["response"]["docs"][0]["id"] == "paper_03"


def test_delete_by_id_in_update_handler():
    seg = Segment("seg_del")
    updater = UpdateHandler()
    doc_id = updater.add_document(seg, {"id": "del_1", "title": "Delete Me"})
    assert seg.live_docs_count() == 1

    updater.delete_by_id(seg, doc_id)
    assert seg.is_deleted(doc_id) is True
    assert seg.live_docs_count() == 0
