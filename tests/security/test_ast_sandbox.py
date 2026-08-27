#!/usr/bin/env python3
"""
Unit tests for AST Security Guard & Sandbox Isolation.
"""

import os
import sys

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    )

from security.sandbox import ASTSecurityGuard, validate_safe_code


def test_ast_guard_blocks_prohibited_modules():
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
        "import importlib",
        "import _thread",
        "import cgi",
        "import pipes",
        "import crypt",
        "import asyncore",
        "import distutils",
        "from subprocess import Popen",
        "from pickle import loads",
        "from ctypes import CDLL",
    ]
    for code in prohibited:
        err = validate_safe_code(code)
        assert err is not None, f"Expected blocked import for: {code}"
        assert "Security Exception" in err, f"Expected Security Exception for: {code}"


def test_ast_guard_blocks_reflection_and_dynamic_execution():
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
        "x.__bases__",
        "x.__mro__",
    ]
    for code in payloads:
        err = validate_safe_code(code)
        assert err is not None, f"Expected blocked reflection for: {code}"
        assert "Security Exception" in err, f"Expected Security Exception for: {code}"


def test_ast_guard_blocks_destructive_file_modes():
    modes = ["w", "a", "x", "w+", "a+", "r+"]
    for m in modes:
        code = f"open('test.txt', '{m}')"
        err = validate_safe_code(code)
        assert err is not None, f"Expected blocked file write mode: {m}"
        assert "Security Exception" in err, f"Expected Security Exception for mode {m}"


def test_ast_guard_allows_safe_code():
    safe_snippets = [
        "x = 1 + 2\ny = [i * 2 for i in range(10)]",
        "import math\nimport json\nimport collections",
        "import re\nmatch = re.search(r'test', 'testing')",
        "with open('safe.txt', 'r') as f:\n    data = f.read()",
        "def compute(a, b):\n    return a * b + 10",
    ]
    for code in safe_snippets:
        err = validate_safe_code(code)
        assert err is None, f"Safe code was unexpectedly rejected: {code} -> {err}"


def test_custom_ast_security_guard():
    custom_guard = ASTSecurityGuard(blocked_modules={"numpy"})
    assert custom_guard.validate("import numpy") is not None
    assert custom_guard.validate("import math") is None
