#!/usr/bin/env python3
"""
Solr Schema Subpackage.
"""

from .managed_schema import FieldDefinition, FieldType, ManagedIndexSchema

__all__ = [
    "FieldDefinition",
    "FieldType",
    "ManagedIndexSchema",
]
