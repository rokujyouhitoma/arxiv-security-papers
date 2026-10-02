from nlp.clustering.trend_analyzer import (
    _build_mermaid_mindmap_tree,
    _render_mindmap_node,
)
from nlp.core.tokens import TopicCluster
from pipeline.transformer.yaml_parser import parse_okf_frontmatter


def test_parse_frontmatter_with_empty_authors():
    raw_md = """---
type: "security-paper"
title: "Test Security Paper"
title_ja: "テストセキュリティ論文"
description: "テスト用の概要です。"
resource: "https://arxiv.org/abs/2609.99999"
tags:
  - "cs.CR"
  - "security"
timestamp: "2026-10-01T00:00:00Z"
provenance:
  source: "arxiv.org"
  raw_meta_file: "test.json"
  published_date: "2026-10-01"
  authors:

trust:
  attestation: "processed_by: arxiv-security-agent"
  confidence: "high"
---

# Test Paper
"""
    data = parse_okf_frontmatter(raw_md)
    assert data.get("title") == "Test Security Paper"
    assert data.get("title_ja") == "テストセキュリティ論文"
    assert data.get("description") == "テスト用の概要です。"
    assert "cs.CR" in data.get("tags", [])


def test_parse_frontmatter_regex_fallback():
    # Intentionally malformed YAML that violates strict PEG but can be recovered
    malformed_md = """---
type: "security-paper"
title: "Malformed Title With Odd Char"
title_ja: "変則タイトルの日本語"
description: "フォールバックで抽出される要約"
resource: "https://arxiv.org/abs/2609.11111"
tags:
  - "cs.CR"
timestamp: "2026-10-01T12:00:00Z"
invalid_indent_key:
  - item:
---
# Content
"""
    data = parse_okf_frontmatter(malformed_md)
    assert data.get("title") == "Malformed Title With Odd Char"
    assert data.get("title_ja") == "変則タイトルの日本語"
    assert data.get("description") == "フォールバックで抽出される要約"


def test_mermaid_mindmap_node_syntax():
    rendered = _render_mindmap_node("AI/LLM セキュリティ", 15)
    # Must be valid mindmap node syntax: `["label"]`, NOT `id["label"]`
    assert rendered.strip().startswith('["')
    assert rendered.strip().endswith('"]')
    assert "node_" not in rendered
    assert "topic[" not in rendered


def test_mermaid_mindmap_tree_structure():
    cluster = TopicCluster(
        cluster_id="cluster_quantum",
        label="量子暗号",
        keywords=("量子", "暗号"),
        score=1.0,
        document_ids=("p1", "p2"),
    )
    papers = [
        {"title": "Paper 1", "title_ja": "論文1"},
        {"title": "Paper 2", "title_ja": "論文2"},
    ]
    tree = _build_mermaid_mindmap_tree([(cluster, papers)], "2026-10-01")
    assert "mindmap" in tree
    assert 'root["セキュリティ動向 (2026-10-01)"]' in tree
    assert '["量子暗号 (2件)"]' in tree
    assert '["論文1"]' in tree
    assert "node_" not in tree
