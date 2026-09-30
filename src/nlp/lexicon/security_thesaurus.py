"""Security Domain Thesaurus and Bilingual Translation Dictionary.

Provides authoritative cybersecurity terminology mapping, synonym expansion,
and canonical term normalization across MITRE ATT&CK, CWE, STRIDE, cryptography,
and AI security. Zero external dependencies and Xenon CC <= 3.
"""

from typing import Dict, Optional, Sequence, Set, Tuple

from nlp.core.context import (
    _DEFAULT_SECURITY_TRANSLATIONS,
    _DEFAULT_SYNONYM_GROUPS,
    CURRENT_SECURITY_TRANSLATIONS,
    CURRENT_SYNONYM_GROUPS,
)

# Backward-compatible module constants
_EN_TO_JA_DICT: Dict[str, str] = _DEFAULT_SECURITY_TRANSLATIONS
_SYNONYM_GROUPS: Tuple[Tuple[str, ...], ...] = _DEFAULT_SYNONYM_GROUPS


class SecurityThesaurus:
    """Cybersecurity Thesaurus and Synonym Engine supporting DI and 3-tier fallback."""

    def __init__(
        self,
        translations: Optional[Dict[str, str]] = None,
        synonym_groups: Optional[Sequence[Sequence[str]]] = None,
    ) -> None:
        """Initialize and index synonym mapping table with DI fallback."""
        raw_trans = (
            translations
            if translations is not None
            else CURRENT_SECURITY_TRANSLATIONS.value
        )
        raw_groups = (
            synonym_groups
            if synonym_groups is not None
            else CURRENT_SYNONYM_GROUPS.value
        )
        self._translations: Dict[str, str] = dict(raw_trans)
        self._term_to_group: Dict[str, Tuple[str, ...]] = {}
        for group in raw_groups:
            group_tuple = tuple(group)
            for term in group_tuple:
                self._term_to_group[term.lower()] = group_tuple

    def lookup_japanese(self, term: str) -> Optional[str]:
        """Lookup Japanese translation for English security term."""
        if not term:
            return None
        cleaned = term.strip().lower()
        return self._translations.get(cleaned)

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

    def get_translations(self) -> Dict[str, str]:
        """Return a copy of the English-to-Japanese mapping dictionary."""
        return self._translations.copy()

    def items(self) -> Tuple[Tuple[str, str], ...]:
        """Return tuple of (english_term, japanese_translation) pairs."""
        return tuple(self._translations.items())

    def get_all_vocabulary(self) -> Tuple[str, ...]:
        """Return all indexed security terms across languages."""
        vocab: Set[str] = set(self._translations.keys()) | set(
            self._translations.values()
        )
        for group in self._term_to_group.values():
            vocab.update(group)
        return tuple(sorted(vocab))
