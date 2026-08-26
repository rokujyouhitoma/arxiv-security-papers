"""CLI entrypoint for pdf_engine (e.g. python -m pdf_engine <file.pdf>)."""

import argparse
import sys
from typing import List

from .extractor import PurePdfTextExtractor


def main(argv: List[str] = sys.argv[1:]) -> int:
    parser = argparse.ArgumentParser(description="Pure Python PDF Text Extractor CLI")
    parser.add_argument("pdf_file", help="Path to PDF file to extract text from")
    parser.add_argument("--output", "-o", help="Optional output text file path")
    parser.add_argument("--head", type=int, default=0, help="Print first N characters")
    args = parser.parse_args(argv)

    try:
        text = PurePdfTextExtractor.extract_text_from_file(args.pdf_file)
        if args.output:
            with open(args.output, "w", encoding="utf-8") as f:
                f.write(text)
            print(f"[+] Successfully extracted {len(text)} characters to {args.output}")
        elif args.head > 0:
            print(text[: args.head])
        else:
            print(text)
        return 0
    except Exception as exc:
        print(f"[ERROR] Extraction failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
