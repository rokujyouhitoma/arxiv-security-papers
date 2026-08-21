#!/usr/bin/env python3
"""
Search Platform Package (Solr Paradigm).
Enterprise Search Server providing Managed Schema (Dynamic & Copy Fields), Select/Update Handlers,
Query Elevation (Fixed Placement), Multi-dimensional Faceting, Highlighting, Multi-tier Caching,
Distributed Search Aggregation, and Core Administration.
"""

from . import admin, cache, distributed, elevation, facet, handler, highlight, schema
from .admin import CoreAdmin, IndexSnapshot
from .cache import DocumentCache, FilterCache, LRUCache, QueryResultCache, SolrCache
from .distributed import DistributedSearcher, ShardHandler, ShardResponse
from .elevation import ElevationRule, QueryElevationComponent
from .facet import FacetEngine, FieldFacet, RangeFacet
from .handler import SelectHandler, UpdateHandler
from .highlight import DynamicHighlighter, FastVectorHighlighter
from .schema import CopyField, DynamicField, FieldDefinition, FieldType, ManagedSchema

__all__ = [
    # Subpackages
    "schema",
    "handler",
    "elevation",
    "facet",
    "highlight",
    "cache",
    "distributed",
    "admin",
    # Schema
    "FieldType",
    "FieldDefinition",
    "DynamicField",
    "CopyField",
    "ManagedSchema",
    # Handlers
    "SelectHandler",
    "UpdateHandler",
    # Elevation / Fixed Placement
    "ElevationRule",
    "QueryElevationComponent",
    # Facets
    "FieldFacet",
    "RangeFacet",
    "FacetEngine",
    # Highlighting
    "DynamicHighlighter",
    "FastVectorHighlighter",
    # Caching
    "LRUCache",
    "FilterCache",
    "QueryResultCache",
    "DocumentCache",
    "SolrCache",
    # Distributed Search
    "ShardResponse",
    "ShardHandler",
    "DistributedSearcher",
    # Administration
    "IndexSnapshot",
    "CoreAdmin",
]
