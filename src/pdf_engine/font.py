"""Font decoding, ToUnicode CMap, and encoding converters conforming to ISO 32000-1 Clause 9.6-9.10."""

import re
from typing import Any, Dict, List, Optional

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


def _parse_bfchar_block(block: str, mapping: Dict[int, str]) -> None:
    for match in re.finditer(r"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>", block):
        src_code = int(match.group(1), 16)
        dst_hex = match.group(2)
        try:
            mapping[src_code] = bytes.fromhex(dst_hex).decode(
                "utf-16-be", errors="replace"
            )
        except Exception:
            pass


def _parse_bfrange_block(block: str, mapping: Dict[int, str]) -> None:
    for match in re.finditer(
        r"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>", block
    ):
        _decode_single_bfrange(match, mapping)

    for match in re.finditer(
        r"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\[(.*?)\]", block, re.DOTALL
    ):
        _decode_array_bfrange(match, mapping)


def _decode_single_bfrange(match: re.Match[str], mapping: Dict[int, str]) -> None:
    start = int(match.group(1), 16)
    end = int(match.group(2), 16)
    dst_hex_str = match.group(3)
    dst_base_int = int(dst_hex_str, 16)
    hex_len = len(dst_hex_str)

    for offset in range(end - start + 1):
        cur_val = dst_base_int + offset
        if cur_val < 0x110000 and hex_len <= 4:
            try:
                mapping[start + offset] = chr(cur_val)
            except ValueError:
                pass
        else:
            try:
                raw_b = cur_val.to_bytes((hex_len + 1) // 2, "big")
                mapping[start + offset] = raw_b.decode("utf-16-be", errors="replace")
            except Exception:
                pass


def _decode_array_bfrange(match: re.Match[str], mapping: Dict[int, str]) -> None:
    start = int(match.group(1), 16)
    end = int(match.group(2), 16)
    dest_list = re.findall(r"<([0-9A-Fa-f]+)>", match.group(3))
    for offset, dst_hex in enumerate(dest_list):
        if start + offset <= end:
            try:
                mapping[start + offset] = bytes.fromhex(dst_hex).decode(
                    "utf-16-be", errors="replace"
                )
            except Exception:
                pass


class ToUnicodeParser:
    """Parses PostScript-style /ToUnicode CMap stream definitions (ISO 32000-1 Clause 9.10.2)."""

    @staticmethod
    def parse(cmap_data: bytes) -> Dict[int, str]:
        mapping: Dict[int, str] = {}
        text = cmap_data.decode("latin1", errors="ignore")

        for block in re.findall(r"beginbfchar(.*?)endbfchar", text, re.DOTALL):
            _parse_bfchar_block(block, mapping)

        for block in re.findall(r"beginbfrange(.*?)endbfrange", text, re.DOTALL):
            _parse_bfrange_block(block, mapping)

        return mapping


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
            if isinstance(item, int):
                cur_code = item
            elif isinstance(item, str):
                glyph_name = item.lstrip("/")
                char_val = STANDARD_AGL.get(glyph_name, glyph_name)
                self.differences_map[cur_code] = char_val
                cur_code += 1

    def decode_bytes(self, raw_bytes: bytes) -> str:
        """Decodes raw character byte sequences using ToUnicode -> Differences -> Latin1 hierarchy."""
        if not raw_bytes:
            return ""

        # 1. 2-byte CID lookup if ToUnicode map contains multi-byte keys
        if any(k > 255 for k in self.to_unicode_map) and len(raw_bytes) % 2 == 0:
            return self._decode_2byte_cid(raw_bytes)

        # 2. 1-byte character code lookup
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
