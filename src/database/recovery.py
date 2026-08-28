#!/usr/bin/env python3
"""Backward-compatibility shim for database.transaction.recovery."""

from .transaction.recovery import ARIESRecoveryManager

__all__ = ["ARIESRecoveryManager"]
