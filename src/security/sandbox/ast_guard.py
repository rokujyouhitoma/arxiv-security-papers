#!/usr/bin/env python3
"""
AST Static Analysis Security Guard & Execution Sandbox.
Strictly blocks prohibited modules, system calls, dynamic reflection, and destructive file operations.
"""

import ast
from typing import Optional, Set, cast

BLOCKED_MODULES: Set[str] = {
    "subprocess",
    "socket",
    "pty",
    "shutil",
    "ctypes",
    "posix",
    "resource",
    "signal",
    "pickle",
    "shelve",
    "marshal",
    "importlib",
    "_thread",
    # PEP 594 removed & legacy modules
    "cgi",
    "cgitb",
    "pipes",
    "crypt",
    "asyncore",
    "asynchat",
    "smtpd",
    "distutils",
    "chunk",
    "imghdr",
    "mailcap",
    "msilib",
    "nis",
    "nntplib",
    "ossaudiodev",
    "sndhdr",
    "spwd",
    "sunau",
    "telnetlib",
    "uu",
    "xdrlib",
}

BLOCKED_CALLS: Set[str] = {
    "system",
    "popen",
    "spawn",
    "fork",
    "kill",
    "remove",
    "rmdir",
    "unlink",
    "truncate",
    "chmod",
    "chown",
}

BLOCKED_BUILTIN_FUNCS: Set[str] = {
    "eval",
    "exec",
    "compile",
    "__import__",
    "getattr",
    "setattr",
    "delattr",
    "globals",
    "locals",
    "vars",
}

BLOCKED_DUNDER_NAMES: Set[str] = {
    "__builtins__",
    "__dict__",
    "__class__",
    "__subclasses__",
    "__bases__",
    "__mro__",
}


class ASTSecurityGuard:
    """
    AST Static Analysis Guard for safe Python code verification.
    """

    def __init__(
        self,
        blocked_modules: Optional[Set[str]] = None,
        blocked_calls: Optional[Set[str]] = None,
        blocked_builtins: Optional[Set[str]] = None,
        blocked_dunders: Optional[Set[str]] = None,
    ):
        self.blocked_modules = (
            blocked_modules if blocked_modules is not None else set(BLOCKED_MODULES)
        )
        self.blocked_calls = (
            blocked_calls if blocked_calls is not None else set(BLOCKED_CALLS)
        )
        self.blocked_builtins = (
            blocked_builtins
            if blocked_builtins is not None
            else set(BLOCKED_BUILTIN_FUNCS)
        )
        self.blocked_dunders = (
            blocked_dunders
            if blocked_dunders is not None
            else set(BLOCKED_DUNDER_NAMES)
        )

    def _is_blocked_module(self, name: str) -> bool:
        """Checks if a module name or root is blocked."""
        mod_root = name.split(".")[0]
        return name in self.blocked_modules or mod_root in self.blocked_modules

    def _check_import_names(self, node: ast.Import) -> Optional[str]:
        """Checks plain import statement names."""
        for alias in node.names:
            if self._is_blocked_module(alias.name):
                return f"Security Exception: Import of module '{alias.name}' is prohibited."
        return None

    def _check_import_from(self, node: ast.ImportFrom) -> Optional[str]:
        """Checks from-import statement module."""
        if node.module and self._is_blocked_module(node.module):
            return f"Security Exception: Import from module '{node.module}' is prohibited."
        return None

    def _check_import(self, node: ast.AST) -> Optional[str]:
        if isinstance(node, ast.Import):
            return self._check_import_names(node)
        if isinstance(node, ast.ImportFrom):
            return self._check_import_from(node)
        return None

    def _is_destructive_mode(self, mode_arg: ast.AST) -> bool:
        """Checks if open mode contains write or destructive flags."""
        if isinstance(mode_arg, ast.Constant) and isinstance(mode_arg.value, str):
            return any(c in mode_arg.value for c in ("w", "a", "x", "+"))
        return False

    def _check_open_call(self, node: ast.Call) -> Optional[str]:
        if not (isinstance(node.func, ast.Name) and node.func.id == "open"):
            return None
        if len(node.args) >= 2 and self._is_destructive_mode(node.args[1]):
            mode_val = cast(ast.Constant, node.args[1]).value
            return f"Security Exception: File modification mode '{mode_val}' in open() is prohibited."
        return None

    def _check_attribute_call(self, node: ast.Attribute) -> Optional[str]:
        """Checks attribute method call against blocked calls and builtins."""
        attr = node.attr
        if attr in self.blocked_calls or attr in self.blocked_builtins:
            return f"Security Exception: Call to '{attr}' is prohibited."
        return None

    def _check_name_call(self, node: ast.Call, func: ast.Name) -> Optional[str]:
        """Checks direct name function call."""
        if func.id in self.blocked_builtins:
            return f"Security Exception: Dynamic call to '{func.id}' is prohibited."
        return self._check_open_call(node)

    def _check_call(self, node: ast.Call) -> Optional[str]:
        if isinstance(node.func, ast.Attribute):
            return self._check_attribute_call(node.func)
        if isinstance(node.func, ast.Name):
            return self._check_name_call(node, node.func)
        return None

    def _check_dunder(self, node: ast.AST) -> Optional[str]:
        if isinstance(node, ast.Attribute) and node.attr in self.blocked_dunders:
            return (
                f"Security Exception: Access to attribute '{node.attr}' is prohibited."
            )
        if isinstance(node, ast.Name) and node.id in self.blocked_dunders:
            return f"Security Exception: Reference to '{node.id}' is prohibited."
        return None

    def _check_node(self, node: ast.AST) -> Optional[str]:
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            return self._check_import(node)
        if isinstance(node, ast.Call):
            return self._check_call(node)
        if isinstance(node, (ast.Attribute, ast.Name)):
            return self._check_dunder(node)
        return None

    def _scan_ast_nodes(self, tree: ast.AST) -> Optional[str]:
        """Walks AST and returns first security error."""
        for node in ast.walk(tree):
            err = self._check_node(node)
            if err is not None:
                return err
        return None

    def validate(self, code_str: str) -> Optional[str]:
        """
        Validates Python code string against security policies.
        Returns None if code is clean, or a Security Exception message if violations are found.
        """
        if not code_str or not isinstance(code_str, str):
            return None

        try:
            tree = ast.parse(code_str)
        except SyntaxError as e:
            return f"Syntax error: {str(e)}"

        return self._scan_ast_nodes(tree)


# Default shared guard instance
_DEFAULT_GUARD = ASTSecurityGuard()


def validate_safe_code(code_str: str) -> Optional[str]:
    """
    Convenience function validating Python code using the default ASTSecurityGuard.
    Returns None if safe, or an informative Security Exception message.
    """
    return _DEFAULT_GUARD.validate(code_str)
