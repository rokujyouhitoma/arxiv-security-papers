#!/usr/bin/env python3
"""
Unit tests for Unified RBAC Engine and Access Control Decorators.
"""

import os
import sys
import pytest

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    )

from security.rbac import (
    AccessController,
    DCLPermissionDeniedError,
    Role,
    SecurityContext,
    require_permission,
    require_role,
)


def test_default_role_hierarchy_and_permissions():
    ctrl = AccessController()

    # Admin has ALL
    assert ctrl.check_permission("admin", "papers", "SELECT")
    assert ctrl.check_permission("admin", "papers", "INSERT")
    assert ctrl.check_permission("admin", "papers", "DELETE")
    assert ctrl.check_permission("admin", "any_table", "ALL")

    # Analyst has SELECT and INSERT
    assert ctrl.check_permission("analyst", "papers", "SELECT")
    assert ctrl.check_permission("analyst", "papers", "INSERT")
    assert not ctrl.check_permission("analyst", "papers", "DELETE")

    # Guest has SELECT only
    assert ctrl.check_permission("guest", "papers", "SELECT")
    assert not ctrl.check_permission("guest", "papers", "INSERT")
    assert not ctrl.check_permission("guest", "papers", "DELETE")


def test_grant_and_revoke_permissions():
    ctrl = AccessController()

    # Grant DELETE on papers to analyst
    ctrl.grant("DELETE", "papers", "analyst")
    assert ctrl.check_permission("analyst", "papers", "DELETE")

    # Revoke DELETE on papers from analyst
    ctrl.revoke("DELETE", "papers", "analyst")
    assert not ctrl.check_permission("analyst", "papers", "DELETE")


def test_enforce_permission_raises_error():
    ctrl = AccessController()

    with pytest.raises(DCLPermissionDeniedError) as exc_info:
        ctrl.enforce_permission("guest", "papers", "DELETE")
    assert "Permission denied: role 'guest' does not have 'DELETE'" in str(exc_info.value)


def test_security_context_evaluation():
    ctrl = AccessController()
    guest_ctx = SecurityContext(user_id="user_123", role=Role.GUEST)
    assert not guest_ctx.is_admin()
    assert ctrl.check_permission(guest_ctx, "papers", "SELECT")
    assert not ctrl.check_permission(guest_ctx, "papers", "INSERT")

    # Context with extra permissions
    privileged_guest = SecurityContext(
        user_id="user_guest_vip", role=Role.GUEST, extra_permissions={"INSERT"}
    )
    assert ctrl.check_permission(privileged_guest, "papers", "INSERT")


def test_require_role_decorator():
    @require_role(Role.ADMIN)
    def admin_only_action(security_context=None):
        return "admin_success"

    # Guest call fails
    with pytest.raises(DCLPermissionDeniedError):
        admin_only_action(security_context=SecurityContext(role=Role.GUEST))

    # Admin call succeeds
    res = admin_only_action(security_context=SecurityContext(role=Role.ADMIN))
    assert res == "admin_success"


def test_require_permission_decorator():
    @require_permission("secrets", "READ")
    def read_secrets(security_context=None):
        return "secret_data"

    # Guest has READ on wildcard '*' by default
    res = read_secrets(security_context=SecurityContext(role=Role.GUEST))
    assert res == "secret_data"
