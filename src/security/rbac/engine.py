#!/usr/bin/env python3
"""
Unified Role-Based Access Control (RBAC) Engine.
Enforces resource-level and table-level permissions across Database SQL, Web API, and MCP tools.
"""

from collections import defaultdict
from typing import Dict, Set, Union

from .context import Role, SecurityContext


class PermissionDeniedError(Exception):
    """Raised when an operation is executed without necessary permissions."""

    pass


class DCLPermissionDeniedError(PermissionDeniedError):
    """Raised when a SQL DCL/DML operation violates table permissions (Database compatibility)."""

    pass


class AccessController:
    """
    Unified Role-Based Access Control (RBAC) Engine.
    Manages role hierarchy, resource grants, and table-level security.
    """

    def __init__(self, default_role: str = "admin") -> None:
        self.current_role: str = default_role
        # role -> resource_name -> set of uppercase permissions
        self._grants: Dict[str, Dict[str, Set[str]]] = defaultdict(
            lambda: defaultdict(set)
        )
        self._initialize_default_roles()

    def _initialize_default_roles(self) -> None:
        """Initializes default system roles and baseline permissions."""
        # Admin has ALL on wildcard '*'
        self._grants["admin"]["*"].add("ALL")
        self._grants["admin"]["*"].add("ADMIN")
        self._grants["admin"]["*"].add("EXECUTE")

        # Analyst can SELECT/INSERT on data and READ/EXECUTE on standard tools
        self._grants["analyst"]["*"].add("SELECT")
        self._grants["analyst"]["*"].add("INSERT")
        self._grants["analyst"]["*"].add("READ")
        self._grants["analyst"]["*"].add("EXECUTE")

        # Guest has read-only access (SELECT / READ)
        self._grants["guest"]["*"].add("SELECT")
        self._grants["guest"]["*"].add("READ")

    def grant(
        self, permission: str, resource_name: str, role: Union[str, Role]
    ) -> None:
        """Grants permission on resource_name to role."""
        role_str = role.value if isinstance(role, Role) else role.lower()
        perm = permission.upper()
        self._grants[role_str][resource_name].add(perm)

    def revoke(
        self, permission: str, resource_name: str, role: Union[str, Role]
    ) -> None:
        """Revokes permission on resource_name from role."""
        role_str = role.value if isinstance(role, Role) else role.lower()
        perm = permission.upper()
        self._grants[role_str][resource_name].discard(perm)
        if "ALL" in self._grants[role_str][resource_name] and perm != "ALL":
            self._grants[role_str][resource_name].discard("ALL")

    def check_permission(
        self,
        role_or_context: Union[str, Role, SecurityContext],
        resource_name: str,
        required_permission: str,
    ) -> bool:
        """
        Validates if role or SecurityContext holds required_permission (or ALL) on resource_name (or '*').
        """
        if isinstance(role_or_context, SecurityContext):
            role_str = role_or_context.role.value
            req = required_permission.upper()
            if (
                req in role_or_context.extra_permissions
                or "ALL" in role_or_context.extra_permissions
            ):
                return True
        elif isinstance(role_or_context, Role):
            role_str = role_or_context.value
        else:
            role_str = str(role_or_context).lower()

        req = required_permission.upper()
        role_perms = self._grants.get(role_str, {})

        # 1. Check direct resource permissions
        res_perms = role_perms.get(resource_name, set())
        if "ALL" in res_perms or req in res_perms:
            return True

        # 2. Check wildcard '*' permissions
        wildcard_perms = role_perms.get("*", set())
        if "ALL" in wildcard_perms or req in wildcard_perms:
            return True

        return False

    def enforce_permission(
        self,
        role_or_context: Union[str, Role, SecurityContext],
        resource_name: str,
        required_permission: str,
    ) -> None:
        """Raises DCLPermissionDeniedError if permission check fails."""
        if not self.check_permission(
            role_or_context, resource_name, required_permission
        ):
            role_name = (
                role_or_context.role.value
                if isinstance(role_or_context, SecurityContext)
                else (
                    role_or_context.value
                    if isinstance(role_or_context, Role)
                    else str(role_or_context)
                )
            )
            raise DCLPermissionDeniedError(
                f"Permission denied: role '{role_name}' does not have '{required_permission}' on '{resource_name}'"
            )


# Default shared singleton controller
_DEFAULT_CONTROLLER = AccessController()


def get_access_controller() -> AccessController:
    """Returns default AccessController singleton."""
    return _DEFAULT_CONTROLLER
