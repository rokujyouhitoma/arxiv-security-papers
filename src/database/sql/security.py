#!/usr/bin/env python3
"""
Data Control Language (DCL) Role-Based Access Control (RBAC) & Security Policy.
Enforces table-level permissions (SELECT, INSERT, UPDATE, DELETE, ALL) for user roles
within the self-contained database engine (Zero-dependency).
"""

from collections import defaultdict
from typing import Dict, Set


class DCLPermissionDeniedError(Exception):
    """Raised when an operation is executed without necessary table permissions."""

    pass


class AccessController:
    """
    Self-contained Role-Based Access Control (RBAC) engine for database DCL SQL commands.
    """

    def __init__(self) -> None:
        self.current_role = "admin"
        # role -> table_name -> set of permissions
        self._grants: Dict[str, Dict[str, Set[str]]] = defaultdict(
            lambda: defaultdict(set)
        )
        self._initialize_default_roles()

    def _initialize_default_roles(self) -> None:
        """Initializes default system roles and baseline permissions."""
        # Admin has ALL on wildcard '*'
        self._grants["admin"]["*"].add("ALL")
        self._grants["analyst"]["*"].add("SELECT")
        self._grants["analyst"]["*"].add("INSERT")
        self._grants["guest"]["*"].add("SELECT")

    def grant(self, permission: str, table_name: str, role: str) -> None:
        """Grants permission on table_name to role."""
        perm = permission.upper()
        self._grants[role][table_name].add(perm)

    def revoke(self, permission: str, table_name: str, role: str) -> None:
        """Revokes permission on table_name from role."""
        perm = permission.upper()
        self._grants[role][table_name].discard(perm)
        if "ALL" in self._grants[role][table_name] and perm != "ALL":
            self._grants[role][table_name].discard("ALL")

    def check_permission(
        self, role: str, table_name: str, required_permission: str
    ) -> bool:
        """
        Validates if role holds required_permission (or ALL) on table_name (or wildcard '*').
        """
        req = required_permission.upper()
        role_table_perms = self._grants.get(role, {})

        # 1. Check direct table permissions
        table_perms = role_table_perms.get(table_name, set())
        if "ALL" in table_perms or req in table_perms:
            return True

        # 2. Check wildcard '*' table permissions
        wildcard_perms = role_table_perms.get("*", set())
        if "ALL" in wildcard_perms or req in wildcard_perms:
            return True

        return False

    def enforce_permission(
        self, role: str, table_name: str, required_permission: str
    ) -> None:
        """Raises DCLPermissionDeniedError if permission check fails."""
        if not self.check_permission(role, table_name, required_permission):
            raise DCLPermissionDeniedError(
                f"Permission denied: role '{role}' does not have '{required_permission}' on table '{table_name}'"
            )
