"""Dynamic Context and Dependency Injection Foundation for NLP Subsystem.

Provides thread-safe and async-safe dynamic variable scoping backed by
`pylisp.dynvar.DynamicVar` and immutable configuration dataclasses.
Supports 3-tier fallback resolution:
  Level 1: Explicit argument (Constructor Injection)
  Level 2: Task-local dynamic scope (CURRENT_*.value)
  Level 3: Immutable built-in defaults

Complies with Xenon CC <= 3 (Rank A), zero external dependencies, and mypy strict.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import (
    TYPE_CHECKING,
    AbstractSet,
    Dict,
    FrozenSet,
    Optional,
    Sequence,
    Tuple,
)

from pylisp.dynvar import DynamicVar

if TYPE_CHECKING:
    from nlp.lexicon.security_thesaurus import SecurityThesaurus


# -------------------------------------------------------------------------
# Immutable Configuration Dataclasses
# -------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class DiscourseMarkerConfig:
    """Immutable configuration for discourse markers and rhetorical patterns."""

    threat_markers: Tuple[str, ...]
    proposal_markers: Tuple[str, ...]
    impact_markers: Tuple[str, ...]
    negation_patterns: Tuple[str, ...]
    prior_work_patterns: Tuple[str, ...]
    modality_boosters: Tuple[str, ...]

    def __post_init__(self) -> None:
        """Validate pattern constraints to prevent pathological inputs."""
        max_pat_len = 256
        all_patterns = (
            self.threat_markers
            + self.proposal_markers
            + self.impact_markers
            + self.negation_patterns
            + self.prior_work_patterns
            + self.modality_boosters
        )
        for pat in all_patterns:
            if len(pat) > max_pat_len:
                raise ValueError(
                    f"Pattern exceeds maximum allowed length of {max_pat_len}: {pat[:32]}..."
                )


@dataclass(frozen=True, slots=True)
class SynthesizerRuleConfig:
    """Immutable configuration for structured 3-point summary synthesis."""

    keyword_translations: Tuple[Tuple[str, str], ...]
    phrase_replacements: Tuple[Tuple[str, str], ...]
    threat_default_text: str = "既存システムのセキュリティ境界における脆弱性課題"
    prop_default_template: str = "{j_title}の提案フレームワーク"
    impact_default_text: str = "実験的評価による防御性能と攻撃耐性の実証"
    executive_template: str = "【提案】{prop}。実証評価により{impact}。"


# -------------------------------------------------------------------------
# Default Lexicons, Vocabularies, and Rules (Level 3 Fallbacks)
# -------------------------------------------------------------------------

_DEFAULT_SECURITY_TRANSLATIONS: Dict[str, str] = {
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

_DEFAULT_SYNONYM_GROUPS: Tuple[Tuple[str, ...], ...] = (
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

_EN_STOPWORDS = (
    "a",
    "about",
    "above",
    "after",
    "again",
    "against",
    "all",
    "am",
    "an",
    "and",
    "any",
    "are",
    "aren't",
    "as",
    "at",
    "be",
    "because",
    "been",
    "before",
    "being",
    "below",
    "between",
    "both",
    "but",
    "by",
    "can't",
    "cannot",
    "could",
    "couldn't",
    "did",
    "didn't",
    "do",
    "does",
    "doesn't",
    "doing",
    "don't",
    "down",
    "during",
    "each",
    "few",
    "for",
    "from",
    "further",
    "had",
    "hadn't",
    "has",
    "hasn't",
    "have",
    "haven't",
    "having",
    "he",
    "her",
    "here",
    "hers",
    "herself",
    "him",
    "himself",
    "his",
    "how",
    "i",
    "if",
    "in",
    "into",
    "is",
    "isn't",
    "it",
    "it's",
    "its",
    "itself",
    "just",
    "me",
    "more",
    "most",
    "my",
    "myself",
    "no",
    "nor",
    "not",
    "now",
    "of",
    "off",
    "on",
    "once",
    "only",
    "or",
    "other",
    "our",
    "ours",
    "ourselves",
    "out",
    "over",
    "own",
    "same",
    "she",
    "should",
    "shouldn't",
    "so",
    "some",
    "such",
    "than",
    "that",
    "the",
    "their",
    "theirs",
    "them",
    "themselves",
    "then",
    "there",
    "these",
    "they",
    "this",
    "those",
    "through",
    "to",
    "too",
    "under",
    "until",
    "up",
    "very",
    "was",
    "wasn't",
    "we",
    "were",
    "weren't",
    "what",
    "when",
    "where",
    "which",
    "while",
    "who",
    "whom",
    "why",
    "with",
    "won't",
    "would",
    "wouldn't",
    "you",
    "your",
    "yours",
    "yourself",
)

_JA_STOPWORDS = (
    "これ",
    "それ",
    "あれ",
    "この",
    "その",
    "あの",
    "ここ",
    "そこ",
    "あそこ",
    "こちら",
    "どこ",
    "だれ",
    "なに",
    "なん",
    "私",
    "僕",
    "自分",
    "ため",
    "こと",
    "もの",
    "とき",
    "よう",
    "そう",
    "ほう",
    "など",
    "および",
    "また",
    "しかし",
    "ただし",
    "さらに",
    "について",
    "において",
    "における",
    "による",
    "として",
    "とともに",
    "から",
    "まで",
    "より",
    "へ",
    "に",
    "で",
    "を",
    "と",
    "の",
    "が",
    "は",
    "も",
    "や",
    "ね",
    "よ",
    "である",
    "です",
    "ます",
    "だ",
    "た",
    "ない",
    "れる",
    "られる",
    "せる",
    "させる",
)

_ACADEMIC_NOISE = (
    "paper",
    "study",
    "propose",
    "proposed",
    "method",
    "approach",
    "framework",
    "evaluation",
    "evaluate",
    "evaluated",
    "result",
    "results",
    "analysis",
    "experiment",
    "experimental",
    "author",
    "authors",
    "work",
    "novel",
    "present",
    "presents",
    "presented",
    "demonstrate",
    "demonstrates",
    "show",
    "shows",
    "本論文",
    "提案",
    "手法",
    "研究",
    "評価",
    "実験",
    "結果",
    "考察",
    "モデル",
    "システム",
)

_DEFAULT_STOPWORDS: FrozenSet[str] = frozenset(
    set(_EN_STOPWORDS) | set(_JA_STOPWORDS) | set(_ACADEMIC_NOISE)
)

_DEFAULT_GRAMMAR_ENTRIES: Tuple[Tuple[str, int, str], ...] = (
    ("は", 20, "助詞"),
    ("が", 20, "助詞"),
    ("の", 15, "助詞"),
    ("に", 20, "助詞"),
    ("を", 20, "助詞"),
    ("で", 20, "助詞"),
    ("と", 20, "助詞"),
    ("から", 30, "助詞"),
    ("より", 30, "助詞"),
    ("へ", 30, "助詞"),
    ("も", 25, "助詞"),
    ("や", 25, "助詞"),
    ("である", 30, "助動詞"),
    ("です", 30, "助動詞"),
    ("ます", 30, "助動詞"),
    ("だ", 30, "助動詞"),
    ("た", 30, "助動詞"),
    ("ない", 40, "助動詞"),
    ("れる", 40, "助動詞"),
    ("られる", 40, "助動詞"),
    ("せる", 40, "助動詞"),
    ("させる", 40, "助動詞"),
    ("また", 40, "接続詞"),
    ("しかし", 40, "接続詞"),
    ("および", 40, "接続詞"),
    ("さらに", 40, "接続詞"),
    ("防ぐ", 50, "動詞"),
    ("行う", 50, "動詞"),
    ("用いる", 50, "動詞"),
    ("示す", 50, "動詞"),
    ("新しい", 60, "形容詞"),
    ("高い", 60, "形容詞"),
    ("低い", 60, "形容詞"),
    ("手法", 40, "名詞"),
    ("研究", 40, "名詞"),
    ("評価", 40, "名詞"),
    ("技術", 40, "名詞"),
    ("モデル", 40, "名詞"),
    ("システム", 40, "名詞"),
)

_DEFAULT_DISCOURSE_MARKERS = DiscourseMarkerConfig(
    threat_markers=(
        "vulnerab",
        "threat",
        "attack",
        "exploit",
        "leak",
        "risk",
        "flaw",
        "problem",
        "challenge",
        "bypass",
        "poison",
        "jailbreak",
        "side-channel",
        "fault injection",
        "malware",
        "compromise",
        "adversar",
    ),
    proposal_markers=(
        "propose",
        "present",
        "introduce",
        "develop",
        "design",
        "framework",
        "architecture",
        "mechanism",
        "approach",
        "scheme",
        "protocol",
        "system",
        "tool",
        "algorithm",
        "pipeline",
    ),
    impact_markers=(
        "result",
        "evaluat",
        "demonstrat",
        "experiment",
        "achiev",
        "outperform",
        "effective",
        "accuracy",
        "overhead",
        "mitigat",
        "reduc",
        "prevent",
        "success rate",
    ),
    negation_patterns=(
        r"\bnot\b",
        r"\bnever\b",
        r"\bcannot\b",
        r"\bcan't\b",
        r"\bfail(?:s|ed|ing)? to\b",
        r"\bdespite\b",
        r"\bwithout\b",
        r"\bneither\b",
        r"\bno longer\b",
        r"\bunable to\b",
        r"\blacks?\b",
    ),
    prior_work_patterns=(
        r"\bprior work\b",
        r"\bexisting (?:methods?|studies|approaches|tools?|systems?|solutions?)\b",
        r"\btraditionally\b",
        r"\bconventionally\b",
        r"\bprevious literature\b",
        r"\bstate-of-the-art\b",
        r"\bpast work\b",
        r"\bearlier work\b",
        r"\bmost existing\b",
    ),
    modality_boosters=(
        r"\bempirically prove\b",
        r"\bdemonstrate(?:s|d)?\b",
        r"\boutperform(?:s|ed)?\b",
        r"\bachieve(?:s|d)?\b",
        r"\breduce(?:s|d)?\s+.*?\s+by\b",
        r"\b\d+(?:\.\d+)?%\b",
        r"\bsignificant(?:ly)?\b",
        r"\brobust(?:ness)?\b",
    ),
)

_DEFAULT_SYNTHESIZER_RULES = SynthesizerRuleConfig(
    keyword_translations=(
        ("prompt injection", "プロンプトインジェクション"),
        ("jailbreak", "ジェイルブレイク"),
        ("side-channel", "サイドチャネル攻撃"),
        ("fault injection", "フォールト注入"),
        ("zero-trust", "ゼロトラスト"),
        ("differential privacy", "差分プライバシー"),
        ("smart contract", "スマートコントラクト"),
        ("malware", "マルウェア"),
        ("rowhammer", "RowHammer"),
        ("quantum", "量子"),
        ("cryptography", "暗号技術"),
        ("vulnerability", "脆弱性"),
        ("adversarial attack", "敵対的攻撃"),
        ("denial of service", "サービス拒否攻撃"),
        ("access control", "アクセス制御"),
        ("post-quantum", "耐量子計算機暗号"),
    ),
    phrase_replacements=(
        ("in this paper, we", "本論文では"),
        ("we propose", "新規に提案し"),
        ("we present", "提示し"),
        ("we design", "設計し"),
        ("we develop", "開発し"),
        ("we introduce", "導入し"),
        ("we evaluate", "評価し"),
        ("our results show that", "検証結果として"),
        ("in this work,", "本研究では"),
    ),
)

_DEFAULT_TOPIC_DOMAINS: Tuple[Tuple[str, Tuple[str, ...]], ...] = (
    (
        "AI/LLM セキュリティ & 敵対的攻撃",
        (
            "llm",
            "prompt injection",
            "jailbreak",
            "agent",
            "adversarial",
            "rag",
            "poisoning",
            "backdoor",
        ),
    ),
    (
        "ハードウェア & 低レイヤ物理セキュリティ",
        (
            "rowhammer",
            "fault injection",
            "dram",
            "hardware",
            "side-channel",
            "spectre",
            "meltdown",
        ),
    ),
    (
        "量子暗号 & ゼロ知識証明技術",
        (
            "quantum",
            "qkd",
            "post-quantum",
            "lattice",
            "zero-knowledge",
            "cryptography",
            "pqc",
            "zkp",
        ),
    ),
    (
        "ソフトウェア脆弱性 & Web3/DeFi",
        (
            "smart contract",
            "defi",
            "blockchain",
            "vulnerability",
            "fuzzing",
            "malware",
            "exploit",
        ),
    ),
    (
        "ネットワークセキュリティ & 通信耐障害性",
        ("network", "ipsec", "ddos", "traffic", "quic", "routing", "firewall", "dns"),
    ),
    (
        "プライバシー保護 & 匿名化技術",
        (
            "privacy",
            "anonymity",
            "differential privacy",
            "federated learning",
            "tracking",
        ),
    ),
)

_DEFAULT_ABBREVIATIONS: Tuple[Tuple[str, str], ...] = (
    ("et al.", "et al\ue001"),
    ("e.g.", "e\ue001g\ue001"),
    ("i.e.", "i\ue001e\ue001"),
    ("etc.", "etc\ue001"),
    ("cf.", "cf\ue001"),
    ("vs.", "vs\ue001"),
    ("approx.", "approx\ue001"),
    ("viz.", "viz\ue001"),
    ("al.", "al\ue001"),
)


# -------------------------------------------------------------------------
# DynamicVar Definitions (Level 2 Dynamic Scope)
# -------------------------------------------------------------------------

CURRENT_SECURITY_TRANSLATIONS: DynamicVar[Dict[str, str]] = DynamicVar(
    "SECURITY_TRANSLATIONS", _DEFAULT_SECURITY_TRANSLATIONS
)

CURRENT_SYNONYM_GROUPS: DynamicVar[Tuple[Tuple[str, ...], ...]] = DynamicVar(
    "SYNONYM_GROUPS", _DEFAULT_SYNONYM_GROUPS
)

CURRENT_THESAURUS: DynamicVar[Optional[SecurityThesaurus]] = DynamicVar(
    "THESAURUS", None
)

CURRENT_STOPWORDS: DynamicVar[FrozenSet[str]] = DynamicVar(
    "STOPWORDS", _DEFAULT_STOPWORDS
)

CURRENT_GRAMMAR_ENTRIES: DynamicVar[Tuple[Tuple[str, int, str], ...]] = DynamicVar(
    "GRAMMAR_ENTRIES", _DEFAULT_GRAMMAR_ENTRIES
)

CURRENT_DISCOURSE_MARKERS: DynamicVar[DiscourseMarkerConfig] = DynamicVar(
    "DISCOURSE_MARKERS", _DEFAULT_DISCOURSE_MARKERS
)

CURRENT_SYNTHESIZER_RULES: DynamicVar[SynthesizerRuleConfig] = DynamicVar(
    "SYNTHESIZER_RULES", _DEFAULT_SYNTHESIZER_RULES
)

CURRENT_TOPIC_DOMAINS: DynamicVar[Tuple[Tuple[str, Tuple[str, ...]], ...]] = DynamicVar(
    "TOPIC_DOMAINS", _DEFAULT_TOPIC_DOMAINS
)

CURRENT_ABBREVIATIONS: DynamicVar[Tuple[Tuple[str, str], ...]] = DynamicVar(
    "ABBREVIATIONS", _DEFAULT_ABBREVIATIONS
)


# -------------------------------------------------------------------------
# 3-Tier Fallback Resolvers (Pure Helper Functions, CC <= 3)
# -------------------------------------------------------------------------


def resolve_thesaurus(
    explicit: Optional[SecurityThesaurus] = None,
) -> SecurityThesaurus:
    """Resolve SecurityThesaurus via 3-tier fallback."""
    if explicit is not None:
        return explicit
    dyn = CURRENT_THESAURUS.value
    if dyn is not None:
        return dyn
    from nlp.lexicon.security_thesaurus import SecurityThesaurus

    return SecurityThesaurus()


def resolve_stopwords(
    explicit: Optional[AbstractSet[str]] = None,
) -> AbstractSet[str]:
    """Resolve stopwords set via 3-tier fallback."""
    if explicit is not None:
        return explicit
    return CURRENT_STOPWORDS.value


def resolve_grammar_entries(
    explicit: Optional[Sequence[Tuple[str, int, str]]] = None,
) -> Sequence[Tuple[str, int, str]]:
    """Resolve grammar entries via 3-tier fallback."""
    if explicit is not None:
        return explicit
    return CURRENT_GRAMMAR_ENTRIES.value


def resolve_discourse_markers(
    explicit: Optional[DiscourseMarkerConfig] = None,
) -> DiscourseMarkerConfig:
    """Resolve discourse markers configuration via 3-tier fallback."""
    if explicit is not None:
        return explicit
    return CURRENT_DISCOURSE_MARKERS.value


def resolve_synthesizer_rules(
    explicit: Optional[SynthesizerRuleConfig] = None,
) -> SynthesizerRuleConfig:
    """Resolve synthesizer rules configuration via 3-tier fallback."""
    if explicit is not None:
        return explicit
    return CURRENT_SYNTHESIZER_RULES.value


def resolve_topic_domains(
    explicit: Optional[Sequence[Tuple[str, Sequence[str]]]] = None,
) -> Sequence[Tuple[str, Sequence[str]]]:
    """Resolve canonical topic domain map via 3-tier fallback."""
    if explicit is not None:
        return explicit
    return CURRENT_TOPIC_DOMAINS.value


def resolve_abbreviations(
    explicit: Optional[Sequence[Tuple[str, str]]] = None,
) -> Sequence[Tuple[str, str]]:
    """Resolve abbreviation mapping via 3-tier fallback."""
    if explicit is not None:
        return explicit
    return CURRENT_ABBREVIATIONS.value
