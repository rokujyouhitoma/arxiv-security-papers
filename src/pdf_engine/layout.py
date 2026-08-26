"""2D Spatial Layout Reconstructor and Two-Column Flow Engine."""

from typing import List, Optional, Tuple

from .contracts import GlyphBox, TextLine


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

    histogram = _build_gutter_histogram(glyphs, min_center_x, bin_width, num_bins)
    best_len, best_center = _find_widest_gutter(histogram, min_center_x, bin_width, num_bins)

    if best_len * bin_width >= 12.0 and best_center is not None:
        if abs(best_center - mid_x) < page_width * 0.12:
            return best_center
    return None


def _build_gutter_histogram(
    glyphs: List[GlyphBox], min_x: float, bin_width: float, num_bins: int
) -> List[int]:
    histogram = [0] * num_bins
    for g in glyphs:
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


def cluster_into_lines(glyphs: List[GlyphBox]) -> List[TextLine]:
    """Groups sorted glyphs into discrete horizontal text lines."""
    if not glyphs:
        return []

    # Sort primarily by Y descending (top-to-bottom), then X ascending
    sorted_glyphs = sorted(glyphs, key=lambda g: (-g.y, g.x))
    lines: List[TextLine] = []
    cur_line = TextLine(glyphs=[sorted_glyphs[0]])

    for g in sorted_glyphs[1:]:
        prev_g = cur_line.glyphs[-1]
        y_diff = abs(g.y - prev_g.y)
        threshold = max(g.font_size, prev_g.font_size) * 0.45

        if y_diff <= threshold:
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


def render_line_text(line: TextLine) -> str:
    """Renders text line adding spaces between separated glyph clusters."""
    if not line.glyphs:
        return ""

    tokens: List[str] = [line.glyphs[0].text]
    for i in range(1, len(line.glyphs)):
        prev_g = line.glyphs[i - 1]
        cur_g = line.glyphs[i]
        gap = cur_g.x - (prev_g.x + prev_g.width)

        space_threshold = max(prev_g.font_size, cur_g.font_size) * 0.2
        if (
            gap >= space_threshold
            and not prev_g.text.endswith(" ")
            and not cur_g.text.startswith(" ")
        ):
            tokens.append(" ")
        tokens.append(cur_g.text)

    return "".join(tokens).strip()


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
            return cls._render_single_column(glyphs)

        return cls._render_two_column_flow(glyphs, gutter_x, page_height)

    @classmethod
    def _render_single_column(cls, glyphs: List[GlyphBox]) -> str:
        lines = cluster_into_lines(glyphs)
        out: List[str] = []
        for line in lines:
            t = render_line_text(line)
            if t:
                out.append(t)
        return "\n".join(out)

    @classmethod
    def _render_two_column_flow(
        cls, glyphs: List[GlyphBox], gutter_x: float, page_height: float
    ) -> str:
        lines = cluster_into_lines(glyphs)
        header, left, right, footer = cls._partition_lines(lines, gutter_x, page_height)

        sections: List[str] = []
        for group in (header, left, right, footer):
            if group:
                rendered = "\n".join(render_line_text(line) for line in group if render_line_text(line))
                if rendered:
                    sections.append(rendered)

        return "\n\n".join(sections)

    @staticmethod
    def _partition_lines(
        lines: List[TextLine], gutter_x: float, page_height: float
    ) -> Tuple[List[TextLine], List[TextLine], List[TextLine], List[TextLine]]:
        header_lines: List[TextLine] = []
        left_lines: List[TextLine] = []
        right_lines: List[TextLine] = []
        footer_lines: List[TextLine] = []

        for line in lines:
            if line.min_x < gutter_x - 30 and line.max_x > gutter_x + 30:
                if line.min_y > page_height * 0.5:
                    header_lines.append(line)
                else:
                    footer_lines.append(line)
            elif line.max_x <= gutter_x + 10:
                left_lines.append(line)
            else:
                right_lines.append(line)

        return header_lines, left_lines, right_lines, footer_lines
