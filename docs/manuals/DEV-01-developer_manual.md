# [DEV-01] 開発者マニュアル ＆ 品質検証ガイド (Developer Manual)

---

## 1. 開発者向けアーキテクチャ ＆ リポジトリ構成 (Architecture & Source Layout)

本リポジトリ `arxiv-security-papers` は、学術論文の自動収集から原本保存、Google Open Knowledge Format (OKF) v0.2 構造化変換、W3C OWL 2.0 オントロジー (TBox) 生成、プロパティグラフDB (ABox) 構築、4段階ハイブリッド検索エンジン (Dense + BM25 + GraphRAG)、Glassmorphic Web ポータル、および 4 大 Model Context Protocol (MCP) サーバー群までを内包する統合セキュリティインテリジェンス基盤です。

### 1.1 ソースコードディレクトリ構成 (`src/`)

すべてのコアコンポーネントは `src/` 配下に完全ゼロ外部依存（Zero External Dependencies）を指向してモジュール化されています。

```text
src/
├── __main__.py          # 統合 CLI エントリポイント (cycle, pir, harvest, credibility, etc.)
├── analytics/           # 戦略 KPI および脅威アナリティクス集計エンジン
│   ├── aggregator.py    # バッチ事前集計ロジック
│   └── cli.py           # アナリティクス CLI
├── core/                # システム共通データ構造・基盤アルゴリズム
│   └── structures/      # Roaring Bitmap, Bloom Filter, Trie, SkipList 等
├── database/            # ゼロ外部依存 自作データベースエンジン (DSN-05, DSN-14)
│   ├── engine.py        # 4KB SlottedPage, 2Q Buffer Pool, WAL & ARIES リカバリ
│   ├── storage/         # B+Tree, LSM-Tree, PAX 列指向ストレージ
│   └── transaction/     # MVCC, SS2PL トランザクション管理
├── graph/               # プロパティグラフDB & CTI ナレッジグラフ (DSN-18)
│   ├── engine.py        # Dual CSR (Compressed Sparse Row) 高速グラフ探索
│   └── cli.py           # グラフ構築 (--backfill) および探索 CLI (query)
├── intelligence/        # 閉ループ自律インテリジェンス・オーケストレーター (DSN-15)
│   ├── orchestrator.py  # 6フェーズ閉ループライフサイクル統制
│   ├── pir.py           # 3-Horizon PIR (優先インテリジェンス要件) 管理
│   ├── router.py        # 自律型自己修復ハーベストルーター & サーキットブレーカー
│   └── bayesian.py      # ベイズ仮説検証エンジン
├── mcp/                 # Model Context Protocol (MCP) JSON-RPC 2.0 サーバー群 (DSN-08)
│   ├── papers_server.py         # 学術知見・論文検索 MCP サーバー
│   ├── observability_server.py  # コード観測・プロファイラ MCP サーバー
│   ├── threat_defense_server.py # 脅威防御・パッチ生成 MCP サーバー
│   └── tech_radar_server.py     # 技術レーダー・動向予測 MCP サーバー
├── ontology/            # W3C OWL 2.0 / Turtle オントロジー基盤 (DSN-17, DSN-22)
│   ├── schema.py        # オントロジー述語・クラス仕様の単一情報源 (SSOT)
│   └── turtle_engine.py # Pure-Python Turtle (.ttl) シリアライザー & CLI
├── pdf_engine/          # ISO 32000 準拠 Pure-Python PDF 解析エンジン (DSN-13)
│   ├── extractor.py     # ゼロコピー字句解析、2段組レイアウト再構築
│   └── benchmark.py     # PDF 抽出エンジンパフォーマンステスト
├── pipeline/            # 論文収集・ETL・OKF変換・サマリー生成 (DSN-03)
│   ├── arxiv_okf_fetcher.py # arXiv API/RSS 収集・原本保存・OKF 変換
│   └── summary_generator.py # 5階層サマリー自律生成 (01_per_run 〜 05_annual)
├── search/              # 2層検索エンジン ＆ 検索プラットフォーム (DSN-04)
│   ├── core/            # Lucene パラダイム BM25 コアエンジン
│   ├── platform/        # Solr パラダイム ManagedSchema & キャッシュ
│   └── vector/          # HNSW セマンティックベクトル検索 & RRF 融合
├── security/            # 共通セキュリティ基盤・AST ガード & RBAC (DSN-07)
│   └── cti/             # MITRE ATT&CK / CWE / CVE 統合インジェスト (DSN-20)
├── spider/              # 分散 Web クローラー & スパイダー基盤 (DSN-06)
├── supervisor/          # プリフォーク型プロセススーパーバイザー & アービター (DSN-12)
├── web/                 # WSGI API Gateway & プレゼンテーション (DSN-09, DSN-21)
└── workflow/            # 常駐型スケジューラー & 汎用ワークフロー (DSN-11)
```

