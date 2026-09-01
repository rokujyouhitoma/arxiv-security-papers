#!/usr/bin/env python3
"""
Model Context Protocol (MCP) Server for arXiv Security Papers
Exposes security paper knowledge base, hybrid vector search, and trend tools via standard MCP JSON-RPC protocol.
"""

import glob
import json
import os
import sys
import time
from typing import Any, Callable, Dict, List, Optional

from mcp.base import log_mcp_performance, paginate_results
from search.vector_engine import VectorEngine
from security.validation import is_safe_workspace_path


def get_workspace_dir() -> str:
    cur = os.path.abspath(os.path.dirname(__file__))
    while cur != os.path.dirname(cur):
        if (
            os.path.exists(os.path.join(cur, "pyproject.toml"))
            or os.path.exists(os.path.join(cur, "Makefile"))
            or os.path.exists(os.path.join(cur, ".agents"))
        ):
            return cur
        cur = os.path.dirname(cur)
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


WORKSPACE_DIR = get_workspace_dir()
_VECTOR_ENGINE = None


def get_vector_engine() -> VectorEngine:
    global _VECTOR_ENGINE
    if _VECTOR_ENGINE is None:
        _VECTOR_ENGINE = VectorEngine(workspace_dir=WORKSPACE_DIR)
    return _VECTOR_ENGINE


def set_vector_engine(engine: Optional[VectorEngine] = None) -> None:
    global _VECTOR_ENGINE
    _VECTOR_ENGINE = engine


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
        "name": "search_papers_hybrid",
        "description": (
            "Execute full 4-stage RAG hybrid pipeline search combining Inverted/BM25/Dense vectors, "
            "GraphRAG entity context, PageRank authority boost, and RAPTOR summary clusters."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search query or security problem description",
                },
                "top_k": {
                    "type": "integer",
                    "description": "Number of matching papers to return",
                    "default": 10,
                },
                "category": {
                    "type": "string",
                    "description": "Optional category filter e.g. cs.CR",
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "query_knowledge_graph",
        "description": "Explore security entities (CVE, techniques, tools) and their graph relationships (GraphRAG).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "entity": {
                    "type": "string",
                    "description": "Entity name or keyword e.g. マルウェア・脅威解析, CVE-2026-1001",
                },
                "max_depth": {
                    "type": "integer",
                    "description": "Max hop depth for graph traversal",
                    "default": 2,
                },
            },
            "required": ["entity"],
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
    {
        "name": "get_related_papers_graph",
        "description": (
            "Retrieve topological k-NN proximity graph and Mermaid visualization "
            "for a given paper to explore connected research."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "arxiv_id": {
                    "type": "string",
                    "description": "arXiv paper ID e.g. 2608.02671",
                }
            },
            "required": ["arxiv_id"],
        },
    },
    {
        "name": "verify_code_security",
        "description": (
            "Analyze a code snippet or git diff against recent academic security papers "
            "to identify potential attack vectors, cryptographic weaknesses, and suggest mitigations."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "code_snippet": {
                    "type": "string",
                    "description": "Source code snippet, function, or git diff to verify",
                },
                "language": {
                    "type": "string",
                    "description": "Programming language e.g. python, javascript, rust, go, c",
                    "default": "python",
                },
            },
            "required": ["code_snippet"],
        },
    },
    {
        "name": "get_cwe_mitigation_recipe",
        "description": (
            "Retrieve academic paper-backed secure coding patterns, defense algorithms, "
            "and reference papers for a given Common Weakness Enumeration (CWE) ID."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "cwe_id": {
                    "type": "string",
                    "description": "CWE identifier e.g. CWE-89, CWE-78, CWE-22, CWE-79, CWE-327",
                },
            },
            "required": ["cwe_id"],
        },
    },
]

RESOURCES_MANIFEST = [
    {
        "uri": "arxiv://paper/{arxiv_id}",
        "name": "arXiv Security Paper OKF Document",
        "description": "Fetch the full Google OKF v0.2 Markdown document for an arXiv paper ID.",
        "mimeType": "text/markdown",
    },
    {
        "uri": "arxiv://trends/latest",
        "name": "Latest Security Trends Executive Summary",
        "description": "Fetch the latest monthly security trend summary and emerging technology analysis.",
        "mimeType": "text/markdown",
    },
    {
        "uri": "arxiv://cwe-taxonomy",
        "name": "CWE & MITRE ATT&CK Mapping Taxonomy",
        "description": "Fetch the dictionary mapping top CWEs to ATT&CK techniques and mitigation patterns.",
        "mimeType": "application/json",
    },
]

