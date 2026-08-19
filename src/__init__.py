#!/usr/bin/env python3
"""
arXiv Security Papers Core Package.
Provides 5 modular packages matching the tests hierarchy:
- database: Zero-dependency SQLite-inspired 4-tier Vector Database
- fetcher: arXiv API metadata fetcher, PDF extractor & OKF converter
- mcp: Model Context Protocol JSON-RPC servers (Papers, Threat Defense, Tech Radar, Observability)
- search: Lucene/Solr-inspired modular search engine & RRF hybrid ranking
- web: Glassmorphic Web Portal & PEP 3333 WSGI Application
"""

import database
import fetcher
import gateway
import mcp
import presentation
import search
import web

__all__ = [
    "database",
    "fetcher",
    "gateway",
    "mcp",
    "presentation",
    "search",
    "web",
]
