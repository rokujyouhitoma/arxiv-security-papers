# Changelog

本ドキュメントは、「`arxiv-security-papers`」のすべての注目すべき変更を記録します。

フォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に基づき、
バージョニングは [Semantic Versioning](https://semver.org/lang/ja/) （メジャー.マイナー.パッチ）に準拠します。

---

## バージョニングポリシー

| バージョン種別 | 変更内容 |
| :--- | :--- |
| **メジャー** (`X.0.0`) | 後方互換性のない大規模な変更（アーキテクチャ全面改修、データ形式変更等） |
| **マイナー** (`0.X.0`) | 後方互換性のある新機能の追加（新Skill追加、新フェッチエンジン追加、自動化フック導入等） |
| **パッチ** (`0.0.X`) | 後方互換性のあるバグ修正・小改善（`__pycache__`除外、設定最適化、ドキュメント更新等） |

### 変更カテゴリ

- `[Added]` — 新機能の追加
- `[Changed]` — 既存機能の変更
- `[Deprecated]` — 将来削除予定の機能の案内
- `[Removed]` — 機能の削除
- `[Fixed]` — バグ修正
- `[Security]` — セキュリティ関連の修正
- `[Docs]` — ドキュメントの追加・更新

---

## [Unreleased]

### [Added]
- **Graph Engineering Dashboard & Context Mesh 可視化基盤 (`site/dashboard.html` / DSN-14)**:
  - **ゼロ外部依存 (Zero Dependencies)**: 外部ライブラリ（React/Vue/Tailwind/D3.js/Chart.js）や外部 CDN スクリプトを一切排除し、Pure JavaScript (ES6+), Vanilla CSS3, HTML5 Canvas API のみで完結する単一スタンドアロンダッシュボードを新規実装
  - **力学モデル (Force-Directed Layout) 物理演算エンジン**: クーロン反発力 ($F_{\text{rep}} = k_r / r^2$)、フックのバネ引力 ($F_{\text{spring}} = k_s \cdot (r - l_0)$)、重心復元力、摩擦減衰 (0.86)、および境界クランプを自律計算する 60 FPS Canvas レンダリングエンジン
  - **4大クラスタ・データモデル (arxiv-security-papers テーラリング)**: `Sources` (論文・情報源), `Entities` (脅威・暗号要素), `Claims` (脆弱性・証明), `Decisions` (推奨対策・パッチ)
  - **スイススタイル・レトロデザイン UI**: レトロオフホワイト (`#f4efe6`) 背景、1px シャープボーダー (`#2b2b2b`)、モノスペースタイポグラフィ
  - **リアルタイムテレメトリ & 5大分析パネル**:
    - トップ KPI (Resolved Nodes, Edges/Tick, Walks/Min, Latency, Token Savings)
    - パイプライン進捗ステータスバー (CHUNK $\to$ EXTRACT $\to$ RESOLVE $\to$ LINK $\to$ EMBED $\to$ PRUNE)
    - Hop Budget ヒストグラム (深度 1〜5)
    - Edge Ledger リレーショントラフィック横棒バーチャート
    - Walk vs Flat トークン削減時系列エリアチャート (74.2% 削減)
    - Traversal Grid 動的ドットマトリクス (100セル)
    - Dead-End Ledger 失敗原因内訳 & 自己修復率 (100%)
  - `src/web/gateway/handlers.py`: `/dashboard` および `/dashboard.html` への静的ルーティング統合
  - `tests/web/test_dashboard_html.py`: 外部 CDN リンク 0 件アサーションおよびルーティング単体テストを追加
  - `docs/designs/DSN-14-graph_engineering_dashboard.md`: DSN-05 形式に準拠した包括的詳細アーキテクチャ設計書の策定
- **ゼロ依存 Pure Python PDF テキスト抽出 & 空間レイアウト再構築エンジン (`src/pdf_engine/`) (DSN-13)**:
  - **ISO 32000-1:2008 (PDF 1.7) & ISO 32000-2:2020 (PDF 2.0) 完全準拠**: Poppler / `pdftotext` などの外部バイナリに一切依存せず、Python 3.14+ 標準ライブラリのみで動作する PDF テキスト抽出サブシステムを新規実装
  - **コアモジュール群**:
    - `parser.py`: ISO 32000-1 Clause 7.2/7.3 準拠のゼロコピー字句解析器（`PdfLexer`）および再帰オブジェクトパーサー（`PdfParser`）
    - `xref.py`: Clause 7.5 準拠の古典的 `xref` テーブル、PDF 1.5+ 圧縮 `/Type /XRef` ストリーム（可変長バイト幅 `/W`）、および `/Type /ObjStm` オブジェクトストリームのオンデマンド解決
    - `decompress.py`: Clause 7.4 準拠の `/FlateDecode`（`zlib`）、`/ASCIIHexDecode`、`/ASCII85Decode`、および Table 8 PNG Predictor（None/Sub/Up/Average/Paeth）差分解除
    - `navigator.py`: Clause 7.7 準拠の `/Catalog` $\to$ `/Pages` ツリー深さ優先走査と `/Resources`（`/Font`）のスコープ継承解決
    - `font.py`: Clause 9.6-9.10 準拠の `/ToUnicode` CMap パーサー（`bfchar`, `bfrange`）、`/Differences` 配列 + AGL（Adobe Glyph List）解決、数学記号・ギリシャ文字・リガチャ（合字: fi, fl, ff 等）正規化
    - `interpreter.py`: Clause 8.3 & 9.2-9.4 準拠の Content Stream テキストオペレータ（`BT`, `ET`, `Tf`, `Tm`, `Td`, `TD`, `T*`, `Tj`, `TJ`, `'`, `"`）のステートマシン実行器と変換行列（$T_m, T_{lm}, CTM$）追跡
    - `layout.py`: 2次元幾何空間配置、arXiv 2段組（Two-Column）ガター境界自動検出、読書順序（ヘッダー $\to$ 左カラム $\to$ 右カラム $\to$ フッター）ソート、行クラスタリング、単語間スペース補正、行末ハイフネーション結合（De-hyphenation）
    - `extractor.py` & `__main__.py`: 高水準統一インターフェース（ファイルパス、バイナリバイト列、BytesIO 対応）および CLI ランナー
    - `benchmark.py`: 蓄積済み実 PDF 論文群に対する自動精度評価・回帰ベンチマークツール
  - `src/pipeline/ingestion/pdf_extractor.py`: `fetch_single_pdf_and_text` 内で `PurePdfTextExtractor` を優先実行し、パース失敗時のみ `pdftotext` CLI にフォールバックする二重防護体制を統合
  - `docs/designs/DSN-13-pure_python_pdf_text_extractor.md`: DSN-05 形式に準拠した包括的詳細設計書（ISO 32000 仕様分析、数理モデル、14,449件実データ検証計画）の策定

### [Fixed]
- **論文モーダルプレビューが「読み込み中...」のまま停止する不具合の修正 (Issue 079)**:
  - `src/web/gateway/handlers.py`: `/api/paper/<clean_id>` エンドポイントにおいて、ディスク上の OKF Markdown 実体（`outputs/okf_papers/...`）を自動探索・オンデマンド読み込みし、API レスポンスに `content` および `path` を付与するように改修
  - `site/app.js`: `openPaperModal` において `data.content` と `data.paper` の双方からタイトル・概要・本文を即座に安全抽出・HTML 展開し、ロード停止を根絶
  - `tests/web/gateway/test_gateway.py`: `test_gateway_handle_paper_with_content` 単体テストを追加
- **Supervisor Arbiter ローリングリロード時の `control.sock` 保護**:
  - `src/supervisor/control.py`: ローリングリロード（`SIGQUIT`）時に終了する子プロセスが親 Arbiter の UNIX ドメインソケット（`control.sock`）を誤って unlink 削除する問題を修正し、`_creator_pid` チェックおよび atexit unregister を導入
  - `tests/supervisor/test_control.py`: 子プロセス終了時のソケット保持を検証する単体テストを追加
- **YAML Frontmatter 内のエスケープ引用符パーサー修正 & サマリー全件再生成**:
  - `src/pipeline/reporter/summary_generator.py` および `index_updater.py`: YAML Frontmatter 内のエスケープ引用符（`\"`）を正確にアンエスケープする正規表現パーサーを導入し、タイトル途切れ（`[When \]`）を解消
  - `outputs/executive_summaries/`（02_daily, 03_monthly, 04_quarterly, 05_annual）および `outputs/index.md` の全マークダウンサマリーを再生成

### [Changed]
- **Python 3.14.7 ランタイム移行 ＆ .venv 仮想環境の再構築 (Issue 009)**:
  - 開発・実行ランタイムを Python 3.14.7 (`~/.local/python-3.14.7/bin/python3`) へアップグレードし、`.venv` 仮想環境を再作成
  - `requirements.txt`: Python 3.14.7 に適合した最新解析ツール群 (`isort-8.0.1`, `black-26.5.1`, `flake8-7.3.0`, `mypy-2.3.1`, `pytest-9.1.1`, `poetry-2.4.1` 等) を完全導入
  - `Makefile`: `PYTHON` パス解決ロジックを更新し、`~/.local/python-3.14.7/bin/python3` を優先検出するように設定
  - `pyproject.toml`: 依存 Python バージョンを `>=3.14` に更新し、`[tool.mypy]` の `python_version = "3.14"` へ同期
  - `tests/test_web_server.py`: `WSGIApplication` の型アサーションテストを追加し、flake8 F401 警告を解消
  - `docs/designs/DSN-01-high_level_design.md` & `docs/designs/DSN-02-low_level_design.md`: Python 3.14.7 実行仕様およびディレクトリツリー表記を更新

### [Added]
- **アブストラクト全文の重み付けインデックス拡張 ＆ VectorEngine 検索再現率の向上 (Issue 008)**:
  - `src/vector_engine.py`: OKF マークダウンから原本アブストラクトを自動抽出する `extract_abstract_from_okf()` を実装し、`abstract_tokens` としてインデックスへ保持
  - マルチフィールド重み付け辞書 `FIELD_WEIGHTS` に `abstract: 1.5`（Title: 3.5, Tags: 3.0, Keywords: 4.0, Description: 2.5, Abstract: 1.5）を統合し、タイトルに含まれない評価対象モデル（例: `Claude Mythos`, `GPT-5.5`, `CyberGym` 等）の本文言及論文を網羅的にヒット可能に改善
  - `outputs/vector_db/index.json`: 全 14,169 件の OKF ドキュメントのアブストラクトトークンを再インデックス化し、キャッシュ時 `< 1ms` の超高速検索性能を維持
  - `tests/test_vector_engine.py`: アブストラクト抽出およびモックアブストラクト検索テストを追加し、全 23 件のテストが 100% PASS
  - `docs/designs/DSN-05-multi_engine_hybrid_search.md`: アブストラクトインデックス化仕様および重み付け設計を更新
- **PEP 3333 WSGI Web サーバー ＆ MCP ゲートウェイ統合 (Issue 007)**:
  - `src/web_server.py`: Python 標準 Web サーバー共通仕様である **PEP 3333 (WSGI v1.0.1)** に完全準拠した `WSGIApplication` および `application(environ, start_response)` エントリポイントの実装
  - Gunicorn / uWSGI / `wsgiref` によるマルチワーカー本番ホストおよびコンテナデプロイ対応
  - `src/mcp_server.py`: `--http` オプションによる HTTP/WSGI サーバーダイレクト起動機能の追加
  - `tests/test_web_server.py`: WSGI `environ` モックを用いた 12 項目の単体テスト（API ルーティング、CORS ヘッダー、パストラバーサル防御、不正 JSON エラーハンドリング）の拡充
  - `docs/designs/DSN-07-web_portal_and_markdown_compiler.md`: WSGI アーキテクチャ構成図および Gunicorn 連携仕様の追記
- **5手法統合マルチエンジン・ハイブリッド検索 ＆ 自動特徴語抽出・事前注釈 (Issue 006)**:
  - `src/vector_engine.py` (v3.0.0): **転置インデックス (Inverted Index)**、**Okapi BM25 確率ランク ($k_1=1.5, b=0.75$)**、**FM-Index (BWT/Suffix Array による部分文字列高速検索)**、**ベクトル概念 TF-IDF**、および **時間減衰 Recency Boost** を融合した 5 手法統合ハイブリッド検索エンジンの実装
  - `extract_feature_keywords`: セキュリティパターン抽出およびドメイン専門用語頻度解析による自動特徴語抽出・事前注釈 (`annotated_keywords`) 機能の導入
  - `src/synonym_expander.py`: Web, AI/LLM, System/IoT, Quantum, SOC/Incident 等のセキュリティドメインシノニム辞書の飛躍的拡充
  - `tests/test_vector_engine.py`: FMIndex 単体テストおよびマルチエンジンフュージョン検索テストの追加
- **Google Closure Compiler ツール統合 ＆ JS モジュール分割 (Issue 005 & Issue 004)**:
  - `yuzora` リポジトリの仕様に準拠し、`tools/closure-compiler/closure-compiler-v20240317.jar` を配備し `Makefile` に `make build_js` ターゲットを追加
  - `site/js/`: Lexer (`lexer.js`), Parser (`parser.js`), Evaluator (`evaluator.js`), Renderer (`renderer.js`), Orchestrator (`markdown_compiler.js`) にファイル分割モジュール化し、`site/externs.js` による型保護と Closure Compiler 最適化ミニファイ (`site/app-min.js`) を実現
  - `docs/designs/DSN-01-high_level_design.md` および `DSN-02-low_level_design.md` にモジュール構造とビルド仕様を反映
- **Glassmorphism Web 検索 UI ＆ MCP バックエンドサーバー (Issue 003)**:
  - `src/web_server.py`: REST API (`/api/search`, `/api/paper/`, `/api/trends`, `/api/mcp`) および静的 Web 配信を提供する Python HTTP サーバーの構築
  - `site/`: リッチ Glassmorphism ダークモード Web UI (`index.html`, `style.css`, `app.js`) を開発 (リアルタイム RAG 検索, OKF モーダルプレビュー, Mermaid マインドマップ動的描画, MCP JSON-RPC テストサンドボックス統合)
  - `Makefile`: `make run_web` コマンドを追加し、`http://localhost:8000` での即時ポータル起動を実現
- **セキュリティ専門用語シノニム拡張 ＆ マルチフィールドハイブリッド検索エンジン (Issue 002)**:
  - `registered-information-security-specialist-examination` の高品質モジュール設計を参考に、`src/synonym_expander.py` (日英セキュリティ用語相互拡張) を開発・統合
  - `src/vector_engine.py` (v2.0.0): フィールド重み付け (Title:3.5, Tags:3.0, Description:2.5, Abstract:1.5) とシノニム展開を組み込んだハイブリッド検索スコアを実装 (適合率大幅向上)
- **[MNG-01] 文書管理台帳 ＆ `docs/` ディレクトリ統廃合**:
  - `docs/processes/MNG-01-document_ledger.md`: ゆうぞら (Yuzora) 標準仕様をテーラリングした文書管理台帳およびプレフィックス管理体系 (MNG, REQ, DSN, MCP, ISS) の導入
  - `docs/` 配下を `processes/`, `requirements/`, `designs/`, `mcp/`, `issues/` に構造化し、`docs/README.md` マスターポータルを作成
- **MCP サーバ ＆ ベクトル DB セマンティック検索基盤 (Issue 001)**:
  - `src/vector_engine.py`: 14,000件以上の全 OKF 論文ドキュメントを永続インデックス化するセマンティックベクトル＋BM25ハイブリッド検索エンジンの実装
  - `src/mcp_server.py`: 標準 Model Context Protocol JSON-RPC サーバを実装し、4大 MCP ツール (`search_security_papers`, `get_paper_summary`, `get_latest_trends`, `query_attack_technique`) を提供
  - `.agents/mcp_config.json`: ワークスペース用 MCP サーバ自動登録設定の配置
  - `Makefile`: `make build_vector_db`, `make run_mcp_server`, `make rag_query Q="クエリ"` ターゲットの追加
- **Antigravity IDE & 2.0 連携機能**:
  - `schedule` ツールによる **1日4回 (00:00, 06:00, 12:00, 18:00 UTC/JST)** のバックグラウンド自動実行 Cron タスクの構築
  - Artifacts および Mermaid マインドマップによる最新動向のリアルタイム可視化
  - ブラウザ自動化 Subagent (`browser_subagent`) による外部 CVE / NIST SP 800 / MITRE ATT&CK 情報の自動検証機能
- **高度インテリジェンス Skill 群 (4件)**:
  - `paper-trend-analyzer`: 論文テキストマイニングによる急上昇キーワード検出および Mermaid マインドマップ自動挿入
  - `backfill-pipeline`: 過去160日間の論文データの安全フェッチ・PDF抽出・OKF変換・5層サマリー再集計
  - `threat-model-tagger`: MITRE ATT&CK テクニック ID、STRIDE 脅威分類、CWE 関連性の自動マッピング
  - `health-check-monitor`: arXiv API/RSS 疎通状況、`pdftotext` 抽出成功率、`processed_papers.json` 健全性の自動診断
- **Git 統合 & Pre-commit フック**:
  - `.agents/hooks.json` によるコミット前全自動構文チェック (`make py_compile`) および絶対パス排除ガバナンスフック

### [Changed]
- **ディレクトリ構造再編成**:
  - `arxiv_okf_fetcher.py` を `src/arxiv_okf_fetcher.py` へ移動し、Python 標準パッケージ構成（`src/`）に適合
  - 単体テストスイート `tests/test_fetcher.py` を追加し、`pytest` によるカバレッジ自動計測を整備
- **Skill & Agent 統廃合**:
  - 旧試験対策用リポジトリの Skill・Agent・ルールを全廃し、`arxiv-security-papers` 専有版へ刷新
  - `refine-content-data` を `refine-okf-data` に改称し、OKF ドキュメントおよび要約推敲専用手順へリビルド
  - `verify-quality-gates` を Python 構文・OKF仕様・相対パス・冪等性アサーションへ強化
- **ビルド・依存管理**:
  - `python-project-template` より `Makefile` を導入し、`.venv` 仮想環境および `requirements.txt` 依存管理と統合

### [Fixed]
- **[Fixed]** `__pycache__` ディレクトリおよび `.pyc` バイトコードファイルが Git に誤追跡されていた不具合を修正し、インデックスから完全削除

---

## [0.2.0] - 2026-08-15

### [Changed]
- **サマリー階層再編成**:
  - 06_semi_annual（半期サマリー）を完全廃止
  - エグゼクティブサマリーディレクトリを 5 階層連続項番（`01_per_run`, `02_daily`, `03_monthly`, `04_quarterly`, `05_annual`）へ再定義・ソート可能化

---

## [0.1.0] - 2026-08-14

### [Added]
- **コアフェッチエンジン (`arxiv_okf_fetcher.py`) 初期リリース**:
  - arXiv API (`cs.CR`) からの論文メタデータフェッチ、arXiv RSS 自動フォールバック機能
  - 原本保存 (`<clean_id>_meta.json`, `<clean_id>_raw_abstract.txt`, `<clean_id>.pdf`, `<clean_id>.txt`)
  - Google OKF (Open Knowledge Format) v0.2 スキーマへの自動変換
  - `processed_papers.json` による重複排除・冪等性管理
  - 動的テンプレート (`templates/`) による 5 階層エグゼクティブサマリー自動レンダリング機構

[Unreleased]: https://github.com/rokujyouhitoma/arxiv-security-papers/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/rokujyouhitoma/arxiv-security-papers/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rokujyouhitoma/arxiv-security-papers/releases/tag/v0.1.0