PROMPTS_MANIFEST = [
    {
        "name": "audit_code_with_papers",
        "description": "Audit a given source code or PR diff against recent academic security attack papers.",
        "arguments": [
            {
                "name": "code",
                "description": "The source code or diff to audit",
                "required": True,
            },
            {
                "name": "language",
                "description": "Programming language (default: python)",
                "required": False,
            },
        ],
    },
    {
        "name": "generate_exploit_poc_tests",
        "description": (
            "Generate automated security regression / PoC verification tests (e.g. pytest) "
            "based on attack techniques from a specific arXiv paper."
        ),
        "arguments": [
            {
                "name": "arxiv_id",
                "description": "arXiv paper ID e.g. 2502.16730",
                "required": True,
            },
            {
                "name": "target_framework",
                "description": "Test framework (e.g. pytest, unittest, jest)",
                "required": False,
            },
        ],
    },
    {
        "name": "recommend_cwe_mitigation",
        "description": "Generate academically proven secure coding patterns to remediate a specific CWE.",
        "arguments": [
            {
                "name": "cwe_id",
                "description": "CWE identifier e.g. CWE-89, CWE-78, CWE-22",
                "required": True,
            },
            {
                "name": "language",
                "description": "Target programming language",
                "required": False,
            },
        ],
    },
]


def handle_search_security_papers(args: Dict[str, Any]) -> Dict[str, Any]:
    query = args.get("query", "")
    top_k = args.get("top_k", 5)
    offset = int(args.get("offset", 0))
    limit = int(args.get("limit", top_k))
    category = args.get("category")
    compact = args.get("compact", True)
    results = get_vector_engine().search(
        query, top_k=max(top_k, offset + limit), category=category
    )

    if compact:
        compact_results = []
        for r in results:
            compact_results.append(
                {
                    "id": r.get("id"),
                    "title": r.get("title"),
                    "title_ja": r.get("title_ja", r.get("title")),
                    "category": r.get("category"),
                    "tags": r.get("tags", [])[:5],
                    "score": round(r.get("score", 0.0), 4),
                    "summary": r.get("description", r.get("abstract", ""))[:180]
                    + "...",
                }
            )
        results = compact_results

    paginated_results, pagination_meta = paginate_results(
        results, offset=offset, limit=limit
    )

    return {
        "status": "success",
        "query": query,
        "count": len(paginated_results),
        "compact": compact,
        "pagination": pagination_meta,
        "results": paginated_results,
    }


def _compact_doc_item(d: Dict[str, Any]) -> Dict[str, Any]:
    raw_desc = d.get("description") or d.get("abstract") or ""
    summary = raw_desc[:200] + ("..." if len(raw_desc) > 200 else "")
    return {
        "id": d.get("id"),
        "title": d.get("title"),
        "title_ja": d.get("title_ja", d.get("title")),
        "category": d.get("category", ""),
        "score": round(float(d.get("score", 0.0)), 4),
        "summary": summary,
    }


def handle_search_papers_hybrid(args: Dict[str, Any]) -> Dict[str, Any]:
    query = args.get("query", "")
    top_k = args.get("top_k", 10)
    offset = int(args.get("offset", 0))
    limit = int(args.get("limit", top_k))
    category = args.get("category")
    facets = {"category": category} if category else None
    resp = get_vector_engine().search_hybrid_pipeline(
        query, facets=facets, top_k=max(top_k, offset + limit)
    )

    raw_results = resp.get("results", []) if isinstance(resp, dict) else []
    compact_docs = [_compact_doc_item(d) for d in raw_results]
    paginated_docs, pagination_meta = paginate_results(
        compact_docs, offset=offset, limit=limit
    )

    return {
        "status": "success",
        "query": query,
        "count": len(paginated_docs),
        "pagination": pagination_meta,
        "results": paginated_docs,
        "data": {"results": paginated_docs},
    }


