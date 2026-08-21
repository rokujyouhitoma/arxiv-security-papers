"""Legacy compatibility shim for arxiv_okf_fetcher."""

from pipeline.arxiv_okf_fetcher import *  # noqa: F401, F403
from pipeline.arxiv_okf_fetcher import main

if __name__ == "__main__":
    main()
