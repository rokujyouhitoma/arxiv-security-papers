"""
Unit tests for SynonymExpander, FMIndex, and Extended Multi-Stage RAG VectorEngine
"""

import os
import sys

from search import SynonymExpander
from vector_engine import (
    CitationNetworkIndex,
    FacetedIndex,
    FMIndex,
    KnowledgeGraphIndex,
    ProximityGraphIndex,
    QuerySemanticCache,
    RAPTORTreeIndex,
    VectorEngine,
    extract_abstract_from_okf,
)

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
    )


def test_synonym_expander():
    expander = SynonymExpander()

    # Test Japanese to English penetration testing expansion
    expanded_pentest = expander.expand_query("ペンテスト")
    assert "penetration testing" in expanded_pentest or "pentest" in expanded_pentest
    assert "exploit" in expanded_pentest

    # Test autonomous vehicle expansion
    expanded_av = expander.expand_query("自動運転")
    assert "autonomous vehicle" in expanded_av or "autonomous vehicles" in expanded_av


def test_fm_index_substring_search():
    fm = FMIndex("マルウェア解析と自動運転セキュリティの脆弱性")
    count1 = fm.count_substring("マルウェア")
    count2 = fm.count_substring("自動運転")
    assert count1 == 1
    assert count2 == 1


def test_extract_abstract_from_okf():
    sample_okf = """---
title: "Test Paper"
---
# Test Paper
### Abstract (原文)
> AI agents are rapidly gaining capabilities in exploitation.
> Specifically, Claude Mythos Preview achieved state of the art results.
"""
    abstract = extract_abstract_from_okf(sample_okf)
    assert "AI agents are rapidly gaining" in abstract
    assert "Claude Mythos Preview" in abstract


def test_query_semantic_cache():
    cache = QuerySemanticCache(max_entries=10, similarity_threshold=0.6)
    cache.set(
        "malware analysis", ["malware", "analysis"], [{"id": "doc1"}], {"total_ms": 5.0}
    )

    # Exact Hit
    hit_exact = cache.get("malware analysis", ["malware", "analysis"])
    assert hit_exact is not None
    hit, prof = hit_exact
    assert hit[0]["id"] == "doc1"

    # Semantic Hit with similar tokens (Jaccard = 2/3 = 0.666 >= 0.6)
    hit_semantic = cache.get("malware analysis deep", ["malware", "analysis", "deep"])
    assert hit_semantic is not None

    stats = cache.get_stats()
    assert stats["hits"] >= 2
    assert stats["total_entries"] == 1


def test_faceted_index():
    facet = FacetedIndex()
    facet.add_document(
        "doc1", "2026-06-01", ["cs.CR", "malware"], ["マルウェア・脅威解析"]
    )
    facet.add_document("doc2", "2025-05-01", ["cs.AI"], ["LLM・AIセキュリティ"])

    # Filter by Year
    cand2026 = facet.filter(year="2026")
    assert cand2026 == {"doc1"}

    # Filter by Category
    cand_cr = facet.filter(category="cs.CR")
    assert cand_cr == {"doc1"}

    # Filter by Domain
    cand_domain = facet.filter(domain="マルウェア・脅威解析")
    assert cand_domain == {"doc1"}


def test_knowledge_graph_index():
    kg = KnowledgeGraphIndex()
    kg.add_entity("CVE-2026-001", "vulnerability", "CVE-2026-001", "paper1")
    kg.add_entity("SoundMalware", "attack", "SoundMalware", "paper1")
    kg.add_relationship("SoundMalware", "CVE-2026-001", "exploits", "paper1")

    subgraph = kg.get_neighbors("SoundMalware", max_depth=1)
    assert subgraph["root"] == "SoundMalware"
    assert len(subgraph["nodes"]) >= 1
    assert "paper1" in subgraph["related_papers"]


def test_citation_network_pagerank():
    cit = CitationNetworkIndex()
    cit.add_citation("paper1", "paper2")
    cit.add_citation("paper3", "paper2")

    ranks = cit.compute_pagerank(["paper1", "paper2", "paper3"], max_iter=10)
    assert ranks["paper2"] > ranks["paper1"]
    assert cit.get_score("paper2") > 0