def handle_query_knowledge_graph(args: Dict[str, Any]) -> Dict[str, Any]:
    entity = args.get("entity", "")
    max_depth = args.get("max_depth", 2)
    graph_res = get_vector_engine().knowledge_graph.get_neighbors(
        entity, max_depth=max_depth
    )
    return {
        "status": "success",
        "graph": graph_res,
    }


def handle_get_paper_summary(args: Dict[str, Any]) -> Dict[str, Any]:
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


def _find_table_cut_index(content: str) -> int:
    split_markers = [
        "## 4. 論文一覧",
        "## 論文一覧",
        "### 4. 論文一覧",
        "### 全論文一覧",
        "| arxiv_id |",
    ]
    indices = [content.find(m) for m in split_markers if content.find(m) > 0]
    return min(indices) if indices else -1


def _truncate_trends_content(content: str, max_chars: int) -> tuple[str, bool]:
    """Helper to truncate massive markdown tables from trend summaries."""
    cut_idx = _find_table_cut_index(content)
    if cut_idx > 0:
        msg = (
            f"\n\n> [!NOTE]\n> （個別論文表は文字数抑制のため省略されました。"
            f"全文が必要な場合は full_content=True を指定してください。総文字数: {len(content):,}文字）\n"
        )
        return content[:cut_idx].strip() + msg, True

    if len(content) > max_chars:
        msg = (
            f"\n\n> [!NOTE]\n> （{max_chars}文字で切り詰められました。"
            f"全文が必要な場合は full_content=True を指定してください。）\n"
        )
        return content[:max_chars].strip() + msg, True

    return content, False


def _get_trend_summary_files(period: str) -> tuple[Optional[str], List[str]]:
    period_prefix_map = {
        "monthly": "03_monthly",
        "quarterly": "04_quarterly",
        "annual": "05_annual",
    }
    prefix = period_prefix_map.get(period, "03_monthly")
    summary_dir = os.path.join(WORKSPACE_DIR, "outputs", "executive_summaries", prefix)
    if not os.path.exists(summary_dir):
        return f"Summary directory for period '{period}' not found.", []
    files = sorted(glob.glob(os.path.join(summary_dir, "*.md")), reverse=True)
    if not files:
        return f"No trend summary found for period '{period}'.", []
    return None, files


def handle_get_latest_trends(args: Dict[str, Any]) -> Dict[str, Any]:
    period = args.get("period", "monthly")
    full_content = args.get("full_content", False)
    max_chars = args.get("max_chars", 4000)

    err, summary_files = _get_trend_summary_files(period)
    if err:
        return {"status": "error", "message": err}

    target_file = summary_files[0]
    with open(target_file, "r", encoding="utf-8") as f:
        content = f.read()

    truncated = False
    if not full_content:
        content, truncated = _truncate_trends_content(content, max_chars)

    return {
        "status": "success",
        "period": period,
        "file": os.path.basename(target_file),
        "path": os.path.relpath(target_file, WORKSPACE_DIR),
        "total_chars": len(content),
        "is_truncated": truncated,
        "content": content,
    }


def handle_query_attack_technique(args: Dict[str, Any]) -> Dict[str, Any]:
    technique_id = args.get("technique_id", "").lower()
    results = get_vector_engine().search(technique_id, top_k=10)
    return {
        "status": "success",
        "technique_id": technique_id,
        "count": len(results),
        "papers": results,
    }


def handle_get_related_papers_graph(args: Dict[str, Any]) -> Dict[str, Any]:
    arxiv_id = args.get("arxiv_id", "").strip().replace("/", "_").replace("..", "")
    return get_vector_engine().get_related_papers(arxiv_id)


