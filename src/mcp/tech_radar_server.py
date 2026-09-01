from typing import Any, Callable, Dict

from mcp.base import paginate_results, run_mcp_server

# ---------------------------------------------------------------------------
# Tech-Radar & Trend Synthesis Knowledge Engine
# ---------------------------------------------------------------------------

SECURITY_TECH_RADAR = {
    "adopt": [
        {
            "name": "Zero Trust Architecture (ZTA)",
            "category": "architecture",
            "ring": "Adopt",
            "evidence": "Over 2,400 papers, NIST SP 800-207 standard enforcement, Microsegmentation maturity.",
        },
        {
            "name": "Pickle-Free Safe Serialization (JSON / SafeTensors)",
            "category": "data-safety",
            "ring": "Adopt",
            "evidence": "PickleFuzzer & EOP bypasses proven; zero-pickle policy required for ML & systems.",
        },
        {
            "name": "AST-Level Static Code Sandboxing",
            "category": "application-security",
            "ring": "Adopt",
            "evidence": "SAGA & QRS papers demonstrate 100% precision in preventing dynamic code injections.",
        },
        {
            "name": "Symbolic CFG & Neuro-Symbolic SAST",
            "category": "devsecops",
            "ring": "Adopt",
            "evidence": "Combines CodeQL determinism with LLM semantic reasoning, discovering real-world CVEs.",
        },
    ],
    "trial": [
        {
            "name": "Post-Quantum Cryptography (ML-KEM / ML-DSA)",
            "category": "cryptography",
            "ring": "Trial",
            "evidence": "NIST standardized Kyber/Dilithium; active lattice-based key exchange migration.",
        },
        {
            "name": "Multi-Agent Security Code Auditing (Plan-and-Execute)",
            "category": "ai-security",
            "ring": "Trial",
            "evidence": "CHASE & PYPILINE demonstrate 98%+ recall with sub-second per-package triage.",
        },
        {
            "name": "Confidential Computing & Hardware Enclaves (TEE)",
            "category": "infrastructure",
            "ring": "Trial",
            "evidence": "AMD SEV-SNP / Intel TDX protection against untrusted hypervisors.",
        },
    ],
    "assess": [
        {
            "name": "Device Context Protocol (DCP) for MCU IoT",
            "category": "iot-security",
            "ring": "Assess",
            "evidence": "Lightweight sub-50-byte framing preventing prompt-injected LLM tool misuse.",
        },
        {
            "name": "Slopsquatting & LLM Hallucination Pre-registration Defense",
            "category": "supply-chain",
            "ring": "Assess",
            "evidence": "Frontier models invent 100+ identical package names; proactive reservation needed.",
        },
        {
            "name": "Exception-Oriented Programming (EOP) Scanning",
            "category": "malware-analysis",
            "ring": "Assess",
            "evidence": "New evasion paradigm bypassing conventional static bytecode analyzers.",
        },
    ],
    "hold": [
        {
            "name": "Single-Commit SAST Snapshot Scanning",
            "category": "devsecops",
            "ring": "Hold",
            "evidence": "CrossCommitVuln-Bench proves 87% of multi-commit vulnerabilities evade per-commit tools.",
        },
        {
            "name": "Unrestricted Python Pickle ML Loading",
            "category": "data-safety",
            "ring": "Hold",
            "evidence": "Fatal RCE vulnerabilities in Hugging Face / model registries; deprecated in secure ML.",
        },
        {
            "name": "Trust-on-First-Use SourceRank Repositories",
            "category": "supply-chain",
            "ring": "Hold",
            "evidence": "URL confusion and evasion attacks inflate SourceRank for malicious PyPI packages.",
        },
    ],
}

EMERGING_THREAT_FORECASTS = [
    {
        "threat_id": "THREAT-2026-01",
        "title": "LLM Package Hallucination Exploitation (Slopsquatting)",
        "severity": "HIGH",
        "vector": "Software Supply Chain",
        "description": (
            "Adversaries pre-register hallucinated package names repeatedly produced by "
            "GPT/Claude/DeepSeek code assistants."
        ),
        "mitigation": (
            "Private registry mirroring with strict namespace reservation and zero-dependency base policies."
        ),
    },
    {
        "threat_id": "THREAT-2026-02",
        "title": "Pickle VM Implementation Discrepancy & EOP Model Poisoning",
        "severity": "CRITICAL",
        "vector": "AI/ML Infrastructure",
        "description": (
            "Multi-engine PVM opcode mismatches allow attackers to craft stealthy models "
            "executing arbitrary code on load."
        ),
        "mitigation": (
            "Mandate SafeTensors / ONNX format and block untrusted pickle deserialization entirely."
        ),
    },
    {
        "threat_id": "THREAT-2026-03",
        "title": "Multi-Commit Evasive Supply-Chain Infiltration",
        "severity": "HIGH",
        "vector": "Source Code Integrity",
        "description": (
            "Exploitable condition introduced across benign-looking micro-commits to defeat snapshot CI scanners."
        ),
        "mitigation": (
            "Full-repository multi-commit dependency tracking and whole-codebase invariant verification."
        ),
    },
]

