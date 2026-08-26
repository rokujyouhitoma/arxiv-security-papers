"""Regression tests verifying Pure Python PDF Engine against real arXiv papers in outputs/raw_data/."""

import glob
import os

from pdf_engine.benchmark import evaluate_single_paper
from pdf_engine.extractor import PurePdfTextExtractor


def test_real_arxiv_pdf_extraction():
    sample_pdfs = sorted(glob.glob("outputs/raw_data/**/*.pdf", recursive=True))
    if not sample_pdfs:
        return

    # Test the first 5 real arXiv papers
    targets = sample_pdfs[:5]
    for pdf_path in targets:
        txt_path = pdf_path.replace(".pdf", ".txt")
        if not os.path.exists(txt_path):
            continue

        metrics = evaluate_single_paper(pdf_path, txt_path)
        assert metrics.char_recall >= 0.80
        assert metrics.word_f1 >= 0.65
        assert metrics.similarity >= 0.50


def test_pure_pdf_extractor_in_memory():
    sample_pdfs = sorted(glob.glob("outputs/raw_data/**/*.pdf", recursive=True))
    if not sample_pdfs:
        return

    with open(sample_pdfs[0], "rb") as f:
        pdf_bytes = f.read()

    text = PurePdfTextExtractor.extract_text_from_bytes(pdf_bytes)
    assert len(text) > 100
