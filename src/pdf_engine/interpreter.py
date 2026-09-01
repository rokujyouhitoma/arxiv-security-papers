"""Content Stream text operator interpreter conforming to ISO 32000-1 Clause 8.3 & 9.2-9.4."""

from typing import Any, Callable, Dict, List

from .contracts import GlyphBox, PdfPage
from .font import FontDecoder
from .parser import PdfParser


class TextInterpreter:
    """Interprets PDF content streams and tracks 2D glyph bounding boxes."""

    def __init__(self, page: PdfPage) -> None:
        self.page = page
        self.font_decoders: Dict[str, FontDecoder] = page.resources.get(
            "_font_decoders", {}
        )
        self.glyphs: List[GlyphBox] = []

        # Text State Machine Variables (ISO 32000-1 Clause 9.3)
        self.active_font: str = ""
        self.font_size: float = 12.0
        self.leading: float = 12.0
        self.char_spacing: float = 0.0
        self.word_spacing: float = 0.0
        self.horiz_scale: float = 100.0

        # Transformation Matrices [a, b, c, d, e, f]
        self.tm: List[float] = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
        self.tlm: List[float] = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]

    def extract_glyphs(self) -> List[GlyphBox]:
        """Parses all content streams for this page and returns extracted glyphs."""
        self.glyphs.clear()
        for content_stream in self.page.contents:
            if not content_stream:
                continue
            self._execute_stream(content_stream)
        return self.glyphs

    def _parse_next_stream_token(self, parser: PdfParser, stack: List[Any]) -> bool:
        parser.lexer.skip_whitespace_and_comments()
        if parser.lexer.pos >= parser.lexer.length:
            return False

        obj = parser.parse_object()
        if obj is None:
            return False

        if isinstance(obj, str) and not obj.startswith("/"):
            self._dispatch_operator(obj, stack)
            stack.clear()
        else:
            stack.append(obj)
        return True

    def _execute_stream(self, data: bytes) -> None:
        parser = PdfParser(data)
        stack: List[Any] = []
        while self._parse_next_stream_token(parser, stack):
            pass

    def _dispatch_operator(self, op: str, stack: List[Any]) -> None:
        dispatch_table: Dict[str, Callable[[], None]] = {
            "BT": self._handle_bt,
            "Tf": lambda: self._handle_tf(stack),
            "Tm": lambda: self._handle_tm(stack),
            "Td": lambda: self._handle_td(stack, set_leading=False),
            "TD": lambda: self._handle_td(stack, set_leading=True),
            "T*": self._handle_tstar,
            "'": lambda: (self._handle_tstar(), self._handle_tj(stack)),
            "TL": lambda: self._set_state_param("leading", stack),
            "Tc": lambda: self._set_state_param("char_spacing", stack),
            "Tw": lambda: self._set_state_param("word_spacing", stack),
            "Tz": lambda: self._set_state_param("horiz_scale", stack),
            "Tj": lambda: self._handle_tj(stack),
            "TJ": lambda: self._handle_tj_array(stack),
            '"': lambda: self._handle_double_quote(stack),
        }
        handler = dispatch_table.get(op)
        if handler:
            handler()

    def _set_state_param(self, attr_name: str, stack: List[Any]) -> None:
        if stack and isinstance(stack[0], (int, float)):
            setattr(self, attr_name, float(stack[0]))

    def _handle_double_quote(self, stack: List[Any]) -> None:
        if len(stack) >= 3:
            self.word_spacing = float(stack[0])
            self.char_spacing = float(stack[1])
            self._handle_tstar()
            self._handle_tj(stack[2:])

    def _handle_bt(self) -> None:
        self.tm = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
        self.tlm = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]

    def _handle_tf(self, stack: List[Any]) -> None:
        if len(stack) >= 2:
            self.active_font = str(stack[0])
            try:
                self.font_size = float(stack[1])
            except (ValueError, TypeError):
                self.font_size = 12.0

    def _handle_tm(self, stack: List[Any]) -> None:
        if len(stack) >= 6:
            try:
                m = [float(x) for x in stack[:6]]
                self.tm = list(m)
                self.tlm = list(m)
            except (ValueError, TypeError):
                pass

    def _handle_td(self, stack: List[Any], set_leading: bool) -> None:
        if len(stack) >= 2:
            try:
                tx = float(stack[0])
                ty = float(stack[1])
                if set_leading:
                    self.leading = -ty
                # Tm = [1 0 0 1 tx ty] x Tlm
                self.tlm[4] += tx * self.tlm[0] + ty * self.tlm[2]
                self.tlm[5] += tx * self.tlm[1] + ty * self.tlm[3]
                self.tm = list(self.tlm)
            except (ValueError, TypeError):
                pass

    def _handle_tstar(self) -> None:
        # Move down by leading
        self.tlm[4] += -self.leading * self.tlm[2]
        self.tlm[5] += -self.leading * self.tlm[3]
        self.tm = list(self.tlm)

    def _handle_tj(self, stack: List[Any]) -> None:
        if not stack:
            return
        raw_str = stack[0]
        if isinstance(raw_str, bytes):
            self._render_text_bytes(raw_str)

    def _process_tj_elem(self, elem: Any) -> None:
        if isinstance(elem, bytes):
            self._render_text_bytes(elem)
        elif isinstance(elem, (int, float)):
            displacement = (
                -float(elem) / 1000.0 * self.font_size * (self.horiz_scale / 100.0)
            )
            self.tm[4] += displacement * self.tm[0]

    def _handle_tj_array(self, stack: List[Any]) -> None:
        if not stack or not isinstance(stack[0], list):
            return
        for elem in stack[0]:
            self._process_tj_elem(elem)

    def _render_text_bytes(self, raw_bytes: bytes) -> None:
        decoder = self.font_decoders.get(self.active_font)
        decoded_text = (
            decoder.decode_bytes(raw_bytes)
            if decoder
            else raw_bytes.decode("latin1", errors="replace")
        )

        if not decoded_text:
            return

        cur_x = self.tm[4]
        cur_y = self.tm[5]
        approx_char_width = self.font_size * 0.5 * (self.horiz_scale / 100.0)
        total_width = approx_char_width * len(decoded_text)

        glyph_box = GlyphBox(
            text=decoded_text,
            x=cur_x,
            y=cur_y,
            width=total_width,
            height=self.font_size,
            font_size=self.font_size,
            font_name=self.active_font,
        )
        self.glyphs.append(glyph_box)

        # Advance horizontal position
        self.tm[4] += total_width + (self.char_spacing * len(decoded_text))
