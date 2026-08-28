#!/usr/bin/env python3
"""Backward-compatibility shim for database.ipc.protocol."""

from .ipc.protocol import VectorDBProtocolError, VectorDBProtocolHandler

__all__ = ["VectorDBProtocolError", "VectorDBProtocolHandler"]