def test_raptor_tree_index():
    raptor = RAPTORTreeIndex()
    docs = [
        {"id": "doc1", "annotated_keywords": ["マルウェア・脅威解析"]},
        {"id": "doc2", "annotated_keywords": ["LLM・AIセキュリティ"]},
    ]
    raptor.build_summary_tree(docs)
    summaries = raptor.search_clusters(["マルウェア"], top_k=1)
    assert len(summaries) == 1
    assert "マルウェア" in summaries[0]["domain"]


def test_vector_engine_multi_engine_search():
    engine = VectorEngine()
    results = engine.search("マルウェア解析", top_k=3)
    assert isinstance(results, list)
    if results:
        assert "score" in results[0]
        assert "path" in results[0]
        assert "annotated_keywords" in results[0]


def test_vector_engine_hybrid_pipeline():
    engine = VectorEngine()
    resp = engine.search_hybrid_pipeline("脱獄攻撃", top_k=3)
    assert "papers" in resp
    assert "profile" in resp
    assert "raptor_macro_summaries" in resp
    assert "cache_stats" in resp
    assert isinstance(resp["papers"], list)


def test_proximity_graph_index():
    prox = ProximityGraphIndex(top_k_neighbors=2)
    doc1 = {
        "id": "doc1",
        "title": "Acoustic Malware Attack",
        "description": "Audio side channel",
        "tags": ["cs.CR"],
        "annotated_keywords": [
            "マルウェア・脅威解析",
            "サイドチャネル・組込みセキュリティ",
        ],
        "token_counts": {"acoustic": 2, "malware": 3, "attack": 1},
    }
    doc2 = {
        "id": "doc2",
        "title": "Acoustic Keylogger Detection",
        "description": "Defense for audio side channel",
        "tags": ["cs.CR"],
        "annotated_keywords": ["サイドチャネル・組込みセキュリティ"],
        "token_counts": {"acoustic": 2, "keylogger": 1, "detection": 1},
    }
    doc3 = {
        "id": "doc3",
        "title": "Quantum Key Distribution",
        "description": "Post quantum crypto",
        "tags": ["quant-ph"],
        "annotated_keywords": ["暗号・プライバシー技術"],
        "token_counts": {"quantum": 3, "crypto": 2},
    }

    prox.build_graph([doc1, doc2, doc3])
    neighbors_1 = prox.get_neighbors("doc1")
    assert len(neighbors_1) >= 1
    assert neighbors_1[0]["target_id"] == "doc2"
    assert neighbors_1[0]["similarity"] > 0

    mermaid_str = prox.generate_mermaid_graph("doc1", "Acoustic Malware Attack")
    assert "flowchart TD" in mermaid_str
    assert "doc2" in mermaid_str


def test_vector_engine_get_related_papers():
    engine = VectorEngine()
    # Test on existing index
    if engine.documents:
        first_id = engine.documents[0]["id"]
        res = engine.get_related_papers(first_id)
        assert res["status"] == "success"
        assert "related_papers" in res
        assert "mermaid_graph" in res


def test_multi_field_schema_postings():
    from search.field_schema import MultiFieldPostingsIndex

    idx = MultiFieldPostingsIndex()
    idx.add_field_tokens("doc1", "title", ["rapidpen", "penetration", "testing"])
    idx.add_field_tokens("doc1", "author", ["tohru", "nakatani"])
    idx.add_field_tokens("doc2", "title", ["malware", "analysis"])
    idx.add_field_tokens("doc2", "author", ["john", "doe"])
    idx.compute_field_statistics(2)

    # Postings check
    postings = idx.get_postings("author", "nakatani")
    assert len(postings) == 1
    assert postings[0][0] == "doc1"
    assert postings[0][1] == [1]

    # Prefix search
    pref_matches = idx.search_prefix("author", "nakat")
    assert "doc1" in pref_matches

    # Fuzzy search
    fuzz_matches = idx.search_fuzzy("author", "nakatany", max_distance=1)
    assert "doc1" in fuzz_matches


