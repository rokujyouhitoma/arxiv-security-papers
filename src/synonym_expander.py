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
        {
            "ペンテスト", "ペネトレーションテスト", "侵入テスト", "脆弱性検証", "エクスプロイト",
            "penetration testing", "penetration-testing", "pentest", "exploit", "exploitability", "atobench"
        },

        # Autonomous Vehicles & Automotive Security
        {
            "自動運転", "自動運転車", "自動運転車両", "車載ネットワーク", "canバス",
            "autonomous vehicle", "autonomous vehicles", "autonomous driving", "autoware", "av"
        },

        # Malware & Threat Analysis
        {
            "マルウェア", "マルウェア検出", "マルウェア解析", "悪意のあるソフトウェア", "ランサムウェア", "身代金型", "ボットネット",
            "malware", "ransomware", "trojan", "spyware", "rootkit", "botnet", "virus"
        },

        # Cryptography, Quantum & Privacy
        {
            "暗号", "暗号解読", "耐量子暗号", "公開鍵暗号", "同態暗号", "ホモモルフィック暗号", "ゼロ知識証明", "差分プライバシー",
            "cryptography", "crypto", "post-quantum", "pqc", "lattice-based", "encryption", "homomorphic", "zkp", "zero-knowledge", "differential privacy"
        },

        # LLM & AI Security
        {
            "llm", "大言語モデル", "大規模言語モデル", "生成ai", "脱獄", "プロンプトインジェクション", "モデル抽出", "ポイズニング", "アドバーサリアル攻撃", "敵対的サンプル",
            "large language model", "prompt injection", "jailbreak", "rag", "agent", "adversarial attack", "poisoning", "backdoor"
        },

        # Vulnerabilities, Web & Threat Modeling
        {
            "脆弱性", "弱点", "脅威分析", "脅威モデリング", "ファジング", "クロスサイトスクリプティング", "sqlインジェクション",
            "vulnerability", "vulnerabilities", "weakness", "stride", "cwe", "cve", "cvss", "mitre", "mitre att&ck", "fuzzing", "xss", "sqli", "injection"
        },

        # Zero Trust & IAM
        {
            "ゼロトラスト", "アイデンティティ管理", "アクセス制御", "権限昇格",
            "zero trust", "zero-trust", "iam", "oauth", "pkce", "pdp", "pep", "access control", "privilege escalation"
        },

        # Network, System & Hardware Security
        {
            "ネットワーク", "トポロジ", "ファイアウォール", "侵入検知", "サイドチャネル", "サイドチャネル攻撃", "マイクロアーキテクチャ", "ファームウェア", "iot", "組み込みセキュリティ",
            "network", "topology", "firewall", "ids", "ips", "sdn", "side-channel", "microarchitecture", "firmware", "iot"
        }
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
        if not token:
            return set()
        token_lower = token.lower()
        if token_lower in self.lookup:
            return set(self.lookup[token_lower])
        return {token_lower}

    def expand_query(self, query):
        """Expands a query string into a comprehensive list of tokens including synonyms."""
        if not query:
            return []

        query_clean = query.strip().lower()
        # Extract tokens from query
        raw_tokens = re.findall(r'[a-zA-Z0-9_\-]+', query_clean)
        ja_tokens = re.findall(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]+', query)

        all_raw = set(raw_tokens + ja_tokens + [query_clean])
        expanded = set(all_raw)

        for token in all_raw:
            expanded.update(self.expand_token(token))
            # Substring matching against lookup
            for term in self.lookup:
                if term in token or token in term:
                    expanded.update(self.lookup[term])

        return [t for t in expanded if t]


if __name__ == "__main__":
    expander = SynonymExpander()
    test_queries = ["マルウェア解析", "LLM脱獄", "ファジング", "サイドチャネル"]
    for q in test_queries:
        print(f"Query: '{q}' -> Expanded: {expander.expand_query(q)}")
