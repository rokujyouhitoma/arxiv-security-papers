#!/usr/bin/env python3
"""
Unified Security & Compliance Framework for arXiv Security Papers.
Provides a Single Source of Truth (SSOT) across Sandboxing, RBAC, Validation, and Threat Taxonomy.
"""

from .audit import (
    ChainedLogEntry,
    ForwardSecureLogChain,
    SecurityAuditEvent,
    SecurityAuditLogger,
    canonical_json,
    compute_entry_hash,
    verify_chain_integrity,
)
from .fim import FileIntegrityMonitor, compute_file_sha256
from .guardrails import (
    DEFAULT_MAX_OUTPUT_CHARS,
    ToolCallGuard,
    detect_prompt_injection,
    mask_pii_and_secrets,
    validate_output_safety,
)
from .merkle_tree import MerkleTree, hash_children, hash_leaf
from .middleware import DEFAULT_SECURITY_HEADERS, SecurityWSGIMiddleware
from .ratelimit import (
    CircuitBreaker,
    CircuitBreakerOpenError,
    CircuitState,
    RateLimitExceededError,
    SlidingWindowRateLimiter,
    TokenBucketRateLimiter,
)
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
from .secrets import (
    EphemeralSecretStore,
    SecretFinding,
    constant_time_compare,
    detect_exposed_secrets,
    generate_csrf_token,
    generate_secure_token,
    mask_secret,
    verify_csrf_token,
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
    DEFAULT_ALLOWED_SCHEMES,
    DEFAULT_MAX_EXPANSION_RATIO,
    DEFAULT_MAX_PDF_PAGES,
    DEFAULT_MAX_UNCOMPRESSED_BYTES,
    METADATA_IPS,
    DecompressionBombError,
    DefusedXMLError,
    IngestSecurityError,
    SSRFSecurityError,
    create_safe_socket,
    detect_dangerous_patterns,
    detect_mime_type_from_bytes,
    get_default_workspace_dir,
    is_safe_remote_url,
    is_safe_text_content,
    is_safe_workspace_path,
    parse_safe_xml,
    resolve_and_validate_ip,
    resolve_safe_path,
    safe_http_fetch,
    sanitize_html,
    validate_pdf_safety_metadata,
    validate_safe_decompression,
    verify_magic_bytes,
)

__all__ = [
    # Audit & Chained Log
    "ChainedLogEntry",
    "ForwardSecureLogChain",
    "SecurityAuditEvent",
    "SecurityAuditLogger",
    "canonical_json",
    "compute_entry_hash",
    "verify_chain_integrity",
    # FIM & Merkle Tree
    "FileIntegrityMonitor",
    "MerkleTree",
    "compute_file_sha256",
    "hash_children",
    "hash_leaf",
    # Guardrails & Tool Call Guard
    "DEFAULT_MAX_OUTPUT_CHARS",
    "ToolCallGuard",
    "detect_prompt_injection",
    "mask_pii_and_secrets",
    "validate_output_safety",
    # Sandbox
    "ASTSecurityGuard",
    "BLOCKED_BUILTIN_FUNCS",
    "BLOCKED_CALLS",
    "BLOCKED_DUNDER_NAMES",
    "BLOCKED_MODULES",
    "validate_safe_code",
    # Rate Limiting & Circuit Breaker
    "CircuitBreaker",
    "CircuitBreakerOpenError",
    "CircuitState",
    "RateLimitExceededError",
    "SlidingWindowRateLimiter",
    "TokenBucketRateLimiter",
    # Middleware
    "DEFAULT_SECURITY_HEADERS",
    "SecurityWSGIMiddleware",
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
    # Secrets & Cryptographic Utilities
    "EphemeralSecretStore",
    "SecretFinding",
    "constant_time_compare",
    "detect_exposed_secrets",
    "generate_csrf_token",
    "generate_secure_token",
    "mask_secret",
    "verify_csrf_token",
    # Taxonomy
    "CWE_DEFENSE_MAP",
    "MITRE_TECHNIQUES_MAP",
    "STRIDE_CATEGORIES_MAP",
    "extract_mitre_techniques",
    "extract_stride_categories",
    "get_cwe_recipe",
    # Validation, Network & Ingest Hardening
    "DEFAULT_ALLOWED_SCHEMES",
    "DEFAULT_MAX_EXPANSION_RATIO",
    "DEFAULT_MAX_PDF_PAGES",
    "DEFAULT_MAX_UNCOMPRESSED_BYTES",
    "DecompressionBombError",
    "DefusedXMLError",
    "IngestSecurityError",
    "METADATA_IPS",
    "SSRFSecurityError",
    "create_safe_socket",
    "detect_dangerous_patterns",
    "detect_mime_type_from_bytes",
    "get_default_workspace_dir",
    "is_safe_remote_url",
    "is_safe_text_content",
    "is_safe_workspace_path",
    "parse_safe_xml",
    "resolve_and_validate_ip",
    "resolve_safe_path",
    "safe_http_fetch",
    "sanitize_html",
    "validate_pdf_safety_metadata",
    "validate_safe_decompression",
    "verify_magic_bytes",
]
