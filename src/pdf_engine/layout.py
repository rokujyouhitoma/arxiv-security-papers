"""2D Spatial Layout Reconstructor and Two-Column Flow Engine."""

import re
from typing import List, Optional, Tuple

from .contracts import GlyphBox, TextLine

# Prefixes and terms that should preserve their hyphen when line-broken
COMPOUND_HYPHEN_PREFIXES = {
    "anti",
    "auto",
    "cross",
    "fault",
    "fine",
    "inter",
    "intra",
    "macro",
    "micro",
    "multi",
    "non",
    "open",
    "out",
    "over",
    "peer",
    "post",
    "pre",
    "pseudo",
    "quasi",
    "real",
    "self",
    "semi",
    "side",
    "tamper",
    "ultra",
    "under",
    "zero",
}

KNOWN_COMPOUND_TERMS = {
    "zero-trust",
    "cross-site",
    "side-channel",
    "fault-tolerant",
    "state-of-the-art",
    "end-to-end",
    "real-time",
    "proof-of-concept",
    "man-in-the-middle",
    "machine-in-the-middle",
    "denial-of-service",
    "zero-day",
    "coarse-grained",
    "fine-grained",
    "tamper-proof",
    "tamper-resistant",
    "self-sovereign",
    "peer-to-peer",
    "open-source",
    "out-of-band",
    "in-band",
    "public-key",
    "private-key",
    "secret-key",
    "role-based",
    "attribute-based",
    "policy-based",
    "rate-limiting",
    "time-of-check",
    "time-of-use",
}


def _should_preserve_hyphen(p1: str, p2: str) -> bool:
    low1 = p1.lower()
    low2 = p2.lower()
    if f"{low1}-{low2}" in KNOWN_COMPOUND_TERMS:
        return True
    if low1 in COMPOUND_HYPHEN_PREFIXES:
        return True
    if p2 and p2[0].isupper():
        return True
    return False


def _dehyphenate_match(match: re.Match[str]) -> str:
    p1 = match.group(1)
    p2 = match.group(2)
    if _should_preserve_hyphen(p1, p2):
        return f"{p1}-{p2}"
    return f"{p1}{p2}"


_DEHYPHEN_REGEX = re.compile(r"([A-Za-z]{2,})-\n\s*([A-Za-z]{2,})")


def dehyphenate_text(text: str) -> str:
    """Intelligently merges line-broken hyphenated words while preserving compound terms."""
    return _DEHYPHEN_REGEX.sub(_dehyphenate_match, text)


def _is_valid_gutter(
    best_len: int,
    best_center: Optional[float],
    bin_width: float,
    mid_x: float,
    page_width: float,
) -> bool:
    if best_len * bin_width < 12.0 or best_center is None:
        return False
    return abs(best_center - mid_x) < page_width * 0.12


def detect_two_column_gutter(
    glyphs: List[GlyphBox], page_width: float
) -> Optional[float]:
    """Detects central vertical whitespace gutter in two-column scientific papers."""
    if len(glyphs) < 30 or page_width <= 0:
        return None

    min_center_x = page_width * 0.35
    max_center_x = page_width * 0.65
    mid_x = page_width * 0.5
    num_bins = 60
    bin_width = (max_center_x - min_center_x) / num_bins

    histogram = _build_gutter_histogram(
        glyphs, min_center_x, bin_width, num_bins, page_width
    )
    best_len, best_center = _find_widest_gutter(
        histogram, min_center_x, bin_width, num_bins
    )

    if _is_valid_gutter(best_len, best_center, bin_width, mid_x, page_width):
        return best_center
    return None


def _is_column_bound(g: GlyphBox, page_width: float) -> bool:
    if page_width <= 0:
        return True
    if g.width > page_width * 0.45:
        return False
    if g.x < page_width * 0.35 and (g.x + g.width) > page_width * 0.65:
        return False
    return True


