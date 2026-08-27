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

    def evaluate_source(
        self, source_type: str, metadata: Optional[Dict[str, Any]] = None
    ) -> tuple[AdmiraltyReliability, str]:
        """Evaluates source reliability based on origin and provenance metadata."""
        meta = metadata or {}
        st = str(source_type).lower()
        venue = str(meta.get("venue", meta.get("journal", ""))).lower()

        if self._is_top_venue(venue) or any(
            k in st for k in ["advisory", "cve", "cert", "nvd"]
        ):
            return (
                AdmiraltyReliability.A,
                "公的セキュリティ機関・公式アドバイザリまたは査読トップ会議",
            )

        source_map = [
            (
                ["arxiv", "iacr", "eprint"],
                AdmiraltyReliability.B,
                "arXiv / IACR 学術プレプリントリポジトリ",
            ),
            (
                ["github", "gitlab", "poc"],
                AdmiraltyReliability.C,
                "コミュニティ公開リポジトリ・PoCコード",
            ),
            (
                ["blog", "medium", "twitter", "x.com"],
                AdmiraltyReliability.D,
                "未検証ブログ・ソーシャルメディア",
            ),
        ]
        for keywords, rel, reason in source_map:
            if any(k in st for k in keywords):
                return rel, reason

        return AdmiraltyReliability.F, "未分類・新規情報ソース"

    def _check_confirmed_or_proven(
        self, t: str, meta: Dict[str, Any]
    ) -> Optional[tuple[AdmiraltyCredibility, str]]:
        """Checks for Level 1 (Confirmed) and Level 2 (Proven) credibility."""
        if bool(re.search(r"cve-\d{4}-\d{4,7}", t)) and (
            bool(re.search(r"cwe-\d{1,5}", t)) or meta.get("verified_by_other_sources")
        ):
            return (
                AdmiraltyCredibility.ONE,
                "CVE/CWE 公式識別子および独立検証所見の一致を確認",
            )

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

    def evaluate_content(
        self, text: str, metadata: Optional[Dict[str, Any]] = None
    ) -> tuple[AdmiraltyCredibility, str]:
        """Evaluates information credibility based on textual rigorousness and verification markers."""
        meta = metadata or {}
        t = text.lower()

        top_tier = self._check_confirmed_or_proven(t, meta)
        if top_tier:
            return top_tier

        has_bench = bool(
            re.search(r"benchmark|empirical|evaluation|dataset|precision|f1-score", t)
        )
        if has_bench or "experiment" in t or "attack demonstration" in t:
            return (
                AdmiraltyCredibility.THREE,
                "実証実験データまたは攻撃デモ観測所見あり",
            )
        if "speculative" in t or "untested" in t or "potential" in t:
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
