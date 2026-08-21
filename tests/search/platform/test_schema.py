"""
Tests for Managed Schema, Dynamic Fields, and Copy Fields (src/search/platform/schema/).
"""

from search.platform.schema import (
    DynamicField,
    FieldDefinition,
    FieldType,
    ManagedSchema,
)


def test_managed_schema_types_and_defaults():
    schema = ManagedSchema(unique_key="id")
    schema.add_field(
        FieldDefinition("title", FieldType.TEXT, indexed=True, stored=True)
    )
    schema.add_field(
        FieldDefinition(
            "year", FieldType.INT, indexed=True, stored=True, doc_values=True
        )
    )

    f_title = schema.get_field_definition("title")
    assert f_title.field_type == FieldType.TEXT
    assert f_title.stored is True

    # Fallback default
    f_unknown = schema.get_field_definition("custom_desc")
    assert f_unknown.field_type == FieldType.TEXT


def test_dynamic_fields_pattern_matching():
    schema = ManagedSchema()
    schema.add_dynamic_field(DynamicField("*_tag", FieldType.STRING, doc_values=True))

    f_sec_tag = schema.get_field_definition("security_tag")
    assert f_sec_tag.field_type == FieldType.STRING
    assert f_sec_tag.doc_values is True

    f_author_s = schema.get_field_definition("first_author_s")
    assert f_author_s.field_type == FieldType.STRING


def test_copy_fields_aggregation():
    schema = ManagedSchema()
    schema.add_copy_field("title", "_text_")
    schema.add_copy_field("abstract", "_text_")
    schema.add_copy_field("tags", "_text_")

    doc = {
        "title": "Quantum Key Distribution",
        "abstract": "Secure communication protocol",
        "tags": ["qkd", "cryptography"],
    }
    processed = schema.process_document(doc)
    assert "_text_" in processed
    text_content = processed["_text_"]
    if isinstance(text_content, list):
        text_content = " ".join(text_content)
    assert "Quantum Key Distribution" in text_content
    assert "qkd" in text_content
