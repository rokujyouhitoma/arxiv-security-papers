import json
import subprocess
import sys
from typing import Any, Dict

SERVERS = [
    {
        "name": "arxiv-security-papers",
        "script": "src/mcp/papers_server.py",
        "interface_tests": [
            {
                "name": "initialize",
                "req": {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {},
                        "clientInfo": {"name": "test-client", "version": "1.0.0"},
                    },
                },
                "validator": lambda r: (
                    r.get("result", {}).get("protocolVersion") == "2024-11-05"
                    and "serverInfo" in r.get("result", {})
                ),
            },
            {
                "name": "ping",
                "req": {"jsonrpc": "2.0", "id": 2, "method": "ping", "params": {}},
                "validator": lambda r: "result" in r and "error" not in r,
            },
            {
                "name": "tools/list",
                "req": {
                    "jsonrpc": "2.0",
                    "id": 3,
                    "method": "tools/list",
                    "params": {},
                },
                "validator": lambda r: (
                    isinstance(r.get("result", {}).get("tools"), list)
                    and len(r["result"]["tools"]) >= 6
                ),
            },
        ],
        "tool_call_tests": [
            {
                "name": "search_security_papers",
                "args": {"query": "Zero Trust", "top_k": 2},
                "max_chars": 5000,
            },
            {
                "name": "search_papers_hybrid",
                "args": {"query": "Pickle deserialization vulnerability", "top_k": 2},
                "max_chars": 5000,
            },
            {
                "name": "get_paper_summary",
                "args": {"arxiv_id": "2504.03936"},
                "max_chars": 10000,
            },
            {
                "name": "get_latest_trends",
                "args": {"period": "monthly"},
                "max_chars": 10000,
            },
            {
                "name": "query_attack_technique",
                "args": {"technique_id": "T1059"},
                "max_chars": 15000,
            },
            {
                "name": "query_ontology_evidence",
                "args": {"entity_id": "2504.03936"},
                "max_chars": 5000,
            },
        ],
    },
    {
        "name": "arxiv-security-observability",
        "script": "src/mcp/observability_server.py",
        "interface_tests": [
            {
                "name": "initialize",
                "req": {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {},
                        "clientInfo": {"name": "test-client", "version": "1.0.0"},
                    },
                },
                "validator": lambda r: (
                    r.get("result", {}).get("protocolVersion") == "2024-11-05"
                    and "serverInfo" in r.get("result", {})
                ),
            },
            {
                "name": "ping",
                "req": {"jsonrpc": "2.0", "id": 2, "method": "ping", "params": {}},
                "validator": lambda r: "result" in r and "error" not in r,
            },
            {
                "name": "tools/list",
                "req": {
                    "jsonrpc": "2.0",
                    "id": 3,
                    "method": "tools/list",
                    "params": {},
                },
                "validator": lambda r: (
                    isinstance(r.get("result", {}).get("tools"), list)
                    and len(r["result"]["tools"]) >= 4
                ),
            },
        ],
        "tool_call_tests": [
            {
                "name": "profile_code_performance",
                "args": {"code": "x = [i**2 for i in range(1000)]", "top_n": 5},
                "max_chars": 3000,
            },
            {
                "name": "track_memory_allocations",
                "args": {"code": "y = ['a'*1000 for _ in range(100)]", "top_lines": 3},
                "max_chars": 3000,
            },
            {
                "name": "inspect_bytecode",
                "args": {"code": "def add(a, b): return a + b"},
                "max_chars": 3000,
            },
            {
                "name": "get_system_metrics",
                "args": {},
                "max_chars": 3000,
            },
        ],
    },
    {
        "name": "arxiv-security-threat-defense",
        "script": "src/mcp/threat_defense_server.py",
        "interface_tests": [
            {
                "name": "initialize",
                "req": {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {},
                        "clientInfo": {"name": "test-client", "version": "1.0.0"},
                    },
                },
                "validator": lambda r: (
                    r.get("result", {}).get("protocolVersion") == "2024-11-05"
                    and "serverInfo" in r.get("result", {})
                ),
            },
            {
                "name": "ping",
                "req": {"jsonrpc": "2.0", "id": 2, "method": "ping", "params": {}},
                "validator": lambda r: "result" in r and "error" not in r,
            },
            {
                "name": "tools/list",
                "req": {
                    "jsonrpc": "2.0",
                    "id": 3,
                    "method": "tools/list",
                    "params": {},
                },
                "validator": lambda r: (
                    isinstance(r.get("result", {}).get("tools"), list)
                    and len(r["result"]["tools"]) >= 3
                ),
            },
        ],
        "tool_call_tests": [
            {
                "name": "generate_semgrep_rule",
                "args": {"cwe_id": "CWE-502"},
                "max_chars": 3000,
            },
            {
                "name": "synthesize_secure_patch",
                "args": {
                    "cwe_id": "CWE-502",
                    "code": "import pickle\ndata = pickle.loads(raw)",
                },
                "max_chars": 3000,
            },
            {
                "name": "check_threat_coverage",
                "args": {"declared_defenses": ["pickle-free", "ast-guard"]},
                "max_chars": 3000,
            },
            {
                "name": "search_defense_causal_chains",
                "args": {"threat_id": "T1059"},
                "max_chars": 5000,
            },
        ],
    },
    {
        "name": "arxiv-security-tech-radar",
        "script": "src/mcp/tech_radar_server.py",
        "interface_tests": [
            {
                "name": "initialize",
                "req": {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {},
                        "clientInfo": {"name": "test-client", "version": "1.0.0"},
                    },
                },
                "validator": lambda r: (
                    r.get("result", {}).get("protocolVersion") == "2024-11-05"
                    and "serverInfo" in r.get("result", {})
                ),
            },
            {
                "name": "ping",
                "req": {"jsonrpc": "2.0", "id": 2, "method": "ping", "params": {}},
                "validator": lambda r: "result" in r and "error" not in r,
            },
            {
                "name": "tools/list",
                "req": {
                    "jsonrpc": "2.0",
                    "id": 3,
                    "method": "tools/list",
                    "params": {},
                },
                "validator": lambda r: (
                    isinstance(r.get("result", {}).get("tools"), list)
                    and len(r["result"]["tools"]) >= 2
                ),
            },
        ],
        "tool_call_tests": [
            {
                "name": "get_technology_radar",
                "args": {"ring": "adopt"},
                "max_chars": 4000,
            },
            {
                "name": "predict_emerging_threats",
                "args": {"min_severity": "HIGH"},
                "max_chars": 3000,
            },
        ],
    },
]


