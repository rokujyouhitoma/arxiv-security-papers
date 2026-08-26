"""
MCP (Model Context Protocol) Package for arxiv-security-papers.
Consolidates search, observability, threat defense, and tech radar servers.
"""

from mcp.analytics import (
    compute_mcp_metrics,
    export_mcp_report_file,
    load_mcp_logs,
    render_mcp_markdown_report,
)
from mcp.base import log_mcp_performance, run_mcp_server
from mcp.observability_server import main as run_observability_server
from mcp.papers_server import main as run_papers_server
from mcp.tech_radar_server import main as run_tech_radar_server
from mcp.threat_defense_server import main as run_threat_defense_server

__all__ = [
    "log_mcp_performance",
    "run_mcp_server",
    "run_papers_server",
    "run_observability_server",
    "run_threat_defense_server",
    "run_tech_radar_server",
    "compute_mcp_metrics",
    "load_mcp_logs",
    "render_mcp_markdown_report",
    "export_mcp_report_file",
]
