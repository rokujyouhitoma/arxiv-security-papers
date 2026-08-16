#!/usr/bin/env python3
"""
Solr-equivalent Enterprise Search Server Package.
Composed of schema, handler, facet, highlight, and cache subpackages.
"""

from . import cache, facet, handler, highlight, schema
from .cache import FilterCache, LRUCache, QueryResultCache
from .facet import FacetEngine
from .handler import SelectHandler
from .highlight import FastVectorHighlighter
from .schema import FieldDefinition, FieldType, ManagedIndexSchema

__all__ = [
    "FacetEngine",
    "FastVectorHighlighter",
    "FieldDefinition",
    "FieldType",
    "FilterCache",
    "LRUCache",
    "ManagedIndexSchema",
    "QueryResultCache",
    "SelectHandler",
    "cache",
    "facet",
    "handler",
    "highlight",
    "schema",
]