def send_rpc(proc: subprocess.Popen, req: Dict[str, Any]) -> Dict[str, Any]:
    req_str = json.dumps(req) + "\n"
    proc.stdin.write(req_str)
    proc.stdin.flush()
    line = proc.stdout.readline()
    if not line:
        return {}
    return json.loads(line)


def run_all_checks() -> bool:
    all_passed = True
    total_checks = 0
    passed_checks = 0

    print(
        "================================================================================"
    )
    print(" 🚀 MCP Protocol Compliance & Response Size Verification Suite")
    print(
        "================================================================================\n"
    )

    for s_info in SERVERS:
        s_name = s_info["name"]
        script = s_info["script"]
        print(f"📦 Server: {s_name} ({script})")

        proc = subprocess.Popen(
            [sys.executable, script],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={
                "PYTHONPATH": "src",
                "PATH": sys.path[0] + ":" + subprocess.os.environ.get("PATH", ""),
            },
        )

        # 1. Interface Protocol Tests
        print("  🔹 MCP Standard Interface Validation:")
        for t in s_info["interface_tests"]:
            total_checks += 1
            t_name = t["name"]
            req = t["req"]
            resp = send_rpc(proc, req)
            valid = t["validator"](resp)
            if valid:
                passed_checks += 1
                print(f"     ✅ [PASS] {t_name:<16} -> Protocol Compliant")
            else:
                all_passed = False
                print(
                    f"     ❌ [FAIL] {t_name:<16} -> Response invalid: {json.dumps(resp)[:150]}"
                )

        # 2. Tool Execution & Character Length Tests
        print("  🔹 Tool Call Execution & Response Size Validation:")
        req_id = 100
        for tool_t in s_info["tool_call_tests"]:
            total_checks += 1
            tool_name = tool_t["name"]
            args = tool_t["args"]
            max_chars = tool_t["max_chars"]
            req_id += 1

            call_req = {
                "jsonrpc": "2.0",
                "id": req_id,
                "method": "tools/call",
                "params": {"name": tool_name, "arguments": args},
            }
            resp = send_rpc(proc, call_req)

            # Measure content text length
            content_len = 0
            if "result" in resp and "content" in resp["result"]:
                for c in resp["result"]["content"]:
                    if c.get("type") == "text":
                        content_len += len(c.get("text", ""))

            has_error = "error" in resp or (
                isinstance(resp.get("result"), dict)
                and resp["result"].get("isError") is True
            )
            within_limit = content_len <= max_chars and not has_error

            if within_limit:
                passed_checks += 1
                print(
                    f"     ✅ [PASS] {tool_name:<28} -> Size: {content_len:>5,} chars "
                    f"(Limit: {max_chars:,} chars)"
                )
            else:
                all_passed = False
                err_msg = "OVER_LIMIT" if content_len > max_chars else "ERROR_RESPONSE"
                print(
                    f"     ❌ [{err_msg}] {tool_name:<28} -> Size: {content_len:>5,} chars "
                    f"(Limit: {max_chars:,} chars)"
                )

        proc.stdin.close()
        proc.terminate()
        proc.wait(timeout=2)
        print()

    print(
        "================================================================================"
    )
    print(
        f" 📊 Final Result: {passed_checks}/{total_checks} Checks Passed (100% PASS: {all_passed})"
    )
    print(
        "================================================================================\n"
    )
    return all_passed


if __name__ == "__main__":
    success = run_all_checks()
    sys.exit(0 if success else 1)
