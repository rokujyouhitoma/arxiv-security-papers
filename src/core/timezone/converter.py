#!/usr/bin/env python3
"""src/core/timezone/converter.py: Pure-Python timezone conversion and normalization engine.

Zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

import re
import zoneinfo
from datetime import datetime, timedelta, timezone
from typing import Any, Optional, Union

DEFAULT_TIME_ZONE: str = "Asia/Tokyo"
DEFAULT_USE_TZ: bool = True
DEFAULT_DATABASE_TIME_ZONE: str = "UTC"

_SAFE_TZ_RE = re.compile(r"^[A-Za-z0-9_\-\+/]+$")
_MIN_EPOCH = -62135596800
_MAX_EPOCH = 253402300799


def _resolve_configured_tz() -> str:
    try:
        from settings import TIME_ZONE

        return str(TIME_ZONE)
    except Exception:
        return DEFAULT_TIME_ZONE


def _resolve_configured_use_tz() -> bool:
    try:
        from settings import USE_TZ

        return bool(USE_TZ)
    except Exception:
        return DEFAULT_USE_TZ


def _resolve_configured_db_tz() -> str:
    try:
        from settings import DATABASE_TIME_ZONE

        return str(DATABASE_TIME_ZONE)
    except Exception:
        return DEFAULT_DATABASE_TIME_ZONE


def _resolve_configured_display_tz() -> str:
    try:
        from settings import DISPLAY_TIME_ZONE

        return str(DISPLAY_TIME_ZONE)
    except Exception:
        return _resolve_configured_tz()


def get_timezone() -> str:
    """Returns the globally configured display timezone."""
    return _resolve_configured_tz()


def is_use_tz() -> bool:
    """Returns whether timezone awareness is globally enabled."""
    return _resolve_configured_use_tz()


def get_database_timezone() -> str:
    """Returns the storage timezone for databases (default: UTC)."""
    return _resolve_configured_db_tz()


def get_display_timezone() -> str:
    """Returns the display timezone for presentations (default: Asia/Tokyo)."""
    return _resolve_configured_display_tz()


def _fallback_zoneinfo(name: str) -> Any:
    """Provides standard offset fallback when IANA tzdata is unavailable."""
    if name in ("Asia/Tokyo", "JST"):
        return timezone(timedelta(hours=9), name="JST")
    return timezone.utc


def _is_valid_tz_name(name: Any) -> bool:
    """Validates timezone name for format and bounds."""
    if not isinstance(name, str) or not (1 <= len(name) <= 64):
        return False
    return bool(_SAFE_TZ_RE.match(name))


def get_zoneinfo(tz_name: Optional[str] = None) -> Any:
    """Resolves tzinfo object with graceful fallback for minimal environments."""
    name = tz_name if tz_name is not None else get_timezone()
    if not _is_valid_tz_name(name):
        return timezone.utc
    if name in ("UTC", "GMT"):
        return timezone.utc
    try:
        return zoneinfo.ZoneInfo(name)
    except Exception:
        return _fallback_zoneinfo(name)


def _parse_timestamp(ts: Union[int, float]) -> datetime:
    """Validates and parses integer or floating epoch timestamp into UTC datetime."""
    if not (_MIN_EPOCH <= ts <= _MAX_EPOCH):
        raise ValueError(f"Epoch timestamp out of range: {ts}")
    return datetime.fromtimestamp(ts, tz=timezone.utc)


def _parse_str_datetime(s: str) -> datetime:
    """Validates and parses ISO 8601 string into UTC datetime."""
    if len(s) > 64 or not s.strip():
        raise ValueError(f"Invalid datetime string length: {len(s)}")
    normalized = s.strip().replace("Z", "+00:00")
    dt = datetime.fromisoformat(normalized)
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _normalize_datetime(dt: datetime) -> datetime:
    """Normalizes naive or aware datetime to timezone-aware UTC datetime."""
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def to_storage_utc(dt_or_val: Union[datetime, str, int, float]) -> datetime:
    """Normalizes input to a timezone-aware UTC datetime for database storage."""
    if isinstance(dt_or_val, (int, float)):
        return _parse_timestamp(dt_or_val)
    if isinstance(dt_or_val, str):
        return _parse_str_datetime(dt_or_val)
    if isinstance(dt_or_val, datetime):
        return _normalize_datetime(dt_or_val)
    raise TypeError(f"Unsupported datetime input type: {type(dt_or_val)}")


def to_display_timezone(
    dt_or_val: Union[datetime, str, int, float],
    tz_name: Optional[str] = None,
) -> datetime:
    """Converts datetime or timestamp to display timezone (default: TIME_ZONE)."""
    utc_dt = to_storage_utc(dt_or_val)
    target_tz = get_zoneinfo(tz_name)
    return utc_dt.astimezone(target_tz)


def format_display_datetime(
    dt_or_val: Union[datetime, str, int, float],
    fmt: str = "%Y-%m-%d %H:%M:%S %Z",
    tz_name: Optional[str] = None,
) -> str:
    """Formats datetime or timestamp into formatted display string."""
    display_dt = to_display_timezone(dt_or_val, tz_name=tz_name)
    return display_dt.strftime(fmt)
