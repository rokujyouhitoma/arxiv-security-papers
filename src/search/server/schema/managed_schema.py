#!/usr/bin/env python3
"""
Solr-style Managed Index Schema.
Defines field types, dynamic properties, and field weightings.
"""

from typing import Dict, List, Optional, Set


class FieldType:
    TEXT = "text"
    KEYWORD = "keyword"
    DATE = "date"
    INTEGER = "int"
    FLOAT = "float"
    VECTOR = "vector"


class FieldDefinition:
    """Defines a single schema field."""

    def __init__(
        self,
        name: str,
        field_type: str = FieldType.TEXT,
        indexed: bool = True,
        stored: bool = True,
        doc_values: bool = False,
        boost: float = 1.0,
    ) -> None:
        self.name = name
        self.field_type = field_type
        self.indexed = indexed
        self.stored = stored
        self.doc_values = doc_values
        self.boost = boost


class ManagedIndexSchema:
    """
    Solr-like schema managing document field definitions and default boosts.
    """

    DEFAULT_FIELDS = [
        FieldDefinition(
            "id",
            FieldType.KEYWORD,
            indexed=True,
            stored=True,
            doc_values=True,
            boost=1.0,
        ),
        FieldDefinition(
            "title",
            FieldType.TEXT,
            indexed=True,
            stored=True,
            doc_values=False,
            boost=4.0,
        ),
        FieldDefinition(
            "author",
            FieldType.TEXT,
            indexed=True,
            stored=True,
            doc_values=True,
            boost=3.5,
        ),
        FieldDefinition(
            "keywords",
            FieldType.KEYWORD,
            indexed=True,
            stored=True,
            doc_values=True,
            boost=3.0,
        ),
        FieldDefinition(
            "tags",
            FieldType.KEYWORD,
            indexed=True,
            stored=True,
            doc_values=True,
            boost=2.5,
        ),
        FieldDefinition(
            "description",
            FieldType.TEXT,
            indexed=True,
            stored=True,
            doc_values=False,
            boost=2.0,
        ),
        FieldDefinition(
            "abstract",
            FieldType.TEXT,
            indexed=True,
            stored=True,
            doc_values=False,
            boost=2.0,
        ),
        FieldDefinition(
            "published_date",
            FieldType.DATE,
            indexed=True,
            stored=True,
            doc_values=True,
            boost=1.0,
        ),
        FieldDefinition(
            "category",
            FieldType.KEYWORD,
            indexed=True,
            stored=True,
            doc_values=True,
            boost=1.0,
        ),
        FieldDefinition(
            "content",
            FieldType.TEXT,
            indexed=True,
            stored=False,
            doc_values=False,
            boost=1.0,
        ),
    ]

    def __init__(self, fields: Optional[List[FieldDefinition]] = None) -> None:
        self.fields: Dict[str, FieldDefinition] = {}
        for f in fields or self.DEFAULT_FIELDS:
            self.fields[f.name] = f

    def get_field(self, name: str) -> Optional[FieldDefinition]:
        return self.fields.get(name)

    def get_boost(self, name: str) -> float:
        f = self.get_field(name)
        return f.boost if f else 1.0

    def get_doc_value_fields(self) -> Set[str]:
        return {f.name for f in self.fields.values() if f.doc_values}
