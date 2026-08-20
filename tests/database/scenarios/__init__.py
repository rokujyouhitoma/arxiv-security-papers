"""
E2E User Scenarios and Acceptance Tests for Next-Gen Database Engine (DSN-14).
Location: tests/database/scenarios/
Covers Scenarios 1 through 7:
1. LSM / Slotted-Page Ingestion
2. B+Tree / PAX / mmap OLAP & Zero-Copy
3. MVCC / SS2PL Concurrency & Deadlock Detection
4. WAL / ARIES Power-Loss Crash Recovery
5. Phi-Accrual & Raft Network Partition / Election
6. Strict Quorum & Merkle Tree Anti-Entropy Autonomous Repair
7. Orchestration Saga Compensation
"""

import os
import sys

# Ensure src is accessible
src_path = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
)
if src_path not in sys.path:
    sys.path.insert(0, src_path)
