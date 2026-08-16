#!/usr/bin/env python3
"""
Unit tests for DSN-11 Security Hardening.
Verifies AST Security Guard bypass resistance, Pickle-free enforcement, and Path Traversal boundary checks.
"""

import os
import sys

if "src" not in sys.path:
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

import pytest
from observability_mcp_server import validate_safe_code
from mcp_server import is_safe_workspace_path, WORKSPACE_DIR


def test_ast_guard_blocks_prohibited_modules():
    """Verify all prohibited low-level and deserialization modules are strictly rejected."""
    prohibited = [
        "import subprocess",
        "import socket",
        "import ctypes",
        "import pickle",
        "import shelve",
        "import marshal",
        "import pty",
        "import shutil",
        "import posix",
        "import resource",
        "import signal",
        "from subprocess import Popen",
        "from pickle import loads",
        "from ctypes import CDLL",
    ]
    for code in prohibited:
        err = validate_safe_code(code)
        assert err is not None, f"Expected blocked import for: {code}"
        assert "Security Exception" in err, f"Expected Security Exception for: {code}"


def test_ast_guard_blocks_reflection_and_dynamic_execution():
    """Verify reflection, dynamic eval, and dunder attribute traversals are rejected."""
    payloads = [
        "eval('1 + 1')",
        "exec('print(1)')",
        "compile('x = 1', '<string>', 'exec')",
        "__import__('os').system('id')",
        "getattr(os, 'system')('id')",
        "setattr(os, 'test', 'id')",
        "globals()['os'].system('id')",
        "locals()['os'].system('id')",
        "vars(os)['system']('id')",
        "__builtins__.__dict__['eval']('1+1')",
        "x.__class__.__subclasses__()",
    ]
    for code in payloads:
        err = validate_safe_code(code)
        assert err is not None, f"Expected blocked reflection for: {code}"
        assert "Security Exception" in err, f"Expected Security Exception for: {code}"


def test_ast_guard_blocks_destructive_file_modes():
    """Verify file modification/append modes in open() are blocked during profiling."""
    destructive = [
        "open('test.txt', 'w')",
        "open('test.txt', 'wb')",
        "open('test.txt', 'a')",
        "open('test.txt', 'r+')",
        "open('test.txt', 'w+')",
    ]
    for code in destructive:
        err = validate_safe_code(code)
        assert err is not None, f"Expected blocked file write mode for: {code}"
        assert "Security Exception" in err, f"Expected Security Exception for: {code}"

    # Read mode should be allowed
    assert validate_safe_code("open('test.txt', 'r')") is None
    assert validate_safe_code("open('test.txt', 'rb')") is None


def test_ast_guard_allows_safe_data_processing():
    """Verify safe algorithmic and data processing code is accepted."""
    safe_snippets = [
        "total = sum(x**2 for x in range(100))",
        "import json\nd = json.loads('{\"key\": 123}')",
        "import math\nr = math.sqrt(256)",
        "import re\nm = re.findall(r'\\w+', 'hello world')",
        "data = [1, 5, 2, 4, 3]\ndata.sort()",
    ]
    for code in safe_snippets:
        err = validate_safe_code(code)
        assert err is None, f"Expected safe code to pass, but got error: {err}"


def test_is_safe_workspace_path_boundaries():
    """Verify workspace path containment and sensitive file filtering."""
    # Safe path within workspace
    safe_path = os.path.join(WORKSPACE_DIR, "outputs", "okf_papers", "paper.md")
    assert is_safe_workspace_path(safe_path) is True

    # Path traversal outside workspace
    traversal_path = os.path.join(WORKSPACE_DIR, "..", "..", "etc", "passwd")
    assert is_safe_workspace_path(traversal_path) is False

    # Path prefix confusion (e.g. /workspace/arxiv-security-papers-fake)
    fake_sibling = os.path.join(os.path.dirname(WORKSPACE_DIR), os.path.basename(WORKSPACE_DIR) + "-fake", "paper.md")
    assert is_safe_workspace_path(fake_sibling) is False

    # Sensitive files within workspace
    sensitive_path = os.path.join(WORKSPACE_DIR, ".env")
    assert is_safe_workspace_path(sensitive_path) is False
    ssh_path = os.path.join(WORKSPACE_DIR, ".ssh", "id_rsa")
    assert is_safe_workspace_path(ssh_path) is False