CWE_MITIGATION_DATABASE = {
    "CWE-89": {
        "name": "Improper Neutralization of Special Elements used in an SQL Command ('SQL Injection')",
        "risk": "HIGH",
        "description": "Untrusted input concatenated into SQL queries allows database reading or modification.",
        "secure_patterns": [
            "Use parameterized queries e.g. cursor.execute('SELECT * FROM users WHERE id=%s', (uid,))",
            "Use Object Relational Mapping (ORM) frameworks with automatic parameter binding",
            "Apply principle of least privilege on database connection accounts",
        ],
        "keywords": [
            "sql",
            "select",
            "insert",
            "update",
            "delete",
            "cursor.execute",
            "query",
            "database",
            "sqlite",
            "postgres",
            "mysql",
        ],
    },
    "CWE-78": {
        "name": "Improper Neutralization of Special Elements used in an OS Command ('OS Command Injection')",
        "risk": "HIGH",
        "description": "User input passed directly to system shells allows arbitrary remote command execution.",
        "secure_patterns": [
            "Avoid shell=True in subprocess.run() or os.system()",
            "Pass arguments as a list of strings: subprocess.run(['ls', '-la', target_dir], check=True)",
            "Validate and sanitize all command arguments with strict allow-lists",
        ],
        "keywords": [
            "subprocess",
            "os.system",
            "os.popen",
            "exec",
            "eval",
            "shell=True",
            "shlex",
            "spawn",
        ],
    },
    "CWE-22": {
        "name": "Improper Limitation of a Pathname to a Restricted Directory ('Path Traversal')",
        "risk": "HIGH",
        "description": "Allowing ../ or unvalidated filenames allows attackers to read/write outside root directory.",
        "secure_patterns": [
            "Use os.path.realpath() and os.path.commonpath() to verify boundaries",
            "Verify that commonpath([base_dir, target_file]) == base_dir",
            "Reject paths containing suspicious sequences (../, etc/passwd, .ssh, .env)",
        ],
        "keywords": [
            "open(",
            "os.path.join",
            "path",
            "filepath",
            "filename",
            "read_file",
            "write_file",
            "../",
        ],
    },
    "CWE-79": {
        "name": "Improper Neutralization of Input During Web Page Generation ('Cross-site Scripting')",
        "risk": "HIGH",
        "description": "Unescaped user input rendered in HTML/DOM permits arbitrary client-side script execution.",
        "secure_patterns": [
            "Use HTML entity escaping (e.g. html.escape(str)) before DOM insertion",
            "Set strict Content-Security-Policy (CSP) HTTP headers",
            "Use template engines with auto-escaping enabled by default",
        ],
        "keywords": [
            "<script>",
            "innerHTML",
            "document.write",
            "dangerouslySetInnerHTML",
            "html",
            "render",
            "template",
        ],
    },
    "CWE-327": {
        "name": "Use of a Broken or Risky Cryptographic Algorithm",
        "risk": "HIGH",
        "description": "Usage of deprecated algorithms (MD5, SHA1, DES, RC4) or non-constant-time token comparison.",
        "secure_patterns": [
            "Use modern algorithms: AES-GCM (256-bit), ChaCha20-Poly1305, Ed25519, Post-Quantum (ML-KEM/Kyber)",
            "Use hmac.compare_digest() for constant-time hash/token comparison",
            "Use Argon2id or bcrypt for password hashing with appropriate work factors",
        ],
        "keywords": [
            "md5",
            "sha1",
            "des",
            "rc4",
            "crypto",
            "cipher",
            "aes",
            "rsa",
            "hash",
            "hmac",
            "encrypt",
            "decrypt",
        ],
    },
    "CWE-502": {
        "name": "Deserialization of Untrusted Data",
        "risk": "HIGH",
        "description": "Deserializing untrusted data with pickle, yaml.load, or Marshal can lead to RCE.",
        "secure_patterns": [
            "Avoid pickle.loads() on untrusted inputs; use JSON or Protocol Buffers instead",
            "Use yaml.safe_load() instead of yaml.load()",
            "Sign and verify serialized payloads using HMAC if serialization is unavoidable",
        ],
        "keywords": [
            "pickle.loads",
            "pickle.load",
            "yaml.load",
            "marshal.loads",
            "unpickle",
            "deserialize",
        ],
    },
}


def _match_cwe_warnings(code_lower: str) -> tuple[List[Dict[str, Any]], List[str]]:
    warnings: List[Dict[str, Any]] = []
    suggested_mitigations: List[str] = []
    for cwe_id, data in CWE_MITIGATION_DATABASE.items():
        hits = [kw for kw in data["keywords"] if kw in code_lower]
        if hits:
            warnings.append(
                {
                    "cwe_id": cwe_id,
                    "name": data["name"],
                    "risk": data["risk"],
                    "trigger_keywords": hits[:3],
                    "description": data["description"],
                }
            )
            suggested_mitigations.extend(data["secure_patterns"])
    return warnings, suggested_mitigations