def _build_gutter_histogram(
    glyphs: List[GlyphBox],
    min_x: float,
    bin_width: float,
    num_bins: int,
    page_width: float,
) -> List[int]:
    histogram = [0] * num_bins
    for g in glyphs:
        if not _is_column_bound(g, page_width):
            continue
        gx1, gx2 = g.x, g.x + g.width
        for b_idx in range(num_bins):
            bx1 = min_x + b_idx * bin_width
            bx2 = bx1 + bin_width
            if max(gx1, bx1) < min(gx2, bx2):
                histogram[b_idx] += 1
    return histogram


def _find_widest_gutter(
    histogram: List[int], min_x: float, bin_width: float, num_bins: int
) -> Tuple[int, Optional[float]]:
    best_len = 0
    best_center = None
    cur_len = 0
    cur_start = 0

    for b_idx in range(num_bins):
        if histogram[b_idx] <= 1:
            if cur_len == 0:
                cur_start = b_idx
            cur_len += 1
            if cur_len > best_len:
                best_len = cur_len
                start_x = min_x + cur_start * bin_width
                end_x = min_x + (cur_start + cur_len) * bin_width
                best_center = (start_x + end_x) / 2.0
        else:
            cur_len = 0
    return best_len, best_center


def _is_same_line(prev_g: GlyphBox, g: GlyphBox, gutter_x: Optional[float]) -> bool:
    y_diff = abs(g.y - prev_g.y)
    threshold = max(g.font_size, prev_g.font_size) * 0.45
    if y_diff > threshold:
        return False
    if gutter_x is not None:
        if (prev_g.x + prev_g.width) <= gutter_x and g.x >= gutter_x:
            return False
    return True


def cluster_into_lines(
    glyphs: List[GlyphBox], gutter_x: Optional[float] = None
) -> List[TextLine]:
    """Groups sorted glyphs into discrete horizontal text lines."""
    if not glyphs:
        return []

    # Sort primarily by Y descending (top-to-bottom), then X ascending
    sorted_glyphs = sorted(glyphs, key=lambda g: (-g.y, g.x))
    lines: List[TextLine] = []
    cur_line = TextLine(glyphs=[sorted_glyphs[0]])

    for g in sorted_glyphs[1:]:
        prev_g = cur_line.glyphs[-1]
        if _is_same_line(prev_g, g, gutter_x):
            cur_line.glyphs.append(g)
        else:
            _finalize_line(cur_line)
            lines.append(cur_line)
            cur_line = TextLine(glyphs=[g])

    _finalize_line(cur_line)
    lines.append(cur_line)
    return lines


def _finalize_line(line: TextLine) -> None:
    # Sort glyphs within line left-to-right
    line.glyphs.sort(key=lambda g: g.x)
    min_x = min(g.x for g in line.glyphs)
    min_y = min(g.y for g in line.glyphs)
    max_x = max(g.x + g.width for g in line.glyphs)
    max_y = max(g.y + g.height for g in line.glyphs)
    line.bbox = (min_x, min_y, max_x, max_y)


def _should_insert_space(prev_g: GlyphBox, cur_g: GlyphBox) -> bool:
    gap = cur_g.x - (prev_g.x + prev_g.width)
    space_threshold = max(prev_g.font_size, cur_g.font_size) * 0.18
    return (
        gap >= space_threshold
        and not prev_g.text.endswith(" ")
        and not cur_g.text.startswith(" ")
    )


def render_line_text(line: TextLine) -> str:
    """Renders text line adding spaces between separated glyph clusters."""
    if not line.glyphs:
        return ""

    tokens: List[str] = [line.glyphs[0].text]
    for i in range(1, len(line.glyphs)):
        prev_g = line.glyphs[i - 1]
        cur_g = line.glyphs[i]
        if _should_insert_space(prev_g, cur_g):
            tokens.append(" ")
        tokens.append(cur_g.text)

    return "".join(tokens).strip()


