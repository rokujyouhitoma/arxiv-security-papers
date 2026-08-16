#!/usr/bin/env python3
"""
Base JSON-RPC Transport and Server Loop for Model Context Protocol (MCP).
Standardizes stdio communication, tool dispatching, prompts, and resources.
"""

import json
import sys
from typing import Any, Callable, Dict, List, Optional


def run_mcp_server(
    tools_manifest: Optional[List[Dict[str, Any]]] = None,
    tool_handlers: Optional[Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]]] = None,
    prompts_manifest: Optional[List[Dict[str, Any]]] = None,
    prompt_handlers: Optional[Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]]] = None,
    resources_manifest: Optional[List[Dict[str, Any]]] = None,
    resource_handlers: Optional[Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]]] = None,
) -> None:
    """
    Standard event loop processing JSON-RPC messages from stdin and replying via stdout.
    """
    tools = tools_manifest or []
    t_handlers = tool_handlers or {}
    prompts = prompts_manifest or []
    p_handlers = prompt_handlers or {}
    resources = resources_manifest or []
    r_handlers = resource_handlers or {}

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            method = req.get("method")
            req_id = req.get("id")

            # 1. Tool capabilities
            if method == "tools/list":
                resp: Dict[str, Any] = {"jsonrpc": "2.0", "id": req_id, "result": {"tools": tools}}
            elif method == "tools/call":
                p = req.get("params", {})
                tool_name = p.get("name")
                args = p.get("arguments", {})

                if tool_name in t_handlers:
                    res = t_handlers[tool_name](args)
                else:
                    res = {"error": f"Unknown tool '{tool_name}'"}

                resp = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "content": [
                            {
                                "type": "text",
                                "text": json.dumps(res, ensure_ascii=False, indent=2),
                            }
                        ]
                    },
                }

            # 2. Prompt capabilities
            elif method == "prompts/list":
                resp = {"jsonrpc": "2.0", "id": req_id, "result": {"prompts": prompts}}
            elif method == "prompts/get":
                p = req.get("params", {})
                prompt_name = p.get("name")
                args = p.get("arguments", {})
                if prompt_name in p_handlers:
                    res = p_handlers[prompt_name](args)
                else:
                    res = {"error": f"Unknown prompt '{prompt_name}'"}
                resp = {"jsonrpc": "2.0", "id": req_id, "result": res}

            # 3. Resource capabilities
            elif method == "resources/list":
                resp = {"jsonrpc": "2.0", "id": req_id, "result": {"resources": resources}}
            elif method == "resources/read":
                p = req.get("params", {})
                uri = p.get("uri")
                if uri in r_handlers:
                    res = r_handlers[uri](p)
                else:
                    res = {"error": f"Unknown resource URI '{uri}'"}
                resp = {"jsonrpc": "2.0", "id": req_id, "result": res}

            # 4. Unknown / Notifications
            else:
                resp = {"jsonrpc": "2.0", "id": req_id, "result": {}}

            sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
            sys.stdout.flush()
        except Exception as e:
            sys.stderr.write(f"Error handling MCP request: {e}\n")
