#!/usr/bin/env python3
"""
RBAC Security Context, Roles, and Permission Types.
Provides unified role definitions and operational permissions across Database, Web, and MCP layers.
"""

from enum import Enum
from typing import Optional, Set


class Role(str, Enum):
    """Standard system roles."""

    ADMIN = "admin"
    ANALYST = "analyst"
    GUEST = "guest"

    @classmethod
    def from_str(cls, value: str) -> "Role":
        for member in cls:
            if member.value == value.lower():
                return member
        return cls.GUEST


class Permission(str, Enum):
    """Granular operation permissions."""

    SELECT = "SELECT"
    INSERT = "INSERT"
    UPDATE = "UPDATE"
    DELETE = "DELETE"
    EXECUTE = "EXECUTE"
    READ = "READ"
    WRITE = "WRITE"
    ADMIN = "ADMIN"
    ALL = "ALL"


class SecurityContext:
    """
    Carries user identity, active role, and session credentials throughout execution lifecycle.
    """

    def __init__(
        self,
        user_id: str = "anonymous",
        role: Role = Role.GUEST,
        extra_permissions: Optional[Set[str]] = None,
    ):
        self.user_id = user_id
        self.role = role if isinstance(role, Role) else Role.from_str(role)
        self.extra_permissions: Set[str] = (
            {p.upper() for p in extra_permissions} if extra_permissions else set()
        )

    def is_admin(self) -> bool:
        return self.role == Role.ADMIN

    def __repr__(self) -> str:
        return f"<SecurityContext user={self.user_id} role={self.role.value}>"
