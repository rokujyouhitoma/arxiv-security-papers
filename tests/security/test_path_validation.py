#!/usr/bin/env python3
"""
Unit tests for Path Traversal Validation and Input Pattern Sanitization.
"""

import os
import sys

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    )

from security.validation import (
    detect_dangerous_patterns,
    get_default_workspace_dir,
    is_safe_workspace_path,
    resolve_safe_path,
    sanitize_html,
)


def test_is_safe_workspace_path():
    ws = get_default_workspace_dir()

    # Valid in-tree paths
    assert is_safe_workspace_path("Makefile")
    assert is_safe_workspace_path("src/fetcher/arxiv_okf_fetcher.py")
    assert is_safe_workspace_path(os.path.join(ws, "docs", "README.md"))

    # Invalid traversal paths
    assert not is_safe_workspace_path("../../etc/passwd")
    assert not is_safe_workspace_path("/etc/passwd")
    assert not is_safe_workspace_path("/var/log/syslog")
    assert not is_safe_workspace_path("docs/../../../etc/shadow")

    # Null bytes and falsy values
    assert not is_safe_workspace_path(None)
    assert not is_safe_workspace_path("")
    assert not is_safe_workspace_path("Makefile\x00.png")

    # Sensitive paths in workspace
    assert not is_safe_workspace_path(".env")
    assert not is_safe_workspace_path(".ssh/id_rsa")


def test_resolve_safe_path():
    ws = get_default_workspace_dir()

    # Existent file
    resolved = resolve_safe_path("Makefile", must_exist=True)
    assert resolved is not None
    assert resolved.startswith(ws)

    # Non-existent file with must_exist=True
    non_existent = resolve_safe_path("does_not_exist_xyz.txt", must_exist=True)
    assert non_existent is None

    # Traversal resolution returns None
    traversal = resolve_safe_path("../../etc/passwd")
    assert traversal is None


def test_input_pattern_detection():
    clean_input = "Machine learning security in cloud networks"
    assert detect_dangerous_patterns(clean_input) == []

    sqli_input = "SELECT * FROM papers WHERE id = '1' OR '1'='1'"
    detected = detect_dangerous_patterns(sqli_input)
    assert any("SQLI" in d for d in detected)

    xss_input = "<script>alert('xss')</script>"
    detected_xss = detect_dangerous_patterns(xss_input)
    assert any("XSS" in d for d in detected_xss)

    cmd_input = "rm -rf /tmp/data"
    detected_cmd = detect_dangerous_patterns(cmd_input)
    assert any("COMMAND_INJECTION" in d for d in detected_cmd)


def test_sanitize_html():
    raw_html = "<script>alert(1)</script>&'\""
    sanitized = sanitize_html(raw_html)
    assert "<script>" not in sanitized
    assert "&lt;script&gt;" in sanitized
    assert "&quot;" in sanitized