def test_search_analyzer():
    from search.analyzer import SearchAnalyzer

    analyzer = SearchAnalyzer()
    tokens = analyzer.tokenize("RapidPen ペネトレーションテスト 脆弱性")
    assert "rapidpen" in tokens
    assert "ペネトレーションテスト" in tokens

    offsets = analyzer.tokenize_with_offsets("RapidPen malware test")
    assert len(offsets) >= 3
    assert offsets[0].text == "rapidpen"
    assert offsets[0].start == 0


def test_query_parser():
    from search.query_parser import EnterpriseQueryParser

    parser = EnterpriseQueryParser()
    clauses = parser.parse(
        'author:Nakatani +title:malware "deep learning"~2 pen* sound~1'
    )
    assert len(clauses) >= 5

    c_author = next(c for c in clauses if c.field == "author")
    assert c_author.term == "Nakatani"

    c_title = next(c for c in clauses if c.field == "title")
    assert c_title.term == "malware"
    assert c_title.is_required is True

    c_phrase = next(c for c in clauses if c.is_phrase)
    assert c_phrase.term == "deep learning"
    assert c_phrase.phrase_slop == 2

    c_pref = next(c for c in clauses if c.is_prefix)
    assert c_pref.term == "pen"

    c_fuzz = next(c for c in clauses if c.is_fuzzy)
    assert c_fuzz.term == "sound"


def test_dynamic_highlighter():
    from search.highlighter import DynamicHighlighter

    hl = DynamicHighlighter()
    text = "This paper presents RapidPen, an automated penetration testing tool."
    res = hl.highlight(text, ["RapidPen", "penetration"])
    assert '<mark class="highlight">' in res
    assert "</mark>" in res
    assert "RapidPen" in res


def test_enterprise_author_and_field_search():
    engine = VectorEngine()
    # Test query parsing and search
    results, profile = engine.search_with_profile("author:Nakatani", top_k=5)
    assert isinstance(results, list)
    assert profile["total_ms"] >= 0


def test_query_context_and_intent():
    from search.query import EnterpriseQueryParser, QueryContext, SynonymExpander

    parser = EnterpriseQueryParser()
    expander = SynonymExpander()

    # Test field specific intent
    ctx_field = parser.create_context("title:malware +author:Smith", expander=expander)
    assert isinstance(ctx_field, QueryContext)
    assert ctx_field.has_field_constraints is True
    assert "title" in ctx_field.target_fields
    assert ctx_field.intent == "field_specific"
    assert len(ctx_field.required_clauses) == 1

    # Test boolean filter intent
    ctx_bool = parser.create_context("+malware -ransomware", expander=expander)
    assert ctx_bool.intent == "boolean_filtered"
    assert len(ctx_bool.prohibited_clauses) == 1

    # Test general synonym expansion in context
    ctx_syn = parser.create_context("ペンテスト", expander=expander)
    assert (
        "penetration testing" in ctx_syn.expanded_tokens
        or "exploit" in ctx_syn.expanded_tokens
    )


def test_modular_search_pipeline():
    engine = VectorEngine()
    if os.path.exists(engine.index_file):
        engine.load_index()
    else:
        engine.build_index()

    # Step 1: Query Context Preparation
    ctx = engine.prepare_query_context("title:security")
    assert ctx.raw_query == "title:security"

    # Step 2: Retrieval
    candidates = engine.retrieve_candidates(ctx, max_candidates=50)
    assert isinstance(candidates, list)

    # Step 3: Reranking
    ranked = engine.rerank_candidates(ctx, candidates, top_k=3)
    assert isinstance(ranked, list)

    # Step 4: Formatting
    presentation = engine.format_presentation(ctx, ranked)
    assert isinstance(presentation, list)
    if presentation:
        assert "highlight" in presentation[0]
        assert "score" in presentation[0]


