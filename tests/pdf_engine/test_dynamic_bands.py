"""
Unit tests for Dynamic Vertical Band Segmentation in academic paper layout reconstruction.
Verifies reading order: Title/Abstract -> Body Left -> Body Right -> Full-width Figure.
"""

from pdf_engine.contracts import GlyphBox
from pdf_engine.layout import SpatialLayoutEngine


def test_mixed_single_and_two_column_reading_order() -> None:
    page_width = 600.0
    page_height = 800.0

    # 1. Full-width Title (Y=750, X=100..500)
    title_glyph = GlyphBox(
        text="A Secure Zero-Trust Framework",
        x=100.0,
        y=750.0,
        width=400.0,
        height=14.0,
        font_size=14.0,
        font_name="F1",
    )

    # 2. Full-width Abstract (Y=700, X=120..480)
    abs_glyph = GlyphBox(
        text="Abstract. In this paper we propose a zero-trust model.",
        x=120.0,
        y=700.0,
        width=360.0,
        height=10.0,
        font_size=10.0,
        font_name="F1",
    )

    # 3. Two-column Body: Left Column (X=50..250, Y=650 and Y=620)
    left_1 = GlyphBox(
        text="1. Introduction to our approach.",
        x=50.0,
        y=650.0,
        width=200.0,
        height=10.0,
        font_size=10.0,
        font_name="F1",
    )
    left_2 = GlyphBox(
        text="Network segmentation is critical.",
        x=50.0,
        y=620.0,
        width=200.0,
        height=10.0,
        font_size=10.0,
        font_name="F1",
    )

    # 4. Two-column Body: Right Column (X=350..550, Y=650 and Y=620)
    right_1 = GlyphBox(
        text="2. Threat Model and Assumptions.",
        x=350.0,
        y=650.0,
        width=200.0,
        height=10.0,
        font_size=10.0,
        font_name="F1",
    )
    right_2 = GlyphBox(
        text="We assume an active adversary.",
        x=350.0,
        y=620.0,
        width=200.0,
        height=10.0,
        font_size=10.0,
        font_name="F1",
    )

    # Add dummy column filler glyphs to establish clear central gutter
    filler_glyphs = []
    for y_fill in range(200, 600, 20):
        filler_glyphs.append(
            GlyphBox(
                text="L",
                x=50.0,
                y=float(y_fill),
                width=200.0,
                height=9.0,
                font_size=9.0,
                font_name="F1",
            )
        )
        filler_glyphs.append(
            GlyphBox(
                text="R",
                x=350.0,
                y=float(y_fill),
                width=200.0,
                height=9.0,
                font_size=9.0,
                font_name="F1",
            )
        )

    all_glyphs = [
        title_glyph,
        abs_glyph,
        left_1,
        left_2,
        right_1,
        right_2,
    ] + filler_glyphs

    rendered = SpatialLayoutEngine.reconstruct(all_glyphs, page_width, page_height)

    # Assert correct natural reading order:
    pos_title = rendered.find("A Secure Zero-Trust Framework")
    pos_abstract = rendered.find("Abstract. In this paper")
    pos_left_intro = rendered.find("1. Introduction to our approach.")
    pos_left_network = rendered.find("Network segmentation is critical.")
    pos_right_threat = rendered.find("2. Threat Model and Assumptions.")
    pos_right_adversary = rendered.find("We assume an active adversary.")

    assert pos_title != -1
    assert pos_abstract != -1
    assert pos_left_intro != -1
    assert pos_left_network != -1
    assert pos_right_threat != -1
    assert pos_right_adversary != -1

    assert pos_title < pos_abstract
    assert pos_abstract < pos_left_intro
    assert pos_left_intro < pos_left_network
    assert pos_left_network < pos_right_threat
    assert pos_right_threat < pos_right_adversary
