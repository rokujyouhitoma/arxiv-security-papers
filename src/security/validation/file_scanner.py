#!/usr/bin/env python3
"""
File Scanner & Safe Ingestion Parser Hardening Module.
Provides defused XML parsing (XXE / Billion Laughs protection),
decompression bomb quota enforcement, and PDF safety heuristics.
Zero external runtime dependencies (Python standard library only).
"""

import re
import xml.etree.ElementTree as ET
from typing import Optional, Tuple, Union
from xml.parsers import expat


class IngestSecurityError(ValueError):
    """Base exception for unsafe external input ingestion."""

    pass


class DefusedXMLError(IngestSecurityError):
    """Raised when XML contains prohibited DTD, entities, or external references."""

    pass


class DecompressionBombError(IngestSecurityError):
    """Raised when decompressed content violates quota or ratio thresholds."""

    pass


# Default thresholds
DEFAULT_MAX_UNCOMPRESSED_BYTES: int = 50 * 1024 * 1024  # 50 MB
DEFAULT_MAX_EXPANSION_RATIO: float = 50.0  # 50x
DEFAULT_MAX_PDF_PAGES: int = 200


def _check_expansion_ratio(
    compressed_size: int, uncompressed_size: int, max_ratio: float
) -> None:
    """Validates that ratio of uncompressed to compressed does not exceed threshold."""
    if compressed_size > 0 and uncompressed_size > 1024 * 1024:
        ratio = uncompressed_size / compressed_size
        if ratio > max_ratio:
            raise DecompressionBombError(
                f"Expansion ratio {ratio:.1f}x exceeds threshold {max_ratio:.1f}x"
            )


def validate_safe_decompression(
    compressed_size: int,
    uncompressed_size: int,
    max_ratio: float = DEFAULT_MAX_EXPANSION_RATIO,
    max_size_bytes: int = DEFAULT_MAX_UNCOMPRESSED_BYTES,
) -> bool:
    """
    Validates decompressed payload size against absolute limit and expansion ratio.
    Prevents Zip Bomb / Gzip Bomb memory exhaustion denial-of-service.
    """
    if uncompressed_size < 0 or compressed_size < 0:
        raise DecompressionBombError("Invalid negative byte length")

    if uncompressed_size > max_size_bytes:
        raise DecompressionBombError(
            f"Decompressed size {uncompressed_size} exceeds quota {max_size_bytes}"
        )

    _check_expansion_ratio(compressed_size, uncompressed_size, max_ratio)
    return True


def _forbid_dtd_handler(
    doctype_name: str,
    system_id: Optional[str],
    public_id: Optional[str],
    has_internal_subset: int,
) -> None:
    """Callback to reject DTD declarations."""
    raise DefusedXMLError(f"XML DTD declarations are prohibited: {doctype_name}")


def _forbid_entity_handler(
    entity_name: str,
    is_parameter_entity: int,
    value: Optional[str],
    base: Optional[str],
    system_id: Optional[str],
    public_id: Optional[str],
    notation_name: Optional[str],
) -> None:
    """Callback to reject XML entity declarations."""
    raise DefusedXMLError(f"XML Entity declaration is prohibited: &{entity_name};")


def _forbid_external_entity_handler(
    context: Optional[str],
    base: Optional[str],
    system_id: Optional[str],
    public_id: Optional[str],
) -> int:
    """Callback to reject external entity references (XXE)."""
    raise DefusedXMLError(f"XML External entity reference is prohibited: {system_id}")


def _configure_defused_parser(parser: expat.XMLParserType, forbid_dtd: bool) -> None:
    """Attaches security hooks to the expat parser."""
    if forbid_dtd:
        parser.StartDoctypeDeclHandler = _forbid_dtd_handler
    parser.EntityDeclHandler = _forbid_entity_handler
    parser.ExternalEntityRefHandler = _forbid_external_entity_handler


def parse_safe_xml(
    xml_content: Union[bytes, str],
    forbid_dtd: bool = True,
) -> ET.Element:
    """
    Parses XML data safely without permitting XXE or entity expansion attacks.
    Returns standard xml.etree.ElementTree.Element root.
    """
    raw_bytes = (
        xml_content.encode("utf-8") if isinstance(xml_content, str) else xml_content
    )

    expat_parser = expat.ParserCreate("utf-8")
    _configure_defused_parser(expat_parser, forbid_dtd)

    tree_builder = ET.TreeBuilder()

    def start_elem(name: str, attrs: dict[str, str]) -> None:
        tree_builder.start(name, attrs)

    def end_elem(name: str) -> None:
        tree_builder.end(name)

    expat_parser.StartElementHandler = start_elem
    expat_parser.EndElementHandler = end_elem
    expat_parser.CharacterDataHandler = tree_builder.data

    try:
        expat_parser.Parse(raw_bytes, True)
    except expat.ExpatError as e:
        raise DefusedXMLError(f"Malformed or unsafe XML: {e}")

    root = tree_builder.close()
    if root is None:
        raise DefusedXMLError("Empty XML root element")
    return root


# Regex patterns for PDF safety checks
_PDF_PAGE_PATTERN = re.compile(rb"/Type\s*/Page\b")
_PDF_PAGES_ROOT_PATTERN = re.compile(rb"/Type\s*/Pages\b")
_PDF_DANGEROUS_ACTIONS: list[tuple[re.Pattern[bytes], str]] = [
    (re.compile(rb"/JavaScript\b"), "embedded JavaScript action"),
    (re.compile(rb"/JS\b"), "embedded JS script"),
    (re.compile(rb"/Launch\b"), "arbitrary executable Launch action"),
]


def _check_pdf_dangerous_actions(pdf_bytes: bytes) -> Optional[str]:
    """Scans for executable or script action dictionaries in PDF byte streams."""
    for pattern, description in _PDF_DANGEROUS_ACTIONS:
        if pattern.search(pdf_bytes):
            return description
    return None


def _estimate_pdf_page_count(pdf_bytes: bytes) -> int:
    """Counts page object definitions while subtracting root catalog Pages."""
    total_matches = len(_PDF_PAGE_PATTERN.findall(pdf_bytes))
    root_pages = len(_PDF_PAGES_ROOT_PATTERN.findall(pdf_bytes))
    return max(0, total_matches - root_pages)


def validate_pdf_safety_metadata(
    pdf_bytes: bytes,
    max_pages: int = DEFAULT_MAX_PDF_PAGES,
    max_file_size: int = DEFAULT_MAX_UNCOMPRESSED_BYTES,
) -> Tuple[bool, Optional[str]]:
    """
    Performs heuristic static inspection on PDF bytes to reject oversized files,
    excessive page counts (PDF bomb), and active embedded JavaScript/Launch payloads.
    Returns:
        (is_safe, failure_reason)
    """
    if not pdf_bytes.startswith(b"%PDF-"):
        return False, "invalid magic header: not a PDF file"

    if len(pdf_bytes) > max_file_size:
        return False, f"file size {len(pdf_bytes)} exceeds maximum {max_file_size}"

    danger = _check_pdf_dangerous_actions(pdf_bytes)
    if danger is not None:
        return False, f"prohibited action detected: {danger}"

    estimated_pages = _estimate_pdf_page_count(pdf_bytes)
    if estimated_pages > max_pages:
        return (
            False,
            f"estimated page count {estimated_pages} exceeds limit {max_pages}",
        )

    return True, None
