"""Security Domain Thesaurus and Bilingual Translation Dictionary.

Provides authoritative cybersecurity terminology mapping, synonym expansion,
and canonical term normalization across MITRE ATT&CK, CWE, STRIDE, cryptography,
and AI security. Zero external dependencies and Xenon CC <= 3.
"""

from typing import Dict, Optional, Set, Tuple

# Mapping from English term to canonical Japanese translation
_EN_TO_JA_DICT: Dict[str, str] = {
    "side-channel attack": "サイドチャネル攻撃",
    "side channel attack": "サイドチャネル攻撃",
    "fault injection": "フォールト注入攻撃",
    "fault attack": "フォールト攻撃",
    "prompt injection": "プロンプトインジェクション",
    "jailbreak": "ジェイルブレイク",
    "zero-trust": "ゼロトラスト",
    "zero trust": "ゼロトラスト",
    "differential privacy": "差分プライバシー",
    "smart contract": "スマートコントラクト",
    "malware": "マルウェア",
    "ransomware": "ランサムウェア",
    "rowhammer": "RowHammer",
    "post-quantum cryptography": "ポスト量子暗号",
    "quantum key distribution": "量子鍵配送",
    "zero-knowledge proof": "ゼロ知識証明",
    "homomorphic encryption": "準同型暗号",
    "lattice-based cryptography": "格子暗号",
    "buffer overflow": "バッファオーバーフロー",
    "privilege escalation": "権限昇格",
    "remote code execution": "リモートコード実行",
    "memory safety": "メモリ安全性",
    "supply chain attack": "サプライチェーン攻撃",
    "denial of service": "サービス運用妨害",
    "man-in-the-middle": "中間者攻撃",
    "adversarial example": "敵対的サンプル",
    "model poisoning": "モデル汚染",
    "model inversion": "モデル反転攻撃",
    "vulnerability": "脆弱性",
    "threat": "脅威",
    "exploit": "エクスプロイト",
    "cryptography": "暗号技術",
}

# Synonym groups (cluster of mutually equivalent terms)
_SYNONYM_GROUPS: Tuple[Tuple[str, ...], ...] = (
    (
        "side-channel attack",
        "side channel attack",
        "サイドチャネル攻撃",
        "サイドチャネル",
    ),
    ("fault injection", "fault attack", "フォールト注入攻撃", "フォールト注入"),
    ("prompt injection", "プロンプトインジェクション", "プロンプト注入"),
    ("jailbreak", "ジェイルブレイク", "脱獄"),
    ("zero-trust", "zero trust", "ゼロトラスト"),
    ("differential privacy", "差分プライバシー"),
    ("post-quantum cryptography", "pqc", "ポスト量子暗号", "量子耐性暗号"),
    ("quantum key distribution", "qkd", "量子鍵配送"),
    ("zero-knowledge proof", "zkp", "ゼロ知識証明"),
    ("homomorphic encryption", "fhe", "準同型暗号", "完全準同型暗号"),
    ("remote code execution", "rce", "リモートコード実行"),
    ("buffer overflow", "バッファオーバーフロー"),
    ("privilege escalation", "権限昇格"),
    ("memory safety", "メモリ安全性"),
    ("supply chain attack", "サプライチェーン攻撃"),
    ("adversarial example", "敵対的サンプル", "敵対的例"),
)


class SecurityThesaurus:
    """Cybersecurity Thesaurus and Synonym Engine."""

    def __init__(self) -> None:
        """Initialize and index synonym mapping table."""
        self._term_to_group: Dict[str, Tuple[str, ...]] = {}
        for group in _SYNONYM_GROUPS:
            for term in group:
                self._term_to_group[term.lower()] = group

    def lookup_japanese(self, term: str) -> Optional[str]:
        """Lookup Japanese translation for English security term."""
        if not term:
            return None
        cleaned = term.strip().lower()
        return _EN_TO_JA_DICT.get(cleaned)

    def get_synonyms(self, term: str) -> Tuple[str, ...]:
        """Return tuple of synonym variants for term, excluding term itself."""
        if not term:
            return ()
        cleaned = term.strip().lower()
        group = self._term_to_group.get(cleaned)
        if not group:
            return ()
        return tuple(s for s in group if s.lower() != cleaned)

    def get_canonical_term(self, term: str) -> str:
        """Return the primary canonical term for a given synonym."""
        if not term:
            return ""
        cleaned = term.strip().lower()
        group = self._term_to_group.get(cleaned)
        if not group:
            return term
        return group[0]

    def get_all_vocabulary(self) -> Tuple[str, ...]:
        """Return all indexed security terms across languages."""
        vocab: Set[str] = set(_EN_TO_JA_DICT.keys()) | set(_EN_TO_JA_DICT.values())
        for group in _SYNONYM_GROUPS:
            vocab.update(group)
        return tuple(sorted(vocab))
