#!/usr/bin/env python3
"""
Audit and Tamper-Evident Chained Logging Package.
Provides RFC 6962-inspired forward-secure chained log and structured security audit logging.
"""

from .chained_log import (
    ChainedLogEntry,
    ForwardSecureLogChain,
    canonical_json,
    compute_entry_hash,
    verify_chain_integrity,
)
from .event_logger import SecurityAuditEvent, SecurityAuditLogger

__all__ = [
    "canonical_json",
    "compute_entry_hash",
    "ChainedLogEntry",
    "verify_chain_integrity",
    "ForwardSecureLogChain",
    "SecurityAuditEvent",
    "SecurityAuditLogger",
]
