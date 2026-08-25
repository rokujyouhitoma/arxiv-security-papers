#!/usr/bin/env python3
"""
Generalized configuration models for Process Supervisor and Arbiter Engine.
Supports defining multiple named stateless worker pools and stateful services with dependency graphs.
"""

from __future__ import annotations

import dataclasses
import os
from typing import Any, Dict, List, Optional


@dataclasses.dataclass
class PoolConfig:
    """Configuration for a named stateless worker pool."""

    name: str = "default_pool"
    workers: int = 2
    worker_class: str = "sync"  # 'sync', 'threaded'/'gthread', 'async'
    threads: int = 1
    bind_host: Optional[str] = "0.0.0.0"
    bind_port: Optional[int] = 8000
    backlog: int = 2048
    target_uri: str = "web.server:app"
    timeout: float = 30.0
    graceful_timeout: float = 30.0
    dependencies: List[str] = dataclasses.field(default_factory=list)


@dataclasses.dataclass
class ServiceConfig:
    """Configuration for a named stateful managed service."""

    name: str = "default_service"
    hook_uri: Optional[str] = None
    sync_interval: float = 2.0
    timeout: float = 30.0
    dependencies: List[str] = dataclasses.field(default_factory=list)


@dataclasses.dataclass
class SupervisorConfig:
    """
    Root configuration managing one or more pools and services.
    """

    # Global Paths & Control
    workspace_dir: str = dataclasses.field(
        default_factory=lambda: os.path.abspath(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        )
    )
    pid_file: Optional[str] = None
    control_socket: Optional[str] = None
    timeout: float = 30.0
    graceful_timeout: float = 30.0
    # request_timeout: applied only to workers actively handling a request.
    # When a worker's heartbeat has not been refreshed within this window *and*
    # the worker has ``is_handling_request=True``, it is considered hung and
    # sent SIGKILL.  Defaults to the same value as ``timeout``.
    request_timeout: float = 30.0
    # idle_timeout: maximum seconds a worker may stay idle (no requests) before
    # being gracefully retired.  0.0 means idle workers are never killed, which
    # is the correct default for a pre-fork server with variable traffic.
    idle_timeout: float = 0.0

    # Generalized Subsystems
    pools: List[PoolConfig] = dataclasses.field(default_factory=list)
    services: List[ServiceConfig] = dataclasses.field(default_factory=list)

    # Top-level Shorthand / Compatibility attributes
    bind_host: str = "0.0.0.0"
    bind_port: int = 8000
    backlog: int = 2048
    workers: int = dataclasses.field(
        default_factory=lambda: max(2, (2 * (os.cpu_count() or 1)) + 1)
    )
    worker_class: str = "sync"
    threads: int = 1
    app_uri: str = "web.server:app"
    manage_database: bool = True
    db_worker_count: int = 1
    db_sync_timeout: float = 10.0

    def __post_init__(self) -> None:
        self._ensure_default_pools_and_services()
        self.validate()

    def _ensure_default_pools_and_services(self) -> None:
        """Constructs default pools and services from top-level shorthand if none provided."""
        if not self.pools:
            deps = ["database"] if self.manage_database else []
            self.pools.append(
                PoolConfig(
                    name="web",
                    workers=self.workers,
                    worker_class=self.worker_class,
                    threads=self.threads,
                    bind_host=self.bind_host,
                    bind_port=self.bind_port,
                    backlog=self.backlog,
                    target_uri=self.app_uri,
                    timeout=self.timeout,
                    graceful_timeout=self.graceful_timeout,
                    dependencies=deps,
                )
            )

        if not self.services and self.manage_database:
            self.services.append(
                ServiceConfig(
                    name="database",
                    sync_interval=2.0,
                    timeout=self.timeout,
                )
            )

    def _validate_pool(self, pool: PoolConfig) -> None:
        """Validates individual pool configuration."""
        if pool.workers < 1:
            raise ValueError(
                f"Pool '{pool.name}' worker count must be >= 1, got {pool.workers}."
            )
        if pool.worker_class not in ("sync", "gthread", "threaded", "async"):
            raise ValueError(
                f"Invalid worker_class '{pool.worker_class}' in pool '{pool.name}'."
            )
        if pool.bind_port is not None and not (1 <= pool.bind_port <= 65535):
            raise ValueError(
                f"Invalid bind_port {pool.bind_port} in pool '{pool.name}'."
            )

    def validate(self) -> None:
        """Validates configuration sanity."""
        if not self.pid_file:
            self.pid_file = os.path.join(
                self.workspace_dir, "outputs", "supervisor", "arbiter.pid"
            )
        if not self.control_socket:
            self.control_socket = os.path.join(
                self.workspace_dir, "outputs", "supervisor", "control.sock"
            )

        if self.threads < 1:
            raise ValueError(f"Thread count must be at least 1, got {self.threads}.")
        if self.timeout <= 0:
            raise ValueError(f"Timeout must be positive, got {self.timeout}.")
        if self.graceful_timeout <= 0:
            raise ValueError(
                f"Graceful timeout must be positive, got {self.graceful_timeout}."
            )

        for pool in self.pools:
            self._validate_pool(pool)

    @classmethod
    def _normalize_bind_alias(cls, d: Dict[str, Any]) -> None:
        """Extracts bind_host and bind_port from 'bind' alias if present."""
        if "bind" in d and "bind_host" not in d and "bind_port" not in d:
            bind_val = d.pop("bind")
            if isinstance(bind_val, str) and ":" in bind_val:
                host, port_str = bind_val.split(":", 1)
                d["bind_host"] = host
                d["bind_port"] = int(port_str)
            elif isinstance(bind_val, (int, str)):
                d["bind_port"] = int(bind_val)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "SupervisorConfig":
        """Constructs a validated SupervisorConfig from dictionary."""
        d = dict(data)
        cls._normalize_bind_alias(d)

        pools_raw = d.pop("pools", None)
        services_raw = d.pop("services", None)

        valid_fields = {f.name for f in dataclasses.fields(cls)}
        filtered = {k: v for k, v in d.items() if k in valid_fields}
        instance = cls(**filtered)

        if pools_raw is not None:
            instance.pools = [
                PoolConfig(**p) if isinstance(p, dict) else p for p in pools_raw
            ]
        if services_raw is not None:
            instance.services = [
                ServiceConfig(**s) if isinstance(s, dict) else s for s in services_raw
            ]

        instance.validate()
        return instance

    @classmethod
    def _load_python_module(cls, mod_name: str) -> Dict[str, Any]:
        """Loads configuration dictionary from an importable Python module."""
        import importlib

        mod = importlib.import_module(mod_name)
        return {k.lower(): getattr(mod, k) for k in dir(mod) if not k.startswith("_")}

    @classmethod
    def _load_python_file(cls, path: str) -> Dict[str, Any]:
        """Executes a Python configuration file and extracts variables."""
        import importlib.util

        spec = importlib.util.spec_from_file_location("supervisor_custom_config", path)
        if spec is None or spec.loader is None:
            raise ImportError(f"Could not load Python configuration file from {path}")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return {k.lower(): getattr(mod, k) for k in dir(mod) if not k.startswith("_")}

    @classmethod
    def from_file(cls, path: str) -> "SupervisorConfig":
        """
        Loads SupervisorConfig from a JSON (.json), TOML (.toml), or Python (.py) config file,
        or from a Python module specification ('python:module.path').
        """
        if path.startswith("file://"):
            path = path[7:]

        if path.startswith("python:"):
            return cls.from_dict(cls._load_python_module(path.split(":", 1)[1]))

        if not os.path.exists(path):
            raise FileNotFoundError(f"Configuration file not found: {path}")

        ext = os.path.splitext(path)[1].lower()
        if ext == ".toml":
            import tomllib

            with open(path, "rb") as f:
                return cls.from_dict(tomllib.load(f))
        if ext == ".py":
            return cls.from_dict(cls._load_python_file(path))

        # Default / JSON parser
        import json

        with open(path, "r", encoding="utf-8") as f:
            return cls.from_dict(json.load(f))

    @classmethod
    def auto_discover(
        cls, root_dir: Optional[str] = None
    ) -> Optional["SupervisorConfig"]:
        """
        Automatically discovers default supervisor/gunicorn configuration files
        in standard locations if present.
        """
        search_dir = root_dir or os.getcwd()
        candidates = [
            "supervisor.conf.py",
            "supervisor_conf.py",
            "gunicorn.conf.py",
            "config/supervisor.py",
            "config/supervisor.json",
            "config/supervisor.toml",
        ]
        for candidate in candidates:
            target = os.path.join(search_dir, candidate)
            if os.path.exists(target):
                try:
                    return cls.from_file(target)
                except Exception:
                    continue
        return None

    def to_dict(self) -> Dict[str, Any]:
        """Exports full structured configuration."""
        return dataclasses.asdict(self)