def _is_header_or_footer(line: TextLine, page_height: float) -> bool:
    text = render_line_text(line).strip()
    if not text:
        return False
    if line.min_y > page_height - 35 and len(text) < 80:
        return True
    if line.min_y < 35 and (text.isdigit() or len(text) < 15):
        return True
    return False


def _classify_line_column_type(line: TextLine, gutter_x: float) -> str:
    """Classifies line as FULL-span, LEFT column, or RIGHT column."""
    if line.min_x < gutter_x - 20.0 and line.max_x > gutter_x + 20.0:
        return "FULL"
    if line.max_x <= gutter_x + 15.0:
        return "LEFT"
    if line.min_x >= gutter_x - 15.0:
        return "RIGHT"
    mid_line = (line.min_x + line.max_x) / 2.0
    return "LEFT" if mid_line < gutter_x else "RIGHT"


class VerticalBand:
    """Represents a discrete horizontal slice of a page (Single-column or Two-column)."""

    def __init__(self, is_two_column: bool) -> None:
        self.is_two_column = is_two_column
        self.full_lines: List[TextLine] = []
        self.left_lines: List[TextLine] = []
        self.right_lines: List[TextLine] = []

    def add_line(self, line: TextLine, col_type: str) -> None:
        if col_type == "FULL":
            self.full_lines.append(line)
        elif col_type == "LEFT":
            self.left_lines.append(line)
        else:
            self.right_lines.append(line)

    def _render_two_column_parts(self) -> Optional[str]:
        parts: List[str] = []
        left_str = [t for line in self.left_lines if (t := render_line_text(line))]
        if left_str:
            parts.append("\n".join(left_str))
        right_str = [t for line in self.right_lines if (t := render_line_text(line))]
        if right_str:
            parts.append("\n".join(right_str))
        return "\n\n".join(parts) if parts else None

    def render(self) -> Optional[str]:
        if not self.is_two_column:
            lines_str = [t for line in self.full_lines if (t := render_line_text(line))]
            return "\n".join(lines_str) if lines_str else None
        return self._render_two_column_parts()


def _segment_into_vertical_bands(
    lines: List[TextLine], gutter_x: float, page_height: float
) -> List[VerticalBand]:
    bands: List[VerticalBand] = []
    cur_band: Optional[VerticalBand] = None

    for line in lines:
        if _is_header_or_footer(line, page_height):
            continue
        col_type = _classify_line_column_type(line, gutter_x)
        is_two_col = col_type != "FULL"
        if cur_band is None or cur_band.is_two_column != is_two_col:
            cur_band = VerticalBand(is_two_col)
            bands.append(cur_band)
        cur_band.add_line(line, col_type)

    return bands


class SpatialLayoutEngine:
    """Reconstructs reading-order text flow with two-column paper layout awareness."""

    @classmethod
    def reconstruct(
        cls, glyphs: List[GlyphBox], page_width: float, page_height: float
    ) -> str:
        if not glyphs:
            return ""

        gutter_x = detect_two_column_gutter(glyphs, page_width)
        if gutter_x is None:
            raw_text = cls._render_single_column(glyphs)
        else:
            raw_text = cls._render_two_column_flow(glyphs, gutter_x, page_height)

        return dehyphenate_text(raw_text)

    @classmethod
    def _render_single_column(cls, glyphs: List[GlyphBox]) -> str:
        lines = cluster_into_lines(glyphs)
        out = [t for line in lines if (t := render_line_text(line))]
        return "\n".join(out)

    @classmethod
    def _render_two_column_flow(
        cls, glyphs: List[GlyphBox], gutter_x: float, page_height: float
    ) -> str:
        lines = cluster_into_lines(glyphs, gutter_x=gutter_x)
        bands = _segment_into_vertical_bands(lines, gutter_x, page_height)
        sections = [res for band in bands if (res := band.render())]
        return "\n\n".join(sections)
