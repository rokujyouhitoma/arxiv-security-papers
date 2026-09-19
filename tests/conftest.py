"""
Global pytest configuration and isolation fixtures.
Ensures production databases and logs are strictly protected during test runs.
"""

from __future__ import annotations

import os
import tempfile
from typing import Generator

import pytest


@pytest.fixture(autouse=True, scope="session")
def isolate_production_spider_db() -> Generator[None, None, None]:
    """
    Globally isolates the spider execution DB to a temporary directory
    during the entire test session. Prevents accidental pollution of
    outputs/database/spider_execution.vdb.
    """
    with tempfile.TemporaryDirectory() as temp_dir:
        test_db = os.path.join(temp_dir, "global_test_spider_execution.vdb")
        original_env = os.environ.get("SPIDER_EXECUTION_DB_PATH")
        os.environ["SPIDER_EXECUTION_DB_PATH"] = test_db
        try:
            yield
        finally:
            if original_env is not None:
                os.environ["SPIDER_EXECUTION_DB_PATH"] = original_env
            else:
                os.environ.pop("SPIDER_EXECUTION_DB_PATH", None)
