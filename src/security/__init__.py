#!/usr/bin/env python3
"""
Unified Security & Compliance Framework for arXiv Security Papers.
Provides a Single Source of Truth (SSOT) across Sandboxing, RBAC, Validation, and Threat Taxonomy.
"""

from .fim import FileIntegrityMonitor, compute_file_sha256
from .merkle_tree import MerkleTree, hash_children, hash_leaf
from .rbac import (
    AccessController,
    DCLPermissionDeniedError,
    Permission,
    PermissionDeniedError,
    Role,
    SecurityContext,
    get_access_controller,
    require_permission,
    require_role,
)
from .sandbox import (
    BLOCKED_BUILTIN_FUNCS,
    BLOCKED_CALLS,
    BLOCKED_DUNDER_NAMES,
    BLOCKED_MODULES,
    ASTSecurityGuard,
    validate_safe_code,
)
from .taxonomy import (
    CWE_DEFENSE_MAP,
    MITRE_TECHNIQUES_MAP,
    STRIDE_CATEGORIES_MAP,
    extract_mitre_techniques,
    extract_stride_categories,
    get_cwe_recipe,
)
from .validation import (
    detect_dangerous_patterns,
    get_default_workspace_dir,
    is_safe_workspace_path,
    resolve_safe_path,
    sanitize_html,
)

__all__ = [
    # FIM & Merkle Tree
    "FileIntegrityMonitor",
    "MerkleTree",
    "compute_file_sha256",
    "hash_children",
    "hash_leaf",
    # Sandbox
    "ASTSecurityGuard",
    "BLOCKED_BUILTIN_FUNCS",
    "BLOCKED_CALLS",
    "BLOCKED_DUNDER_NAMES",
    "BLOCKED_MODULES",
    "validate_safe_code",
    # RBAC
    "AccessController",
    "DCLPermissionDeniedError",
    "Permission",
    "PermissionDeniedError",
    "Role",
    "SecurityContext",
    "get_access_controller",
    "require_permission",
    "require_role",
    # Taxonomy
    "CWE_DEFENSE_MAP",
    "MITRE_TECHNIQUES_MAP",
    "STRIDE_CATEGORIES_MAP",
    "extract_mitre_techniques",
    "extract_stride_categories",
    "get_cwe_recipe",
    # Validation
    "detect_dangerous_patterns",
    "get_default_workspace_dir",
    "is_safe_workspace_path",
    "resolve_safe_path",
    "sanitize_html",
]
