#!/usr/bin/env python3
"""
RBAC Enforcement Decorators for Functions and MCP/Web Handlers.
"""

from functools import wraps
from typing import Any, Callable, Union

from .context import Role, SecurityContext
from .engine import DCLPermissionDeniedError, get_access_controller


def require_role(min_role: Union[str, Role]) -> Callable[..., Any]:
    """
    Decorator enforcing that the caller/context has at least the specified role.
    Role hierarchy: admin > analyst > guest
    """
    hierarchy = {"admin": 3, "analyst": 2, "guest": 1}
    target_role_str = (
        min_role.value if isinstance(min_role, Role) else str(min_role).lower()
    )
    target_level = hierarchy.get(target_role_str, 1)

    def decorator(func: Callable[..., Any]) -> Callable[..., Any]:
        @wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            # Check context from kwargs or default controller
            ctx = kwargs.get("security_context")
            current_role_str = (
                ctx.role.value
                if isinstance(ctx, SecurityContext)
                else get_access_controller().current_role
            )
            current_level = hierarchy.get(current_role_str, 1)

            if current_level < target_level:
                raise DCLPermissionDeniedError(
                    f"Access Denied: Required role '{target_role_str}', but current role is '{current_role_str}'"
                )
            return func(*args, **kwargs)

        return wrapper

    return decorator


def require_permission(resource_name: str, permission: str) -> Callable[..., Any]:
    """
    Decorator enforcing that the active role holds permission on resource_name.
    """

    def decorator(func: Callable[..., Any]) -> Callable[..., Any]:
        @wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            ctx = kwargs.get("security_context")
            controller = get_access_controller()
            caller = (
                ctx if isinstance(ctx, SecurityContext) else controller.current_role
            )
            controller.enforce_permission(caller, resource_name, permission)
            return func(*args, **kwargs)

        return wrapper

    return decorator
