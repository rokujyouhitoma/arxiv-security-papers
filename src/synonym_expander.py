#!/usr/bin/env python3
"""
Security Domain Synonym & Terminology Expander
Expands Japanese & English cybersecurity terms, abbreviations, and technical concepts for improved IR recall.
Inspired by synonym_expander.js in registered-information-security-specialist-examination repository.
"""

import re


class SynonymExpander:
    SYNONYM_GROUPS = [
        # Penetration Testing & Exploitation
        {"ペンテスト", "ペネトレーションテスト", "侵入テスト", "penetration testing", "penetration-testing", "pentest", "exploit", "exploitability", "atobench"},
        
        # Autonomous Vehicles & Automotive Security
        {"自動運転", "自動運転車", "自動運転車両", "autonomous vehicle", "autonomous vehicles", "autonomous driving", "autoware", "av"},

        # Malware & Threat Analysis
        {"マルウェア", "マルウェア検出", "悪意のあるソフトウェア", "malware", "ransomware", "trojan", "spyware", "rootkit", "botnet"},

        # Cryptography & Quantum Security
        {"暗号", "暗号解読", "耐量子暗号", "公開鍵暗号", "cryptography", "crypto", "post-quantum", "pqc", "lattice-based", "encryption"},

        # LLM & AI Security
        {"llm", "大言語モデル", "大規模言語モデル", "生成ai", "large language model", "prompt injection", "jailbreak", "rag", "agent"},

        # Vulnerabilities & Threat Modeling
        {"脆弱性", "弱点", "脅威分析", "vulnerability", "vulnerabilities", "weakness", "stride", "cwe", "cve", "mitre"},

        # Zero Trust & IAM
        {"ゼロトラスト", "アイデンティティ管理", "zero trust", "zero-trust", "iam", "oauth", "pkce", "pdp", "pep"},

        # Network & Infrastructure
        {"ネットワーク", "トポロジ", "ファイアウォール", "侵入検知", "network", "topology", "firewall", "ids", "ips", "sdn"}
    ]

    def __init__(self):
        # Build lookup table mapping each token to its full synonym set
        self.lookup = {}
        for group in self.SYNONYM_GROUPS:
            for term in group:
                term_lower = term.lower()
                if term_lower not in self.lookup:
                    self.lookup[term_lower] = set()
                self.lookup[term_lower].update({t.lower() for t in group})

    def expand_token(self, token):
        """Expands a single token into its synonyms."""
        token_lower = token.lower()
        if token_lower in self.lookup:
            return set(self.lookup[token_lower])
        return {token_lower}

    def expand_query(self, query):
        """Expands a query string into a comprehensive list of tokens including synonyms."""
        if not query:
            return []

        # Extract tokens from query
        raw_tokens = re.findall(r'[a-zA-Z0-9_\-]+', query.lower())
        ja_tokens = re.findall(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]+', query)
        
        all_raw = set(raw_tokens + ja_tokens + [query.strip().lower()])
        expanded = set(all_raw)

        for token in all_raw:
            expanded.update(self.expand_token(token))
            # Also check if token matches substring in lookup
            for term in self.lookup:
                if term in token or token in term:
                    expanded.update(self.lookup[term])

        return list(expanded)


if __name__ == "__main__":
    expander = SynonymExpander()
    test_queries = ["ペンテスト自動化", "自動運転の脆弱性", "暗号"]
    for q in test_queries:
        print(f"Query: '{q}' -> Expanded: {expander.expand_query(q)}")
