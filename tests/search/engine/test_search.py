"""
Tests for Core Search Engine Queries, BM25, SpellChecker, and Sorter (src/search/engine/search/).
"""

from search.engine.index import Segment
from search.engine.search import (
    BM25Similarity,
    BooleanQuery,
    BoostQuery,
    FuzzyQuery,
    MatchAllDocsQuery,
    Occur,
    PhraseQuery,
    Sorter,
    SortField,
    SortOrder,
    SpellChecker,
    TermQuery,
    TopDocsCollector,
    WildcardQuery,
)


def test_bm25_and_term_boost_queries():
    seg = Segment("seg_search")
    seg.add_document(
        0,
        fields={
            "title": "Deep Learning Ransomware Analysis",
            "category": "cs.CR",
            "citations": 10,
        },
        analyzed_fields={
            "title": ["deep", "learning", "ransomware", "analysis"],
            "category": ["cs.cr"],
        },
    )
    seg.add_document(
        1,
        fields={
            "title": "Ransomware Attack Defense",
            "category": "cs.CR",
            "citations": 50,
        },
        analyzed_fields={
            "title": ["ransomware", "attack", "defense"],
            "category": ["cs.cr"],
        },
    )

    sim = BM25Similarity()
    tq = TermQuery("title", "ransomware")
    scores = tq.match(seg, sim)
    assert len(scores) == 2

    bq = BoostQuery(tq, boost=3.0)
    boosted = bq.match(seg, sim)
    assert round(boosted[0], 4) == round(scores[0] * 3.0, 4)

    all_q = MatchAllDocsQuery()
    assert len(all_q.match(seg, sim)) == 2


def test_complex_boolean_phrase_wildcard_fuzzy():
    seg = Segment("seg_complex")
    seg.add_document(
        0,
        fields={"title": "Ransomware Attack", "category": "cs.CR"},
        analyzed_fields={"title": ["ransomware", "attack"], "category": ["cs.cr"]},
    )
    seg.add_document(
        1,
        fields={"title": "Quantum Key Distribution", "category": "quant-ph"},
        analyzed_fields={
            "title": ["quantum", "key", "distribution"],
            "category": ["quant-ph"],
        },
    )

    sim = BM25Similarity()

    # BooleanQuery
    bool_q = BooleanQuery()
    bool_q.add(TermQuery("category", "cs.cr"), Occur.MUST)
    bool_q.add(TermQuery("title", "attack"), Occur.MUST)
    assert len(bool_q.match(seg, sim)) == 1

    # PhraseQuery
    phrase_q = PhraseQuery("title", ["ransomware", "attack"], slop=0)
    assert 0 in phrase_q.match(seg, sim)

    # WildcardQuery
    wild_q = WildcardQuery("title", "quant*")
    assert 1 in wild_q.match(seg, sim)

    # FuzzyQuery
    fuzzy_q = FuzzyQuery("title", "ransmware", max_edits=2)
    assert 0 in fuzzy_q.match(seg, sim)


def test_spellchecker_and_sorter():
    seg = Segment("seg_sorter")
    seg.add_document(
        0,
        fields={"title": "Ransomware Defense", "citations": 10},
        analyzed_fields={"title": ["ransomware", "defense"]},
    )
    seg.add_document(
        1,
        fields={"title": "Ransomware Overview", "citations": 100},
        analyzed_fields={"title": ["ransomware", "overview"]},
    )

    spell = SpellChecker(seg, field="title")
    suggestions = spell.suggest("ransmware", max_suggestions=2)
    assert "ransomware" in suggestions

    sorter = Sorter([SortField("citations", order=SortOrder.DESC)])
    top_docs = TopDocsCollector(top_k=2, sorter=sorter).collect(seg, {0: 1.0, 1: 1.0})
    assert top_docs.score_docs[0].doc_id == 1  # 100 citations
    assert top_docs.score_docs[1].doc_id == 0  # 10 citations
