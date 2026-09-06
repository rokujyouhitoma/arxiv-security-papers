#!/usr/bin/env python3
"""
Declarative Pure Python Class DSL for Ontology Authoring.
Provides decorators and descriptors allowing domain experts to define ontologies
as native Python classes without any coupling to the underlying storage or serializer.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Type, TypeVar

T = TypeVar("T", bound=Type[Any])


@dataclass
class PropertyField:
    """Base descriptor representing a property declaration in an ontology class."""

    uri: Optional[str] = None
    label: str = ""
    comment: str = ""
    range: Optional[str] = None
    is_functional: bool = False
    name: str = ""

    def __set_name__(self, owner: Type[Any], name: str) -> None:
        self.name = name
        if not self.uri:
            self.uri = name


@dataclass
class ObjectPropertyField(PropertyField):
    """Descriptor declaring an owl:ObjectProperty on an ontology class."""

    inverse_of: Optional[str] = None
    is_transitive: bool = False
    is_symmetric: bool = False


@dataclass
class DatatypePropertyField(PropertyField):
    """Descriptor declaring an owl:DatatypeProperty on an ontology class."""

    pass


@dataclass
class ClassDeclaration:
    """Metadata container for decorated ontology classes."""

    uri: str
    label: str = ""
    comment: str = ""
    sub_class_of: Optional[str] = None
    disjoint_with: List[str] = field(default_factory=list)
    fields: Dict[str, PropertyField] = field(default_factory=dict)


def ontology_class(
    uri: Optional[str] = None,
    label: str = "",
    comment: str = "",
    sub_class_of: Optional[str] = None,
    disjoint_with: Optional[List[str]] = None,
) -> Callable[[T], T]:
    """
    Decorator marking a standard Python class as a formal Ontology Class definition.
    """

    def decorator(cls: T) -> T:
        resolved_uri = uri or cls.__name__
        fields: Dict[str, PropertyField] = {}
        for attr_name, attr_val in list(cls.__dict__.items()):
            if isinstance(attr_val, PropertyField):
                fields[attr_name] = attr_val

        meta = ClassDeclaration(
            uri=resolved_uri,
            label=label or cls.__name__,
            comment=comment or (cls.__doc__ or "").strip(),
            sub_class_of=sub_class_of,
            disjoint_with=list(disjoint_with or []),
            fields=fields,
        )
        setattr(cls, "_ontology_meta", meta)
        return cls

    return decorator
