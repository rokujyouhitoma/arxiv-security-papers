#!/usr/bin/env python3
"""Validation & Path / Network Sanitization Security Package."""

from .input import detect_dangerous_patterns, sanitize_html
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
    "DEFAULT_ALLOWED_SCHEMES",
    "METADATA_IPS",
    "SSRFSecurityError",
    "create_safe_socket",
    "detect_dangerous_patterns",
    "get_default_workspace_dir",
    "is_safe_remote_url",
    "is_safe_workspace_path",
    "resolve_and_validate_ip",
    "resolve_safe_path",
    "safe_http_fetch",
    "sanitize_html",
]
