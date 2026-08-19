#!/usr/bin/env python3
"""
Unit and Integration Tests for PAX (Partition Attributes Across) Columnar Storage.
Verifies RLE & Dictionary column compression, 4KB Mini-Page binary layout,
selective column decoding, and OLAP vectorized aggregations (COUNT, SUM, AVG, GROUP BY).
"""

import os
import sys
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    )

from database.pax import ColumnDecoder, ColumnEncoder, PAXPage, PAXTable


class TestColumnEncoding(unittest.TestCase):
    """Tests for individual column compression and encoding algorithms."""

    def test_rle_encoding_and_compression(self) -> None:
        # 100 repeated year values
        years = [2024] * 50 + [2025] * 30 + [2026] * 20
        rle_bytes = ColumnEncoder.encode_rle(years, "int")
        plain_bytes = ColumnEncoder.encode_plain(years, "int")

        # RLE should be significantly smaller (3 runs vs 100 * 8 bytes = 800 bytes)
        self.assertLess(len(rle_bytes), len(plain_bytes) // 5)

        # Decode roundtrip
        decoded = ColumnDecoder.decode_rle(rle_bytes, total_count=100, val_type="int")
        self.assertEqual(decoded, years)

    def test_dictionary_encoding_and_compression(self) -> None:
        # Low cardinality categories
        categories = ["crypto"] * 40 + ["network"] * 40 + ["zero-trust"] * 20
        dict_bytes, dict_table = ColumnEncoder.encode_dictionary(categories)

        self.assertEqual(len(dict_table), 3)
        self.assertIn("crypto", dict_table)
        self.assertIn("network", dict_table)

        # Decode roundtrip
        decoded = ColumnDecoder.decode_dictionary(dict_bytes, total_count=100)
        self.assertEqual(decoded, categories)


class TestPAXPage(unittest.TestCase):
    """Tests for PAX 4KB page binary format and selective Mini-Page reads."""

    def test_pax_page_creation_and_selective_read(self) -> None:
        schema = [
            ("id", "int"),
            ("year", "int"),
            ("category", "str"),
            ("score", "float"),
        ]

        rows = [
            [
                i,
                2026 if i % 2 == 0 else 2025,
                "crypto" if i % 3 == 0 else "network",
                float(i) * 1.5,
            ]
            for i in range(20)
        ]

        page_bytes = PAXPage.create_page(schema, rows)
        self.assertEqual(len(page_bytes), 4096)

        view = memoryview(page_bytes)

        # 1. Selective column read (read ONLY category column without touching other Mini-Pages)
        cat_col = PAXPage.read_column(view, col_idx=2, schema=schema)
        expected_cats = [r[2] for r in rows]
        self.assertEqual(cat_col, expected_cats)

        # 2. Selective read of score column
        score_col = PAXPage.read_column(view, col_idx=3, schema=schema)
        expected_scores = [r[3] for r in rows]
        self.assertEqual(score_col, expected_scores)

        # 3. Full row reconstruction
        reconstructed = PAXPage.read_rows(view, schema)
        self.assertEqual(reconstructed, rows)


class TestPAXScannerAndTable(unittest.TestCase):
    """Tests for PAXTable storage and PAXScanner OLAP aggregations."""

    def setUp(self) -> None:
        self.schema = [
            ("id", "int"),
            ("year", "int"),
            ("category", "str"),
            ("score", "float"),
            ("title", "str"),
        ]
        self.table = PAXTable(
            table_name="papers_pax",
            schema=self.schema,
            max_rows_per_page=30,  # Forces multiple 4KB pages
        )

        # Populate 100 sample records
        for i in range(100):
            year = 2024 + (i % 3)  # 2024, 2025, 2026
            cat = ["crypto", "network", "web-security", "zero-trust"][i % 4]
            score = float((i % 10) + 1) * 10.0  # 10.0 to 100.0
            title = f"Paper on {cat} - Part {i}"
            self.table.insert([i, year, cat, score, title])

    def test_pax_olap_aggregations(self) -> None:
        scanner = self.table.get_scanner()
        pages = self.table.get_pages()
        self.assertGreaterEqual(len(pages), 3)

        # 1. Fast COUNT
        self.assertEqual(scanner.count(), 100)

        # 2. Filtered COUNT
        crypto_count = scanner.count(predicate=lambda r: r["category"] == "crypto")
        self.assertEqual(crypto_count, 25)

        # 3. SUM and AVG
        total_score = scanner.sum("score")
        self.assertAlmostEqual(
            total_score, sum(float((i % 10) + 1) * 10.0 for i in range(100)), places=2
        )

        avg_score = scanner.avg("score")
        self.assertAlmostEqual(avg_score, total_score / 100.0, places=2)

        # 4. MIN and MAX
        self.assertEqual(scanner.min("year"), 2024)
        self.assertEqual(scanner.max("year"), 2026)

        # 5. GROUP BY aggregations
        group_counts = scanner.group_by("category", "id", agg_fn="COUNT")
        self.assertEqual(group_counts["crypto"], 25)
        self.assertEqual(group_counts["network"], 25)
        self.assertEqual(group_counts["web-security"], 25)
        self.assertEqual(group_counts["zero-trust"], 25)

        group_avg_scores = scanner.group_by("category", "score", agg_fn="AVG")
        for cat in ["crypto", "network", "web-security", "zero-trust"]:
            self.assertGreater(group_avg_scores[cat], 0.0)

    def test_scan_all_rows(self) -> None:
        all_rows = self.table.scan_all_rows()
        self.assertEqual(len(all_rows), 100)
        self.assertEqual(all_rows[0][0], 0)
        self.assertEqual(all_rows[99][0], 99)


if __name__ == "__main__":
    unittest.main()
