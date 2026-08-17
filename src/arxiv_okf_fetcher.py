#!/usr/bin/env python3
"""
Thin compatibility shim forwarding to the fetcher package.
"""

from fetcher.arxiv_okf_fetcher import *  # noqa: F401, F403
from fetcher.arxiv_okf_fetcher import main

if __name__ == "__main__":
    main()
