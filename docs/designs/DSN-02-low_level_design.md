# [DSN-02] 詳細設計書 (Low-Level Design - LLD) - arxiv-security-papers

本ドキュメントは、「`arxiv-security-papers`」プロジェクトのモジュール構造、関数シグネチャ、アルゴリズム、データ構造、およびファイルパス解決ロジックを物理レベルで詳細に定義する詳細設計書です。

---

## 1. モジュールおよび関数仕様

### 1.1 パイプライン・OKF 変換モジュール ([`src/arxiv_okf_fetcher.py`](../../src/arxiv_okf_fetcher.py))

#### `load_config()` -> `dict`
- **目的**: システム設定 `config.json` をロード。
- **パス解決順序**: `src/../config.json` ➔ `src/config.json` ➔ `abspath("config.json")`

#### `save_raw_paper_data(paper: dict, workspace_dir: str, config: dict)` -> `str`
- **目的**: 原論文データの個別保存 (`outputs/raw_data/YYYY-MM-DD/`)。
- **生成ファイル**: `<clean_id>_meta.json`, `<clean_id>_raw_abstract.txt`, `<clean_id>.pdf`, `<clean_id>.txt`

#### `fetch_single_pdf_and_text(paper: dict, raw_dir: str)` -> `tuple[bool, bool]`
- **目的**: `ThreadPoolExecutor` により arXiv より PDF を直接並列ダウンロードし、`pdftotext` により全文 TXT を抽出。

#### `build_okf_from_raw(raw_meta_path: str, workspace_dir: str, config: dict)` -> `dict`
- **目的**: Google OKF v0.2 仕様準拠の YAML フロントマター付き Markdown ドキュメントを作成し、`outputs/okf_papers/YYYY-MM-DD/<clean_id>.md` へ保存。

---

### 1.2 5手法統合マルチエンジン検索モジュール ([`src/vector_engine.py`](../../src/vector_engine.py))

#### `FMIndex(text: str)`
- **クラス概要**: Suffix Array / Burrows-Wheeler Transform (BWT) に基づく軽量全文部分文字列インデックス。
- **`count_substring(query: str) -> int`**: Suffix Array 上の二分探索により、日本語・英語問わず任意の完全部分文字列出現回数を $O(\log N)$ で計数。

#### `VectorEngine(workspace_dir=None)`
- **クラス概要**: 5 大検索エンジン（ベクトル概念 TF-IDF、Okapi BM25、転置インデックス、FM-Index、最新性減衰ブースト）を維持・統合フュージョン検索。

#### `tokenize(text: str) -> list[str]`
- **アルゴリズム**: 英数字トークン、日本語単語、および日本語 2-gram / 3-gram 文字 N-gram を抽出し、部分一致適合率を高精度化。

#### `extract_feature_keywords(title: str, desc: str, content: str) -> list[str]`
- **自動注釈**: セキュリティ知識パターン（マルウェア解析, ペンテスト, 自動運転, 暗号, LLM脱獄, ファジング, ゼロトラスト, サイドチャネル）および高頻度ドメイン専門用語を自動抽出・事前注釈。

#### `calculate_bm25_score(query_tokens: list, doc: dict) -> float`
- **確率的ランク**: $BM25(q, d) = \sum IDF(t) \cdot \frac{f(t,d)(k_1+1)}{f(t,d)+k_1(1-b+b\frac{|d|}{avgdl})}$ ($k_1=1.5, b=0.75$) による長さ正規化スコア計算。

#### `search(query: str, top_k: int = 5, category: str = None) -> list[dict]`
- **フュージョンスコア**: Vector (30%) + BM25 (30%) + Inverted Keywords (20%) + FM-Index (20%) の加重和に対し、経過時間による Recency Decay Boost ($1.0 + 0.5 \cdot e^{-\Delta days/180}$) を乗算してソート返却。

---

### 1.3 MCP サーバモジュール ([`src/mcp_server.py`](../../src/mcp_server.py))

#### `is_safe_workspace_path(file_path: str)` -> `bool`
- **セキュリティ検証**: `os.path.realpath(file_path)` を呼び出し、パスが `WORKSPACE_DIR` 内に収まっているか、および敏感ファイル (`.ssh`, `.env`, `etc/passwd`) を含まないかを検査。

#### `handle_search_security_papers(args: dict)` -> `dict`
- **MCP ツール処理**: `search_security_papers` のリクエストを処理し、検索結果オブジェクトを返却。

#### `handle_get_paper_summary(args: dict)` -> `dict`
- **MCP ツール処理**: 指定された `arxiv_id` の OKF ドキュメントおよび日本語サマリーを安全検証付きで取得。

#### `run_jsonrpc_server()`
- **通信規格**: Standard stdio MCP JSON-RPC 2.0 サーバーのメインループ。`tools/list` および `tools/call` メソッドに応答。

---

## 2. 成果物データ構造・テンプレート仕様

