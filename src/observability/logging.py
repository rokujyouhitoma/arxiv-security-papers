"""
AI-Friendly Structured JSON Logging & Observability Framework.
Zero external dependencies (pure standard library).
Outputs OpenTelemetry / ECS aligned single-line JSON (.jsonl).
"""

import datetime
import json
import logging
import os
import sys
import traceback
from typing import Any, Dict, List, Optional, Tuple

from observability.masking import mask_dict, mask_text
from observability.propagation import get_current_span_id, get_current_trace_id


def _ensure_trace_ids(record: logging.LogRecord) -> None:
    if not getattr(record, "trace_id", None):
        setattr(record, "trace_id", get_current_trace_id())
    if not getattr(record, "span_id", None):
        setattr(record, "span_id", get_current_span_id())


class TraceContextFilter(logging.Filter):
    """Injects active W3C trace_id and span_id into log records from contextvars."""

    def filter(self, record: logging.LogRecord) -> bool:
        _ensure_trace_ids(record)
        return True


def _mask_record_args(args: Any) -> Any:
    if isinstance(args, dict):
        return mask_dict(args)
    if isinstance(args, tuple):
        return tuple(mask_text(str(a)) if isinstance(a, str) else a for a in args)
    return args


class SensitiveMaskingFilter(logging.Filter):
    """Masks credentials, tokens, and PII from log messages and arguments."""

    def filter(self, record: logging.LogRecord) -> bool:
        if isinstance(record.msg, str):
            record.msg = mask_text(record.msg)
        if record.args:
            record.args = _mask_record_args(record.args)
        return True


def _format_exc_tb(exc_tb: Any) -> List[str]:
    raw_tb = traceback.format_tb(exc_tb) if exc_tb else []
    return [
        line.strip() for chunk in raw_tb for line in chunk.splitlines() if line.strip()
    ]


def _extract_exc_info_dict(exc_info: Tuple[Any, Any, Any]) -> Dict[str, Any]:
    exc_type, exc_val, exc_tb = exc_info
    type_name = getattr(exc_type, "__name__", "Exception")
    return {
        "class": type_name,
        "message": mask_text(str(exc_val)),
        "stacktrace": _format_exc_tb(exc_tb),
    }


class StructuredJsonFormatter(logging.Formatter):
    """
    Serializes Python logging records into single-line, deterministic JSON (JSON Lines).
    Alignd with OpenTelemetry Log Data Model and Elastic Common Schema (ECS).
    """

    def __init__(self, service_name: str = "arxiv-security-papers") -> None:
        super().__init__()
        self.service_name = service_name

    def _format_timestamp(self, record: logging.LogRecord) -> str:
        dt = datetime.datetime.fromtimestamp(record.created, tz=datetime.timezone.utc)
        return dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")

    def _extract_error_block(
        self, record: logging.LogRecord
    ) -> Optional[Dict[str, Any]]:
        if record.exc_info and record.exc_info[0] is not None:
            return _extract_exc_info_dict(record.exc_info)
        explicit_err = getattr(record, "error", None)
        if isinstance(explicit_err, dict):
            return mask_dict(explicit_err)
        return None

    def _build_base_payload(
        self, record: logging.LogRecord, msg: str
    ) -> Dict[str, Any]:
        tid = getattr(record, "trace_id", "") or get_current_trace_id()
        sid = getattr(record, "span_id", "") or get_current_span_id()
        payload: Dict[str, Any] = {
            "timestamp": self._format_timestamp(record),
            "level": record.levelname,
            "service": getattr(record, "service", self.service_name),
            "logger": record.name,
            "module": record.module,
            "func": record.funcName,
            "line": record.lineno,
            "pid": record.process,
            "message": msg,
        }
        if tid:
            payload["trace_id"] = tid
        if sid:
            payload["span_id"] = sid
        return payload

    def _attach_context_blocks(
        self, payload: Dict[str, Any], record: logging.LogRecord
    ) -> None:
        for key in ("event", "http", "db", "diagnostic", "metrics"):
            val = getattr(record, key, None)
            if val is not None:
                payload[key] = mask_dict(val) if isinstance(val, dict) else val

    def format(self, record: logging.LogRecord) -> str:
        msg = mask_text(record.getMessage())
        payload = self._build_base_payload(record, msg)
        self._attach_context_blocks(payload, record)
        err_block = self._extract_error_block(record)
        if err_block:
            payload["error"] = err_block
        return json.dumps(payload, ensure_ascii=False)


def _create_stream_handler(
    formatter: logging.Formatter,
) -> logging.Handler:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(formatter)
    return handler


def _create_file_handler(
    log_file: str, formatter: logging.Formatter
) -> logging.Handler:
    os.makedirs(os.path.dirname(os.path.abspath(log_file)), exist_ok=True)
    handler = logging.FileHandler(log_file, encoding="utf-8")
    handler.setFormatter(formatter)
    return handler


def configure_logging(
    service_name: str,
    log_level: str = "INFO",
    log_file: Optional[str] = None,
    console: bool = True,
) -> logging.Logger:
    """Configures structured JSON logging for a designated subsystem."""
    level = getattr(logging, log_level.upper(), logging.INFO)
    logger = logging.getLogger(service_name)
    logger.setLevel(level)
    logger.handlers.clear()
    logger.propagate = False

    formatter = StructuredJsonFormatter(service_name=service_name)
    trace_filter = TraceContextFilter()
    mask_filter = SensitiveMaskingFilter()

    if console:
        sh = _create_stream_handler(formatter)
        sh.addFilter(trace_filter)
        sh.addFilter(mask_filter)
        logger.addHandler(sh)

    if log_file:
        fh = _create_file_handler(log_file, formatter)
        fh.addFilter(trace_filter)
        fh.addFilter(mask_filter)
        logger.addHandler(fh)

    return logger


__all__ = [
    "StructuredJsonFormatter",
    "TraceContextFilter",
    "SensitiveMaskingFilter",
    "configure_logging",
]