def test_subpackages_structure():
    # Test Ingestion subpackage
    from search.ingestion import FMIndex, MultiFieldPostingsIndex, SearchAnalyzer

    analyzer = SearchAnalyzer()
    assert len(analyzer.tokenize("cybersecurity")) > 0
    fm = FMIndex("test text")
    assert fm.count_substring("test") == 1
    mf = MultiFieldPostingsIndex()
    assert mf is not None

    # Test Query subpackage
    from search.query import EnterpriseQueryParser, QueryContext, SynonymExpander

    parser = EnterpriseQueryParser()
    ctx = parser.create_context("author:Smith")
    assert isinstance(ctx, QueryContext)
    exp = SynonymExpander()
    assert "exploit" in exp.expand_query("ペンテスト")

    # Test Ranking subpackage
    from search.ranking import (
        CitationNetworkIndex,
        KnowledgeGraphIndex,
        ProximityGraphIndex,
    )

    kg = KnowledgeGraphIndex()
    assert kg is not None
    cn = CitationNetworkIndex()
    assert cn is not None
    pg = ProximityGraphIndex()
    assert pg is not None

    # Test Presentation subpackage
    from search.presentation import DynamicHighlighter

    hl = DynamicHighlighter()
    hl_res = hl.highlight("RapidPen automated tool", ["RapidPen"])
    assert "mark" in hl_res


def test_lucene_core_analysis():
    """Validates Lucene-style CharFilter, Tokenizer, TokenFilter, and Analyzer."""
    from search.core.analysis import (
        Analyzer,
        HTMLStripCharFilter,
        LowerCaseFilter,
        StandardTokenizer,
        StopWordFilter,
        UnicodeNormalizeCharFilter,
    )

    # CharFilter
    cf_html = HTMLStripCharFilter()
    assert cf_html.filter("<b>Malware</b> &amp; Exploit") == " Malware  & Exploit"

    cf_unicode = UnicodeNormalizeCharFilter()
    assert cf_unicode.filter("ＡＢＣ") == "ABC"

    # Tokenizer & TokenFilter
    analyzer = Analyzer(
        char_filters=[HTMLStripCharFilter(), UnicodeNormalizeCharFilter()],
        tokenizer=StandardTokenizer(),
        token_filters=[LowerCaseFilter(), StopWordFilter()],
    )
    tokens = analyzer.analyze("<title>The Ransomware Attack in ２０２６</title>")
    terms = [t.text for t in tokens]
    assert "ransomware" in terms
    assert "attack" in terms
    assert "the" not in terms  # filtered by stop words


def test_lucene_core_store_and_index():
    """Validates Directory, PostingsList, MultiFieldPostingsIndex, DocValues, and StoredFields."""
    from search.core.index import DocValues, MultiFieldPostingsIndex, StoredFields
    from search.core.store import DeletedDocsBitset, RAMDirectory, SegmentInfo

    # Store
    ram_dir = RAMDirectory()
    ram_dir.write_bytes("segment_0.idx", b"binary_data")
    assert ram_dir.file_exists("segment_0.idx")
    assert ram_dir.read_bytes("segment_0.idx") == b"binary_data"

    bitset = DeletedDocsBitset()
    bitset.mark_deleted("doc_1")
    assert bitset.is_deleted("doc_1") is True
    assert bitset.is_deleted("doc_2") is False

    seg = SegmentInfo("seg_1", 100)
    assert seg.doc_count == 100

    # Index (Postings & DocValues)
    postings = MultiFieldPostingsIndex()
    postings.add_term("title", "fuzzing", "doc_101", 0)
    postings.add_term("title", "fuzzing", "doc_102", 0)
    assert len(postings.get_postings("title", "fuzzing")) == 2
    assert "doc_101" in postings.search_prefix("title", "fuzz")

    doc_values = DocValues()
    doc_values.set_value("year", "doc_101", "2026")
    doc_values.set_value("year", "doc_102", "2025")
    assert doc_values.get_value("year", "doc_101") == "2026"
    assert doc_values.get_doc_ids_matching("year", "2026") == {"doc_101"}

    # StoredFields
    stored = StoredFields()
    stored.put_document("doc_101", {"id": "doc_101", "title": "Advanced Fuzzing"})
    assert stored.get_document("doc_101")["title"] == "Advanced Fuzzing"


