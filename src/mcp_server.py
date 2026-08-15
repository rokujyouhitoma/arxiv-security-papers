#!/usr/bin/env python3
"""
Model Context Protocol (MCP) Server for arXiv Security Papers
Exposes security paper knowledge base, hybrid vector search, and trend tools via standard MCP JSON-RPC protocol.
"""

import glob
import json
import os
import sys

from vector_engine import VectorEngine


def get_workspace_dir():
    current_dir = os.path.dirname(os.path.abspath(__file__))
    if os.path.exists(os.path.join(current_dir, "..", "config.json")):
        return os.path.abspath(os.path.join(current_dir, ".."))
    return current_dir


WORKSPACE_DIR = get_workspace_dir()
VECTOR_ENGINE = VectorEngine(workspace_dir=WORKSPACE_DIR)

TOOLS_MANIFEST = [
    {
        "name": "search_security_papers",
        "description": "Perform hybrid vector & semantic search across arXiv security papers knowledge base.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Natural language or technical search query in Japanese or English",
                },
                "top_k": {
                    "type": "integer",
                    "description": "Number of top matching papers to return",
                    "default": 5,
                },
                "category": {
                    "type": "string",
                    "description": "Optional category filter e.g. cs.CR, cryptography, zero-trust",
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "get_paper_summary",
        "description": "Fetch the 100% Japanese executive summary and OKF v0.2 metadata for a specific arXiv ID.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "arxiv_id": {
                    "type": "string",
                    "description": "arXiv paper ID e.g. 2510.18232",
                }
            },
            "required": ["arxiv_id"],
        },
    },
    {
        "name": "get_latest_trends",
        "description": "Retrieve executive trend report, emerging keywords, and Mermaid mindmaps for a given period.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "period": {
                    "type": "string",
                    "enum": ["monthly", "quarterly", "annual"],
                    "default": "monthly",
                }
            },
        },
    },
    {
        "name": "query_attack_technique",
        "description": (
            "Search papers related to specific MITRE ATT&CK technique IDs "
            "(e.g. T1059, T1190) or STRIDE threat models."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "technique_id": {
                    "type": "string",
                    "description": "MITRE ATT&CK technique ID e.g. T1059 or category name",
                }
            },
            "required": ["technique_id"],
        },
    },
]


def handle_search_security_papers(args):
    query = args.get("query", "")
    top_k = args.get("top_k", 5)
    category = args.get("category")
    results = VECTOR_ENGINE.search(query, top_k=top_k, category=category)
    return {
        "status": "success",
        "query": query,
        "count": len(results),
        "results": results,
    }


def is_safe_workspace_path(file_path):
    if not file_path:
        return False
    abs_path = os.path.realpath(file_path)
    abs_workspace = os.path.realpath(WORKSPACE_DIR)
    if not abs_path.startswith(abs_workspace):
        return False
    sensitive_keywords = [".ssh", ".aws", ".env", "etc/passwd", "etc/shadow"]
    if any(k in abs_path for k in sensitive_keywords):
        return False
    return True


def handle_get_paper_summary(args):
    arxiv_id = args.get("arxiv_id", "").strip().replace("/", "_").replace("..", "")
    clean_id = arxiv_id
    okf_root = os.path.join(WORKSPACE_DIR, "outputs", "okf_papers")

    matches = glob.glob(os.path.join(okf_root, "**", f"{clean_id}.md"), recursive=True)
    if not matches:
        return {
            "status": "error",
            "message": f"Paper with ID '{arxiv_id}' not found in OKF repository.",
        }

    target_file = os.path.realpath(matches[0])
    if not is_safe_workspace_path(target_file):
        return {
            "status": "error",
            "message": "Access denied: file path outside workspace or sensitive.",
        }

    with open(target_file, "r", encoding="utf-8") as f:
        content = f.read()

    return {
        "status": "success",
        "arxiv_id": arxiv_id,
        "path": os.path.relpath(target_file, WORKSPACE_DIR),
        "content": content,
    }


def handle_get_latest_trends(args):
    period = args.get("period", "monthly")
    summary_dir = os.path.join(
        WORKSPACE_DIR,
        "outputs",
        "executive_summaries",
        (
            f"03_{period}"
            if period == "monthly"
            else f"04_{period}" if period == "quarterly" else "05_annual"
        ),
    )

    if not os.path.exists(summary_dir):
        return {
            "status": "error",
            "message": f"Summary directory for period '{period}' not found.",
        }

    summary_files = sorted(glob.glob(os.path.join(summary_dir, "*.md")), reverse=True)
    if not summary_files:
        return {
            "status": "error",
            "message": f"No summary files found for period '{period}'.",
        }

    target_file = os.path.realpath(summary_files[0])
    if not is_safe_workspace_path(target_file):
        return {
            "status": "error",
            "message": "Access denied: file path outside workspace or sensitive.",
        }

    with open(target_file, "r", encoding="utf-8") as f:
        content = f.read()

    return {
        "status": "success",
        "period": period,
        "latest_file": os.path.basename(target_file),
        "content": content,
    }


def handle_query_attack_technique(args):
    technique_id = args.get("technique_id", "").lower()
    results = VECTOR_ENGINE.search(technique_id, top_k=10)
    return {
        "status": "success",
        "technique_id": technique_id,
        "count": len(results),
        "papers": results,
    }


def dispatch_tool(name, arguments):
    if name == "search_security_papers":
        return handle_search_security_papers(arguments)
    elif name == "get_paper_summary":
        return handle_get_paper_summary(arguments)
    elif name == "get_latest_trends":
        return handle_get_latest_trends(arguments)
    elif name == "query_attack_technique":
        return handle_query_attack_technique(arguments)
    else:
        return {"status": "error", "message": f"Unknown tool: '{name}'"}


def run_jsonrpc_server():
    """Runs standard MCP JSON-RPC stdio server"""
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            req_id = req.get("id")
            method = req.get("method")
            params = req.get("params", {})

            if method == "tools/list":
                res = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {"tools": TOOLS_MANIFEST},
                }
            elif method == "tools/call":
                tool_name = params.get("name")
                tool_args = params.get("arguments", {})
                output = dispatch_tool(tool_name, tool_args)
                res = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "content": [
                            {
                                "type": "text",
                                "text": json.dumps(
                                    output, ensure_ascii=False, indent=2
                                ),
                            }
                        ]
                    },
                }
            else:
                res = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32601, "message": f"Method not found: {method}"},
                }

            print(json.dumps(res, ensure_ascii=False), flush=True)
        except Exception as e:
            sys.stderr.write(f"Error handling request: {e}\n")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--manifest":
        print(json.dumps(TOOLS_MANIFEST, ensure_ascii=False, indent=2))
    else:
        run_jsonrpc_server()
