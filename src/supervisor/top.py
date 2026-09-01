#!/usr/bin/env python3
"""
Real-time Process Monitoring Dashboard (top) for Process Supervisor Arbiter & Workers.
Provides ANSI-colored dynamic TUI / CLI metrics rendering for process lifecycle observation.
"""

from __future__ import annotations

import os
import sys
import time
from typing import Any, Dict, List

from .control import ControlClient


class SupervisorTopViewer:
    """
    Renders a live, real-time top-like monitoring dashboard for Supervisor Arbiter and Workers.
    """

    COLOR_RESET = "\033[0m"
    COLOR_BOLD = "\033[1m"
    COLOR_CYAN = "\033[36m"
    COLOR_GREEN = "\033[32m"
    COLOR_YELLOW = "\033[33m"
    COLOR_RED = "\033[31m"
    COLOR_MAGENTA = "\033[35m"
    COLOR_BLUE = "\033[34m"
    COLOR_GRAY = "\033[90m"

    def __init__(self, client: ControlClient, no_color: bool = False) -> None:
        self.client = client
        self.no_color = no_color

    def _c(self, color_code: str, text: str) -> str:
        """Applies ANSI color if colors are enabled."""
        if self.no_color:
            return text
        return f"{color_code}{text}{self.COLOR_RESET}"

    @staticmethod
    def _parse_proc_line_kb(line: str) -> float:
        parts = line.split()
        return float(parts[1]) if len(parts) >= 2 else 0.0

    @staticmethod
    def _parse_smaps_line(
        line: str, rss_mb: float, pss_mb: float
    ) -> tuple[float, float]:
        if line.startswith("Rss:"):
            return (
                round(SupervisorTopViewer._parse_proc_line_kb(line) / 1024.0, 1),
                pss_mb,
            )
        if line.startswith("Pss:"):
            return rss_mb, round(
                SupervisorTopViewer._parse_proc_line_kb(line) / 1024.0, 1
            )
        return rss_mb, pss_mb

    @staticmethod
    def _read_smaps_memory(pid: int) -> tuple[float, float]:
        rss_mb, pss_mb = 0.0, 0.0
        smaps_file = f"/proc/{pid}/smaps_rollup"
        if not os.path.exists(smaps_file):
            return 0.0, 0.0
        try:
            with open(smaps_file, "r", encoding="utf-8") as f:
                for line in f:
                    rss_mb, pss_mb = SupervisorTopViewer._parse_smaps_line(
                        line, rss_mb, pss_mb
                    )
        except Exception:
            return 0.0, 0.0
        return rss_mb, pss_mb

    @staticmethod
    def _read_status_rss(pid: int) -> float:
        status_file = f"/proc/{pid}/status"
        if not os.path.exists(status_file):
            return 0.0
        try:
            with open(status_file, "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        return round(
                            SupervisorTopViewer._parse_proc_line_kb(line) / 1024.0, 1
                        )
        except Exception:
            return 0.0
        return 0.0

    @staticmethod
    def get_process_memory_mb(pid: int) -> tuple[float, float]:
        """
        Reads RSS and PSS memory in Megabytes for a given PID from /proc.
        Returns (rss_mb, pss_mb).
        """
        rss_mb, pss_mb = SupervisorTopViewer._read_smaps_memory(pid)
        if rss_mb > 0 or pss_mb > 0:
            return rss_mb, pss_mb
        return SupervisorTopViewer._read_status_rss(pid), 0.0

    @staticmethod
    def get_process_rss_mb(pid: int) -> float:
        """
        Reads Resident Set Size (RSS) memory in Megabytes for a given PID from /proc.
        Returns 0.0 if inaccessible or not on Linux.
        """
        rss_mb, _ = SupervisorTopViewer.get_process_memory_mb(pid)
        return rss_mb

    def format_uptime(self, seconds: float) -> str:
        """Formats uptime into human-readable duration."""
        sec = int(seconds)
        days = sec // 86400
        hours = (sec % 86400) // 3600
        minutes = (sec % 3600) // 60
        remaining_sec = sec % 60

        if days > 0:
            return f"{days}d {hours:02d}h {minutes:02d}m {remaining_sec:02d}s"
        if hours > 0:
            return f"{hours:02d}h {minutes:02d}m {remaining_sec:02d}s"
        return f"{minutes:02d}m {remaining_sec:02d}s"

    def _build_pools_summary(self, pools_meta: Any) -> str:
        parts = []
        if isinstance(pools_meta, dict):
            for name, meta in pools_meta.items():
                if isinstance(meta, dict):
                    parts.append(
                        f"{name}: {meta.get('active', 0)}/{meta.get('target', 0)}"
                    )
                else:
                    parts.append(f"{name}: {meta}")
        return ", ".join(parts) if parts else "No pools configured"

    def _render_arbiter_panel(self, data: Dict[str, Any]) -> List[str]:
        arbiter_pid = data.get("arbiter_pid", "-")
        uptime_str = self.format_uptime(data.get("uptime", 0.0))
        arbiter_rss, arbiter_pss = 0.0, 0.0
        if isinstance(arbiter_pid, int):
            arbiter_rss, arbiter_pss = self.get_process_memory_mb(arbiter_pid)
        mem_str = (
            f"{arbiter_rss:.1f} ({arbiter_pss:.1f}) MB"
            if arbiter_pss > 0
            else f"{arbiter_rss:.1f} MB"
        )
        w_summary = self._build_pools_summary(data.get("pools", {}))
        return [
            f"  {self._c(self.COLOR_BOLD, 'Arbiter PID:')} {self._c(self.COLOR_YELLOW, str(arbiter_pid)):<8} "
            f"  {self._c(self.COLOR_BOLD, 'Uptime:')} {uptime_str:<14} "
            f"  {self._c(self.COLOR_BOLD, 'Memory (PSS):')} {mem_str}",
            f"  {self._c(self.COLOR_BOLD, 'Pools:')}       {w_summary}",
            self._c(self.COLOR_GRAY, "─" * 78),
        ]

    def _render_worker_row(self, w_info: Dict[str, Any], spid: str) -> str:
        pid = w_info.get("pid", spid)
        w_type = w_info.get("type", "worker")
        status = w_info.get("status", "UNKNOWN")
        healthy = w_info.get("is_healthy", False)
        req_count = w_info.get("requests_handled", 0)
        idle_sec = w_info.get("idle_seconds", 0.0)

        rss_mb, pss_mb = self.get_process_memory_mb(int(pid))
        status_color = self.COLOR_GREEN if status == "ALIVE" else self.COLOR_RED
        health_color = self.COLOR_GREEN if healthy else self.COLOR_YELLOW
        health_str = "HEALTHY" if healthy else "UNHEALTHY"

        status_fmt = self._c(status_color, status)
        health_fmt = self._c(health_color, health_str)
        type_fmt = self._c(self.COLOR_CYAN, w_type)

        idle_str = f"{idle_sec:.1f}s"
        mem_display = (
            f"{rss_mb:.1f} ({pss_mb:.1f}) MB" if pss_mb > 0 else f"{rss_mb:.1f} MB"
        )
        return (
            f"  {str(pid):<6} "
            f"{type_fmt:<18} "
            f"{status_fmt:<16} "
            f"{health_fmt:<16} "
            f"{req_count:<8} "
            f"{idle_str:<10} "
            f"{mem_display}"
        )

    def render_dashboard(self, data: Dict[str, Any]) -> str:
        """Constructs the full formatted string for the top dashboard."""
        now_str = time.strftime("%Y-%m-%d %H:%M:%S")
        title = self._c(
            self.COLOR_BOLD + self.COLOR_CYAN,
            "⚡ [Supervisor Process Top Monitor]",
        )
        lines: List[str] = [
            f"{title}  {self._c(self.COLOR_GRAY, now_str)}",
            self._c(self.COLOR_GRAY, "─" * 78),
        ]
        lines.extend(self._render_arbiter_panel(data))

        # Workers Table Header
        header = (
            f"  {self._c(self.COLOR_BOLD, 'PID'):<14} "
            f"{self._c(self.COLOR_BOLD, 'TYPE'):<18} "
            f"{self._c(self.COLOR_BOLD, 'STATUS'):<16} "
            f"{self._c(self.COLOR_BOLD, 'HEALTH'):<16} "
            f"{self._c(self.COLOR_BOLD, 'REQ'):<8} "
            f"{self._c(self.COLOR_BOLD, 'IDLE'):<10} "
            f"{self._c(self.COLOR_BOLD, 'MEM (PSS)')}"
        )
        lines.append(header)
        lines.append(self._c(self.COLOR_GRAY, "  " + "─" * 74))

        # Workers List
        workers_map = data.get("workers", {})
        if not workers_map:
            lines.append(
                f"  {self._c(self.COLOR_YELLOW, 'No active workers registered.')}"
            )
        else:
            sorted_pids = sorted(workers_map.keys(), key=lambda x: int(x))
            for spid in sorted_pids:
                lines.append(self._render_worker_row(workers_map[spid], spid))

        lines.append(self._c(self.COLOR_GRAY, "─" * 78))
        lines.append(
            self._c(
                self.COLOR_GRAY,
                "  Press Ctrl+C to exit top monitoring.",
            )
        )
        return "\n".join(lines)

    def _run_once(self) -> int:
        resp = self.client.get_status()
        if resp.get("status") != "ok":
            err_msg = resp.get("error", "Unknown error connecting to Arbiter.")
            print(
                f"{self._c(self.COLOR_RED, '[ERROR]')} Failed to retrieve status: {err_msg}",
                file=sys.stderr,
            )
            return 1
        print(self.render_dashboard(resp))
        return 0

    def _run_streaming(self, interval: float) -> int:
        while True:
            resp = self.client.get_status()
            if resp.get("status") != "ok":
                err_msg = resp.get("error", "Unknown error connecting to Arbiter.")
                print(
                    f"{self._c(self.COLOR_RED, '[ERROR]')} Failed to retrieve status: {err_msg}",
                    file=sys.stderr,
                )
                return 1
            sys.stdout.write("\033[2J\033[H")
            sys.stdout.write(self.render_dashboard(resp) + "\n")
            sys.stdout.flush()
            time.sleep(interval)

    def run_loop(self, interval: float = 1.0, once: bool = False) -> int:
        """
        Executes the monitoring loop.
        """
        if interval <= 0:
            interval = 1.0
        try:
            if once:
                return self._run_once()
            return self._run_streaming(interval)
        except KeyboardInterrupt:
            print(f"\n{self._c(self.COLOR_GRAY, '[*] Top monitor stopped.')}")
            return 0


def run_top(
    client: ControlClient,
    interval: float = 1.0,
    once: bool = False,
    no_color: bool = False,
) -> int:
    """Convenience helper to run the Supervisor Top viewer."""
    viewer = SupervisorTopViewer(client, no_color=no_color)
    return viewer.run_loop(interval=interval, once=once)
