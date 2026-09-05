#!/usr/bin/env python3
"""Validation & Path / Network / Ingestion Sanitization Security Package."""

from .file_scanner import (
    DEFAULT_MAX_EXPANSION_RATIO,
    DEFAULT_MAX_PDF_PAGES,
    DEFAULT_MAX_UNCOMPRESSED_BYTES,
    DecompressionBombError,
    DefusedXMLError,
    IngestSecurityError,
    parse_safe_xml,
    validate_pdf_safety_metadata,
    validate_safe_decompression,
)
from .input import detect_dangerous_patterns, sanitize_html
from .mime import (
    MIME_GIF,
    MIME_GZIP,
    MIME_JPEG,
    MIME_JSON,
    MIME_PDF,
    MIME_PNG,
    MIME_TAR,
    MIME_TEXT,
    MIME_XML,
    MIME_ZIP,
    detect_mime_type_from_bytes,
    is_safe_text_content,
    verify_magic_bytes,
)
from .network import (
    DEFAULT_ALLOWED_SCHEMES,
    METADATA_IPS,
    SSRFSecurityError,
    create_safe_socket,
    is_safe_remote_url,
    resolve_and_validate_ip,
    safe_http_fetch,
)
from .path import get_default_workspace_dir, is_safe_workspace_path, resolve_safe_path

__all__ = [
    # File Scanner & Parser Hardening
    "DEFAULT_MAX_EXPANSION_RATIO",
    "DEFAULT_MAX_PDF_PAGES",
    "DEFAULT_MAX_UNCOMPRESSED_BYTES",
    "DecompressionBombError",
    "DefusedXMLError",
    "IngestSecurityError",
    "parse_safe_xml",
    "validate_pdf_safety_metadata",
    "validate_safe_decompression",
    # Input
    "detect_dangerous_patterns",
    "sanitize_html",
    # MIME & Magic Bytes
    "MIME_GIF",
    "MIME_GZIP",
    "MIME_JPEG",
    "MIME_JSON",
    "MIME_PDF",
    "MIME_PNG",
    "MIME_TAR",
    "MIME_TEXT",
    "MIME_XML",
    "MIME_ZIP",
    "detect_mime_type_from_bytes",
    "is_safe_text_content",
    "verify_magic_bytes",
    # Network & SSRF
    "DEFAULT_ALLOWED_SCHEMES",
    "METADATA_IPS",
    "SSRFSecurityError",
    "create_safe_socket",
    "is_safe_remote_url",
    "resolve_and_validate_ip",
    "safe_http_fetch",
    # Path
    "get_default_workspace_dir",
    "is_safe_workspace_path",
    "resolve_safe_path",
]