### 1.2 設計仕様書 (DSN) へのトレーサビリティ

機能追加や内部改修を行う際は、必ず対応する設計ドキュメントを参照してください：
- 全体基本設計: [[DSN-01] 全体高位アーキテクチャ設計書 (HLD)](../designs/DSN-01-high_level_design.md)
- 詳細設計・プロトコル: [[DSN-02] 全体低位アーキテクチャ設計書 (LLD)](../designs/DSN-02-low_level_design.md)
- 文書管理基準: [[MNG-01] 文書管理・ドキュメント台帳](../processes/MNG-01-document_ledger.md)

---

## 2. 開発環境セットアップ (`make setup`)

本リポジトリは、開発者がスムーズにオンボーディングできるよう、`Makefile` による一括セットアップを提供しています。

### 2.1 前提環境要件
- **OS**: Linux (Ubuntu 22.04 / 24.04 LTS 推奨), macOS, または WSL2
- **Python**: 3.14 以上（Python 3.14.7 標準動作確認済み）
- **システムツール**: `git`, `make`, `curl`
- ※ PDF 解析は内製 Pure-Python エンジン（`src/pdf_engine/`）で動作するため、`poppler-utils` や `pdftotext` のシステムインストールは不要です。

### 2.2 開発環境の初期構築

リポジトリ直下で `make setup` を実行します。

```bash
# 仮想環境の構築、開発・テスト依存パッケージのインストール、Git フックの登録
make setup
```

`make setup` は以下の処理を自動実行します：
1. `.venv` ディレクトリに Python 3.14 仮想環境を初期化。
2. 開発・リント・テスト・型検査に必要なパッケージ群（`pytest`, `pytest-cov`, `black`, `isort`, `flake8`, `mypy`, `radon`, `xenon` 等）をインストール。
3. コミット時品質検証のための Git フックを登録。

### 2.3 データベース統合管理 CLI による整合性確認 (`manage.py`)

本リポジトリでは、Django スタイルの統合管理 CLI `manage.py`（DSN-24 準拠）を提供しています。セットアップ後やデータベース・ストレージ層の改修時には、以下のサブコマンドで整合性を検証できます。

```bash
# 1. マウントされている全データベースおよび仮想テーブルの整合性と行数を確認
./manage.py tables

# 2. 実テーブル（例: processed_papers）のスキーマ定義とサンプルレコードをインスペクション
./manage.py inspect processed_papers

# 3. 対話型 SQL シェルによる直接クエリ検証（または -c によるワンライナー実行）
./manage.py dbshell -c "SELECT clean_id, title FROM processed_papers LIMIT 3;"

# 4. CTI カタログスコープに対する直接 SQL クエリ検証
./manage.py dbshell -d cti_catalog_db -c "SELECT technique_id, name FROM cti_techniques LIMIT 3;"

# 5. 物理ファイル（raw_data / okf_papers）と DB カタログの同期整合性スキャン
./manage.py dbsync --dry-run
```

### 2.4 環境のクリーンアップ (`make clean`)

ビルド成果物、キャッシュ（`__pycache__`, `.pytest_cache`, `.mypy_cache`）、一時ファイルを初期化したい場合は以下を実行します。

```bash
make clean
```

---

## 3. テストスイートの実行 ＆ TDD ガイド (`make test`)

本リポジトリでは、すべてのコード変更に対して厳格な自動テストの通過を義務付けています。

### 3.1 高速ユニットテスト (`make test`)
日常の開発サイクル（TDD）では、実行速度を最優先した単体テストスイートを実行します（`@pytest.mark.slow` を除く）。

```bash
make test
```

