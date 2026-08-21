#!/usr/bin/env python3
"""
arXiv Security Papers Core Package.
Provides clean 4-tier domain-driven packages:
- database: Zero-dependency SQLite-inspired 4-tier Vector Database & Distributed Engine
- pipeline: Extract-Transform-Load (ETL) Intelligence Pipeline & 5-tier Summaries
- search: Lucene/Solr-inspired modular search engine & hybrid ranking
- security: Unified security guards, AST sandbox, RBAC & threat taxonomies
- spider: Zero-dependency distributed spider & crawler platform
- web: Unified Web/API Serving Layer (WSGI, Gateway, Presentation)
- mcp: Model Context Protocol JSON-RPC servers
- compat: Backward-compatibility shims
"""

import compat
import database
import mcp
import pipeline
import search
import security
import spider
import web

__all__ = [
    "compat",
    "database",
    "mcp",
    "pipeline",
    "search",
    "security",
    "spider",
    "web",
]
