"""Admiralty System Credibility Scoring Engine (NATO STANAG 2022 Compliant).

Evaluates source reliability (A to F) and information credibility (1 to 6),
calculates multidimensional compound credibility scores, and provides audit justifications.
"""

import re
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


class AdmiraltyReliability(str, Enum):
    """Source Reliability Rating (NATO STANAG 2022 / Joint Intelligence)."""

    A = "A"  # Completely reliable (Peer-reviewed top venue, NIST, official advisory)
    B = "B"  # Usually reliable (arXiv, IACR ePrint with verified affiliation)
    C = "C"  # Fairly reliable (Community-verified PoC, reputable GitHub repo)
    D = "D"  # Not usually reliable (Unverified blog, social media)
    E = "E"  # Unreliable (Known misinformation or compromised source)
    F = "F"  # Reliability cannot be judged (New or uncategorized source)


class AdmiraltyCredibility(str, Enum):
    """Information Credibility Rating (NATO STANAG 2022 / Joint Intelligence)."""

    ONE = "1"  # Confirmed by other independent sources (Multiple independent proofs, CVE/NVD entry)
    TWO = "2"  # Probably true (Mathematical proof, formal verification, rigorous methodology)
    THREE = "3"  # Possibly true (Empirical benchmark, limited reproduction)
    FOUR = "4"  # Doubtfully true (Conflicting evidence, missing ablation/dataset)
    FIVE = "5"  # Improbable (Theoretical contradiction, refuted claims)
    SIX = "6"  # Truth cannot be judged (Insufficient data to evaluate)


@dataclass
class AdmiraltyRating:
    """Full Admiralty Code rating and mathematical credibility score."""

    reliability: AdmiraltyReliability
    credibility: AdmiraltyCredibility
    score: float  # Compound numerical score in [0.01, 1.0]
    justification: str  # 100% Japanese detailed rationale
    metadata: Dict[str, Any] = field(default_factory=dict)

    @property
    def code(self) -> str:
        return f"{self.reliability.value}{self.credibility.value}"


