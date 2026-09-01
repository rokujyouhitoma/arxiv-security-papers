#!/usr/bin/env python3
"""
Managed Index Schema with Dynamic Fields and Copy Fields (Solr Paradigm).
"""

import fnmatch
from enum import Enum
from typing import Any, Dict, List, Optional


class FieldType(Enum):
    STRING = "string"
    TEXT = "text"
    TEXT_JA = "text_ja"
    INT = "int"
    FLOAT = "float"
    DATE = "date"
    VECTOR = "vector"


class FieldDefinition:
    """Definition of an individual index field."""

    def __init__(
        self,
        name: str,
        field_type: FieldType = FieldType.TEXT,
        indexed: bool = True,
        stored: bool = True,
        doc_values: bool = False,
        multi_valued: bool = False,
        default_value: Optional[Any] = None,
    ) -> None:
        self.name = name
        self.field_type = field_type
        self.indexed = indexed
        self.stored = stored
        self.doc_values = doc_values
        self.multi_valued = multi_valued
        self.default_value = default_value


class DynamicField:
    """Dynamic field definition matching wildcard patterns (e.g. '*_s', '*_i', '*_txt')."""

    def __init__(
        self,
        pattern: str,
        field_type: FieldType = FieldType.TEXT,
        indexed: bool = True,
        stored: bool = True,
        doc_values: bool = False,
    ) -> None:
        self.pattern = pattern
        self.field_type = field_type
        self.indexed = indexed
        self.stored = stored
        self.doc_values = doc_values

    def matches(self, field_name: str) -> bool:
        return fnmatch.fnmatch(field_name, self.pattern)


class CopyField:
    """Rules for copying and aggregating values from source fields to a destination field."""

    def __init__(self, source_pattern: str, destination_field: str) -> None:
        self.source_pattern = source_pattern
        self.destination_field = destination_field

    def matches(self, field_name: str) -> bool:
        return fnmatch.fnmatch(field_name, self.source_pattern)


class ManagedSchema:
    """Enterprise Schema Manager supporting explicit fields, dynamic fields, and copy fields."""

    def __init__(self, unique_key: str = "id") -> None:
        self.unique_key = unique_key
        self.fields: Dict[str, FieldDefinition] = {}
        self.dynamic_fields: List[DynamicField] = []
        self.copy_fields: List[CopyField] = []

        # Default dynamic field rules
        self.dynamic_fields.extend(
            [
                DynamicField("*_s", FieldType.STRING, doc_values=True),
                DynamicField("*_t", FieldType.TEXT),
                DynamicField("*_txt", FieldType.TEXT_JA),
                DynamicField("*_i", FieldType.INT, doc_values=True),
                DynamicField("*_dt", FieldType.DATE, doc_values=True),
            ]
        )

    def add_field(self, field: FieldDefinition) -> "ManagedSchema":
        self.fields[field.name] = field
        return self

    def add_dynamic_field(self, dynamic_field: DynamicField) -> "ManagedSchema":
        self.dynamic_fields.append(dynamic_field)
        return self

    def add_copy_field(self, source: str, destination: str) -> "ManagedSchema":
        self.copy_fields.append(CopyField(source, destination))
        return self

    def get_field_definition(self, name: str) -> FieldDefinition:
        """Resolves field definition via explicit fields or dynamic wildcard matching."""
        if name in self.fields:
            return self.fields[name]
        for df in self.dynamic_fields:
            if df.matches(name):
                return FieldDefinition(
                    name=name,
                    field_type=df.field_type,
                    indexed=df.indexed,
                    stored=df.stored,
                    doc_values=df.doc_values,
                )
        # Default fallback
        return FieldDefinition(name=name, field_type=FieldType.TEXT, doc_values=True)

    def _extract_field_val(self, src_val: Any, copied: List[str]) -> None:
        if not src_val:
            return
        if isinstance(src_val, list):
            copied.extend(str(v) for v in src_val)
        else:
            copied.append(str(src_val))

    def _collect_copied_values(
        self, cf: CopyField, raw_doc: Dict[str, Any]
    ) -> List[str]:
        copied: List[str] = []
        for src_name, src_val in raw_doc.items():
            if cf.matches(src_name):
                self._extract_field_val(src_val, copied)
        return copied

    def _apply_copied_to_field(
        self, dst_field: str, copied_values: List[str], processed: Dict[str, Any]
    ) -> None:
        if not copied_values:
            return
        existing = processed.get(dst_field)
        if not existing:
            processed[dst_field] = " ".join(copied_values)
        elif isinstance(existing, list):
            existing.extend(copied_values)
        else:
            processed[dst_field] = [str(existing)] + copied_values

    def process_document(self, raw_doc: Dict[str, Any]) -> Dict[str, Any]:
        """Applies default values and copyField transformations to incoming document."""
        processed = dict(raw_doc)

        for cf in self.copy_fields:
            copied_values = self._collect_copied_values(cf, raw_doc)
            self._apply_copied_to_field(cf.destination_field, copied_values, processed)

        return processed
