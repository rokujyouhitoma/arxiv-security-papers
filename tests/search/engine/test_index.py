"""
Tests for Core Search Engine Index & Compression (src/search/engine/index/).
"""

from search.engine.index import (
    PostingsList,
    Segment,
    TieredMergePolicy,
    decode_gap_vbyte,
    decode_vbyte,
    encode_gap_vbyte,
    encode_vbyte,
)


def test_vbyte_and_gap_compression():
    numbers = [0, 1, 127, 128, 300, 16384, 1000000]
    encoded = encode_vbyte(numbers)
    decoded = decode_vbyte(encoded)
    assert decoded == numbers

    doc_ids = [10, 25, 30, 105, 500, 501, 1000]
    gap_encoded = encode_gap_vbyte(doc_ids)
    gap_decoded = decode_gap_vbyte(gap_encoded)
    assert gap_decoded == doc_ids

    plist = PostingsList("title:security")
    plist.add(1, position=0)
    plist.add(5, position=2)
    plist.add(10, position=4)
    comp_bytes = plist.compress()
    assert len(comp_bytes) > 0
    decomp_entries = plist.decompress()
    assert len(decomp_entries) == 3
    assert [e.doc_id for e in decomp_entries] == [1, 5, 10]


def test_segment_docvalues_and_stored_fields():
    seg = Segment("seg_01")
    seg.add_document(
        0,
        fields={"title": "Ransomware Detection", "year": 2025, "citations": 12},
        analyzed_fields={"title": ["ransomware", "detection"]},
    )
    assert seg.doc_count == 1
    assert seg.stored_fields.get(0)["title"] == "Ransomware Detection"
    assert seg.doc_values["year"].get(0) == 2025

    # Test deletion
    seg.deleted_docs.delete(0)
    assert seg.is_deleted(0) is True
    assert seg.live_docs_count() == 0


def test_tiered_merge_policy():
    seg1 = Segment("seg_01")
    seg1.add_document(
        0,
        fields={"title": "Ransomware Detection", "year": 2025},
        analyzed_fields={"title": ["ransomware", "detection"]},
    )
    seg2 = Segment("seg_02")
    seg2.add_document(
        0,
        fields={"title": "Zero-Day Exploit", "year": 2026},
        analyzed_fields={"title": ["zero-day", "exploit"]},
    )

    merge_policy = TieredMergePolicy(max_segments=1)
    merges = merge_policy.find_merges([seg1, seg2])
    assert len(merges) == 1

    merged_seg = merge_policy.merge_segments([seg1, seg2], "merged_01")
    assert merged_seg.doc_count == 2
    assert merged_seg.stored_fields.get(0)["title"] == "Ransomware Detection"
    assert merged_seg.stored_fields.get(1)["title"] == "Zero-Day Exploit"
