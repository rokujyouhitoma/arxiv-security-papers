#!/usr/bin/env python3
"""
Heartbeat Watchdog and Health Monitoring for Child Workers.
Tracks per-worker activity timestamps, detect hung/deadlocked processes,
and provides telemetry metadata.
"""

from __future__ import annotations

import os
import threading
import time
from typing import Any, Dict, List, Optional


class HeartbeatWatchdog:
    """
    Thread-safe watchdog maintaining liveness and health states of all managed child workers.
    """

    def __init__(self, timeout: float = 30.0, base_dir: Optional[str] = None) -> None:
        self.timeout = timeout
        self.base_dir = base_dir
        self._lock = threading.Lock()
        self._heartbeats: Dict[int, float] = {}
        self._last_active: Dict[int, float] = {}
        self._last_requests_handled: Dict[int, int] = {}
        self._worker_meta: Dict[int, Dict[str, Any]] = {}

    def _update_activity_state(
        self, pid: int, data: Dict[str, Any], now: float
    ) -> None:
        prev_req = self._last_requests_handled.get(pid, 0)
        curr_req = int(data.get("requests_handled", prev_req))
        if curr_req > prev_req or data.get("is_handling_request", False):
            self._last_active[pid] = now
            self._last_requests_handled[pid] = curr_req
        elif pid not in self._last_active:
            self._last_active[pid] = now

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
                self._update_activity_state(pid, metadata, now)
                self._worker_meta[pid].update(metadata)
                self._worker_meta[pid]["last_seen_monotonic"] = now
                self._worker_meta[pid]["last_seen_epoch"] = time.time()

    def _sync_single_worker_file(self, pid: int, target_dir: str) -> None:
        path = os.path.join(target_dir, f"heartbeat_{pid}.json")
        if not os.path.exists(path):
            return
        try:
            import json

            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                now = time.monotonic()
                self._heartbeats[pid] = now
                if pid not in self._worker_meta:
                    self._worker_meta[pid] = {}
                self._update_activity_state(pid, data, now)
                self._worker_meta[pid].update(data)
                self._worker_meta[pid]["last_seen_monotonic"] = now
        except Exception:
            pass

    def sync_from_disk(self, base_dir: Optional[str] = None) -> None:
        """Reads worker heartbeat state files from disk and synchronizes in-memory tables."""
        target_dir = base_dir or self.base_dir
        if not target_dir or not os.path.isdir(target_dir):
            return
        with self._lock:
            tracked_pids = list(self._worker_meta.keys())
            for pid in tracked_pids:
                self._sync_single_worker_file(pid, target_dir)

    def register_worker(
        self, pid: int, worker_type: str, metadata: Optional[Dict[str, Any]] = None
    ) -> None:
        """Registers a newly spawned worker with initial metadata."""
        with self._lock:
            now = time.monotonic()
            self._heartbeats[pid] = now
            self._last_active[pid] = now
            self._last_requests_handled[pid] = 0
            meta = {
                "pid": pid,
                "type": worker_type,
                "spawned_at": time.time(),
                "requests_handled": 0,
                "status": "ALIVE",
            }
            if metadata:
                meta.update(metadata)
                self._update_activity_state(pid, metadata, now)
            self._worker_meta[pid] = meta

    def remove_worker(self, pid: int) -> None:
        """Removes a terminated worker from tracking tables and cleans up disk files."""
        with self._lock:
            self._heartbeats.pop(pid, None)
            self._last_active.pop(pid, None)
            self._last_requests_handled.pop(pid, None)
            self._worker_meta.pop(pid, None)
        target_dir = self.base_dir
        if target_dir and os.path.isdir(target_dir):
            try:
                path = os.path.join(target_dir, f"heartbeat_{pid}.json")
                if os.path.exists(path):
                    os.remove(path)
            except Exception:
                pass

    @staticmethod
    def _check_meta_health(
        meta: Dict[str, Any], last_pulse: float, t_limit: float
    ) -> bool:
        if meta.get("status") != "ALIVE":
            return False
        if "is_healthy" in meta:
            return bool(meta["is_healthy"])
        if meta.get("is_handling_request", False):
            return (time.monotonic() - last_pulse) <= t_limit
        return True

    def is_healthy(self, pid: int, timeout: Optional[float] = None) -> bool:
        """Checks if a worker is healthy based on its operational state."""
        t_limit = timeout if timeout is not None else self.timeout
        with self._lock:
            last_pulse = self._heartbeats.get(pid)
            if last_pulse is None:
                return False
            meta = self._worker_meta.get(pid, {})
            return self._check_meta_health(meta, last_pulse, t_limit)

    def get_hung_workers(self, timeout: Optional[float] = None) -> List[int]:
        """Returns a list of worker PIDs that exceeded the heartbeat timeout.

        Only workers actively handling a request (``is_handling_request=True``)
        are considered hung candidates.  Idle workers that have received no
        requests simply have no opportunity to refresh their heartbeat, so they
        must not be killed — killing them would destroy the worker pool even
        under zero traffic.
        """
        t_limit = timeout if timeout is not None else self.timeout
        now = time.monotonic()
        hung: List[int] = []
        with self._lock:
            for pid, last_pulse in self._heartbeats.items():
                meta = self._worker_meta.get(pid, {})
                # Skip idle workers — they are waiting for requests, not hung.
                if not meta.get("is_handling_request", False):
                    continue
                if (now - last_pulse) > t_limit:
                    hung.append(pid)
        return hung

    def _compute_idle_seconds(
        self, pid: int, meta: Dict[str, Any], now_monotonic: float, now_epoch: float
    ) -> float:
        if meta.get("is_handling_request", False):
            return 0.0
        if "last_active_epoch" in meta:
            try:
                return max(0.0, round(now_epoch - float(meta["last_active_epoch"]), 1))
            except (ValueError, TypeError):
                pass
        last_act = self._last_active.get(pid, now_monotonic)
        return max(0.0, round(now_monotonic - last_act, 1))

    def _compute_worker_health(
        self, meta: Dict[str, Any], last_pulse: float, now: float
    ) -> bool:
        """Helper to determine worker health based on type and request state."""
        if meta.get("status") != "ALIVE":
            return False
        if "is_healthy" in meta:
            return bool(meta["is_healthy"])
        if meta.get("is_handling_request", False):
            return (now - last_pulse) <= self.timeout
        return True

    def get_worker_status(self, pid: int) -> Optional[Dict[str, Any]]:
        """Retrieves structured telemetry metadata for a specific worker."""
        self.sync_from_disk()
        with self._lock:
            if pid not in self._worker_meta:
                return None
            meta = dict(self._worker_meta[pid])
            now_m = time.monotonic()
            now_e = time.time()
            last_pulse = self._heartbeats.get(pid, 0.0)
            meta["idle_seconds"] = self._compute_idle_seconds(pid, meta, now_m, now_e)
            meta["is_healthy"] = self._compute_worker_health(meta, last_pulse, now_m)
            return meta

    def get_all_statuses(self) -> Dict[int, Dict[str, Any]]:
        """Returns snapshot dictionary of all currently tracked workers."""
        self.sync_from_disk()
        with self._lock:
            res: Dict[int, Dict[str, Any]] = {}
            now_m = time.monotonic()
            now_e = time.time()
            for pid, meta in self._worker_meta.items():
                m = dict(meta)
                last_pulse = self._heartbeats.get(pid, 0.0)
                m["idle_seconds"] = self._compute_idle_seconds(pid, m, now_m, now_e)
                m["is_healthy"] = self._compute_worker_health(m, last_pulse, now_m)
                res[pid] = m
            return res

    @staticmethod
    def get_worker_memory_mb(pid: int) -> float:
        """
        Reads memory usage in Megabytes for a given PID.
        Prefers PSS (proportional set size), falling back to RSS.
        """
        from .top import SupervisorTopViewer

        rss_mb, pss_mb = SupervisorTopViewer.get_process_memory_mb(pid)
        return pss_mb if pss_mb > 0.0 else rss_mb

    def _is_worker_memory_exceeded(
        self, pid: int, meta: Dict[str, Any], spec_map: Dict[str, Any]
    ) -> bool:
        pool_name = str(meta.get("type", "default"))
        spec = spec_map.get(pool_name)
        if not spec:
            return False
        max_mem = float(getattr(spec, "max_worker_memory_mb", 0.0))
        if max_mem <= 0.0:
            return False
        return self.get_worker_memory_mb(pid) > max_mem

    def get_memory_exceeded_workers(self, spec_map: Dict[str, Any]) -> List[int]:
        """
        Scans all tracked workers and returns PIDs of workers exceeding their memory limit.
        """
        exceeded: List[int] = []
        with self._lock:
            for pid, meta in self._worker_meta.items():
                if self._is_worker_memory_exceeded(pid, meta, spec_map):
                    exceeded.append(pid)
        return exceeded