### 3.2 データベース耐障害性・シナリオテスト (`make test_scenarios`)
自作 DB エンジン（`src/database/`）の ARIES クラッシュリカバリプロトコルや、カオス耐性シミュレーション（ChaosVFS による電源断再現）を含む包括シナリオテストを実行します。

```bash
make test_scenarios
```

### 3.3 低速ストレステスト (`make test_slow`)
大量データや高負荷環境を想定した長時間実行テストのみを対象として実行します。

```bash
make test_slow
```

### 3.4 包括テストスイート ＆ カバレッジ検証 (`make test_all`)
全テストを一括実行し、テストカバレッジ 80% 以上を検証します。CI パイプラインで実行される最高水準のテストです。

```bash
make test_all
```

### 3.5 MCP サーバー仕様準拠性テスト
4 大 MCP サーバー（`papers`, `observability`, `threat_defense`, `tech_radar`）の JSON-RPC 2.0 仕様準拠性、入出力スキーマ、および最大返却文字数上限（コンテキスト溢れ防止ガード）をテストします。

```bash
PYTHONPATH=src .venv/bin/python3 tests/test_all_mcp_servers.py
```

### 3.6 オントロジー ＆ グラフDB統合テスト
W3C OWL 2.0 Turtle シリアライズ整合性および Dual CSR グラフエンジンの推論精度を検証します。

```bash
PYTHONPATH=src .venv/bin/python3 -m pytest tests/ontology/ tests/graph/
```

---

## 4. 静的解析・コード品質ゲート (`make check` / `make verify_quality`)

本リポジトリは、Python コードおよび Web フロントエンドコードの品質を担保するため、厳格な品質ゲートを設けています。PR 作成前やコミット前には必ず品質ゲートを実行してください。

### 4.1 コード自動整形 ＆ スタイル検査 (`make format` / `make check_format`)

PEP 8 準拠のコードスタイル、import 順序の自動整理を行います。

```bash
# 自動フォーマットの適用 (isort, black, flake8)
make format

# フォーマット差分の非破壊検証（CI向け）
make check_format
```

### 4.2 静的コード解析 ＆ 型検査 (`make static_analysis`)

以下の基準をすべて満たす必要があります：
- **radon**: 循環的複雑度 (Cyclomatic Complexity)、保守性指標 (MI)、Halstead メトリクスの計測。
- **xenon**: コードの複雑度を **Grade A**（最高品質）以内に強制（違反時は非ゼロ終了）。
- **mypy**: `--strict` モードで全モジュールの完全型安全性を検証（型エラー 0 件必須）。
- **py_compile**: 全 Python ソースの構文解析検査。

```bash
make static_analysis
```

### 4.3 Python 構文コンパイル検査 (`make py_compile`)
全 Python スクリプトの SyntaxError を高速に検証します。

```bash
make py_compile
```

### 4.4 JavaScript 最適化ビルド (`make build_js`)
Web ポータル（`site/js/`）の JavaScript コードは、**Google Closure Compiler** により ADVANCED 最適化・バンドルビルドされます。

```bash
make build_js
```

### 4.5 開発者向け日常品質ゲート (`make check`)
コード整形、静的解析、単体テストを一括で検証する標準ゲートです。

```bash
make check
```

### 4.6 最終品質検証ゲート (`make verify_quality` / `make build`)
Python および JavaScript のビルド・テスト・リントを網羅する厳格な最終ゲートです。

```bash
make verify_quality
# または
make build
```

---

## 5. 情報検索（IR）評価 ＆ CI 回帰防止ゲート

検索エンジン（`src/search/`）のアルゴリズム変更やインデックス構造の修正を行った際は、検索精度指標の回帰（デグレ）が発生していないかを検証する必要があります。

### 5.1 検索エンジン品質ベンチマーク評価 (`make eval_search`)
情報検索の標準指標（Precision@K, Recall@K, MAP, MRR, NDCG）を自動計測します。

```bash
make eval_search
```

### 5.2 ベースライン IR メトリクスの更新 (`make ir_eval`)
新しい検索機能やアルゴリズム改善の成果を、リポジトリの公式ベースライン（NDCG@10 等）として再記録します。

```bash
make ir_eval
```

### 5.3 検索精度回帰防止 CI ゲート (`make check_ir_regression`)
ベースライン指標と比較し、検索精度が **3% 以上低下**した場合にビルドを遮断する回帰防止ゲートです。

