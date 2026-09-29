"""Pure-Python Morphological Analyzer and Viterbi Tokenizer.

Implements zero-dependency minimum-cost path segmentation using dynamic
programming (Viterbi forward algorithm) backed by PrefixTrie and
domain-specific cybersecurity lexicon.
Guaranteed linear O(N) runtime and Xenon CC <= 3 (Rank A).
"""

from typing import List, Optional, Tuple

from nlp.core.protocols import MorphologicalAnalyzerSPI, TokenizerSPI
from nlp.core.tokens import Morpheme, Span, Token
from nlp.lexicon.security_thesaurus import SecurityThesaurus
from nlp.morphology.trie import PrefixTrie

# Default Japanese grammar vocabulary (surface, cost, pos)
_GRAMMAR_ENTRIES: Tuple[Tuple[str, int, str], ...] = (
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

_MAX_UNKNOWN_LEN = 32
_INF_COST = 1_000_000_000


_CJK_RANGES = (
    (0x4E00, 0x9FFF, 1),  # Kanji
    (0x3040, 0x309F, 2),  # Hiragana
    (0x30A0, 0x30FF, 3),  # Katakana
)


def _is_cjk_kind(code: int) -> int:
    """Return 1 for Kanji, 2 for Hiragana, 3 for Katakana, 0 otherwise."""
    for low, high, kind in _CJK_RANGES:
        if low <= code <= high:
            return kind
    return 0


def _char_kind(char: str) -> int:
    """Return character kind category index (1:Kanji, 2:Hira, 3:Kata, 4:Alnum, 0:Other)."""
    cjk = _is_cjk_kind(ord(char))
    if cjk != 0:
        return cjk
    if char.isalnum() or char in "_-":
        return 4
    return 0


def _unknown_cost_and_pos(kind: int) -> Tuple[int, str]:
    """Map character kind to default cost and part-of-speech tag."""
    if kind == 3:  # Katakana
        return 80, "名詞(カタカナ)"
    if kind == 4:  # Alphanumeric
        return 70, "名詞(英数)"
    if kind == 1:  # Kanji
        return 100, "名詞(漢字)"
    return 150, "未知語"


def _extract_unknown_span(text: str, start: int) -> Tuple[int, int, str]:
    """Extract contiguous span of same character kind up to limit."""
    kind = _char_kind(text[start])
    limit = min(len(text), start + _MAX_UNKNOWN_LEN)
    end = start + 1
    while end < limit and _char_kind(text[end]) == kind:
        end += 1
    cost, pos = _unknown_cost_and_pos(kind)
    return end, cost, pos


def _build_default_trie() -> PrefixTrie:
    """Construct PrefixTrie populated with grammar and security vocabularies."""
    trie = PrefixTrie()
    for surface, cost, pos in _GRAMMAR_ENTRIES:
        trie.insert(surface, (cost, pos))

    thesaurus = SecurityThesaurus()
    for term in thesaurus.get_all_vocabulary():
        # Security terms given high priority (low cost = 10)
        trie.insert(term, (10, "名詞(セキュリティ)"))
    return trie


class PureMorphTokenizer(MorphologicalAnalyzerSPI, TokenizerSPI):
    """Zero-dependency Viterbi-based morphological analyzer and tokenizer."""

    def __init__(self, trie: Optional[PrefixTrie] = None) -> None:
        """Initialize tokenizer with trie dictionary."""
        self._trie = trie if trie is not None else _build_default_trie()

    def parse(self, text: str) -> List[Morpheme]:
        """Segment Japanese/English text into a list of Morpheme instances."""
        tokens = self.tokenize(text)
        return [
            Morpheme(
                surface=t.text,
                pos=t.tag if t.tag else "名詞",
                base_form=t.text,
            )
            for t in tokens
        ]

    def tokenize(self, text: str) -> List[Token]:
        """Tokenize text into linguistic Token objects with accurate character spans."""
        if not text:
            return []
        spans = self._viterbi_segment(text)
        return [
            Token(
                text=text[start:end],
                span=Span(start, end),
                tag=tag,
            )
            for start, end, tag in spans
        ]

    def _collect_step_candidates(
        self, text: str, pos: int
    ) -> List[Tuple[int, int, str]]:
        """Collect all matching candidates from pos as (end_pos, cost, pos_tag)."""
        candidates: List[Tuple[int, int, str]] = []
        matches = self._trie.common_prefix_search(text, pos)
        for word, val in matches:
            cost, tag = val if isinstance(val, tuple) else (50, "名詞")
            candidates.append((pos + len(word), cost, tag))

        unk_end, unk_cost, unk_tag = _extract_unknown_span(text, pos)
        candidates.append((unk_end, unk_cost, unk_tag))
        return candidates

    def _viterbi_segment(self, text: str) -> List[Tuple[int, int, str]]:
        """Compute minimum-cost lattice segmentation path."""
        n = len(text)
        min_cost = [0] + [_INF_COST] * n
        prev_node: List[Optional[Tuple[int, str]]] = [None] * (n + 1)

        for i in range(n):
            if min_cost[i] == _INF_COST:
                continue
            candidates = self._collect_step_candidates(text, i)
            for end, cost, tag in candidates:
                new_cost = min_cost[i] + cost
                if new_cost < min_cost[end]:
                    min_cost[end] = new_cost
                    prev_node[end] = (i, tag)

        return self._reconstruct_path(prev_node, n)

    def _reconstruct_path(
        self, prev_node: List[Optional[Tuple[int, str]]], n: int
    ) -> List[Tuple[int, int, str]]:
        """Backtrack through optimal path from end to start."""
        spans: List[Tuple[int, int, str]] = []
        curr = n
        while curr > 0:
            step = prev_node[curr]
            if step is None:
                spans.append((curr - 1, curr, "記号"))
                curr -= 1
                continue
            prev_pos, tag = step
            spans.append((prev_pos, curr, tag))
            curr = prev_pos
        spans.reverse()
        return spans