### 2.1 ベクトル ＆ 高度多段階インデックス JSON スキーマ (`outputs/vector_db/index.json`)
```json
{
  "version": "2.0.0",
  "updated_at": "2026-08-16T17:20:00+09:00",
  "total_documents": 14169,
  "documents": [
    {
      "id": "2606.07005",
      "title": "The Sound of Malware",
      "description": "要約本文...",
      "tags": ["cs.CR", "malware"],
      "published": "2026-06-05",
      "path": "outputs/okf_papers/2026-06-05/2606.07005.md",
      "annotated_keywords": ["マルウェア", "サイドチャネル"],
      "pagerank": 0.00142
    }
  ],
  "idf": {
    "malware": 3.452,
    "security": 1.021
  },
  "facets": {
    "years": {"2026": [0, 1, 2]},
    "categories": {"cs.CR": [0, 1, 2]},
    "tags": {"malware": [0]}
  },
  "knowledge_graph": {
    "nodes": [
      {"id": "CVE-2026-1001", "type": "vulnerability"},
      {"id": "SoundMalware", "type": "attack_technique"}
    ],
    "edges": [
      {"source": "SoundMalware", "target": "CVE-2026-1001", "relation": "exploits"}
    ]
  },
  "citation_network": {
    "citations": {
      "2606.07005": ["2605.01234"]
    },
    "pagerank": {
      "2606.07005": 0.00142
    }
  },
  "raptor_tree": {
    "clusters": [
      {
        "id": "cluster-001",
        "level": 1,
        "summary": "音響サイドチャネルマルウェアおよび攻撃手法の包括的動向",
        "doc_ids": ["2606.07005"]
      }
    ]
  },
  "proximity_graph": {
    "2606.07005": [
      {
        "target_id": "2605.01234",
        "title": "Acoustic Side-Channel Attacks",
        "similarity": 0.884,
        "shared_keywords": ["サイドチャネル", "マルウェア"]
      }
    ]
  }
}
```

---

## 3. Markdown Compiler Engine モジュール構造仕様 (`site/js/`)

### 3.1 Lexer モジュール ([`site/js/lexer.js`](../../site/js/lexer.js))
- **クラス**: `MarkdownLexer`
- **目的**: マークダウン文字列を行・ブロック単位でトークナイズ。
- **対応トークン**:
  - `HEADING`: `#`, `##`, `###` 見出し
  - `TABLE`: `| Col1 | Col2 |` マークダウンテーブル
  - `MERMAID`: ```mermaid ブロック
  - `CODE_BLOCK`: ```lang コードブロック
  - `LIST`: `- item` リスト
  - `BLOCKQUOTE`: `> text` 引用
  - `HR`: `---` 水平線
  - `PARAGRAPH`: 通常段落テキスト

### 3.2 Parser モジュール ([`site/js/parser.js`](../../site/js/parser.js))
- **クラス**: `MarkdownParser`
- **目的**: トークンストリームから抽象構文木 (`DocumentNode` AST) を構築。

### 3.3 Evaluator モジュール ([`site/js/evaluator.js`](../../site/js/evaluator.js))
- **クラス**: `MarkdownEvaluator`
- **目的**: AST ノードを走査し、インライン装飾（`**太字**`, `` `コード` ``, `[リンク](url)`）のトランスフォームおよび Mermaid ID のユニーク割り当てを実施。

### 3.4 Renderer モジュール ([`site/js/renderer.js`](../../site/js/renderer.js))
- **クラス**: `MarkdownRenderer`
- **目的**: AST から HTML5 DOM 要素（`.md-table`, `.md-h1`〜`.md-h3`, `.md-blockquote`）を生成し、`mermaid.run()` を非同期実行して図を描画。

### 3.5 Compiler Orchestrator ([`site/js/markdown_compiler.js`](../../site/js/markdown_compiler.js))
- **クラス**: `MarkdownCompilerEngine`
- **公開インタフェース**: `window.MarkdownCompiler.compile(rawMarkdown)` ＆ `window.MarkdownCompiler.renderMermaid(container)`

---

## 4. Google Closure Compiler ツール ＆ ビルド仕様 (`yuzora` 準拠)

### 4.1 ツール配置 (`tools/closure-compiler/`)
- `tools/closure-compiler/closure-compiler-v20240317.jar`: Google Closure Compiler 本体 JAR
- `tools/closure-compiler/setup_compiler.py`: JAR 自動取得・バックアップスクリプト
- `tools/closure-compiler/LICENSE`: Apache 2.0 ライセンス

### 4.2 外部シンボル保護 (`site/externs.js`)
- Closure Compiler 最適化時に、`mermaid`, `MarkdownCompiler`, `fetch`, `history`, `performance` などの外部シンボル名が縮小改変（Rename）されるのを防止する型定義宣言ファイル。

### 4.3 Makefile ビルド定義
```makefile
COMPILER = tools/closure-compiler/closure-compiler-v20240317.jar
JS_SRCS = site/js/lexer.js \
          site/js/parser.js \
          site/js/evaluator.js \
          site/js/renderer.js \
          site/js/markdown_compiler.js \
          site/app.js
JS_OUT = site/app-min.js

build_js: activate
	${VENV_PYTHON} tools/closure-compiler/setup_compiler.py
	java -jar $(COMPILER) \
		--compilation_level SIMPLE_OPTIMIZATIONS \
		--warning_level VERBOSE \
		--language_in ECMASCRIPT_NEXT \
		--language_out ECMASCRIPT_2020 \
		--externs site/externs.js \
		--js $(JS_SRCS) \
		--js_output_file $(JS_OUT)
```