```bash
make check_ir_regression
```

---

## 6. コンポーネント別 内部開発ガイド (Subsystem Development)

### 6.1 内製 Pure-Python PDF 解析エンジン (`src/pdf_engine/`)
外部ツール（`pdftotext` 等）に依存せず、Python 標準ライブラリのみで ISO 32000 仕様に準拠した PDF テキスト・レイアウト抽出を行うエンジンです。

```bash
# 単一 PDF ファイルのテキスト抽出テスト
PYTHONPATH=src .venv/bin/python3 -m pdf_engine outputs/raw_data/2026-09-06/2504.03936.pdf

# PDF エンジンのパフォーマンステスト・抽出速度ベンチマーク実行
PYTHONPATH=src .venv/bin/python3 -m pdf_engine.benchmark
```

### 6.2 オントロジー (TBox) ＆ Turtle 生成エンジン (`src/ontology/`)
W3C RDF 1.1 / OWL 2.0 準拠の Pure-Python オントロジー生成エンジンです。概念体系の定義は `src/ontology/schema.py` を単一情報源 (SSOT) としています。

```bash
# デフォルト出力先 (outputs/ontology/security_ontology_v2.ttl) へのシリアライズ
PYTHONPATH=src .venv/bin/python3 -m ontology.turtle_engine

# 出力先パスを指定して生成
PYTHONPATH=src .venv/bin/python3 -m ontology.turtle_engine --output outputs/ontology/custom_ontology.ttl

# 標準出力に出力（パイプライン処理向け）
PYTHONPATH=src .venv/bin/python3 -m ontology.turtle_engine --stdout
```

### 6.3 プロパティグラフDB (ABox) の構築 ＆ 統計 (`src/graph/`)
全 OKF 論文から実体（エンティティ）および因果連鎖トリプルを抽出し、Dual CSR 高速プロパティグラフ DB を構築・検証します。

```bash
# 全 OKF 論文からのバックフィル構築
PYTHONPATH=src .venv/bin/python3 src/graph/cli.py build --backfill

# グラフ DB のトポロジ統計・頂点/エッジ分布の表示
PYTHONPATH=src .venv/bin/python3 src/graph/cli.py show --stats
```

### 6.4 データベース・ストレージ層の検証・SQL デバッグ (`manage.py`)
自作 DB エンジン（`src/database/`）や CTI カタログ、仮想テーブル（VFS）の開発・テスト時には、`manage.py` が開発者用の強力なインスペクション・デバッグツールとして機能します。

```bash
# マウントされている全テーブルのストレージ型（B+Tree, PAX, Virtual 等）と行数を表示
./manage.py tables

# テーブルの物理スキーマ・型定義・推論 DDL の確認 (例: processed_papers, cti_techniques)
./manage.py inspect processed_papers

# 対話型 dbshell で SQL クエリの実行結果や動作を直接デバッグ
./manage.py dbshell
# dbshell 内で使用可能なメタコマンド:
#   .tables           - マウントテーブル一覧の表示
#   .schema [table]   - スキーマ DDL の表示
#   .use <db_scope>   - アクティブ DB スコープの切り替え
#   .quit / .exit     - シェルの終了

# 物理ストレージとカタログインデックスの同期検証
./manage.py dbsync
```

### 6.5 MCP サーバーの新規ツール拡張 (`src/mcp/`)
MCP サーバー群（`src/mcp/`）に新しいツールを追加する際は、以下の原則を遵守してください：
1. **JSON-RPC 2.0 スキーマ定義**: 入出力引数の型ヒントを明示し、詳細な説明（description）を付与する。
2. **文字数上限ガード**: AI エージェントのコンテキスト溢れを防止するため、返却テキストの文字数を一定上限（例: 8,000文字）で安全に切り詰める。
3. **境界防御**: ファイルアクセスを行うツールは、リポジトリ外へのパストラバーサルを厳格に遮断する（`src/security/` 連携）。
4. **テスト追加**: `tests/test_all_mcp_servers.py` に新規ツールの単体・準拠性テストを追加する。

---

## 7. 開発・ビルド・CI/CD コマンドリファレンス (Developer Cheat Sheet)

開発者が日常的に使用する主要な Makefile ＆ CLI コマンドの一覧です。

