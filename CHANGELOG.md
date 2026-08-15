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
