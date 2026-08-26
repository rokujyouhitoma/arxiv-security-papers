"""Unit tests for 2D spatial layout and two-column reading order reconstruction."""

from pdf_engine.contracts import GlyphBox
from pdf_engine.layout import (
    SpatialLayoutEngine,
    cluster_into_lines,
    detect_two_column_gutter,
)


def test_cluster_into_lines():
    glyphs = [
        GlyphBox(
            text="Hello", x=100.0, y=700.0, width=30.0, height=12.0, font_size=12.0
        ),
        GlyphBox(
            text="World", x=140.0, y=701.0, width=30.0, height=12.0, font_size=12.0
        ),
        GlyphBox(
            text="Second Line",
            x=100.0,
            y=680.0,
            width=60.0,
            height=12.0,
            font_size=12.0,
        ),
    ]
    lines = cluster_into_lines(glyphs)
    assert len(lines) == 2
    assert "Hello World" == lines[0].text or "Hello" in lines[0].text
    assert "Second Line" in lines[1].text


def test_two_column_gutter_and_flow():
    # Construct a synthetic 2-column page (width=600, mid=300)
    glyphs = []
    # Header
    glyphs.append(
        GlyphBox(
            text="Paper Title",
            x=200.0,
            y=750.0,
            width=200.0,
            height=16.0,
            font_size=16.0,
        )
    )

    # Left Column (x: 50..250)
    for i in range(20):
        y = 700.0 - i * 15.0
        glyphs.append(
            GlyphBox(
                text=f"Left {i}", x=50.0, y=y, width=150.0, height=10.0, font_size=10.0
            )
        )

    # Right Column (x: 350..550)
    for i in range(20):
        y = 700.0 - i * 15.0
        glyphs.append(
            GlyphBox(
                text=f"Right {i}",
                x=350.0,
                y=y,
                width=150.0,
                height=10.0,
                font_size=10.0,
            )
        )

    gutter = detect_two_column_gutter(glyphs, page_width=600.0)
    assert gutter is not None
    assert 250.0 <= gutter <= 350.0

    flow_text = SpatialLayoutEngine.reconstruct(
        glyphs, page_width=600.0, page_height=800.0
    )
    assert "Paper Title" in flow_text
    assert flow_text.find("Left 0") < flow_text.find("Right 0")
