"""
MCP (Model Context Protocol) Package for arxiv-security-papers.
Consolidates search, observability, threat defense, and tech radar servers.
"""

from mcp.base import run_mcp_server
from mcp.papers_server import main as run_papers_server
from mcp.observability_server import main as run_observability_server
from mcp.threat_defense_server import main as run_threat_defense_server
from mcp.tech_radar_server import main as run_tech_radar_server

__all__ = [
    "run_mcp_server",
    "run_papers_server",
    "run_observability_server",
    "run_threat_defense_server",
    "run_tech_radar_server",
]
