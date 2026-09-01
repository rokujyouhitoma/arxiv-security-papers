#!/usr/bin/env python3
"""
Unified Role-Based Access Control (RBAC) Engine.
Enforces resource-level and table-level permissions across Database SQL, Web API, and MCP tools.
"""

from collections import defaultdict
from typing import Dict, Set, Tuple, Union

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

    def _has_perm_or_all(self, perms: Set[str], req: str) -> bool:
        """Checks if required permission or wildcard ALL is in permission set."""
        return "ALL" in perms or req in perms

    def _resolve_context_role(
        self, role_or_context: Union[str, Role, SecurityContext], req: str
    ) -> Tuple[str, bool]:
        """Resolves role string and checks extra permissions on SecurityContext."""
        if isinstance(role_or_context, SecurityContext):
            has_extra = self._has_perm_or_all(role_or_context.extra_permissions, req)
            return role_or_context.role.value, has_extra
        if isinstance(role_or_context, Role):
            return role_or_context.value, False
        return str(role_or_context).lower(), False

    def check_permission(
        self,
        role_or_context: Union[str, Role, SecurityContext],
        resource_name: str,
        required_permission: str,
    ) -> bool:
        """
        Validates if role or SecurityContext holds required_permission (or ALL) on resource_name (or '*').
        """
        req = required_permission.upper()
        role_str, has_extra = self._resolve_context_role(role_or_context, req)
        if has_extra:
            return True

        role_perms = self._grants.get(role_str, {})
        res_perms = role_perms.get(resource_name, set())
        if self._has_perm_or_all(res_perms, req):
            return True

        wildcard_perms = role_perms.get("*", set())
        return self._has_perm_or_all(wildcard_perms, req)

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
