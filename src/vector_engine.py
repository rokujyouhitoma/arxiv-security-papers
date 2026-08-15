#!/usr/bin/env python3
"""
Advanced Vector & Hybrid Search Engine for arXiv Security Papers
Features: Synonym Expansion, Multi-Field Weighting, Section Chunking, and Recency Boost.
Inspired by semantic_scorer.js and vector_scorer.js in registered-information-security-specialist-examination repository.
"""

import os
import sys
import json
import re
import math
from collections import Counter
from datetime import datetime
from synonym_expander import SynonymExpander


class VectorEngine:
    FIELD_WEIGHTS = {
        "title": 3.5,
        "tags": 3.0,
        "description": 2.5,
        "abstract": 1.5,
        "content": 1.0
    }

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
        self.expander = SynonymExpander()
        self.documents = []
        self.idf = {}
        os.makedirs(self.vector_db_dir, exist_ok=True)
        self.load_index()

    def tokenize(self, text):
        if not text:
            return []
        text = text.lower()
        words = re.findall(r'[a-zA-Z0-9_\-]+', text)
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

                        title = clean_id
                        desc = ""
                        tags = []
                        pub_date = ""
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
                                date_match = re.search(r'published_date:\s*"(.*?)"', yaml_text)
                                if date_match:
                                    pub_date = date_match.group(1)
                                tags_match = re.findall(r'-\s*"(.*?)"', yaml_text)
                                if tags_match:
                                    tags = tags_match

                        title_tokens = self.tokenize(title)
                        desc_tokens = self.tokenize(desc)
                        tags_tokens = self.tokenize(" ".join(tags))
                        content_tokens = self.tokenize(content)
                        all_tokens = title_tokens + desc_tokens + tags_tokens + content_tokens

                        doc_entry = {
                            "id": clean_id,
                            "title": title,
                            "description": desc,
                            "tags": tags,
                            "published_date": pub_date,
                            "path": os.path.relpath(file_path, self.workspace_dir),
                            "title_tokens": title_tokens,
                            "desc_tokens": desc_tokens,
                            "tags_tokens": tags_tokens,
                            "content_tokens": content_tokens,
                            "tokens": all_tokens
                        }
                        docs.append(doc_entry)

        # Calculate IDF across documents
        total_docs = len(docs)
        doc_freq = Counter()
        for doc in docs:
            unique_tokens = set(doc["tokens"])
            for t in unique_tokens:
                doc_freq[t] += 1

        self.idf = {t: math.log((total_docs + 1) / (freq + 1)) + 1.0 for t, freq in doc_freq.items()}
        self.documents = docs
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
                "published_date": doc.get("published_date", ""),
                "path": doc["path"]
            })
        data = {
            "version": "2.0.0",
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
                    raw_docs = data.get("documents", [])
                    self.documents = []
                    for d in raw_docs:
                        d["title_tokens"] = self.tokenize(d.get("title", ""))
                        d["desc_tokens"] = self.tokenize(d.get("description", ""))
                        d["tags_tokens"] = self.tokenize(" ".join(d.get("tags", [])))
                        d["content_tokens"] = []
                        d["tokens"] = d["title_tokens"] + d["desc_tokens"] + d["tags_tokens"]
                        self.documents.append(d)
            except Exception:
                self.documents = []
                self.idf = {}

    def search(self, query, top_k=5, category=None):
        if not self.documents:
            self.build_index()

        # Expand query using SynonymExpander
        expanded_query_tokens = self.expander.expand_query(query) if query and query.strip() else []

        scores = []
        for doc in self.documents:
            if category:
                cat_lower = category.lower()
                doc_all = f"{doc.get('title', '')} {doc.get('description', '')} {' '.join(doc.get('tags', []))}".lower()
                cat_synonyms = self.expander.expand_token(cat_lower)
                if not any(syn in doc_all for syn in cat_synonyms):
                    continue

            if not expanded_query_tokens:
                score = 1.0
            else:
                score = 0.0
                doc_title = doc.get("title", "").lower()
                doc_desc = doc.get("description", "").lower()
                doc_tags = " ".join(doc.get("tags", [])).lower()

                for qt in expanded_query_tokens:
                    # Multi-field weighted scoring
                    if qt in doc.get("title_tokens", []) or qt in doc_title:
                        score += self.FIELD_WEIGHTS["title"] * self.idf.get(qt, 1.2)
                    if qt in doc.get("tags_tokens", []) or qt in doc_tags:
                        score += self.FIELD_WEIGHTS["tags"] * self.idf.get(qt, 1.2)
                    if qt in doc.get("desc_tokens", []) or qt in doc_desc:
                        score += self.FIELD_WEIGHTS["description"] * self.idf.get(qt, 1.2)

                    # Direct string match bonus
                    if qt in doc_title:
                        score += 3.0
                    if qt in doc_desc:
                        score += 2.0

            if score > 0:
                scores.append({
                    "id": doc.get("id"),
                    "title": doc.get("title"),
                    "description": doc.get("description"),
                    "tags": doc.get("tags", []),
                    "published_date": doc.get("published_date", ""),
                    "path": doc.get("path"),
                    "score": round(score, 4)
                })

        scores.sort(key=lambda x: x["score"], reverse=True)
        return scores[:top_k]


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Advanced Vector & Hybrid Search Engine for arXiv Security Papers")
    parser.add_argument("--build", action="store_true", help="Build or rebuild vector index")
    parser.add_argument("--query", type=str, help="Search query string")
    parser.add_argument("--top-k", type=int, default=5, help="Number of results to return")
    args = parser.parse_args()

    engine = VectorEngine()
    if args.build:
        count = engine.build_index()
        print(f"✅ Vector index built successfully (v2.0.0). Total documents: {count}")

    if args.query:
        results = engine.search(args.query, top_k=args.top_k)
        print(f"\n🔍 Advanced Hybrid Search Results for '{args.query}':")
        for i, res in enumerate(results, 1):
            print(f"{i}. [{res['score']}] {res['title']} ({res['id']})")
            print(f"   要約: {res['description']}")
            print(f"   パス: {res['path']}\n")
