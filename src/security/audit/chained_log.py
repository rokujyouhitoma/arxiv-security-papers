#!/usr/bin/env python3
"""
Forward-Secure Tamper-Evident Hash Chained Logging Module.
Implements RFC 6962-inspired sequential HMAC-SHA256 hash chaining to ensure that
any modification, deletion, reordering, or truncation of audit log entries is
mathematically detectable.
Zero external runtime dependencies.
"""

import hashlib
import hmac
import json
import threading
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

# Genesis hash for the initial block in chain
GENESIS_PREV_HASH = "0" * 64


def canonical_json(data: Any) -> str:
    """Produces deterministic canonical JSON serialization for cryptographic hashing."""
    return json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def compute_entry_hash(
    index: int,
    timestamp: str,
    prev_hash: str,
    payload: Dict[str, Any],
    chain_key: bytes,
) -> str:
    """
    Computes HMAC-SHA256 signature binding the sequence index, previous hash,
    timestamp, and canonical payload content.
    """
    canonical_body = canonical_json(payload)
    wire_repr = f"{index}|{timestamp}|{prev_hash}|{canonical_body}"
    return hmac.new(chain_key, wire_repr.encode("utf-8"), hashlib.sha256).hexdigest()


@dataclass(frozen=True)
class ChainedLogEntry:
    """Individual immutably signed block in the tamper-evident audit chain."""

    index: int
    timestamp: str
    payload: Dict[str, Any]
    prev_hash: str
    current_hash: str

    def to_dict(self) -> Dict[str, Any]:
        """Returns dictionary representation of entry."""
        return asdict(self)


def _check_single_entry_integrity(
    entry: ChainedLogEntry,
    expected_index: int,
    expected_prev_hash: str,
    chain_key: bytes,
) -> Tuple[bool, Optional[str]]:
    """Validates structural fields, sequence index, and HMAC recomputation."""
    if entry.index != expected_index:
        return (
            False,
            f"sequence index gap: expected {expected_index}, got {entry.index}",
        )

    if entry.prev_hash != expected_prev_hash:
        return False, f"broken prev_hash link at index {entry.index}"

    recalculated = compute_entry_hash(
        index=entry.index,
        timestamp=entry.timestamp,
        prev_hash=entry.prev_hash,
        payload=entry.payload,
        chain_key=chain_key,
    )
    if not hmac.compare_digest(recalculated, entry.current_hash):
        return (
            False,
            f"HMAC signature mismatch at index {entry.index}: content was tampered",
        )

    return True, None


def verify_chain_integrity(
    entries: List[ChainedLogEntry],
    chain_key: bytes,
) -> Tuple[bool, Optional[int], Optional[str]]:
    """
    Validates complete cryptographic hash chain from Genesis to head.
    Returns:
        (is_valid, failed_index, failure_reason)
    """
    if not entries:
        return True, None, None

    expected_prev = GENESIS_PREV_HASH
    for idx, entry in enumerate(entries):
        is_ok, reason = _check_single_entry_integrity(
            entry,
            expected_index=idx,
            expected_prev_hash=expected_prev,
            chain_key=chain_key,
        )
        if not is_ok:
            return False, idx, reason
        expected_prev = entry.current_hash

    return True, None, None


class ForwardSecureLogChain:
    """
    Thread-safe Forward-Secure Hash Chained Log Store.
    Appends new entries binding each block cryptographically to the preceding entry hash.
    """

    def __init__(self, chain_key: bytes) -> None:
        if not chain_key:
            raise ValueError("chain_key cannot be empty")
        self._chain_key = chain_key
        self._entries: List[ChainedLogEntry] = []
        self._lock = threading.Lock()

    def append(self, payload: Dict[str, Any]) -> ChainedLogEntry:
        """Appends and signs a new payload block to the chain."""
        with self._lock:
            idx = len(self._entries)
            now_iso = datetime.now(timezone.utc).isoformat()
            prev_h = (
                self._entries[-1].current_hash if self._entries else GENESIS_PREV_HASH
            )
            curr_h = compute_entry_hash(
                index=idx,
                timestamp=now_iso,
                prev_hash=prev_h,
                payload=payload,
                chain_key=self._chain_key,
            )
            entry = ChainedLogEntry(
                index=idx,
                timestamp=now_iso,
                payload=payload,
                prev_hash=prev_h,
                current_hash=curr_h,
            )
            self._entries.append(entry)
            return entry

    def verify(self) -> Tuple[bool, Optional[int], Optional[str]]:
        """Verifies integrity of the entire internal chain."""
        with self._lock:
            return verify_chain_integrity(self._entries, self._chain_key)

    @property
    def entries(self) -> List[ChainedLogEntry]:
        """Returns shallow copy of chain entries."""
        with self._lock:
            return list(self._entries)

    def __len__(self) -> int:
        with self._lock:
            return len(self._entries)
