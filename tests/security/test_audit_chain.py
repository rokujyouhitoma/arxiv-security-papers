#!/usr/bin/env python3
"""
Unit Tests for Structured Security Audit Logging & Forward-Secure Hash Chained Log.
Issue #158.
"""

import json

import pytest

from src.security.audit.chained_log import (
    GENESIS_PREV_HASH,
    ChainedLogEntry,
    ForwardSecureLogChain,
    canonical_json,
    compute_entry_hash,
    verify_chain_integrity,
)
from src.security.audit.event_logger import SecurityAuditEvent, SecurityAuditLogger


def test_canonical_json_deterministic():
    """Ensures canonical JSON sorts keys and has no extra whitespace."""
    data = {"z": 1, "a": {"k2": "val2", "k1": "val1"}}
    res = canonical_json(data)
    assert res == '{"a":{"k1":"val1","k2":"val2"},"z":1}'


def test_security_audit_event_creation_and_masking():
    """Validates SecurityAuditEvent properties and metadata secret masking."""
    event = SecurityAuditEvent(
        event_type="AUTH",
        severity="HIGH",
        actor="admin_user",
        action="LOGIN",
        target_resource="/api/v1/auth",
        status="SUCCESS",
        client_ip="192.168.1.50",
        metadata={
            "session_id": "sess-999",
            "api_key": "AKIA1234567890SECRETKEY",
            "password": "SuperSecretPassword123",
            "safe_param": "regular_value",
        },
    )
    assert event.event_id is not None
    assert event.timestamp is not None

    d = event.to_dict()
    assert d["actor"] == "admin_user"
    assert d["metadata"]["safe_param"] == "regular_value"
    assert d["metadata"]["session_id"] == "sess-999"
    # Sensitive keys should be masked
    assert d["metadata"]["api_key"].startswith("*******************")
    assert d["metadata"]["password"].startswith("******************")

    raw_json = event.to_json()
    parsed = json.loads(raw_json)
    assert parsed["metadata"]["api_key"].startswith("*******************")


def test_security_audit_logger_buffering_and_filtering():
    """Tests buffer size capping and event filtering."""
    logger = SecurityAuditLogger(max_buffer_size=3)

    logger.record("AUTH", "INFO", "user1", "LOGIN", "/login", "SUCCESS")
    logger.record("AUTH", "WARN", "user2", "LOGIN", "/login", "FAILURE")
    logger.record("RBAC", "HIGH", "user3", "DELETE", "/papers", "DENIED")

    assert len(logger) == 3

    # Add a 4th event, oldest should be evicted
    logger.record("AUDIT", "INFO", "system", "ROTATE", "/keys", "SUCCESS")
    assert len(logger) == 3
    events = logger.get_events()
    assert events[0].actor == "user2"
    assert events[-1].actor == "system"

    # Filter by event_type
    auth_events = logger.get_events(event_type="AUTH")
    assert len(auth_events) == 1
    assert auth_events[0].actor == "user2"

    # Filter by severity
    high_events = logger.get_events(severity="HIGH")
    assert len(high_events) == 1
    assert high_events[0].actor == "user3"

    # Clear
    logger.clear()
    assert len(logger) == 0


def test_chained_log_empty():
    """Empty chain should verify as valid."""
    chain_key = b"secret-chain-key-32-bytes-long!!"
    is_valid, idx, reason = verify_chain_integrity([], chain_key)
    assert is_valid is True
    assert idx is None
    assert reason is None


def test_forward_secure_log_chain_valid():
    """Validates append and integrity verification across sequential entries."""
    chain_key = b"secret-chain-key-32-bytes-long!!"
    chain = ForwardSecureLogChain(chain_key)

    e0 = chain.append({"action": "INGEST", "paper_id": "2401.00001"})
    assert e0.index == 0
    assert e0.prev_hash == GENESIS_PREV_HASH

    e1 = chain.append({"action": "EXTRACT", "paper_id": "2401.00001"})
    assert e1.index == 1
    assert e1.prev_hash == e0.current_hash

    e2 = chain.append({"action": "PUBLISH", "paper_id": "2401.00001"})
    assert e2.index == 2
    assert e2.prev_hash == e1.current_hash

    assert len(chain) == 3

    is_valid, bad_idx, reason = chain.verify()
    assert is_valid is True
    assert bad_idx is None
    assert reason is None


def test_chained_log_detects_payload_tampering():
    """Tampering with an entry payload breaks HMAC-SHA256 signature."""
    chain_key = b"secret-chain-key-32-bytes-long!!"
    chain = ForwardSecureLogChain(chain_key)

    chain.append({"event": "transfer", "amount": 100})
    chain.append({"event": "transfer", "amount": 200})

    entries = chain.entries

    # Tamper with payload in entry 0
    tampered_e0 = ChainedLogEntry(
        index=entries[0].index,
        timestamp=entries[0].timestamp,
        payload={"event": "transfer", "amount": 999999},  # modified
        prev_hash=entries[0].prev_hash,
        current_hash=entries[0].current_hash,
    )
    tampered_chain = [tampered_e0, entries[1]]

    is_valid, bad_idx, reason = verify_chain_integrity(tampered_chain, chain_key)
    assert is_valid is False
    assert bad_idx == 0
    assert "HMAC signature mismatch" in str(reason)


def test_chained_log_detects_sequence_gap():
    """Removing or reordering entries creates a sequence index gap."""
    chain_key = b"secret-chain-key-32-bytes-long!!"
    chain = ForwardSecureLogChain(chain_key)

    chain.append({"entry": 0})
    chain.append({"entry": 1})
    chain.append({"entry": 2})

    entries = chain.entries
    # Delete entry 1
    skipped_chain = [entries[0], entries[2]]

    is_valid, bad_idx, reason = verify_chain_integrity(skipped_chain, chain_key)
    assert is_valid is False
    assert bad_idx == 1
    assert "sequence index gap" in str(reason)


def test_chained_log_detects_broken_hash_link():
    """Changing prev_hash link should fail verification."""
    chain_key = b"secret-chain-key-32-bytes-long!!"
    chain = ForwardSecureLogChain(chain_key)

    chain.append({"entry": 0})
    chain.append({"entry": 1})

    entries = chain.entries
    # In entry 1, set broken prev_hash and recompute its HMAC
    broken_prev_hash = "f" * 64
    recomputed_hash = compute_entry_hash(
        index=entries[1].index,
        timestamp=entries[1].timestamp,
        prev_hash=broken_prev_hash,
        payload=entries[1].payload,
        chain_key=chain_key,
    )
    tampered_e1 = ChainedLogEntry(
        index=entries[1].index,
        timestamp=entries[1].timestamp,
        payload=entries[1].payload,
        prev_hash=broken_prev_hash,
        current_hash=recomputed_hash,
    )

    is_valid, bad_idx, reason = verify_chain_integrity(
        [entries[0], tampered_e1], chain_key
    )
    assert is_valid is False
    assert bad_idx == 1
    assert "broken prev_hash link" in str(reason)


def test_forward_secure_log_chain_empty_key_raises():
    """Empty chain key must raise ValueError."""
    with pytest.raises(ValueError, match="chain_key cannot be empty"):
        ForwardSecureLogChain(b"")
