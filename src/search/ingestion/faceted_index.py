#!/usr/bin/env python3
"""
Faceted and Temporal Index for Fast Bitmap/Set Boolean Filtering.
"""

from collections import defaultdict
from typing import Dict, List, Optional, Set

CATEGORY_ALIASES: Dict[str, List[str]] = {
    "pentest": [
        "ペネトレーションテスト・脆弱性検証",
        "pentest",
        "penetration",
        "exploit",
        "侵入テスト",
        "ファジング・脆弱性調査",
    ],
    "malware": [
        "マルウェア・脅威解析",
        "malware",
        "ransomware",
        "botnet",
        "マルウェア",
        "ランサムウェア",
    ],
    "autonomous": [
        "自動運転・車載セキュリティ",
        "autonomous",
        "autoware",
        "can bus",
        "自動運転",
    ],
    "llm": [
        "llm・aiセキュリティ",
        "llm",
        "jailbreak",
        "prompt injection",
        "大言語モデル",
        "生成ai",
    ],
    "crypto": [
        "暗号・プライバシー技術",
        "crypto",
        "cryptography",
        "pqc",
        "暗号",
    ],
    "fuzzing": [
        "ファジング・脆弱性調査",
        "fuzzing",
        "vulnerability",
        "脆弱性",
    ],
    "zero-trust": [
        "ゼロトラスト・アクセス制御",
        "zero-trust",
        "zerotrust",
        "ゼロトラスト",
    ],
    "zerotrust": [
        "ゼロトラスト・アクセス制御",
        "zero-trust",
        "zerotrust",
        "ゼロトラスト",
    ],
    "iot": [
        "サイドチャネル・組込みセキュリティ",
        "iot",
        "side-channel",
        "サイドチャネル",
    ],
}


class FacetedIndex:
    """
    Faceted and Temporal Index for Fast Bitmap/Set Boolean Filtering.
    """

    def __init__(self) -> None:
        self.years: Dict[str, Set[str]] = defaultdict(set)
        self.categories: Dict[str, Set[str]] = defaultdict(set)
        self.tags: Dict[str, Set[str]] = defaultdict(set)
        self.domains: Dict[str, Set[str]] = defaultdict(set)

    def _add_single_tag(self, tag: str, doc_id: str) -> None:
        t_clean = tag.strip().lower()
        if t_clean.startswith("cs."):
            self.categories[t_clean].add(doc_id)
        else:
            self.tags[t_clean].add(doc_id)

    def add_document(
        self,
        doc_id: str,
        published_date: str,
        tags: List[str],
        annotated_keywords: List[str],
    ) -> None:
        if published_date and len(published_date) >= 4:
            self.years[published_date[:4]].add(doc_id)

        for t in tags:
            self._add_single_tag(t, doc_id)

        for kw in annotated_keywords:
            self.domains[kw.strip().lower()].add(doc_id)

    def _intersect_candidates(
        self, candidates: Optional[Set[str]], target_docs: Set[str]
    ) -> Set[str]:
        if candidates is None:
            return target_docs
        return candidates & target_docs

    def _filter_facet(
        self,
        val: Optional[str],
        mapping: Dict[str, Set[str]],
        candidates: Optional[Set[str]],
    ) -> Optional[Set[str]]:
        if not val:
            return candidates
        clean_val = val.strip().lower()
        target_docs = mapping.get(clean_val, set())
        return self._intersect_candidates(candidates, target_docs)

    def _lookup_exact_facets(self, term: str) -> Set[str]:
        matched: Set[str] = set()
        for facet_map in (self.categories, self.tags, self.domains):
            matched.update(facet_map.get(term, ()))
        return matched

    def _collect_alias_matches(self, clean_val: str) -> Set[str]:
        matched: Set[str] = set()
        for alias in CATEGORY_ALIASES.get(clean_val, []):
            matched.update(self._lookup_exact_facets(alias.strip().lower()))
        return matched

    def _fallback_domain_matches(self, clean_val: str) -> Set[str]:
        matched: Set[str] = set()
        for domain_key, docs in self.domains.items():
            if clean_val in domain_key:
                matched.update(docs)
        return matched

    def resolve_category_candidates(self, category_val: str) -> Set[str]:
        """Resolves candidate document IDs matching category, domain, or tag."""
        if not category_val:
            return set()
        clean_val = category_val.strip().lower()
        matched = self._lookup_exact_facets(clean_val)
        matched.update(self._collect_alias_matches(clean_val))
        if not matched:
            matched.update(self._fallback_domain_matches(clean_val))
        return matched

    def filter(
        self,
        year: Optional[str] = None,
        category: Optional[str] = None,
        tag: Optional[str] = None,
        domain: Optional[str] = None,
    ) -> Optional[Set[str]]:
        candidates: Optional[Set[str]] = None
        if year and year in self.years:
            candidates = set(self.years[year])

        if category:
            cat_docs = self.resolve_category_candidates(category)
            candidates = self._intersect_candidates(candidates, cat_docs)

        candidates = self._filter_facet(tag, self.tags, candidates)
        candidates = self._filter_facet(domain, self.domains, candidates)

        return candidates
