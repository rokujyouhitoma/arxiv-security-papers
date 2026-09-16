"""Font decoding, ToUnicode CMap, and encoding converters conforming to ISO 32000-1 Clause 9.6-9.10."""

import threading
from typing import Any, Dict, List, Optional

from core.structures.peg import PEGSyntaxError
from pdf_engine.generated_cmap_parser import PDFCMapParser

# Standard Adobe Glyph List (AGL) sample mappings for common font characters
STANDARD_AGL: Dict[str, str] = {
    "space": " ",
    "exclam": "!",
    "quotedbl": '"',
    "numbersign": "#",
    "dollar": "$",
    "percent": "%",
    "ampersand": "&",
    "quotesingle": "'",
    "parenleft": "(",
    "parenright": ")",
    "asterisk": "*",
    "plus": "+",
    "comma": ",",
    "hyphen": "-",
    "period": ".",
    "slash": "/",
    "colon": ":",
    "semicolon": ";",
    "less": "<",
    "equal": "=",
    "greater": ">",
    "question": "?",
    "at": "@",
    "bracketleft": "[",
    "backslash": "\\",
    "bracketright": "]",
    "asciicircum": "^",
    "underscore": "_",
    "grave": "`",
    "braceleft": "{",
    "bar": "|",
    "braceright": "}",
    "asciitilde": "~",
    "endash": "–",
    "emdash": "—",
    "quoteleft": "‘",
    "quoteright": "’",
    "quotedblleft": "“",
    "quotedblright": "”",
    "bullet": "•",
    "dagger": "†",
    "ddagger": "‡",
    "section": "§",
    "paragraph": "¶",
    "copyright": "©",
    "registered": "®",
    "trademark": "™",
    "plusminus": "±",
    "degree": "°",
    "minus": "-",
    "multiply": "×",
    "divide": "÷",
    "approxequal": "≈",
    "notequal": "≠",
    "lessequal": "≤",
    "greaterequal": "≥",
    "infinity": "∞",
    "partialdiff": "∂",
    "summation": "∑",
    "product": "∏",
    "integral": "∫",
    "alpha": "α",
    "beta": "β",
    "gamma": "γ",
    "delta": "δ",
    "epsilon": "ε",
    "theta": "θ",
    "lambda": "λ",
    "mu": "μ",
    "pi": "π",
    "sigma": "σ",
    "tau": "τ",
    "phi": "φ",
    "omega": "ω",
    "Delta": "Δ",
    "Gamma": "Γ",
    "Lambda": "Λ",
    "Sigma": "Σ",
    "Omega": "Ω",
    "fi": "fi",
    "fl": "fl",
    "ff": "ff",
    "ffi": "ffi",
    "ffl": "ffl",
    "oplus": "⊕",
    "otimes": "⊗",
    "leftarrow": "←",
    "rightarrow": "→",
    "subset": "⊂",
    "subseteq": "⊆",
    "element": "∈",
    "notelement": "∉",
    "forall": "∀",
    "exists": "∃",
    "xor": "⊕",
    "land": "∧",
    "lor": "∨",
    "neg": "¬",
    "perp": "⊥",
    "cdot": "·",
    "equiv": "≡",
}


LIGATURE_MAP: Dict[str, str] = {
    "\ufb00": "ff",
    "\ufb01": "fi",
    "\ufb02": "fl",
    "\ufb03": "ffi",
    "\ufb04": "ffl",
    "\ufb05": "ft",
    "\ufb06": "st",
}


_cmap_parser_lock = threading.Lock()
_global_cmap_parser: Optional[PDFCMapParser] = None


def _get_cmap_parser() -> PDFCMapParser:
    """Thread-safe singleton getter for PDFCMapParser."""
    global _global_cmap_parser
    if _global_cmap_parser is None:
        with _cmap_parser_lock:
            if _global_cmap_parser is None:
                _global_cmap_parser = PDFCMapParser()
    return _global_cmap_parser


def _has_cmap_markers(text: str) -> bool:
    return "beginbfchar" in text or "beginbfrange" in text


def _parse_cmap_text(text: str) -> Dict[int, str]:
    try:
        parser = _get_cmap_parser()
        result = parser.parse(text)
        return result if isinstance(result, dict) else {}
    except PEGSyntaxError:
        return {}


class ToUnicodeParser:
    """Parses PostScript-style /ToUnicode CMap stream definitions (ISO 32000-1 Clause 9.10.2)."""

    @staticmethod
    def parse(cmap_data: bytes) -> Dict[int, str]:
        text = cmap_data.decode("latin1", errors="ignore")
        if not _has_cmap_markers(text):
            return {}
        return _parse_cmap_text(text)


class FontDecoder:
    """Translates raw character codes from content streams into normalized UTF-8 text."""

    def __init__(
        self, font_dict: Dict[str, Any], to_unicode_map: Optional[Dict[int, str]] = None
    ) -> None:
        self.font_dict = font_dict
        self.to_unicode_map = to_unicode_map or {}
        self.differences_map: Dict[int, str] = {}
        self._init_differences()

    def _init_differences(self) -> None:
        encoding = self.font_dict.get("/Encoding")
        if not isinstance(encoding, dict):
            return
        diffs = encoding.get("/Differences")
        if not isinstance(diffs, list):
            return

        cur_code = 0
        for item in diffs:
            cur_code = self._process_diff_item(item, cur_code)

    def _process_diff_item(self, item: Any, cur_code: int) -> int:
        if isinstance(item, int):
            return item
        if isinstance(item, str):
            glyph_name = item.lstrip("/")
            self.differences_map[cur_code] = STANDARD_AGL.get(glyph_name, glyph_name)
            return cur_code + 1
        return cur_code

    def _is_2byte_cid(self, raw_bytes: bytes) -> bool:
        return any(k > 255 for k in self.to_unicode_map) and len(raw_bytes) % 2 == 0

    def decode_bytes(self, raw_bytes: bytes) -> str:
        """Decodes raw character byte sequences using ToUnicode -> Differences -> Latin1 hierarchy."""
        if not raw_bytes:
            return ""

        if self._is_2byte_cid(raw_bytes):
            return self._decode_2byte_cid(raw_bytes)

        chars = [self._decode_single_byte(b) for b in raw_bytes]
        return self._normalize_text("".join(chars))

    def _decode_2byte_cid(self, raw_bytes: bytes) -> str:
        chars: List[str] = []
        for i in range(0, len(raw_bytes), 2):
            cid = int.from_bytes(raw_bytes[i : i + 2], "big")
            if cid in self.to_unicode_map:
                chars.append(self.to_unicode_map[cid])
            else:
                chars.append(chr(cid) if cid < 0x110000 else "?")
        return self._normalize_text("".join(chars))

    def _decode_single_byte(self, b: int) -> str:
        if b in self.to_unicode_map:
            return self.to_unicode_map[b]
        if b in self.differences_map:
            return self.differences_map[b]
        if 32 <= b <= 126:
            return chr(b)
        return chr(b) if b < 256 else "?"

    @staticmethod
    def _normalize_text(text: str) -> str:
        res = text
        for lig, repl in LIGATURE_MAP.items():
            if lig in res:
                res = res.replace(lig, repl)
        return res