def _assess_code_risk(warnings: List[Dict[str, Any]]) -> str:
    if any(w["risk"] == "HIGH" for w in warnings):
        return "HIGH"
    return "MEDIUM" if warnings else "LOW"


def handle_verify_code_security(args: Dict[str, Any]) -> Dict[str, Any]:
    code = args.get("code_snippet", "")
    language = args.get("language", "python").lower()

    if len(code) > 65536:
        return {
            "status": "error",
            "message": "Payload too large: code_snippet exceeds maximum limit of 64KB (CWE-400 mitigation).",
        }

    warnings, suggested_mitigations = _match_cwe_warnings(code.lower())
    query_terms = " ".join([w["name"] for w in warnings]) if warnings else code[:100]
    relevant_papers = get_vector_engine().search(query_terms, top_k=3)
    risk_level = _assess_code_risk(warnings)

    return {
        "status": "success",
        "language": language,
        "risk_level": risk_level,
        "warnings_count": len(warnings),
        "warnings": warnings,
        "suggested_mitigations": suggested_mitigations[:5],
        "matched_academic_papers": [
            {
                "id": p["id"],
                "title": p["title"],
                "score": p["score"],
                "url": f"https://arxiv.org/abs/{p['id']}",
            }
            for p in relevant_papers
        ],
    }


def handle_get_cwe_mitigation_recipe(args: Dict[str, Any]) -> Dict[str, Any]:
    cwe_id = args.get("cwe_id", "").strip().upper()
    if not cwe_id.startswith("CWE-"):
        cwe_id = f"CWE-{cwe_id}"

    data = CWE_MITIGATION_DATABASE.get(cwe_id)
    if not data:
        results = get_vector_engine().search(cwe_id, top_k=5)
        return {
            "status": "success",
            "cwe_id": cwe_id,
            "name": f"Academic references for {cwe_id}",
            "risk": "MEDIUM",
            "description": f"Custom weakness exploration for {cwe_id}",
            "secure_patterns": [
                "Review academic reference papers for state-of-the-art defense mitigations."
            ],
            "academic_papers": results,
        }

    relevant_papers = get_vector_engine().search(f"{cwe_id} {data['name']}", top_k=5)
    return {
        "status": "success",
        "cwe_id": cwe_id,
        "name": data["name"],
        "risk": data["risk"],
        "description": data["description"],
        "secure_coding_patterns": data["secure_patterns"],
        "academic_reference_papers": [
            {
                "id": p["id"],
                "title": p["title"],
                "score": p["score"],
                "url": f"https://arxiv.org/abs/{p['id']}",
            }
            for p in relevant_papers
        ],
    }


def _read_paper_resource(uri: str) -> Dict[str, Any]:
    arxiv_id = uri.replace("arxiv://paper/", "").strip()
    res = handle_get_paper_summary({"arxiv_id": arxiv_id})
    if res.get("status") != "success":
        return {"status": "error", "message": f"Resource '{uri}' not found."}
    return {"uri": uri, "mimeType": "text/markdown", "text": res.get("content", "")}


def _read_trends_resource(uri: str) -> Dict[str, Any]:
    res = handle_get_latest_trends({"period": "monthly"})
    if res.get("status") != "success":
        return {"status": "error", "message": "Trend resource not found."}
    return {"uri": uri, "mimeType": "text/markdown", "text": res.get("content", "")}


def handle_read_resource(uri: str) -> Dict[str, Any]:
    """Handles MCP resources/read for arxiv:// URIs"""
    if uri.startswith("arxiv://paper/"):
        return _read_paper_resource(uri)
    if uri == "arxiv://trends/latest":
        return _read_trends_resource(uri)
    if uri == "arxiv://cwe-taxonomy":
        return {
            "uri": uri,
            "mimeType": "application/json",
            "text": json.dumps(CWE_MITIGATION_DATABASE, ensure_ascii=False, indent=2),
        }
    return {"status": "error", "message": f"Unknown resource URI: '{uri}'"}


