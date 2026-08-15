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

### 1.2 ベクトル検索エンジンモジュール ([`src/vector_engine.py`](../../src/vector_engine.py))

#### `VectorEngine(workspace_dir=None)`
- **クラス概要**: 全 OKF ドキュメントを解析し、セマンティックベクトル＋BM25ハイブリッド検索インデックス（`outputs/vector_db/index.json`）を維持・検索。

#### `tokenize(text: str)` -> `list[str]`
- **アルゴリズム**: 英語アルファベット・数値トークンおよび日本語文字（ひらがな・カタカナ・漢字）を正規表現抽出。

#### `build_index()` -> `int`
- **目的**: `outputs/okf_papers/` 配下の全 `.md` ファイルを走査し、TF-IDF 重み付け計算および語彙辞書作成を行い `outputs/vector_db/index.json` に永続保存。

#### `search(query: str, top_k: int = 5, category: str = None)` -> `list[dict]`
- **目的**: 検索クエリに対するスコアリング（TF-IDF + 完全一致ボーナス 2.0）を行い、上位 `top_k` 件の適合論文リストをスコア順で返却。

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

### 2.1 ベクトルインデックス JSON スキーマ (`outputs/vector_db/index.json`)
```json
{
  "version": "1.0.0",
  "updated_at": "2026-08-15T21:05:40+09:00",
  "total_documents": 14169,
  "documents": [
    {
      "id": "2606.07005",
      "title": "The Sound of Malware",
      "description": "要約本文...",
      "tags": ["cs.CR", "malware"],
      "path": "outputs/okf_papers/2026-06-05/2606.07005.md"
    }
  ],
  "idf": {
    "malware": 3.452,
    "security": 1.021
  }
}

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

build_js:
	python3 tools/closure-compiler/setup_compiler.py
	java -jar $(COMPILER) \
		--compilation_level SIMPLE_OPTIMIZATIONS \
		--warning_level VERBOSE \
		--language_in ECMASCRIPT_NEXT \
		--language_out ECMASCRIPT_2020 \
		--externs site/externs.js \
		--js $(JS_SRCS) \
		--js_output_file $(JS_OUT)
```
```
