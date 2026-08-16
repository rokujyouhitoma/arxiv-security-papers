#!/usr/bin/env python3
"""
Live Search Engine Evaluation Benchmark over arXiv Security Papers.
Indexes all paper metadata from outputs/okf_papers/ into Solr SelectHandler,
executes the IR Benchmark suite, and prints the full Markdown evaluation report with observability metrics.
"""

import glob
import os
import re
import sys
import time

if "src" not in sys.path:
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

from search.core.index.doc_values import DocValues
from search.core.index.postings import MultiFieldPostingsIndex
from search.core.index.stored_fields import StoredFields
from search.eval.dataset import EvaluationQuery
from search.eval.evaluator import SearchEvaluator
from search.server.handler.select_handler import SelectHandler
from search.server.schema.managed_schema import ManagedIndexSchema
from search.utils.profiler import ExecutionProfiler

print("=== 1. arXiv セキュリティ論文コーパスのインデックス構築 ===")
postings = MultiFieldPostingsIndex()
stored = StoredFields()
doc_values = DocValues()
schema = ManagedIndexSchema()

# Get files from latest date folders
import os
dirs = sorted(glob.glob("outputs/okf_papers/*"), reverse=True)
md_files = []
for d in dirs:
    if os.path.isdir(d):
        md_files.extend(glob.glob(f"{d}/*.md"))
        if len(md_files) >= 200:
            break

md_files = md_files[:200]
print(f"ベンチマーク対象 OKF 論文ドキュメント: {len(md_files)} 件 (直近 200 件コーパス)")

t0 = time.perf_counter()
indexed_count = 0
for fpath in md_files:
    try:
        with open(fpath, "r", encoding="utf-8") as f:
            content = f.read()

        # Parse YAML frontmatter & title
        clean_id = os.path.splitext(os.path.basename(fpath))[0]
        title_m = re.search(r'title:\s*"?(.*?)"?$', content, re.MULTILINE)
        desc_m = re.search(r'description:\s*"?(.*?)"?$', content, re.MULTILINE)
        tags_m = re.findall(r'-\s*"([a-zA-Z0-9_\-\.]+)"', content)

        title = title_m.group(1).strip('"') if title_m else clean_id
        description = desc_m.group(1).strip('"') if desc_m else ""
        tags = [t.lower() for t in tags_m]

        doc = {
            "id": clean_id,
            "title": title,
            "description": description,
            "tags": tags,
            "category": tags[0] if tags else "security",
            "content": content[:2000],
        }
        stored.put_document(clean_id, doc)
        doc_values.set_value("category", clean_id, doc["category"])
        doc_values.set_value("tags", clean_id, tags)

        # Index terms into fields
        for term in re.findall(r"[a-zA-Z0-9_\-]+", title.lower()):
            postings.add_term("title", term, clean_id)
        for term in re.findall(r"[a-zA-Z0-9_\-]+", description.lower()):
            postings.add_term("description", term, clean_id)
        for tag in tags:
            postings.add_term("tags", tag, clean_id)
        for term in re.findall(r"[a-zA-Z0-9_\-]+", content[:2000].lower()):
            postings.add_term("content", term, clean_id)

        indexed_count += 1
    except Exception as e:
        print(f"Error parsing {fpath}: {e}")
        continue

index_time_ms = round((time.perf_counter() - t0) * 1000, 2)
print(f"インデックス完了: {indexed_count} 件の論文を登録 ({index_time_ms} ms)")

# Initialize Solr SelectHandler
handler = SelectHandler(
    schema=schema,
    postings_index=postings,
    doc_values=doc_values,
    stored_fields=stored,
)

print("\n=== 2. セキュリティ専門クエリ集合の Ground Truth 構築 ===")
all_docs = stored.all_documents()

queries = [
    EvaluationQuery(
        query_id="Q01",
        query_text="zero trust architecture access control",
        category="zero-trust",
        relevant_doc_ids=[d["id"] for d in all_docs if any(k in d["title"].lower() or k in d["description"].lower() for k in ["zero trust", "zero-trust", "trust", "ztna"])][:8],
        description="Zero Trust, Identity-aware access control",
    ),
    EvaluationQuery(
        query_id="Q02",
        query_text="large language model prompt injection adversarial attacks",
        category="ai-security",
        relevant_doc_ids=[d["id"] for d in all_docs if any(k in d["title"].lower() or k in d["description"].lower() for k in ["llm", "prompt", "adversarial", "injection", "language model"])][:8],
        description="LLM Prompt Injection and Jailbreak",
    ),
    EvaluationQuery(
        query_id="Q03",
        query_text="post-quantum cryptography lattice encryption",
        category="cryptography",
        relevant_doc_ids=[d["id"] for d in all_docs if any(k in d["title"].lower() or k in d["description"].lower() for k in ["quantum", "cryptography", "encryption", "lattice"])][:8],
        description="Post-quantum and Lattice-based Cryptography",
    ),
    EvaluationQuery(
        query_id="Q04",
        query_text="hardware side channel cache attack transient execution",
        category="hardware-security",
        relevant_doc_ids=[d["id"] for d in all_docs if any(k in d["title"].lower() or k in d["description"].lower() for k in ["side-channel", "hardware", "cache", "spectre", "execution", "attack"])][:8],
        description="Side-channel, cache timing, microarchitecture",
    ),
    EvaluationQuery(
        query_id="Q05",
        query_text="network intrusion detection anomaly malicious traffic",
        category="network-security",
        relevant_doc_ids=[d["id"] for d in all_docs if any(k in d["title"].lower() or k in d["description"].lower() for k in ["intrusion", "detection", "network", "traffic", "anomaly", "malicious"])][:8],
        description="Network intrusion detection and traffic anomaly",
    ),
]

evaluator = SearchEvaluator(queries=queries, top_k=5)

def search_func(q: str, k: int):
    res = handler.handle_select(query=q, top_k=k)
    return [d.get("id", "") for d in res.get("response", {}).get("docs", [])]

print("\n=== 3. 検索精度 & 可観測性ベンチマークの実行 ===")
with ExecutionProfiler("ir_evaluation_benchmark") as prof:
    eval_result = evaluator.evaluate(search_func)

print(evaluator.generate_markdown_report(eval_result))

print("=== 4. 可観測性実行メトリクス (Execution Profiler) ===")
print(f"・Wall-Clock 時間: {prof.metrics.wall_time_ms} ms")
print(f"・CPU 使用時間: {prof.metrics.cpu_time_ms} ms")
print(f"・ピークメモリ消費量: {prof.metrics.peak_memory_kb} KB ({round(prof.metrics.peak_memory_kb / 1024, 2)} MB)")
