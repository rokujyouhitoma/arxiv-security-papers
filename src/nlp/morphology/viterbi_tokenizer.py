"""Pure-Python Morphological Analyzer and Viterbi Tokenizer.

Implements zero-dependency minimum-cost path segmentation using dynamic
programming (Viterbi forward algorithm) backed by PrefixTrie and
domain-specific cybersecurity lexicon.
Guaranteed linear O(N) runtime and Xenon CC <= 3 (Rank A).
"""

from typing import List, Optional, Sequence, Tuple

from nlp.core.context import (
    _DEFAULT_GRAMMAR_ENTRIES,
    resolve_grammar_entries,
    resolve_thesaurus,
)
from nlp.core.protocols import MorphologicalAnalyzerSPI, TokenizerSPI
from nlp.core.tokens import Morpheme, Span, Token
from nlp.lexicon.security_thesaurus import SecurityThesaurus
from nlp.morphology.trie import PrefixTrie

# Default Japanese grammar vocabulary (surface, cost, pos)
_GRAMMAR_ENTRIES: Tuple[Tuple[str, int, str], ...] = _DEFAULT_GRAMMAR_ENTRIES


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


def _build_default_trie(
    grammar_entries: Optional[Sequence[Tuple[str, int, str]]] = None,
    thesaurus: Optional[SecurityThesaurus] = None,
) -> PrefixTrie:
    """Construct PrefixTrie populated with grammar and security vocabularies."""
    trie = PrefixTrie()
    entries = resolve_grammar_entries(grammar_entries)
    for surface, cost, pos in entries:
        trie.insert(surface, (cost, pos))

    active_thesaurus = resolve_thesaurus(thesaurus)
    for term in active_thesaurus.get_all_vocabulary():
        # Security terms given high priority (low cost = 10)
        trie.insert(term, (10, "名詞(セキュリティ)"))
    return trie


def _is_default_morph_context() -> bool:
    """Return True if dynamic morph context matches default constants."""
    from nlp.core.context import (
        _DEFAULT_GRAMMAR_ENTRIES,
        _DEFAULT_SECURITY_TRANSLATIONS,
        _DEFAULT_SYNONYM_GROUPS,
        CURRENT_GRAMMAR_ENTRIES,
        CURRENT_SECURITY_TRANSLATIONS,
        CURRENT_SYNONYM_GROUPS,
        CURRENT_THESAURUS,
    )

    flags = (
        CURRENT_THESAURUS.value is None,
        CURRENT_GRAMMAR_ENTRIES.value is _DEFAULT_GRAMMAR_ENTRIES,
        CURRENT_SECURITY_TRANSLATIONS.value is _DEFAULT_SECURITY_TRANSLATIONS,
        CURRENT_SYNONYM_GROUPS.value is _DEFAULT_SYNONYM_GROUPS,
    )
    return all(flags)


class PureMorphTokenizer(MorphologicalAnalyzerSPI, TokenizerSPI):
    """Zero-dependency Viterbi-based morphological analyzer and tokenizer."""

    def __init__(
        self,
        trie: Optional[PrefixTrie] = None,
        grammar_entries: Optional[Sequence[Tuple[str, int, str]]] = None,
        thesaurus: Optional[SecurityThesaurus] = None,
    ) -> None:
        """Initialize tokenizer with optional trie, grammar entries, or thesaurus."""
        self._explicit_trie: Optional[PrefixTrie] = trie
        if trie is None and (grammar_entries is not None or thesaurus is not None):
            self._explicit_trie = _build_default_trie(grammar_entries, thesaurus)
        self._cached_default_trie: Optional[PrefixTrie] = None

    def _get_active_trie(self) -> PrefixTrie:
        """Return the active PrefixTrie using 3-tier fallback."""
        if self._explicit_trie is not None:
            return self._explicit_trie
        if not _is_default_morph_context():
            return _build_default_trie()
        if self._cached_default_trie is None:
            self._cached_default_trie = _build_default_trie()
        return self._cached_default_trie

    @property
    def _trie(self) -> PrefixTrie:
        """Backward-compatible trie accessor."""
        return self._get_active_trie()

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
