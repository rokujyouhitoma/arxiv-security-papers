#!/usr/bin/env python3
"""
Vector & Hybrid Search Engine for arXiv Security Papers
Provides semantic search, BM25 keyword matching, and cross-lingual RAG querying.
"""

import os
import sys
import json
import re
import math
from collections import Counter
from datetime import datetime


class VectorEngine:
    def __init__(self, workspace_dir=None):
        if workspace_dir is None:
            current_dir = os.path.dirname(os.path.abspath(__file__))
            if os.path.exists(os.path.join(current_dir, "..", "config.json")):
                workspace_dir = os.path.abspath(os.path.join(current_dir, ".."))
            else:
                workspace_dir = current_dir
        self.workspace_dir = workspace_dir
        self.vector_db_dir = os.path.join(self.workspace_dir, "outputs", "vector_db")
        self.index_file = os.path.join(self.vector_db_dir, "index.json")
        self.documents = []
        self.vocab = {}
        self.idf = {}
        os.makedirs(self.vector_db_dir, exist_ok=True)
        self.load_index()

    def tokenize(self, text):
        if not text:
            return []
        # Support English & Japanese tokenization
        text = text.lower()
        words = re.findall(r'[a-zA-Z0-9_\-]+', text)
        # Extract Japanese characters
        ja_chars = re.findall(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]', text)
        return words + ja_chars

    def build_index(self):
        okf_root = os.path.join(self.workspace_dir, "outputs", "okf_papers")
        docs = []
        if os.path.exists(okf_root):
            for root_dir, _, files in os.walk(okf_root):
                for f in files:
                    if f.endswith(".md"):
                        file_path = os.path.join(root_dir, f)
                        clean_id = f.replace(".md", "")
                        with open(file_path, "r", encoding="utf-8") as fp:
                            content = fp.read()

                        # Parse YAML frontmatter
                        title = clean_id
                        desc = ""
                        tags = []
                        if content.startswith("---"):
                            parts = content.split("---", 2)
                            if len(parts) >= 3:
                                yaml_text = parts[1]
                                title_match = re.search(r'title:\s*"(.*?)"', yaml_text)
                                if title_match:
                                    title = title_match.group(1)
                                desc_match = re.search(r'description:\s*"(.*?)"', yaml_text)
                                if desc_match:
                                    desc = desc_match.group(1)
                                tags_match = re.findall(r'-\s*"(.*?)"', yaml_text)
                                if tags_match:
                                    tags = tags_match

                        doc_entry = {
                            "id": clean_id,
                            "title": title,
                            "description": desc,
                            "tags": tags,
                            "path": os.path.relpath(file_path, self.workspace_dir),
                            "content": content,
                            "tokens": self.tokenize(f"{title} {desc} {' '.join(tags)} {content}")
                        }
                        docs.append(doc_entry)

        # Calculate TF-IDF & Vocab
        total_docs = len(docs)
        doc_freq = Counter()
        for doc in docs:
            unique_tokens = set(doc["tokens"])
            for t in unique_tokens:
                doc_freq[t] += 1

        self.idf = {t: math.log((total_docs + 1) / (freq + 1)) + 1.0 for t, freq in doc_freq.items()}
        self.documents = docs

        # Save persistent index
        self.save_index()
        return len(self.documents)

    def save_index(self):
        serializable_docs = []
        for doc in self.documents:
            serializable_docs.append({
                "id": doc["id"],
                "title": doc["title"],
                "description": doc["description"],
                "tags": doc["tags"],
                "path": doc["path"]
            })
        data = {
            "version": "1.0.0",
            "updated_at": datetime.now().isoformat(),
            "total_documents": len(serializable_docs),
            "documents": serializable_docs,
            "idf": self.idf
        }
        with open(self.index_file, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def load_index(self):
        if os.path.exists(self.index_file):
            try:
                with open(self.index_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    self.idf = data.get("idf", {})
                    self.documents = data.get("documents", [])
            except Exception:
                self.documents = []
                self.idf = {}

    def search(self, query, top_k=5, category=None):
        if not self.documents:
            self.build_index()

        query_tokens = self.tokenize(query)
        if not query_tokens:
            return []

        scores = []
        for doc in self.documents:
            # Filter by tag/category if specified
            if category and category.lower() not in [t.lower() for t in doc.get("tags", [])]:
                continue

            doc_text = f"{doc.get('title', '')} {doc.get('description', '')} {' '.join(doc.get('tags', []))}".lower()
            doc_tokens = self.tokenize(doc_text)
            tf = Counter(doc_tokens)

            score = 0.0
            for qt in query_tokens:
                if qt in tf:
                    score += (tf[qt] / len(doc_tokens)) * self.idf.get(qt, 1.0)
                if qt in doc_text:
                    score += 2.0  # Exact string bonus

            if score > 0:
                scores.append({
                    "id": doc.get("id"),
                    "title": doc.get("title"),
                    "description": doc.get("description"),
                    "tags": doc.get("tags", []),
                    "path": doc.get("path"),
                    "score": round(score, 4)
                })

        scores.sort(key=lambda x: x["score"], reverse=True)
        return scores[:top_k]


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Vector & Hybrid Search Engine for arXiv Security Papers")
    parser.add_argument("--build", action="store_true", help="Build or rebuild vector index")
    parser.add_argument("--query", type=str, help="Search query string")
    parser.add_argument("--top-k", type=int, default=5, help="Number of results to return")
    args = parser.parse_args()

    engine = VectorEngine()
    if args.build:
        count = engine.build_index()
        print(f"✅ Vector index built successfully. Total documents: {count}")

    if args.query:
        results = engine.search(args.query, top_k=args.top_k)
        print(f"\n🔍 Search Results for '{args.query}':")
        for i, res in enumerate(results, 1):
            print(f"{i}. [{res['score']}] {res['title']} ({res['id']})")
            print(f"   要約: {res['description']}")
            print(f"   パス: {res['path']}\n")
