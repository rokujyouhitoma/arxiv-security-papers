#!/usr/bin/env python3
"""
Heartbeat Watchdog and Health Monitoring for Child Workers.
Tracks per-worker activity timestamps, detect hung/deadlocked processes,
and provides telemetry metadata.
"""

from __future__ import annotations

import threading
import time
from typing import Any, Dict, List, Optional


class HeartbeatWatchdog:
    """
    Thread-safe watchdog maintaining liveness and health states of all managed child workers.
    """

    def __init__(self, timeout: float = 30.0) -> None:
        self.timeout = timeout
        self._lock = threading.Lock()
        self._heartbeats: Dict[int, float] = {}
        self._worker_meta: Dict[int, Dict[str, Any]] = {}

    def record_heartbeat(
        self, pid: int, metadata: Optional[Dict[str, Any]] = None
    ) -> None:
        """Records an active pulse for the given worker PID."""
        with self._lock:
            now = time.monotonic()
            self._heartbeats[pid] = now
            if metadata:
                if pid not in self._worker_meta:
                    self._worker_meta[pid] = {}
                self._worker_meta[pid].update(metadata)
                self._worker_meta[pid]["last_seen_monotonic"] = now
                self._worker_meta[pid]["last_seen_epoch"] = time.time()

    def register_worker(
        self, pid: int, worker_type: str, metadata: Optional[Dict[str, Any]] = None
    ) -> None:
        """Registers a newly spawned worker with initial metadata."""
        with self._lock:
            now = time.monotonic()
            self._heartbeats[pid] = now
            meta = {
                "pid": pid,
                "type": worker_type,
                "spawned_at": time.time(),
                "requests_handled": 0,
                "status": "ALIVE",
            }
            if metadata:
                meta.update(metadata)
            self._worker_meta[pid] = meta

    def remove_worker(self, pid: int) -> None:
        """Removes a terminated worker from tracking tables."""
        with self._lock:
            self._heartbeats.pop(pid, None)
            self._worker_meta.pop(pid, None)

    def is_healthy(self, pid: int, timeout: Optional[float] = None) -> bool:
        """Checks if a worker has sent a heartbeat within the timeout threshold."""
        t_limit = timeout if timeout is not None else self.timeout
        with self._lock:
            last_pulse = self._heartbeats.get(pid)
            if last_pulse is None:
                return False
            return (time.monotonic() - last_pulse) <= t_limit

    def get_hung_workers(self, timeout: Optional[float] = None) -> List[int]:
        """Returns a list of worker PIDs that exceeded the heartbeat timeout."""
        t_limit = timeout if timeout is not None else self.timeout
        now = time.monotonic()
        hung: List[int] = []
        with self._lock:
            for pid, last_pulse in self._heartbeats.items():
                if (now - last_pulse) > t_limit:
                    hung.append(pid)
        return hung

    def get_worker_status(self, pid: int) -> Optional[Dict[str, Any]]:
        """Retrieves structured telemetry metadata for a specific worker."""
        with self._lock:
            if pid not in self._worker_meta:
                return None
            meta = dict(self._worker_meta[pid])
            last_pulse = self._heartbeats.get(pid, 0.0)
            meta["idle_seconds"] = round(time.monotonic() - last_pulse, 2)
            meta["is_healthy"] = meta["idle_seconds"] <= self.timeout
            return meta

    def get_all_statuses(self) -> Dict[int, Dict[str, Any]]:
        """Returns snapshot dictionary of all currently tracked workers."""
        with self._lock:
            res: Dict[int, Dict[str, Any]] = {}
            now = time.monotonic()
            for pid, meta in self._worker_meta.items():
                m = dict(meta)
                last_pulse = self._heartbeats.get(pid, 0.0)
                m["idle_seconds"] = round(now - last_pulse, 2)
                m["is_healthy"] = m["idle_seconds"] <= self.timeout
                res[pid] = m
            return res
