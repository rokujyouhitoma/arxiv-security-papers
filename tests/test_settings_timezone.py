#!/usr/bin/env python3
"""tests/test_settings_timezone.py: Unit tests for timezone settings and DSN configuration.

Verifies Django-compatible TIME_ZONE and USE_TZ settings, pure-Python conversion
helpers, safety boundaries, and database metadata introspection.
"""

import unittest
from datetime import datetime, timedelta, timezone
from typing import Any

from core.settings import get_all_configured_databases, get_database_metadata
from core.timezone import (
    format_display_datetime,
    get_database_timezone,
    get_display_timezone,
    get_timezone,
    get_zoneinfo,
    is_use_tz,
    to_display_timezone,
    to_storage_utc,
)
from settings import (
    DATABASE_TIME_ZONE,
    DATABASES,
    DB_TIME_ZONE,
    DISPLAY_TIME_ZONE,
    TIME_ZONE,
    USE_TZ,
)


class TestSettingsConstants(unittest.TestCase):
    """Tests for top-level timezone constants and getters."""

    def test_timezone_constants(self) -> None:
        self.assertEqual(TIME_ZONE, "Asia/Tokyo")
        self.assertTrue(USE_TZ)
        self.assertEqual(DATABASE_TIME_ZONE, "UTC")
        self.assertEqual(DISPLAY_TIME_ZONE, "Asia/Tokyo")
        self.assertEqual(DB_TIME_ZONE, "UTC")

    def test_getter_functions(self) -> None:
        self.assertEqual(get_timezone(), "Asia/Tokyo")
        self.assertTrue(is_use_tz())
        self.assertEqual(get_database_timezone(), "UTC")
        self.assertEqual(get_display_timezone(), "Asia/Tokyo")

    def test_settings_module_has_zero_functions(self) -> None:
        """Verifies Issue 325: settings.py is purely declarative with 0 functions."""
        import inspect

        import settings

        defined_funcs = [
            k
            for k, v in vars(settings).items()
            if not k.startswith("__") and inspect.isfunction(v)
        ]
        self.assertEqual(
            defined_funcs,
            [],
            f"settings.py should have zero functions, found: {defined_funcs}",
        )


class TestDatabasesDSNTimezone(unittest.TestCase):
    """Tests for centralized DSN timezone metadata across all database scopes."""

    def test_all_databases_configured(self) -> None:
        scopes = list(DATABASES.keys())
        expected_scopes = [
            "default",
            "arxiv_security_db",
            "cti_catalog_db",
            "graph_db",
            "analytics_db",
            "spider_execution_db",
        ]
        for exp in expected_scopes:
            self.assertIn(exp, scopes)

    def test_get_database_metadata_includes_timezone_from_constants(self) -> None:
        for scope_name in get_all_configured_databases():
            meta = get_database_metadata(scope_name)
            self.assertEqual(meta["time_zone"], "UTC")
            self.assertTrue(meta["use_tz"])
            self.assertEqual(meta["display_time_zone"], "Asia/Tokyo")


class TestGetZoneinfo(unittest.TestCase):
    """Tests for zoneinfo resolution and safety fallback mechanisms."""

    def test_resolve_default_tokyo(self) -> None:
        tz = get_zoneinfo()
        self.assertIsNotNone(tz)

    def test_resolve_utc(self) -> None:
        tz = get_zoneinfo("UTC")
        self.assertEqual(tz, timezone.utc)

    def test_security_unsafe_traversal(self) -> None:
        # Prevent CWE-22 directory traversal attempts
        tz = get_zoneinfo("../../etc/passwd")
        self.assertEqual(tz, timezone.utc)

        tz_cmd = get_zoneinfo("; rm -rf /")
        self.assertEqual(tz_cmd, timezone.utc)

    def test_empty_or_excessive_length(self) -> None:
        tz_empty = get_zoneinfo("")
        self.assertEqual(tz_empty, timezone.utc)

        tz_long = get_zoneinfo("A" * 65)
        self.assertEqual(tz_long, timezone.utc)

    def test_unknown_timezone_fallback(self) -> None:
        tz_unknown = get_zoneinfo("Invalid/NonExistentZone_XYZ")
        self.assertEqual(tz_unknown, timezone.utc)