def handle_get_prompt(name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
    """Handles MCP prompts/get"""
    if name == "audit_code_with_papers":
        code = arguments.get("code", "")
        lang = arguments.get("language", "python")
        prompt_text = (
            f"You are an expert security auditor. Audit the following {lang} code against recent academic papers:\n\n"
            f"```{lang}\n{code}\n```\n\n"
            "Please analyze potential vulnerabilities (e.g. CWEs, side-channel attacks, injection risks), "
            "provide citations to known attack methodologies, and supply robust, academically verified fix code."
        )
        return {
            "description": f"Security audit prompt for {lang} code",
            "messages": [
                {"role": "user", "content": {"type": "text", "text": prompt_text}}
            ],
        }
    if name == "generate_exploit_poc_tests":
        arxiv_id = arguments.get("arxiv_id", "")
        framework = arguments.get("target_framework", "pytest")
        summary_res = handle_get_paper_summary({"arxiv_id": arxiv_id})
        paper_text = summary_res.get("content", f"Paper ID {arxiv_id}")
        prompt_text = (
            f"Based on the attack technique and vulnerability findings in arXiv paper {arxiv_id}:\n\n"
            f"{paper_text[:1500]}\n...\n\n"
            f"Generate a comprehensive {framework} test suite to verify whether the system is vulnerable "
            "and confirm that the mitigation is effective."
        )
        return {
            "description": f"PoC regression test generator for arXiv:{arxiv_id}",
            "messages": [
                {"role": "user", "content": {"type": "text", "text": prompt_text}}
            ],
        }
    if name == "recommend_cwe_mitigation":
        cwe_id = arguments.get("cwe_id", "CWE-89")
        lang = arguments.get("language", "python")
        recipe = handle_get_cwe_mitigation_recipe({"cwe_id": cwe_id})
        cwe_name = recipe.get("name", "")
        patterns = "\n".join(
            [f"- {p}" for p in recipe.get("secure_coding_patterns", [])]
        )
        prompt_text = (
            f"Recommend remediation patterns for weakness {cwe_id} ({cwe_name}) in {lang}.\n\n"
            f"### Verified Secure Coding Patterns:\n{patterns}\n\n"
            "Generate production-grade, hardened code avoiding this weakness."
        )
        return {
            "description": f"Remediation pattern prompt for {cwe_id}",
            "messages": [
                {"role": "user", "content": {"type": "text", "text": prompt_text}}
            ],
        }
    return {"status": "error", "message": f"Unknown prompt: '{name}'"}


def dispatch_tool(name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
    tool_map: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]] = {
        "search_security_papers": handle_search_security_papers,
        "search_papers_hybrid": handle_search_papers_hybrid,
        "query_knowledge_graph": handle_query_knowledge_graph,
        "get_paper_summary": handle_get_paper_summary,
        "get_latest_trends": handle_get_latest_trends,
        "query_attack_technique": handle_query_attack_technique,
        "get_related_papers_graph": handle_get_related_papers_graph,
        "verify_code_security": handle_verify_code_security,
        "get_cwe_mitigation_recipe": handle_get_cwe_mitigation_recipe,
    }
    handler = tool_map.get(name)
    if handler:
        return handler(arguments)
    return {"status": "error", "message": f"Unknown tool: '{name}'"}


def _count_output_items(output: Dict[str, Any]) -> Optional[int]:
    if "count" in output:
        return output["count"]
    for key in ("results", "papers"):
        val = output.get(key)
        if isinstance(val, list):
            return len(val)
    return None


def _extract_papers_metrics(output: Any) -> Dict[str, Any]:
    if not isinstance(output, dict):
        return {}
    c = _count_output_items(output)
    return {"hits": c} if c is not None else {}


def _dispatch_papers_tool_call(req_id: Any, params: Dict[str, Any]) -> Dict[str, Any]:
    tool_name = params.get("name", "")
    tool_args = params.get("arguments", {})
    t0 = time.perf_counter()
    output = dispatch_tool(tool_name, tool_args)
    exec_ms = (time.perf_counter() - t0) * 1000.0
    status = (
        "error"
        if isinstance(output, dict) and output.get("status") == "error"
        else "success"
    )
    metrics = _extract_papers_metrics(output)

    log_mcp_performance(
        server_name="arxiv-security-papers",
        method="tools/call",
        name=tool_name,
        execution_ms=exec_ms,
        status=status,
        args_summary=tool_args,
        metrics=metrics,
    )
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "result": {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(output, ensure_ascii=False, indent=2),
                }
            ]
        },
    }


