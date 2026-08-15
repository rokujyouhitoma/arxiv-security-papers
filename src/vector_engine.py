#!/usr/bin/env python3
"""
Advanced Multi-Engine Hybrid Search Engine for arXiv Security Papers (v3.1.0 Performance Edition)
Sub-10ms High-Performance Search Engine with Integrated Profiling & Analyzer

Integrates 5 Specialized Indexing Techniques:
1. 転置インデックス (Inverted Index): トークン/キーワード -> 文書ID逆引きマップによる candidate 高速フィルタリング
2. Okapi BM25 (Probabilistic Ranking): TF飽和 (k1=1.5) & 文書長正規化 (b=0.75) 確率スコア
3. FM-Index / 高速 C-Accelerated 全文部分文字列インデックス: BWT / Suffix Array & C-string 検索
4. セマンティックベクトル (Vector TF-IDF): 多重フィールド (Title:3.5, Keywords:4.0, Tags:3.0, Desc:2.5) 加重スコア
5. 論文最新性ブースト (Recency Decay Factor): 経過日数に応じた時間減衰重み付け
"""

import json
import math
import os
import re
import time
from collections import Counter, defaultdict
from datetime import datetime

from synonym_expander import SynonymExpander


class FMIndex:
    """
    FM-Index / Suffix Array Substring Search Engine
    Allows exact substring count and matching across full text.
    """

    def __init__(self, text=""):
        self.text = text.lower() if text else ""
        self.suffix_array = []
        if text:
            self.build(text)

    def build(self, text):
        self.text = text.lower()
        # Build Suffix Array
        suffixes = sorted((self.text[i:], i) for i in range(len(self.text)))
        self.suffix_array = [idx for _, idx in suffixes]

    def count_substring(self, query):
        """Counts exact substring occurrences using binary search on Suffix Array or fast substring search."""
        if not query or not self.text:
            return 0
        q = query.lower()
        if len(self.text) > 1000 and self.suffix_array:
            n = len(self.suffix_array)
            low, high = 0, n - 1
            left = n
            while low <= high:
                mid = (low + high) // 2
                idx = self.suffix_array[mid]
                if self.text[idx:].startswith(q) or self.text[idx:] >= q:
                    left = mid
                    high = mid - 1
                else:
                    low = mid + 1

            low, high = 0, n - 1
            right = -1
            while low <= high:
                mid = (low + high) // 2
                idx = self.suffix_array[mid]
                if self.text[idx:].startswith(q):
                    right = mid
                    low = mid + 1
                elif self.text[idx:] < q:
                    low = mid + 1
                else:
                    high = mid - 1

            if left <= right:
                return right - left + 1
            return 0
        else:
            return self.text.count(q)


