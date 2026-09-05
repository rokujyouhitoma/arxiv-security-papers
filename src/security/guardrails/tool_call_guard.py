#!/usr/bin/env python3
"""
Tool Call Guard & Invocation Policy Validator.
Protects against unauthorized tool execution, command chaining injection,
directory traversal, and accidental mutation in read-only operational modes.
Zero external runtime dependencies.
"""

from typing import Any, Dict, Optional, Set, Tuple

# Shell command injection and control-flow meta characters
SHELL_META_SEQUENCES = (";", "&&", "||", "|", "`", "$(")

# Path traversal markers
PATH_TRAVERSAL_SEQUENCES = ("../", "..\\", "~/")

# Default prefixes / names for state-mutating operations
MUTATING_TOOL_PREFIXES = (
    "write_",
    "delete_",
    "create_",
    "remove_",
    "drop_",
    "update_",
    "insert_",
    "edit_",
    "replace_",
)
MUTATING_TOOL_EXACT = {
    "run_command",
    "send_input",
    "kill",
    "apply_patch",
    "execute_script",
}


def _is_mutating_tool(tool_name: str) -> bool:
    """Returns True if tool name matches mutating prefixes or exact names."""
    if tool_name in MUTATING_TOOL_EXACT:
        return True
    return any(tool_name.startswith(p) for p in MUTATING_TOOL_PREFIXES)


def _check_string_safety(val: str, key_name: str) -> Optional[str]:
    """Inspects a string argument for path traversal and shell injection markers."""
    for seq in PATH_TRAVERSAL_SEQUENCES:
        if seq in val:
            return f"Path traversal sequence '{seq}' detected in argument '{key_name}'"
    for seq in SHELL_META_SEQUENCES:
        if seq in val:
            return f"Dangerous shell meta-sequence '{seq}' detected in argument '{key_name}'"
    return None


def _scan_dict(data: Dict[str, Any]) -> Optional[str]:
    """Scans dictionary values recursively."""
    for k, v in data.items():
        err = _scan_arguments_recursive(v, str(k))
        if err is not None:
            return err
    return None


def _scan_sequence(data: Any, key_name: str) -> Optional[str]:
    """Scans sequence items recursively."""
    for item in data:
        err = _scan_arguments_recursive(item, key_name)
        if err is not None:
            return err
    return None


def _scan_arguments_recursive(data: Any, key_name: str = "root") -> Optional[str]:
    """Recursively validates nested argument structures."""
    if isinstance(data, str):
        return _check_string_safety(data, key_name)
    if isinstance(data, dict):
        return _scan_dict(data)
    if isinstance(data, (list, tuple)):
        return _scan_sequence(data, key_name)
    return None


def _check_permission(
    tool_name: str, allowed_tools: Optional[Set[str]], is_ro: bool
) -> Optional[str]:
    """Validates tool against whitelist and read-only constraints."""
    if allowed_tools is not None and tool_name not in allowed_tools:
        return f"Tool '{tool_name}' is not in allowed tools whitelist"
    if is_ro and _is_mutating_tool(tool_name):
        return f"Mutating tool '{tool_name}' is prohibited in read-only mode"
    return None


class ToolCallGuard:
    """
    Policy engine and argument sanitizer for agent tool execution.
    """

    def __init__(
        self,
        allowed_tools: Optional[Set[str]] = None,
        default_read_only: bool = False,
    ) -> None:
        self.allowed_tools = allowed_tools
        self.default_read_only = default_read_only

    def validate_tool_call(
        self,
        tool_name: str,
        arguments: Dict[str, Any],
        read_only: Optional[bool] = None,
    ) -> Tuple[bool, Optional[str]]:
        """
        Validates tool invocation permissions and argument safety.
        Returns:
            (is_allowed, denial_reason)
        """
        is_ro = self.default_read_only if read_only is None else read_only
        perm_err = _check_permission(tool_name, self.allowed_tools, is_ro)
        if perm_err is not None:
            return False, perm_err

        arg_err = _scan_arguments_recursive(arguments)
        if arg_err is not None:
            return False, arg_err

        return True, None

    def sanitize_arguments(self, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """
        Sanitizes tool arguments by stripping path traversal prefixes.
        """
        sanitized: Dict[str, Any] = {}
        for k, v in arguments.items():
            if isinstance(v, str):
                cleaned = v.replace("../", "").replace("..\\", "")
                sanitized[k] = cleaned
            elif isinstance(v, dict):
                sanitized[k] = self.sanitize_arguments(v)
            else:
                sanitized[k] = v
        return sanitized