| カテゴリ | コマンド (`make <target>` / CLI) | 説明・主な用途 |
| :--- | :--- | :--- |
| **セットアップ** | `make setup` | 仮想環境構築、依存パッケージインストール、Git フック登録 |
| | `make clean` | 一時ファイル・ビルド成果物・テストキャッシュの完全削除 |
| **DB 管理・検証** | `./manage.py tables` | マウントテーブル一覧・行数・ストレージ種別表示 |
| | `./manage.py inspect <table>` | テーブルスキーマ定義・サンプル行表示 |
| | `./manage.py dbshell` | 対話型 SQL シェル起動 / `-c` ワンライナー実行 |
| | `./manage.py dbsync` | 物理ファイルと DB カタログの自動同期・修復 |
| **フォーマット** | `make check_format` | isort, black, flake8 によるスタイル差分検証（非破壊） |
| | `make format` | isort, black, flake8 による自動コードフォーマット適用 |
| **静的解析** | `make static_analysis` | radon (CC/MI), xenon (Grade A), mypy (--strict), py_compile |
| | `make py_compile` | 全 Python ソースコードの構文コンパイル検査 |
| **フロントエンド** | `make build_js` | Google Closure Compiler による site/js 最適化ビルド |
| **テスト** | `make test` | pytest 高速テスト実行（@pytest.mark.slow を除く） |
| | `make test_scenarios` | データベース整合性・耐障害性シナリオテスト実行 |
| | `make test_slow` | 長時間実行ストレステストのみを実行 |
| | `make test_all` | カバレッジ 80% 以上を検証する全テスト一括実行 |
| **品質ゲート** | `make check` | `check_format`, `static_analysis`, `test` の一括ゲート |
| | `make verify_quality` | Python & JS を網羅する厳格な最終品質検証ゲート |
| | `make build` | フォーマット、品質ゲート、JS 最適化ビルドの一括実行 |
| **検索・IR 評価** | `make eval_search` | 検索エンジン精度指標 (MAP, MRR, NDCG 等) の自動計測 |
| | `make ir_eval` | IR ランキング精度ベースラインの更新 |
| | `make check_ir_regression` | 検索精度回帰防止 CI ゲート検証（劣化 3% 以内で遮断） |
| **オントロジー** | `make build_knowledge_graph` | 全 OKF 論文から Property Graph DB をバックフィル構築 |
| | `make graph_stats` | Property Graph DB のトポロジ統計・頂点/エッジ分布表示 |
| **MCP 検証** | `make mcp_stats` | MCP 利用メトリクス集計およびレポート出力 |

※ 論文収集・Web 起動・スーパーバイザー起動などの運用・利用コマンドについては、[[USR-01] ユーザーマニュアル](USR-01-user_manual.md) を参照してください。

---

## 8. 開発環境トラブルシューティング ＆ デバッグ

| 症状 / エラー | 原因 | 対処法 |
| :--- | :--- | :--- |
| `mypy: error: Untyped decorator` または型エラー | 関数の型アノテーション欠落、または厳格型不適合 | 関数の引数・戻り値に厳格な型ヒントを追記してください。外部ライブラリの場合は型スタブを確認してください。 |
| `xenon: ERROR: Block ... has complexity ... (Grade B/C)` | 関数の循環的複雑度（Cyclomatic Complexity）超過 | 複雑なネスト（if/for）をヘルパー関数へ分割し、Grade A（最高品質）へリファクタリングしてください。 |
| `pytest: ModuleNotFoundError: No module named 'src'` | `PYTHONPATH` が未設定 | `export PYTHONPATH=src` を設定するか、`PYTHONPATH=src .venv/bin/python3 -m pytest` で実行してください。 |
| `Google Closure Compiler build failed` | JS 構文エラー、または未定義変数の参照 | `site/js/` 内の構文エラーを確認してください。Closure Compiler のエラー行番号を参照して修正します。 |
| `git commit: hook rejected` | 静的解析またはフォーマット検査が未通過 | `make format` および `make static_analysis` を実行し、すべてのエラーを解消してから再コミットしてください。 |
| 仮想環境の依存関係競合 | 古いパッケージキャッシュの残存 | `make clean` を実行後、`rm -rf .venv` で仮想環境を削除し、再度 `make setup` を実行してください。 |