class AdmiraltyEngine:
    """Multidimensional credibility assessment engine."""

    # Weights for Source Reliability (A -> 1.0, B -> 0.85, C -> 0.65, D -> 0.40, E -> 0.10, F -> 0.50)
    RELIABILITY_WEIGHTS: Dict[AdmiraltyReliability, float] = {
        AdmiraltyReliability.A: 1.00,
        AdmiraltyReliability.B: 0.85,
        AdmiraltyReliability.C: 0.65,
        AdmiraltyReliability.D: 0.40,
        AdmiraltyReliability.E: 0.10,
        AdmiraltyReliability.F: 0.50,
    }

    # Weights for Information Credibility (1 -> 1.0, 2 -> 0.85, 3 -> 0.65, 4 -> 0.40, 5 -> 0.10, 6 -> 0.50)
    CREDIBILITY_WEIGHTS: Dict[AdmiraltyCredibility, float] = {
        AdmiraltyCredibility.ONE: 1.00,
        AdmiraltyCredibility.TWO: 0.85,
        AdmiraltyCredibility.THREE: 0.65,
        AdmiraltyCredibility.FOUR: 0.40,
        AdmiraltyCredibility.FIVE: 0.10,
        AdmiraltyCredibility.SIX: 0.50,
    }

    def _is_top_venue(self, venue: str) -> bool:
        top_venues = [
            "ieee s&p",
            "acm ccs",
            "usenix",
            "ndss",
            "crypto",
            "eurocrypt",
            "nist",
        ]
        return any(v in venue for v in top_venues)

    def _is_advisory_source(self, st: str) -> bool:
        return any(k in st for k in ["advisory", "cve", "cert", "nvd"])

    def _check_official_source(
        self, st: str, venue: str
    ) -> Optional[tuple[AdmiraltyReliability, str]]:
        if self._is_top_venue(venue) or self._is_advisory_source(st):
            return (
                AdmiraltyReliability.A,
                "公的セキュリティ機関・公式アドバイザリまたは査読トップ会議",
            )
        return None

    def _lookup_source_map(self, st: str) -> Optional[tuple[AdmiraltyReliability, str]]:
        source_map = [
            (
                ["arxiv", "iacr", "eprint"],
                AdmiraltyReliability.B,
                "arXiv / IACR \u5b66\u8853\u30d7\u30ec\u30d7\u30ea\u30f3\u30c8\u30ea\u30dd\u30b8\u30c8\u30ea",
            ),
            (
                ["github", "gitlab", "poc"],
                AdmiraltyReliability.C,
                "\u30b3\u30df\u30e5\u30cb\u30c6\u30a3\u516c\u958b"
                "\u30ea\u30dd\u30b8\u30c8\u30ea\u30fbPoC\u30b3\u30fc\u30c9",
            ),
            (
                ["blog", "medium", "twitter", "x.com"],
                AdmiraltyReliability.D,
                "\u672a\u691c\u8a3c\u30d6\u30ed\u30b0\u30fb\u30bd\u30fc\u30b7\u30e3\u30eb\u30e1\u30c7\u30a3\u30a2",
            ),
        ]
        for keywords, rel, reason in source_map:
            if any(k in st for k in keywords):
                return rel, reason
        return None

    def evaluate_source(
        self, source_type: str, metadata: Optional[Dict[str, Any]] = None
    ) -> tuple[AdmiraltyReliability, str]:
        """Evaluates source reliability based on origin and provenance metadata."""
        meta = metadata or {}
        st = str(source_type).lower()
        venue = str(meta.get("venue", meta.get("journal", ""))).lower()

        official = self._check_official_source(st, venue)
        if official:
            return official

        mapped = self._lookup_source_map(st)
        if mapped:
            return mapped

        return (
            AdmiraltyReliability.F,
            "\u672a\u5206\u985e\u30fb\u65b0\u898f\u60c5\u5831\u30bd\u30fc\u30b9",
        )

    def _check_cve_confirmed(
        self, t: str, meta: Dict[str, Any]
    ) -> Optional[tuple[AdmiraltyCredibility, str]]:
        is_cve = bool(re.search(r"cve-\d{4}-\d{4,7}", t))
        has_cwe = bool(re.search(r"cwe-\d{1,5}", t))
        if is_cve and (has_cwe or meta.get("verified_by_other_sources")):
            return (
                AdmiraltyCredibility.ONE,
                "CVE/CWE 公式識別子および独立検証所見の一致を確認",
            )
        return None

    def _check_proven_evidence(
        self, t: str
    ) -> Optional[tuple[AdmiraltyCredibility, str]]:
        has_proof = bool(
            re.search(r"theorem|proof|formal\s+verification|reduction\s+to", t)
        )
        has_bench = bool(
            re.search(r"benchmark|empirical|evaluation|dataset|precision|f1-score", t)
        )
        if has_proof or (has_bench and "methodology" in t):
            return (
                AdmiraltyCredibility.TWO,
                "数理的・形式的証明または厳密な評価メトリクスに基づく検証",
            )
        return None

    def _check_confirmed_or_proven(
        self, t: str, meta: Dict[str, Any]
    ) -> Optional[tuple[AdmiraltyCredibility, str]]:
        """Checks for Level 1 (Confirmed) and Level 2 (Proven) credibility."""
        return self._check_cve_confirmed(t, meta) or self._check_proven_evidence(t)

    def _check_experimental_content(
        self, t: str
    ) -> Optional[tuple[AdmiraltyCredibility, str]]:
        has_bench = bool(
            re.search(r"benchmark|empirical|evaluation|dataset|precision|f1-score", t)
        )
        if has_bench or "experiment" in t or "attack demonstration" in t:
            return (
                AdmiraltyCredibility.THREE,
                "実証実験データまたは攻撃デモ観測所見あり",
            )
        return None

    def _is_speculative(self, t: str) -> bool:
        return "speculative" in t or "untested" in t or "potential" in t

    def evaluate_content(
        self, text: str, metadata: Optional[Dict[str, Any]] = None
    ) -> tuple[AdmiraltyCredibility, str]:
        """Evaluates information credibility based on textual rigorousness and verification markers."""
        meta = metadata or {}
        t = text.lower()

        top_tier = self._check_confirmed_or_proven(t, meta)
        if top_tier:
            return top_tier

        experimental = self._check_experimental_content(t)
        if experimental:
            return experimental

        if self._is_speculative(t):
            return AdmiraltyCredibility.FOUR, "推測的記述または実証データ不足"

        return AdmiraltyCredibility.SIX, "確実性を判断するための技術的証拠が不十分"

    def rate_record(self, record: Dict[str, Any]) -> AdmiraltyRating:
        """Rates an intelligence or paper record across both Admiralty dimensions."""
        source = str(record.get("source", record.get("origin", "unknown")))
        text = (
            str(record.get("title", ""))
            + " "
            + str(record.get("summary", ""))
            + " "
            + str(record.get("raw_text", ""))
        )
        metadata = record.get("metadata", {})

        rel, rel_reason = self.evaluate_source(source, metadata)
        cred, cred_reason = self.evaluate_content(text, metadata)

        w_rel = self.RELIABILITY_WEIGHTS[rel]
        w_cred = self.CREDIBILITY_WEIGHTS[cred]
        compound_score = round(w_rel * w_cred, 3)

        justification = f"情報源信頼性: [{rel.value}] ({rel_reason}) / 情報確実性: [{cred.value}] ({cred_reason})"

        return AdmiraltyRating(
            reliability=rel,
            credibility=cred,
            score=compound_score,
            justification=justification,
            metadata={"source_weight": w_rel, "credibility_weight": w_cred},
        )

    def rate_all(self, records: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Applies Admiralty rating to a batch of records and updates their dictionaries."""
        for r in records:
            rating = self.rate_record(r)
            r["admiralty_code"] = rating.code
            r["admiralty_score"] = rating.score
            r["admiralty_justification"] = rating.justification
        return records

    def generate_matrix_markdown(self) -> str:
        """Generates a complete Japanese Markdown table of the NATO STANAG 2022 Admiralty Matrix."""
        lines = [
            "# 🎖️ NATO STANAG 2022 Admiralty 信憑性評価マトリクス",
            "",
            "## 1. 情報源信頼性 (Source Reliability: A〜F)",
            "",
            "| 区分 | 信頼性定義 | 該当ソース例 | 基礎重み |",
            "| :---: | :--- | :--- | :---: |",
            (
                "| **A** | **完全な信頼性 (Completely Reliable)** | "
                "査読トップ会議 (IEEE S&P, USENIX, ACM CCS, NDSS), NIST, 公式Advisory | 1.00 |"
            ),
            "| **B** | **概ね信頼可能 (Usually Reliable)** | arXiv, IACR ePrint (所属機関確認済み学術プレプリント) | 0.85 |",
            "| **C** | **一定の信頼性 (Fairly Reliable)** | コミュニティ検証済み PoC, 知名 GitHub リポジトリ | 0.65 |",
            "| **D** | **通常は信頼できない (Not Usually Reliable)** | 個人技術ブログ, 未検証ソーシャルメディア投稿 | 0.40 |",
            "| **E** | **信頼性なし (Unreliable)** | 既知の誤情報源, 悪意ある改ざんソース | 0.10 |",
            "| **F** | **信頼性判断不能 (Reliability Cannot Be Judged)** | 新規・未分類情報ソース | 0.50 |",
            "",
            "## 2. 情報確実性 (Information Credibility: 1〜6)",
            "",
            "| 区分 | 確実性定義 | 判定基準 | 基礎重み |",
            "| :---: | :--- | :--- | :---: |",
            "| **1** | **独立ソースにより確認済 (Confirmed)** | 複数独立ソースで検証一致, CVE/NVD 公式登録, 再現PoC実証済 | 1.00 |",
            "| **2** | **おそらく真実 (Probably True)** | 数理的・形式的証明あり, 厳格なベンチマーク評価メトリクス | 0.85 |",
            "| **3** | **真実である可能性あり (Possibly True)** | 限定的実験データまたは攻撃デモ観測所見あり | 0.65 |",
            "| **4** | **真実性に疑義あり (Doubtfully True)** | 矛盾する記述あり, 実験不備・推測的記述 | 0.40 |",
            "| **5** | **真実とは考えにくい (Improbable)** | 理論的矛盾, 反証済み主張 | 0.10 |",
            "| **6** | **確実性判断不能 (Truth Cannot Be Judged)** | 確実性を判断するための技術的証拠不足 | 0.50 |",
            "",
            "## 3. 複合信憑性スコア計算式",
            "",
            "$$\\text{Score} = w_{\\text{reliability}} \\times w_{\\text{credibility}} \\in [0.01, 1.00]$$",
            "- **最上位 (A1)**: $1.00 \\times 1.00 = 1.00$",
            "- **学術標準 (B2)**: $0.85 \\times 0.85 = 0.72$",
            "- **コミュニティPoC (C1/C3)**: $0.65 \\times 1.00 = 0.65$ / $0.65 \\times 0.65 = 0.42$",
            "- **未評価 (F6)**: $0.50 \\times 0.50 = 0.25$",
        ]
        return "\n".join(lines)