class TestToStorageUTC(unittest.TestCase):
    """Tests for normalising timestamps and datetimes to UTC aware datetimes."""

    def test_naive_datetime_to_utc(self) -> None:
        dt_naive = datetime(2026, 9, 18, 10, 30, 0)
        dt_utc = to_storage_utc(dt_naive)
        self.assertEqual(dt_utc.tzinfo, timezone.utc)
        self.assertEqual(dt_utc.year, 2026)
        self.assertEqual(dt_utc.month, 9)
        self.assertEqual(dt_utc.day, 18)
        self.assertEqual(dt_utc.hour, 10)
        self.assertEqual(dt_utc.minute, 30)

    def test_aware_jst_datetime_to_utc(self) -> None:
        jst_tz = timezone(timedelta(hours=9))
        dt_jst = datetime(2026, 9, 18, 19, 0, 0, tzinfo=jst_tz)
        dt_utc = to_storage_utc(dt_jst)
        self.assertEqual(dt_utc.tzinfo, timezone.utc)
        self.assertEqual(dt_utc.hour, 10)

    def test_epoch_int_to_utc(self) -> None:
        # 1700000000 -> 2023-11-14 22:13:20 UTC
        dt_utc = to_storage_utc(1700000000)
        self.assertEqual(dt_utc.tzinfo, timezone.utc)
        self.assertEqual(dt_utc.year, 2023)
        self.assertEqual(dt_utc.month, 11)
        self.assertEqual(dt_utc.day, 14)
        self.assertEqual(dt_utc.hour, 22)
        self.assertEqual(dt_utc.minute, 13)

    def test_epoch_float_to_utc(self) -> None:
        dt_utc = to_storage_utc(1700000000.5)
        self.assertEqual(dt_utc.tzinfo, timezone.utc)
        self.assertEqual(dt_utc.microsecond, 500000)

    def test_iso8601_string_with_z(self) -> None:
        dt_utc = to_storage_utc("2026-09-18T10:30:00Z")
        self.assertEqual(dt_utc.tzinfo, timezone.utc)
        self.assertEqual(dt_utc.hour, 10)
        self.assertEqual(dt_utc.minute, 30)

    def test_iso8601_string_with_offset(self) -> None:
        dt_utc = to_storage_utc("2026-09-18T19:00:00+09:00")
        self.assertEqual(dt_utc.tzinfo, timezone.utc)
        self.assertEqual(dt_utc.hour, 10)

    def test_iso8601_naive_string(self) -> None:
        dt_utc = to_storage_utc("2026-09-18 10:00:00")
        self.assertEqual(dt_utc.tzinfo, timezone.utc)
        self.assertEqual(dt_utc.hour, 10)

    def test_invalid_type_raises_type_error(self) -> None:
        with self.assertRaises(TypeError):
            to_storage_utc(None)  # type: ignore[arg-type]

        with self.assertRaises(TypeError):
            to_storage_utc([])  # type: ignore[arg-type]

    def test_invalid_string_raises_value_error(self) -> None:
        with self.assertRaises(ValueError):
            to_storage_utc("invalid-datetime-string")

        with self.assertRaises(ValueError):
            to_storage_utc("")

        with self.assertRaises(ValueError):
            to_storage_utc("2026-09-18" + " " * 60)

    def test_out_of_range_epoch_raises_value_error(self) -> None:
        with self.assertRaises(ValueError):
            to_storage_utc(1e15)

        with self.assertRaises(ValueError):
            to_storage_utc(-1e15)


class TestToDisplayTimezone(unittest.TestCase):
    """Tests for projection from storage UTC to display timezone (JST)."""

    def test_utc_to_jst_conversion(self) -> None:
        dt_utc = datetime(2026, 9, 18, 0, 0, 0, tzinfo=timezone.utc)
        dt_jst = to_display_timezone(dt_utc)
        # UTC 00:00 should be JST 09:00 (+9h)
        self.assertEqual(dt_jst.hour, 9)
        self.assertEqual(dt_jst.day, 18)

    def test_epoch_to_jst_conversion(self) -> None:
        # Epoch 0 -> 1970-01-01 00:00:00 UTC -> 1970-01-01 09:00:00 JST
        dt_jst = to_display_timezone(0)
        self.assertEqual(dt_jst.hour, 9)
        self.assertEqual(dt_jst.day, 1)
        self.assertEqual(dt_jst.year, 1970)

    def test_custom_target_timezone(self) -> None:
        dt_utc = datetime(2026, 9, 18, 12, 0, 0, tzinfo=timezone.utc)
        dt_target = to_display_timezone(dt_utc, tz_name="UTC")
        self.assertEqual(dt_target.hour, 12)
        self.assertEqual(dt_target.tzinfo, timezone.utc)


class TestFormatDisplayDatetime(unittest.TestCase):
    """Tests for formatting timestamps into human-readable display strings."""

    def test_format_display_datetime_default(self) -> None:
        dt_utc = datetime(2026, 9, 18, 0, 0, 0, tzinfo=timezone.utc)
        res = format_display_datetime(dt_utc)
        self.assertTrue(res.startswith("2026-09-18 09:00:00"))

    def test_format_display_datetime_custom_fmt(self) -> None:
        dt_utc = datetime(2026, 9, 18, 0, 0, 0, tzinfo=timezone.utc)
        res = format_display_datetime(dt_utc, fmt="%Y/%m/%d %H:%M")
        self.assertEqual(res, "2026/09/18 09:00")