def _dispatch_papers_resource_read(
    req_id: Any, params: Dict[str, Any]
) -> Dict[str, Any]:
    uri = params.get("uri", "")
    t0 = time.perf_counter()
    output = handle_read_resource(uri)
    exec_ms = (time.perf_counter() - t0) * 1000.0

    if output.get("status") == "error":
        log_mcp_performance(
            server_name="arxiv-security-papers",
            method="resources/read",
            name=uri,
            execution_ms=exec_ms,
            status="error",
            error_message=output.get("message"),
        )
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "error": {
                "code": -32602,
                "message": output.get("message", "Resource error"),
            },
        }

    log_mcp_performance(
        server_name="arxiv-security-papers",
        method="resources/read",
        name=uri,
        execution_ms=exec_ms,
        status="success",
    )
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "result": {
            "contents": [
                {
                    "uri": output.get("uri"),
                    "mimeType": output.get("mimeType"),
                    "text": output.get("text"),
                }
            ]
        },
    }


def _dispatch_papers_prompt_get(req_id: Any, params: Dict[str, Any]) -> Dict[str, Any]:
    prompt_name = params.get("name", "")
    prompt_args = params.get("arguments", {})
    t0 = time.perf_counter()
    output = handle_get_prompt(prompt_name, prompt_args)
    exec_ms = (time.perf_counter() - t0) * 1000.0

    if output.get("status") == "error":
        log_mcp_performance(
            server_name="arxiv-security-papers",
            method="prompts/get",
            name=prompt_name,
            execution_ms=exec_ms,
            status="error",
            args_summary=prompt_args,
            error_message=output.get("message"),
        )
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "error": {"code": -32602, "message": output.get("message", "Prompt error")},
        }

    log_mcp_performance(
        server_name="arxiv-security-papers",
        method="prompts/get",
        name=prompt_name,
        execution_ms=exec_ms,
        status="success",
        args_summary=prompt_args,
    )
    return {"jsonrpc": "2.0", "id": req_id, "result": output}


def _handle_papers_init(req_id: Any) -> Dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "tools": {"listChanged": False},
                "prompts": {"listChanged": False},
                "resources": {"subscribe": False, "listChanged": False},
            },
            "serverInfo": {"name": "arxiv-security-papers", "version": "1.0.0"},
        },
    }


def _dispatch_papers_rpc(req: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    req_id = req.get("id")
    method = req.get("method")
    params = req.get("params", {})

    if method == "initialize":
        return _handle_papers_init(req_id)
    if method == "notifications/initialized":
        return None
    if method == "ping":
        return {"jsonrpc": "2.0", "id": req_id, "result": {}}

    dispatch_map = {
        "tools/list": lambda: {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {"tools": TOOLS_MANIFEST},
        },
        "tools/call": lambda: _dispatch_papers_tool_call(req_id, params),
        "resources/list": lambda: {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {"resources": RESOURCES_MANIFEST},
        },
        "resources/read": lambda: _dispatch_papers_resource_read(req_id, params),
        "prompts/list": lambda: {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {"prompts": PROMPTS_MANIFEST},
        },
        "prompts/get": lambda: _dispatch_papers_prompt_get(req_id, params),
    }
    if method in dispatch_map:
        return dispatch_map[method]()

    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {"code": -32601, "message": f"Method not found: {method}"},
    }


def run_jsonrpc_server() -> None:
    """Runs standard MCP JSON-RPC stdio server with tools, resources, and prompts support"""
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            res = _dispatch_papers_rpc(req)
            if res is not None:
                print(json.dumps(res, ensure_ascii=False), flush=True)
        except Exception as e:
            sys.stderr.write(f"Error handling request: {e}\n")


def _run_cli_mode() -> None:
    if sys.argv[1] == "--manifest":
        manifest_data = {
            "tools": TOOLS_MANIFEST,
            "resources": RESOURCES_MANIFEST,
            "prompts": PROMPTS_MANIFEST,
        }
        print(json.dumps(manifest_data, ensure_ascii=False, indent=2))
    elif sys.argv[1] == "--http":
        from web.server import run_web_server

        port = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 8000
        run_web_server(port=port)


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] in ("--manifest", "--http"):
        _run_cli_mode()
    else:
        run_jsonrpc_server()


if __name__ == "__main__":
    main()