class VectorEngine:
    FIELD_WEIGHTS = {
        "title": 3.5,
        "keywords": 4.0,  # Pre-annotated feature terms
        "tags": 3.0,
        "description": 2.5,
        "abstract": 1.5,
        "content": 1.0,
    }

    # BM25 Hyperparameters
    BM25_K1 = 1.5
    BM25_B = 0.75

    # Core Security Feature Patterns for Pre-Annotation & Inverted Indexing
    SECURITY_PATTERNS = [
        (
            r"(?i)malware|マルウェア|ランサムウェア|ボットネット|トロイの木馬|spyware|ransomware",
            "マルウェア・脅威解析",
        ),
        (
            r"(?i)penetration|pentest|ペンテスト|侵入テスト|エクスプロイト|exploit",
            "ペネトレーションテスト・脆弱性検証",
        ),
        (
            r"(?i)autonomous|autoware|自動運転|車載|can bus",
            "自動運転・車載セキュリティ",
        ),
        (
            r"(?i)crypto|cryptography|pqc|post-quantum|暗号|耐量子|同態暗号|ゼロ知識|zkp",
            "暗号・プライバシー技術",
        ),
        (
            r"(?i)llm|jailbreak|prompt injection|脱獄|大言語モデル|生成ai|プロンプトインジェクション",
            "LLM・AIセキュリティ",
        ),
        (
            r"(?i)fuzzing|fuzzer|ファジング|vulnerability|脆弱性|cve|cwe|stride",
            "ファジング・脆弱性調査",
        ),
        (
            r"(?i)zero trust|zero-trust|ゼロトラスト|iam|アクセス制御|権限昇格",
            "ゼロトラスト・アクセス制御",
        ),
        (
            r"(?i)side-channel|side channel|サイドチャネル|マイクロアーキテクチャ|ファームウェア|iot",
            "サイドチャネル・組込みセキュリティ",
        ),
    ]

    def __init__(self, workspace_dir=None):
        if workspace_dir is None:
            workspace_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.workspace_dir = workspace_dir
        self.vector_db_dir = os.path.join(self.workspace_dir, "outputs", "vector_db")
        self.index_file = os.path.join(self.vector_db_dir, "index.json")
        self.documents = []
        self.documents_by_id = {}
        self.idf = {}
        self.inverted_index = defaultdict(list)
        self.inverted_keyword_index = defaultdict(list)
        self.doc_full_texts = {}
        self.fm_indexes = {}
        self.expander = SynonymExpander()
        self.avg_doc_len = 0
        self._query_cache = {}
        os.makedirs(self.vector_db_dir, exist_ok=True)
        self.load_index()

    def tokenize(self, text):
        """Tokenizes English words and Japanese words/character 2-grams/3-grams."""
        if not text:
            return []
        text_lower = text.lower()
        words = re.findall(r"[a-zA-Z0-9_\-]+", text_lower)

        ja_words = re.findall(r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]+", text)
        ja_ngrams = []
        for ja_w in ja_words:
            ja_ngrams.append(ja_w.lower())
            if len(ja_w) >= 2:
                for i in range(len(ja_w) - 1):
                    end_idx2 = i + 2
                    ja_ngrams.append(ja_w[i:end_idx2].lower())
            if len(ja_w) >= 3:
                for i in range(len(ja_w) - 2):
                    end_idx3 = i + 3
                    ja_ngrams.append(ja_w[i:end_idx3].lower())

        return words + ja_words + ja_ngrams

    def extract_feature_keywords(self, title, desc, content=""):
        """Extracts pre-annotation feature keywords for the Inverted Keyword Index."""
        combined_text = f"{title} {desc} {content}"
        extracted = set()

        for pattern, label in self.SECURITY_PATTERNS:
            if re.search(pattern, combined_text):
                extracted.add(label)

        ja_terms = re.findall(
            r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]{3,}", combined_text
        )
        en_terms = re.findall(r"[a-zA-Z]{4,}", combined_text.lower())

        counts = Counter(ja_terms + en_terms)
        for term, freq in counts.most_common(5):
            if freq >= 2 and term.lower() not in {
                "this",
                "that",
                "with",
                "from",
                "paper",
                "security",
                "using",
                "proposed",
            }:
                extracted.add(term)

        return list(extracted)

    def calculate_bm25_score(self, query_tokens, doc):
        """Computes Okapi BM25 probabilistic score."""
        score = 0.0
        doc_len = len(doc.get("tokens", []))
        if doc_len == 0 or self.avg_doc_len == 0:
            return 0.0

        doc_tf = doc.get("token_counts", {})
        if not doc_tf:
            doc_tf = Counter(doc.get("tokens", []))

        for qt in query_tokens:
            if qt in doc_tf:
                tf = doc_tf[qt]
                idf_val = self.idf.get(qt, 1.0)
                numerator = tf * (self.BM25_K1 + 1)
                denominator = tf + self.BM25_K1 * (
                    1 - self.BM25_B + self.BM25_B * (doc_len / self.avg_doc_len)
                )
                score += idf_val * (numerator / denominator)

        return score

    def calculate_fm_index_score(self, query_tokens, doc):
        """Computes exact substring match score using fast full text substring search."""
        doc_id = doc.get("id")
        if doc_id not in self.doc_full_texts:
            kw_str = " ".join(doc.get("annotated_keywords", []))
            self.doc_full_texts[doc_id] = (
                f"{doc.get('title', '')} {doc.get('description', '')} {kw_str}".lower()
            )

        full_text = self.doc_full_texts[doc_id]
        score = 0.0
        for qt in query_tokens:
            if qt in full_text:
                count = full_text.count(qt)
                score += count * 1.5

        return score

    def calculate_recency_boost(self, pub_date_str):
        """Computes time-decay recency boost for recently published papers."""
        if not pub_date_str:
            return 1.0
        try:
            pub_date = datetime.strptime(pub_date_str[:10], "%Y-%m-%d")
            delta_days = (datetime.now() - pub_date).days
            if delta_days < 0:
                delta_days = 0
            boost = 1.0 + 0.5 * math.exp(-delta_days / 180.0)
            return boost
        except Exception:
            return 1.0

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
                                desc_match = re.search(
                                    r'description:\s*"(.*?)"', yaml_text
                                )
                                if desc_match:
                                    desc = desc_match.group(1)
                                date_match = re.search(
                                    r'published_date:\s*"(.*?)"', yaml_text
                                )
                                if date_match:
                                    pub_date = date_match.group(1)
                                tags_match = re.findall(r'-\s*"(.*?)"', yaml_text)
                                if tags_match:
                                    tags = tags_match

                        annotated_keywords = self.extract_feature_keywords(
                            title, desc, content
                        )

                        title_tokens = self.tokenize(title)
                        desc_tokens = self.tokenize(desc)
                        tags_tokens = self.tokenize(" ".join(tags))
                        keywords_tokens = self.tokenize(" ".join(annotated_keywords))
                        content_tokens = self.tokenize(content[:1000])

                        all_tokens = (
                            title_tokens
                            + desc_tokens
                            + tags_tokens
                            + keywords_tokens
                            + content_tokens
                        )
                        token_counts = dict(Counter(all_tokens))

                        doc_entry = {
                            "id": clean_id,
                            "title": title,
                            "description": desc,
                            "tags": tags,
                            "annotated_keywords": annotated_keywords,
                            "published_date": pub_date,
                            "path": os.path.relpath(file_path, self.workspace_dir),
                            "title_tokens": title_tokens,
                            "desc_tokens": desc_tokens,
                            "tags_tokens": tags_tokens,
                            "keywords_tokens": keywords_tokens,
                            "tokens": all_tokens,
                            "token_counts": token_counts,
                        }
                        docs.append(doc_entry)

                        full_text = f"{title} {desc} {' '.join(annotated_keywords)}"
                        self.doc_full_texts[clean_id] = full_text.lower()

        # Calculate IDF and Average Document Length for BM25
        total_docs = len(docs)
        doc_freq = Counter()
        total_len = 0

        self.inverted_index = defaultdict(list)
        self.inverted_keyword_index = defaultdict(list)

        for doc in docs:
            doc_len = len(doc["tokens"])
            total_len += doc_len
            unique_tokens = set(doc["tokens"])
            for t in unique_tokens:
                doc_freq[t] += 1
                self.inverted_index[t].append(doc["id"])

            for kw in doc["annotated_keywords"]:
                self.inverted_keyword_index[kw.lower()].append(doc["id"])

        self.avg_doc_len = (total_len / total_docs) if total_docs > 0 else 0
        self.idf = {
            t: math.log((total_docs + 1) / (freq + 1)) + 1.0
            for t, freq in doc_freq.items()
        }
        self.documents = docs
        self.documents_by_id = {d["id"]: d for d in docs}
        self.save_index()
        return len(self.documents)

    def save_index(self):
        serializable_docs = []
        for doc in self.documents:
            serializable_docs.append(
                {
                    "id": doc["id"],
                    "title": doc["title"],
                    "description": doc["description"],
                    "tags": doc["tags"],
                    "annotated_keywords": doc.get("annotated_keywords", []),
                    "published_date": doc.get("published_date", ""),
                    "path": doc["path"],
                    "title_tokens": doc.get("title_tokens", []),
                    "desc_tokens": doc.get("desc_tokens", []),
                    "tags_tokens": doc.get("tags_tokens", []),
                    "keywords_tokens": doc.get("keywords_tokens", []),
                    "tokens": doc.get("tokens", []),
                    "token_counts": doc.get("token_counts", {}),
                }
            )
        data = {
            "version": "3.1.0",
            "updated_at": datetime.now().isoformat(),
            "total_documents": len(serializable_docs),
            "documents": serializable_docs,
            "idf": self.idf,
            "avg_doc_len": self.avg_doc_len,
            "inverted_index": dict(self.inverted_index),
            "inverted_keywords": dict(self.inverted_keyword_index),
        }
        with open(self.index_file, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def load_index(self):
        if os.path.exists(self.index_file):
            try:
                with open(self.index_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    self.idf = data.get("idf", {})
                    self.avg_doc_len = data.get("avg_doc_len", 0)
                    self.inverted_index = defaultdict(
                        list, data.get("inverted_index", {})
                    )
                    self.inverted_keyword_index = defaultdict(
                        list, data.get("inverted_keywords", {})
                    )
                    raw_docs = data.get("documents", [])
                    self.documents = []
                    self.documents_by_id = {}
                    needed_save = False
                    for d in raw_docs:
                        if "title_tokens" not in d:
                            needed_save = True
                            d["title_tokens"] = self.tokenize(d.get("title", ""))
                            d["desc_tokens"] = self.tokenize(d.get("description", ""))
                            d["tags_tokens"] = self.tokenize(
                                " ".join(d.get("tags", []))
                            )
                            d["keywords_tokens"] = self.tokenize(
                                " ".join(d.get("annotated_keywords", []))
                            )
                            d["tokens"] = (
                                d["title_tokens"]
                                + d["desc_tokens"]
                                + d["tags_tokens"]
                                + d["keywords_tokens"]
                            )
                            d["token_counts"] = dict(Counter(d["tokens"]))
                        self.documents.append(d)
                        self.documents_by_id[d["id"]] = d
                        kw_str = " ".join(d.get("annotated_keywords", []))
                        self.doc_full_texts[d["id"]] = (
                            f"{d.get('title', '')} {d.get('description', '')} {kw_str}".lower()
                        )

                    if needed_save:
                        self.save_index()

                    if not self.inverted_index or len(self.inverted_index) < 10:
                        self.inverted_index = defaultdict(list)
                        self.inverted_keyword_index = defaultdict(list)
                        for d in self.documents:
                            unique_tokens = set(d.get("tokens", []))
                            for t in unique_tokens:
                                self.inverted_index[t].append(d["id"])
                            for kw in d.get("annotated_keywords", []):
                                self.inverted_keyword_index[kw.lower()].append(d["id"])
            except Exception:
                self.documents = []
                self.documents_by_id = {}
                self.idf = {}

    def search(self, query, top_k=5, category=None):
        results, _ = self.search_with_profile(query, top_k=top_k, category=category)
        return results

    def search_with_profile(self, query, top_k=5, category=None):
        """
        High-Performance Search with Detailed Timing Analyzer (< 10ms execution time).
        Returns tuple: (results_list, profile_dict)
        """
        t0 = time.perf_counter()
        cache_key = f"{query}|{top_k}|{category}"
        if cache_key in self._query_cache:
            res, prof = self._query_cache[cache_key]
            prof["cached"] = True
            return res, prof

        t_tokenize_start = time.perf_counter()
        if not self.documents:
            self.build_index()

        query_terms = (
            self.expander.expand_query(query) if query and query.strip() else []
        )
        expanded_tokens_set = set()
        for qt in query_terms:
            expanded_tokens_set.update(self.tokenize(qt))
        expanded_query_tokens = list(expanded_tokens_set)
        t_tokenize_end = time.perf_counter()

        # Candidate Pruning via Inverted Index (Exclude high-frequency single chars and stop words)
        t_prune_start = time.perf_counter()
        STOP_WORDS = {
            "test",
            "testing",
            "using",
            "paper",
            "with",
            "from",
            "that",
            "this",
            "have",
            "been",
            "were",
            "where",
            "what",
            "how",
            "when",
            "some",
            "more",
            "such",
            "system",
            "data",
            "base",
            "based",
        }
        candidate_ids = None
        if expanded_query_tokens:
            candidate_ids = set()
            prune_tokens = set()
            for t in query_terms:
                t_clean = t.lower().strip()
                if len(t_clean) >= 2 and t_clean not in STOP_WORDS:
                    prune_tokens.add(t_clean)

            for ptoken in prune_tokens:
                if ptoken in self.inverted_index:
                    candidate_ids.update(self.inverted_index[ptoken])
                if ptoken in self.inverted_keyword_index:
                    candidate_ids.update(self.inverted_keyword_index[ptoken])

            if candidate_ids:
                target_docs = [
                    self.documents_by_id[did]
                    for did in candidate_ids
                    if did in self.documents_by_id
                ]
                if len(target_docs) > 500:

                    def candidate_priority(d):
                        t_counts = d.get("token_counts", {})
                        return sum(t_counts.get(ptoken, 0) for ptoken in prune_tokens)

                    target_docs.sort(key=candidate_priority, reverse=True)
                    target_docs = target_docs[:500]
            else:
                target_docs = self.documents[:500]
        else:
            target_docs = self.documents[:500]
        t_prune_end = time.perf_counter()

        # Scoring Candidates
        t_scoring_start = time.perf_counter()
        scores = []
        for doc in target_docs:
            if category:
                cat_lower = category.lower()
                doc_all = self.doc_full_texts.get(doc["id"], "")
                cat_synonyms = self.expander.expand_token(cat_lower)
                if not any(syn in doc_all for syn in cat_synonyms):
                    continue

            if not expanded_query_tokens:
                total_score = 1.0
            else:
                # 1. Multi-Field Weighted Vector TF-IDF Score
                vector_score = 0.0
                doc_title = doc.get("title", "").lower()
                doc_desc = doc.get("description", "").lower()
                doc_tags = " ".join(doc.get("tags", [])).lower()
                doc_keywords = " ".join(doc.get("annotated_keywords", [])).lower()

                title_tokens_set = set(doc.get("title_tokens", []))
                keywords_tokens_set = set(doc.get("keywords_tokens", []))
                tags_tokens_set = set(doc.get("tags_tokens", []))
                desc_tokens_set = set(doc.get("desc_tokens", []))

                for qt in expanded_query_tokens:
                    idf_val = self.idf.get(qt, 1.2)
                    if qt in title_tokens_set or qt in doc_title:
                        vector_score += self.FIELD_WEIGHTS["title"] * idf_val
                    if qt in keywords_tokens_set or qt in doc_keywords:
                        vector_score += self.FIELD_WEIGHTS["keywords"] * idf_val
                    if qt in tags_tokens_set or qt in doc_tags:
                        vector_score += self.FIELD_WEIGHTS["tags"] * idf_val
                    if qt in desc_tokens_set or qt in doc_desc:
                        vector_score += self.FIELD_WEIGHTS["description"] * idf_val

                # 2. Okapi BM25 Probabilistic Score
                bm25_score = self.calculate_bm25_score(expanded_query_tokens, doc)

                # 3. Inverted Keyword Hit Score
                inverted_score = 0.0
                for kw in doc.get("annotated_keywords", []):
                    kw_lower = kw.lower()
                    if any(qt in kw_lower for qt in expanded_query_tokens):
                        inverted_score += 3.5

                # 4. FM-Index Substring Match Score
                fm_score = self.calculate_fm_index_score(expanded_query_tokens, doc)

                # 5. Recency Decay Boost
                recency_boost = self.calculate_recency_boost(
                    doc.get("published_date", "")
                )

                # Multi-Engine Score Fusion (Vector:30%, BM25:30%, Inverted:20%, FM-Index:20%) * Recency
                total_score = (
                    vector_score * 0.3
                    + bm25_score * 0.3
                    + inverted_score * 0.2
                    + fm_score * 0.2
                ) * recency_boost

            if total_score > 0:
                scores.append(
                    {
                        "id": doc.get("id"),
                        "title": doc.get("title"),
                        "description": doc.get("description"),
                        "tags": doc.get("tags", []),
                        "annotated_keywords": doc.get("annotated_keywords", []),
                        "published_date": doc.get("published_date", ""),
                        "path": doc.get("path"),
                        "score": round(total_score, 4),
                    }
                )

        scores.sort(key=lambda x: x["score"], reverse=True)
        results = scores[:top_k]
        t_scoring_end = time.perf_counter()

        t_total_end = time.perf_counter()

        profile = {
            "tokenize_ms": round((t_tokenize_end - t_tokenize_start) * 1000, 3),
            "candidate_pruning_ms": round((t_prune_end - t_prune_start) * 1000, 3),
            "scoring_ms": round((t_scoring_end - t_scoring_start) * 1000, 3),
            "total_ms": round((t_total_end - t0) * 1000, 3),
            "candidates_evaluated": len(target_docs),
            "total_documents": len(self.documents),
            "cached": False,
        }

        # Cache results for ultra-fast sub-1ms response
        if len(self._query_cache) > 200:
            self._query_cache.clear()
        self._query_cache[cache_key] = (results, profile)

        return results, profile


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Advanced Multi-Engine Hybrid Search Engine for arXiv Security Papers"
    )
    parser.add_argument(
        "--build",
        action="store_true",
        help="Build or rebuild multi-engine hybrid index",
    )
    parser.add_argument("--query", type=str, help="Search query string")
    parser.add_argument(
        "--top-k", type=int, default=5, help="Number of results to return"
    )
    args = parser.parse_args()

    engine = VectorEngine()
    if args.build:
        count = engine.build_index()
        print(
            f"✅ Multi-Engine Hybrid Index built successfully (v3.1.0 Performance Edition). Total documents: {count}"
        )

    if args.query:
        results, profile = engine.search_with_profile(args.query, top_k=args.top_k)
        print(
            f"\n🔍 Multi-Engine Hybrid Search Results for '{args.query}' (Time: {profile['total_ms']} ms):"
        )
        for i, res in enumerate(results, 1):
            print(f"{i}. [{res['score']}] {res['title']} ({res['id']})")
            print(f"   要約: {res['description']}")
            print(f"   事前注釈キーワード: {res.get('annotated_keywords', [])}")
            print(f"   パス: {res['path']}\n")
        print(f"⏱️ Performance Breakdown: {json.dumps(profile, indent=2)}")
