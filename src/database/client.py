#!/usr/bin/env python3
"""Backward-compatibility shim for database.ipc.client."""

from .ipc.client import DatabaseClient, VectorDBClient

__all__ = ["DatabaseClient", "VectorDBClient"]
