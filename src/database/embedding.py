#!/usr/bin/env python3
"""Backward-compatibility shim for database.index.embedding."""

from .index.embedding import DeterministicEmbedding

__all__ = ["DeterministicEmbedding"]
