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
    def get_process_rss_mb(pid: int) -> float:
        """
        Reads Resident Set Size (RSS) memory in Megabytes for a given PID from /proc.
        Returns 0.0 if inaccessible or not on Linux.
        """
        try:
            status_file = f"/proc/{pid}/status"
            if not os.path.exists(status_file):
                return 0.0
            with open(status_file, "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        parts = line.split()
                        if len(parts) >= 2:
                            kb = float(parts[1])
                            return round(kb / 1024.0, 1)
        except Exception:
            return 0.0
        return 0.0

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

    def render_dashboard(self, data: Dict[str, Any]) -> str:
        """Constructs the full formatted string for the top dashboard."""
        lines: List[str] = []
        now_str = time.strftime("%Y-%m-%d %H:%M:%S")

        # Header
        title = self._c(
            self.COLOR_BOLD + self.COLOR_CYAN,
            "⚡ [Supervisor Process Top Monitor]",
        )
        lines.append(f"{title}  {self._c(self.COLOR_GRAY, now_str)}")
        lines.append(self._c(self.COLOR_GRAY, "─" * 78))

        # Arbiter Overview Panel
        arbiter_pid = data.get("arbiter_pid", "-")
        uptime_sec = data.get("uptime", 0.0)
        uptime_str = self.format_uptime(uptime_sec)
        bind_addr = data.get("bind", "-")
        worker_cls = data.get("worker_class", "-")
        target_w = data.get("target_workers", 0)
        active_web = data.get("active_web_workers", 0)
        active_db = data.get("active_db_workers", 0)

        arbiter_rss = 0.0
        if isinstance(arbiter_pid, int):
            arbiter_rss = self.get_process_rss_mb(arbiter_pid)

        lines.append(
            f"  {self._c(self.COLOR_BOLD, 'Arbiter PID:')} {self._c(self.COLOR_YELLOW, str(arbiter_pid)):<8} "
            f"  {self._c(self.COLOR_BOLD, 'Uptime:')} {uptime_str:<14} "
            f"  {self._c(self.COLOR_BOLD, 'Memory:')} {arbiter_rss:.1f} MB"
        )
        lines.append(
            f"  {self._c(self.COLOR_BOLD, 'Binding:')}     {bind_addr:<18} "
            f"  {self._c(self.COLOR_BOLD, 'Class:')}  {worker_cls:<10} "
            f"  {self._c(self.COLOR_BOLD, 'Workers:')} Web: {active_web}/{target_w}, DB: {active_db}"
        )
        lines.append(self._c(self.COLOR_GRAY, "─" * 78))

        # Workers Table Header
        header = (
            f"  {self._c(self.COLOR_BOLD, 'PID'):<14} "
            f"{self._c(self.COLOR_BOLD, 'TYPE'):<18} "
            f"{self._c(self.COLOR_BOLD, 'STATUS'):<16} "
            f"{self._c(self.COLOR_BOLD, 'HEALTH'):<16} "
            f"{self._c(self.COLOR_BOLD, 'REQ'):<8} "
            f"{self._c(self.COLOR_BOLD, 'IDLE'):<10} "
            f"{self._c(self.COLOR_BOLD, 'RSS MEM')}"
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
                w_info = workers_map[spid]
                pid = w_info.get("pid", spid)
                w_type = w_info.get("type", "worker")
                status = w_info.get("status", "UNKNOWN")
                healthy = w_info.get("is_healthy", False)
                req_count = w_info.get("requests_handled", 0)
                idle_sec = w_info.get("idle_seconds", 0.0)

                # Fetch RSS memory
                rss_mb = self.get_process_rss_mb(int(pid))

                # Color formatting
                status_color = self.COLOR_GREEN if status == "ALIVE" else self.COLOR_RED
                health_color = self.COLOR_GREEN if healthy else self.COLOR_YELLOW
                health_str = "HEALTHY" if healthy else "UNHEALTHY"

                status_fmt = self._c(status_color, status)
                health_fmt = self._c(health_color, health_str)
                type_fmt = self._c(
                    self.COLOR_MAGENTA if w_type == "database" else self.COLOR_CYAN,
                    w_type,
                )

                idle_str = f"{idle_sec:.1f}s"
                rss_str = f"{rss_mb:.1f} MB"

                row = (
                    f"  {str(pid):<6} "
                    f"{type_fmt:<18} "
                    f"{status_fmt:<16} "
                    f"{health_fmt:<16} "
                    f"{req_count:<8} "
                    f"{idle_str:<10} "
                    f"{rss_str}"
                )
                lines.append(row)

        lines.append(self._c(self.COLOR_GRAY, "─" * 78))
        lines.append(
            self._c(
                self.COLOR_GRAY,
                "  Press Ctrl+C to exit top monitoring.",
            )
        )
        return "\n".join(lines)

    def run_loop(self, interval: float = 1.0, once: bool = False) -> int:
        """
        Executes the monitoring loop.
        """
        if interval <= 0:
            interval = 1.0

        try:
            while True:
                resp = self.client.get_status()
                if resp.get("status") != "ok":
                    err_msg = resp.get("error", "Unknown error connecting to Arbiter.")
                    print(
                        f"{self._c(self.COLOR_RED, '[ERROR]')} Failed to retrieve status: {err_msg}",
                        file=sys.stderr,
                    )
                    return 1

                dashboard = self.render_dashboard(resp)

                if once:
                    print(dashboard)
                    return 0

                # Clear screen & reset cursor
                sys.stdout.write("\033[2J\033[H")
                sys.stdout.write(dashboard + "\n")
                sys.stdout.flush()

                time.sleep(interval)
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