class TestGatewayIntrospectionTimezone(unittest.TestCase):
    """Tests for web gateway database introspection timezone integration."""

    def test_gateway_introspection_contains_timezone_metadata(self) -> None:
        from settings import BASE_DIR
        from web.gateway.handlers import _introspect_database_metrics

        metrics = _introspect_database_metrics(BASE_DIR)
        self.assertEqual(metrics.get("time_zone"), "UTC")
        self.assertTrue(metrics.get("use_tz"))
        self.assertEqual(metrics.get("display_time_zone"), "Asia/Tokyo")

        databases: dict[str, Any] = metrics.get("databases", {})
        for db_name, db_info in databases.items():
            self.assertEqual(
                db_info.get("time_zone"),
                "UTC",
                f"DB {db_name} missing time_zone in introspection",
            )
            self.assertTrue(
                db_info.get("use_tz"),
                f"DB {db_name} missing use_tz in introspection",
            )
            self.assertEqual(
                db_info.get("display_time_zone"),
                "Asia/Tokyo",
                f"DB {db_name} missing display_time_zone in introspection",
            )


class TestCoreTimezoneAndSettingsPackages(unittest.TestCase):
    """Tests verifying direct imports from core.timezone and core.settings packages."""

    def test_direct_core_timezone_import(self) -> None:
        from core.timezone import (
            DEFAULT_DATABASE_TIME_ZONE,
            DEFAULT_TIME_ZONE,
            DEFAULT_USE_TZ,
        )
        from core.timezone import format_display_datetime as core_format
        from core.timezone import get_database_timezone as core_db_tz
        from core.timezone import get_display_timezone as core_disp_tz
        from core.timezone import get_timezone as core_get_tz
        from core.timezone import get_zoneinfo as core_get_zone
        from core.timezone import is_use_tz as core_is_use_tz
        from core.timezone import to_display_timezone as core_to_disp
        from core.timezone import to_storage_utc as core_to_storage

        self.assertEqual(DEFAULT_TIME_ZONE, "Asia/Tokyo")
        self.assertTrue(DEFAULT_USE_TZ)
        self.assertEqual(DEFAULT_DATABASE_TIME_ZONE, "UTC")
        self.assertEqual(core_get_tz(), "Asia/Tokyo")
        self.assertTrue(core_is_use_tz())
        self.assertEqual(core_db_tz(), "UTC")
        self.assertEqual(core_disp_tz(), "Asia/Tokyo")

        dt = datetime(2026, 9, 18, 0, 0, 0, tzinfo=timezone.utc)
        self.assertEqual(core_to_storage(dt), dt)
        disp_dt = core_to_disp(dt)
        self.assertEqual(disp_dt.hour, 9)
        formatted = core_format(dt, fmt="%Y-%m-%d %H:%M:%S")
        self.assertEqual(formatted, "2026-09-18 09:00:00")
        self.assertIsNotNone(core_get_zone("Asia/Tokyo"))

    def test_direct_core_settings_import(self) -> None:
        from core.settings import (
            resolve_all_configured_databases,
            resolve_database_metadata,
            resolve_database_scopes,
            resolve_table_scope,
            resolve_table_type,
        )

        mock_dbs = {
            "default": {"ENGINE": "mem"},
            "test_db": {
                "DESCRIPTION": "Test Database",
                "TABLES": {"test_table": {"TYPE": "MockTable"}},
            },
        }
        scopes = resolve_database_scopes(mock_dbs)
        self.assertIn("test_db", scopes)
        self.assertNotIn("default", scopes)

        all_dbs = resolve_all_configured_databases(mock_dbs)
        self.assertEqual(all_dbs, ["test_db"])

        meta = resolve_database_metadata("test_db", mock_dbs)
        self.assertEqual(meta["time_zone"], "UTC")
        self.assertEqual(meta["display_time_zone"], "Asia/Tokyo")

        tbl_scope = resolve_table_scope("test_table", mock_dbs)
        self.assertEqual(tbl_scope, "test_db")

        tbl_type = resolve_table_type("test_table", mock_dbs)
        self.assertEqual(tbl_type, "MockTable")

    def test_core_settings_aggregated_functions(self) -> None:
        """Verifies Issue 325: core.settings exports all 5 functions and default-binds settings."""
        from core.settings import (
            get_all_configured_databases,
            get_database_metadata,
            get_database_scopes,
            get_table_scope_from_settings,
            get_table_type_from_settings,
        )

        scopes = get_database_scopes()
        self.assertIn("arxiv_security_db", scopes)
        self.assertNotIn("default", scopes)

        all_dbs = get_all_configured_databases()
        self.assertIn("arxiv_security_db", all_dbs)
        self.assertNotIn("default", all_dbs)

        meta = get_database_metadata("arxiv_security_db")
        self.assertEqual(meta["name"], "arxiv_security_db")
        self.assertEqual(meta["time_zone"], "UTC")

        self.assertEqual(
            get_table_scope_from_settings("okf_papers"), "arxiv_security_db"
        )
        self.assertEqual(
            get_table_type_from_settings("okf_papers"), "Virtual (Markdown)"
        )
        self.assertIsNone(get_table_type_from_settings("non_existent_table"))


if __name__ == "__main__":
    unittest.main()
