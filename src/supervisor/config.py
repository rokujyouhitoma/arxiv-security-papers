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
    max_requests: int = 0
    max_requests_jitter: int = 0
    max_worker_lifetime: float = 0.0
    max_worker_lifetime_jitter: float = 0.0
    max_worker_memory_mb: float = 0.0


@dataclasses.dataclass
class ServiceConfig:
    """Configuration for a named stateful managed service."""

    name: str = "default_service"
    workers: int = 3
    hook_uri: Optional[str] = None
    sync_interval: float = 2.0
    timeout: float = 30.0
    graceful_timeout: float = 30.0
    dependencies: List[str] = dataclasses.field(default_factory=list)
    max_requests: int = 0
    max_requests_jitter: int = 0
    max_worker_lifetime: float = 0.0
    max_worker_lifetime_jitter: float = 0.0
    max_worker_memory_mb: float = 0.0


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
    lock_file: Optional[str] = None
    control_socket: Optional[str] = None
    daemon: bool = False
    log_file: Optional[str] = None
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

    # Shorthand for default stateless pool
    bind_host: str = "0.0.0.0"
    bind_port: int = 8000
    backlog: int = 2048
    workers: int = 2
    worker_class: str = "sync"
    threads: int = 1
    app_uri: str = "web.server:app"

    # Global Worker Lifetime, Request Limits, and Memory Watchdog
    max_requests: int = 0
    max_requests_jitter: int = 0
    max_worker_lifetime: float = 0.0
    max_worker_lifetime_jitter: float = 0.0
    max_worker_memory_mb: float = 0.0

    def __post_init__(self) -> None:
        self._ensure_default_pools()
        self.validate()

    @staticmethod
    def _fallback_val(val: float, fallback: float) -> float:
        return val if val > 0 else fallback

    def _create_default_pool(self) -> PoolConfig:
        return PoolConfig(
            name="default",
            workers=self.workers,
            worker_class=self.worker_class,
            threads=self.threads,
            bind_host=self.bind_host,
            bind_port=self.bind_port,
            backlog=self.backlog,
            target_uri=self.app_uri,
            timeout=self.timeout,
            graceful_timeout=self.graceful_timeout,
            max_requests=int(self._fallback_val(self.max_requests, 2000)),
            max_requests_jitter=int(self._fallback_val(self.max_requests_jitter, 200)),
            max_worker_lifetime=self._fallback_val(self.max_worker_lifetime, 3600.0),
            max_worker_lifetime_jitter=self._fallback_val(
                self.max_worker_lifetime_jitter, 300.0
            ),
            max_worker_memory_mb=self._fallback_val(self.max_worker_memory_mb, 250.0),
        )

    def _ensure_default_pools(self) -> None:
        """Constructs default stateless pool if none provided."""
        if not self.pools and not self.services:
            self.pools.append(self._create_default_pool())

    def _resolve_limit(self, pool_val: Any, global_val: Any) -> Any:
        return pool_val if pool_val else global_val

    def _build_pool_spec(self, pool: PoolConfig) -> Any:
        from .contracts import ServiceRole, WorkerSpec

        return WorkerSpec(
            name=pool.name,
            target_count=pool.workers,
            worker_class=pool.worker_class,
            role=ServiceRole.STATELESS_POOL,
            max_requests=self._resolve_limit(pool.max_requests, self.max_requests),
            max_requests_jitter=self._resolve_limit(
                pool.max_requests_jitter, self.max_requests_jitter
            ),
            max_worker_lifetime=self._resolve_limit(
                pool.max_worker_lifetime, self.max_worker_lifetime
            ),
            max_worker_lifetime_jitter=self._resolve_limit(
                pool.max_worker_lifetime_jitter, self.max_worker_lifetime_jitter
            ),
            max_worker_memory_mb=self._resolve_limit(
                pool.max_worker_memory_mb, self.max_worker_memory_mb
            ),
            graceful_timeout=pool.graceful_timeout or self.graceful_timeout,
            metadata={"target_uri": pool.target_uri, "threads": pool.threads},
        )

    def _build_service_spec(self, svc: ServiceConfig) -> Any:
        from .contracts import ServiceRole, WorkerSpec

        return WorkerSpec(
            name=svc.name,
            target_count=svc.workers,
            worker_class="service",
            role=ServiceRole.STATEFUL_SERVICE,
            sync_interval=svc.sync_interval,
            max_requests=self._resolve_limit(svc.max_requests, self.max_requests),
            max_requests_jitter=self._resolve_limit(
                svc.max_requests_jitter, self.max_requests_jitter
            ),
            max_worker_lifetime=self._resolve_limit(
                svc.max_worker_lifetime, self.max_worker_lifetime
            ),
            max_worker_lifetime_jitter=self._resolve_limit(
                svc.max_worker_lifetime_jitter, self.max_worker_lifetime_jitter
            ),
            max_worker_memory_mb=self._resolve_limit(
                svc.max_worker_memory_mb, self.max_worker_memory_mb
            ),
            graceful_timeout=svc.graceful_timeout or self.graceful_timeout,
            metadata={"hook_uri": svc.hook_uri},
        )

    def build_worker_specs(self) -> List[Any]:
        """Constructs declarative WorkerSpec objects for all configured pools and services."""
        specs: List[Any] = []
        for pool in self.pools:
            specs.append(self._build_pool_spec(pool))
        for svc in self.services:
            specs.append(self._build_service_spec(svc))
        return specs

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

    def _fill_log_if_daemon(self, base: str) -> None:
        if self.daemon and not self.log_file:
            self.log_file = os.path.join(base, "supervisor.log")

    def _fill_default_paths(self) -> None:
        base = os.path.join(self.workspace_dir, "outputs", "supervisor")
        self.pid_file = self.pid_file or os.path.join(base, "arbiter.pid")
        self.lock_file = self.lock_file or os.path.join(base, "arbiter.lock")
        self.control_socket = self.control_socket or os.path.join(base, "control.sock")
        self._fill_log_if_daemon(base)

    def _validate_timeouts(self) -> None:
        if self.threads < 1:
            raise ValueError(f"Thread count must be at least 1, got {self.threads}.")
        if self.timeout <= 0:
            raise ValueError(f"Timeout must be positive, got {self.timeout}.")
        if self.graceful_timeout <= 0:
            raise ValueError(
                f"Graceful timeout must be positive, got {self.graceful_timeout}."
            )

    def _validate_rotation(self) -> None:
        if min(self.max_requests, self.max_requests_jitter) < 0:
            raise ValueError("Max requests and jitter must be non-negative.")
        if min(self.max_worker_lifetime, self.max_worker_lifetime_jitter) < 0.0:
            raise ValueError("Max worker lifetime and jitter must be non-negative.")
        if self.max_worker_memory_mb < 0.0:
            raise ValueError("Max worker memory must be non-negative.")

    def _validate_numeric(self) -> None:
        self._validate_timeouts()
        self._validate_rotation()

    def validate(self) -> None:
        """Validates configuration sanity."""
        self._fill_default_paths()
        self._validate_numeric()
        for pool in self.pools:
            self._validate_pool(pool)

    @classmethod
    def _parse_bind_str(cls, bind_val: str, d: Dict[str, Any]) -> None:
        if ":" in bind_val:
            host, port_str = bind_val.split(":", 1)
            d["bind_host"] = host
            d["bind_port"] = int(port_str)
        else:
            d["bind_port"] = int(bind_val)

    @classmethod
    def _resolve_bind_type(cls, bind_val: Any, d: Dict[str, Any]) -> None:
        if isinstance(bind_val, str):
            cls._parse_bind_str(bind_val, d)
        elif isinstance(bind_val, int):
            d["bind_port"] = bind_val

    @classmethod
    def _normalize_bind_alias(cls, d: Dict[str, Any]) -> None:
        """Extracts bind_host and bind_port from 'bind' alias if present."""
        bind_val = d.pop("bind", None)
        if bind_val is None:
            return
        if "bind_host" not in d and "bind_port" not in d:
            cls._resolve_bind_type(bind_val, d)

    @staticmethod
    def _coerce_pool(p: Any) -> PoolConfig:
        return PoolConfig(**p) if isinstance(p, dict) else p

    @staticmethod
    def _coerce_service(s: Any) -> "ServiceConfig":
        return ServiceConfig(**s) if isinstance(s, dict) else s

    @classmethod
    def _parse_pools_and_services(
        cls, instance: "SupervisorConfig", pools_raw: Any, services_raw: Any
    ) -> None:
        if pools_raw is not None:
            instance.pools = [cls._coerce_pool(p) for p in pools_raw]
        if services_raw is not None:
            instance.services = [cls._coerce_service(s) for s in services_raw]

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
        cls._parse_pools_and_services(instance, pools_raw, services_raw)
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
    def _load_config_file(cls, path: str) -> "SupervisorConfig":
        ext = os.path.splitext(path)[1].lower()
        if ext == ".toml":
            import tomllib

            with open(path, "rb") as f:
                return cls.from_dict(tomllib.load(f))
        if ext == ".py":
            return cls.from_dict(cls._load_python_file(path))
        import json

        with open(path, "r", encoding="utf-8") as f:
            return cls.from_dict(json.load(f))

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
        return cls._load_config_file(path)

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