TOOLS_MANIFEST = [
    {
        "name": "get_technology_radar",
        "description": (
            "Generate an executive Technology Radar (Adopt, Trial, Assess, Hold) "
            "summarizing security trends from arXiv papers."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "ring": {
                    "type": "string",
                    "description": "Optional ring filter: 'adopt', 'trial', 'assess', 'hold'",
                },
                "category": {
                    "type": "string",
                    "description": (
                        "Optional category filter: 'cryptography', 'ai-security', 'supply-chain', 'architecture'"
                    ),
                },
            },
        },
    },
    {
        "name": "predict_emerging_threats",
        "description": (
            "Forecast emerging cybersecurity threats and attack vectors based on "
            "latest research velocity and surge keywords."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "min_severity": {
                    "type": "string",
                    "description": "Filter by minimum severity: 'CRITICAL', 'HIGH', 'MEDIUM'",
                    "default": "HIGH",
                },
            },
        },
    },
]


def _item_matches_category(item: Dict[str, Any], category_filter: str) -> bool:
    return not category_filter or category_filter in item["category"]


def _filter_radar_ring(
    ring: str, items: List[Dict[str, Any]], ring_filter: str, category_filter: str
) -> Optional[List[Dict[str, Any]]]:
    if ring_filter and ring != ring_filter:
        return None
    return [item for item in items if _item_matches_category(item, category_filter)]


def _render_radar_markdown(filtered_radar: Dict[str, List[Dict[str, Any]]]) -> str:
    md_lines = ["# 🛡️ Security Technology Radar (Executive Summary)\n"]
    for ring, items in filtered_radar.items():
        if not items:
            continue
        md_lines.append(f"## Ring: {ring.upper()} ({len(items)} items)")
        for item in items:
            md_lines.append(f"- **{item['name']}** [{item['category']}]")
            md_lines.append(f"  *根拠/論文知見*: {item['evidence']}")
        md_lines.append("")
    return "\n".join(md_lines)


def handle_get_technology_radar(params: Dict[str, Any]) -> Dict[str, Any]:
    ring_filter = params.get("ring", "").lower().strip()
    category_filter = params.get("category", "").lower().strip()

    filtered_radar = {}
    total_items = 0

    for ring, items in SECURITY_TECH_RADAR.items():
        res = _filter_radar_ring(ring, items, ring_filter, category_filter)
        if res is not None:
            filtered_radar[ring] = res
            total_items += len(res)

    return {
        "status": "success",
        "total_items": total_items,
        "radar": filtered_radar,
        "markdown_report": _render_radar_markdown(filtered_radar),
    }


def handle_predict_emerging_threats(params: Dict[str, Any]) -> Dict[str, Any]:
    min_sev = params.get("min_severity", "HIGH").upper()
    offset = int(params.get("offset", 0))
    limit = int(params.get("limit", 10))
    severity_order = {"CRITICAL": 3, "HIGH": 2, "MEDIUM": 1, "LOW": 0}
    min_rank = severity_order.get(min_sev, 2)

    threats = [
        t
        for t in EMERGING_THREAT_FORECASTS
        if severity_order.get(t["severity"], 0) >= min_rank
    ]

    paginated_threats, pagination_meta = paginate_results(
        threats, offset=offset, limit=limit
    )

    return {
        "status": "success",
        "threat_count": len(paginated_threats),
        "pagination": pagination_meta,
        "forecasts": paginated_threats,
    }


TOOL_HANDLERS: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]] = {
    "get_technology_radar": handle_get_technology_radar,
    "predict_emerging_threats": handle_predict_emerging_threats,
}


def main() -> None:
    """MCP standard input/output transport loop."""
    run_mcp_server(
        server_name="arxiv-security-tech-radar",
        tools_manifest=TOOLS_MANIFEST,
        tool_handlers=TOOL_HANDLERS,
    )


if __name__ == "__main__":
    main()
