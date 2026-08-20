"""
SQLite Compatibility and User Story Verification Test Suite.
Verifies pure Python database engine and PEP 249 / SQLite bridge compliance.
"""

import os
import sys

_SRC_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
)
if _SRC_DIR not in sys.path:
    sys.path.insert(0, _SRC_DIR)
