#!/usr/bin/env python3
"""
Path Traversal & Workspace Boundary Validation Engine.
Guarantees all file access remains strictly confined within authorized workspace boundaries.
"""

import os
from typing import Optional


def get_default_workspace_dir() -> str:
    """Finds project workspace root containing pyproject.toml / Makefile / .agents."""
    cur = os.path.abspath(os.path.dirname(__file__))
    while cur != os.path.dirname(cur):
        if (
            os.path.exists(os.path.join(cur, "pyproject.toml"))
            or os.path.exists(os.path.join(cur, "Makefile"))
            or os.path.exists(os.path.join(cur, ".agents"))
        ):
            return cur
        cur = os.path.dirname(cur)
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def is_safe_workspace_path(
    file_path: Optional[str], workspace_dir: Optional[str] = None
) -> bool:
    """
    Validates if a file path is securely confined within the workspace directory.
    Rejects:
    - None or empty string
    - Null-bytes (\x00)
    - Directory traversal sequences (../, ../../, symlink escapes)
    - Out-of-bounds absolute paths
    """
    if not file_path or not isinstance(file_path, str):
        return False
    if "\x00" in file_path:
        return False

    try:
        ws = workspace_dir or get_default_workspace_dir()
        ws_real = os.path.realpath(ws)
        target_path = (
            file_path if os.path.isabs(file_path) else os.path.join(ws_real, file_path)
        )
        real_path = os.path.realpath(target_path)

        common = os.path.commonpath([ws_real, real_path])
        if common != ws_real:
            return False

        sensitive_keywords = [
            ".ssh",
            ".aws",
            ".env",
            "etc/passwd",
            "etc/shadow",
            ".git/config",
        ]
        if any(k in real_path for k in sensitive_keywords):
            return False

        return True
    except Exception:
        return False


def resolve_safe_path(
    relative_or_abs_path: str,
    workspace_dir: Optional[str] = None,
    must_exist: bool = False,
) -> Optional[str]:
    """
    Resolves real path if safe, returning None if validation fails or file doesn't exist when required.
    """
    if not is_safe_workspace_path(relative_or_abs_path, workspace_dir=workspace_dir):
        return None

    ws = workspace_dir or get_default_workspace_dir()
    ws_real = os.path.realpath(ws)
    target_path = (
        relative_or_abs_path
        if os.path.isabs(relative_or_abs_path)
        else os.path.join(ws_real, relative_or_abs_path)
    )
    real_path = os.path.realpath(target_path)

    if must_exist and not os.path.exists(real_path):
        return None
    return real_path