def test_solr_server_select_handler_and_faceting():
    """Validates Solr-style SelectHandler with filtering, scoring, highlighting, and faceting."""
    from search.core.analysis import Analyzer
    from search.core.index import DocValues, MultiFieldPostingsIndex, StoredFields
    from search.server.handler import SelectHandler
    from search.server.schema import ManagedIndexSchema

    schema = ManagedIndexSchema()
    analyzer = Analyzer()
    postings = MultiFieldPostingsIndex()
    doc_values = DocValues()
    stored = StoredFields()

    # Index sample documents
    docs = [
        {
            "id": "doc_1",
            "title": "Zero-Trust Architecture in Cloud",
            "category": "cs.CR",
            "year": "2026",
            "description": "Analyzing zero-trust security mechanisms in multi-cloud environments.",
        },
        {
            "id": "doc_2",
            "title": "Automated Binary Fuzzing",
            "category": "cs.CR",
            "year": "2026",
            "description": "High-throughput binary fuzzing tool for vulnerabilities.",
        },
        {
            "id": "doc_3",
            "title": "Deep Learning for Zero-Trust",
            "category": "cs.AI",
            "year": "2025",
            "description": "Applying deep neural models for zero-trust anomaly detection.",
        },
    ]

    for d in docs:
        doc_id = d["id"]
        stored.put_document(doc_id, d)
        doc_values.set_value("category", doc_id, d["category"])
        doc_values.set_value("year", doc_id, d["year"])
        for token in analyzer.analyze(d["title"]):
            postings.add_term("title", token.text, doc_id)
        for token in analyzer.analyze(d["description"]):
            postings.add_term("description", token.text, doc_id)

    handler = SelectHandler(
        schema=schema,
        analyzer=analyzer,
        postings_index=postings,
        doc_values=doc_values,
        stored_fields=stored,
    )

    # 1. Basic search
    res = handler.handle_select(
        "zero-trust", top_k=5, facet_fields=["category", "year"]
    )
    assert res["response"]["numFound"] >= 2
    assert "category" in res["facet_counts"]
    assert "cs.CR" in res["facet_counts"]["category"]
    assert "mark" in res["response"]["docs"][0]["highlight"]

    # 2. Filtered search (fq)
    res_filtered = handler.handle_select(
        "zero-trust",
        filter_queries={"category": "cs.CR", "year": "2026"},
        top_k=5,
    )
    assert res_filtered["response"]["numFound"] == 1
    assert res_filtered["response"]["docs"][0]["id"] == "doc_1"

    # 3. Observability Header Check
    assert "QTime" in res["responseHeader"]
    assert "cpu_time_ms" in res["responseHeader"]
    assert "peak_memory_kb" in res["responseHeader"]


def test_observability_and_profiling_framework():
    """Validates Python standard library observability tools (time, tracemalloc, cProfile, timeit, dis)."""
    from search.utils.profiler import (
        ExecutionProfiler,
        analyze_bytecode,
        benchmark_function,
        profile_function,
    )

    # 1. ExecutionProfiler (time & tracemalloc)
    with ExecutionProfiler("sample_block", track_memory=True) as prof:
        _ = [x**2 for x in range(5000)]

    assert prof.metrics is not None
    assert prof.metrics.wall_time_ms >= 0.0
    assert prof.metrics.cpu_time_ms >= 0.0
    assert prof.metrics.peak_memory_kb >= 0.0
    metric_dict = prof.metrics.to_dict()
    assert metric_dict["name"] == "sample_block"

    # 2. cProfile & pstats
    def sample_func(n: int) -> int:
        return sum(i for i in range(n))

    result, stats_output = profile_function(sample_func, 1000, top_n=5)
    assert result == 499500
    assert "function calls" in stats_output

    # 3. timeit micro-benchmark
    bench = benchmark_function(sample_func, number=50, repeat=2, n=100)
    assert "min_time_ms" in bench
    assert "avg_time_ms" in bench
    assert bench["repeats"] == 2

    # 4. dis bytecode analysis
    dis_res = analyze_bytecode(sample_func)
    assert dis_res["function_name"] == "sample_func"
    assert dis_res["total_instructions"] > 0
    assert any(i["opname"] == "RETURN_VALUE" for i in dis_res["instructions"])
