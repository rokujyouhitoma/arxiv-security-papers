---
ID: 230
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] プロジェクト統合管理 CLI (manage.py) および対話型データベースシェル (dbshell) の実装 (ID: 230)

## 1. 概要 / Summary

本 Issue は、[DSN-24 (プロジェクト統合管理 CLI および対話型データベースシェル仕様書)](../../docs/designs/DSN-24-unified_management_cli_and_interactive_database_shell.md) に基づき、Django の `manage.py` に倣った**プロジェクト全体の統合管理 CLI (`manage.py`)**、および人間や AI がターミナルから直接マルチストレージへ SQL を発行できる**対話型データベースシェル (`dbshell`)** を実装することを目的とする。

### コア提供機能
1. **統合管理 CLI エントリポイント (`manage.py`)**:
   - リポジトリルートに配置し、サブシステムに散在していたコマンド群を Facade パターンで集約。
   - `BaseCommand` 抽象基底クラスによるプラグ可能サブコマンドディスパッチ（`argparse` 活用）。
2. **対話型データベースシェル (`manage.py dbshell`)**:
   - 起動時にリポジトリ内の実データ（バイナリ VDB, JSON 台帳, JSONL ログ, 実ファイル Markdown/Text 仮想テーブル）を**自動マウント**。
   - **インテリジェント入力補完 (Tab Autocompletion)**:
     `readline` を用いて、SQL キーワード、マウント済みテーブル名、テーブル別カラム名、メタコマンド（`.tables`, `.schema`, `.sync` 等）を Tab キーで文脈に応じて自動補完。
   - **データベース自動プロビジョニング ＆ 自己治癒 (Self-Healing & Auto-Provisioning)**:
     未作成ファイルや欠損カタログを安全にフォールバック補完し、大量データ（1.4万件超の OKF Markdown）でもディレクトリスキャンを遅延評価してサブミリ秒で即座に起動。
   - `readline` 対応の REPL 環境（履歴管理、Ctrl+C/D 安全制御、マルチライン入力）。
   - 純 Python・ゼロ外部依存による美しい **ASCII 罫線テーブルフォーマッター**。
   - メタコマンド（`.tables`, `.schema`, `.explain`, `.sync`, `.quit`）およびワンライナー実行モード (`-c "SELECT..."`)。
3. **テーブルインスペクション ＆ データベース同期 (`manage.py tables`, `manage.py inspect`, `manage.py dbsync`)**:
   - 登録テーブル一覧、ストレージ形式、行数、サイズを瞬時に確認可能。
   - `manage.py dbsync`: 実ファイルと JSON カタログ台帳の差分を検出し、未登録レコードを自動補完・修復。
4. **将来拡張性 (Roadmap)**:
   - 次期フェーズで `runserver`（Web Gateway 統合起動）や `supervisor`（プロセス監視）をシームレスに追加可能な拡張性を担保。

---

## 2. セキュリティ脅威モデルと多層防御設計 (STRIDE & Mitigations)

| 脅威カテゴリ (STRIDE) | 潜在リスク (Threat Scenario) | 緩和策・セキュリティ仕様 (Mitigations) |
| :--- | :--- | :--- |
| **Tampering / Traversal (改ざん・不正アクセス)** | `dbshell` や引数経由での外部ファイル破壊・ディレクトリトラバーサル | **ワークスペース境界強制検証**:<br>Issue #229 で実装された `_validate_safe_workspace_path` を自動マウントおよび全ファイル参照に適用し、リポジトリ外部アクセスを 100% 遮断。 |
| **Information Disclosure (情報漏洩)** | クエリパースエラー時の内部絶対パス露出 | **エラー出力サニタイズ**:<br>スタックトレースや例外メッセージをワークスペース相対パスへ自動マスキング。 |
| **Denial of Service (DoS)** | 巨大テーブル（全文テキスト等）に対する無制限クエリによる端末フリーズ | **安全ガード ＆ シグナル割り込み**:<br>デフォルト表示上限（LIMIT 1000）の警告提示、および `SIGINT` (Ctrl+C) ハンドラによるクエリ即時安全中断。 |
| **Elevation of Privilege (特権昇格)** | 未認可のテーブルに対する破壊的 DDL/DML 実行 | `SQLExecutor` の既存 RBAC アクセスコントローラー (`AccessController`) との連携。 |

---

## 3. トレーサビリティ / Traceability

- **設計仕様書**:
  - **統合管理 CLI**: [DSN-24: プロジェクト統合管理 CLI (manage.py) および対話型データベースシェル (dbshell) 仕様書](../../docs/designs/DSN-24-unified_management_cli_and_interactive_database_shell.md)
  - **データベース基盤**: [DSN-05: 第19.4節 (PEP 249) ＆ 第21.7節 (プラガブルストレージ)](../../docs/designs/DSN-05-database_engine_architecture.md#217-プラグ可能ストレージ切り替え共存アーキテクチャuri自動判別--ddl-using-句ハイブリッドモデル)
  - **スーパーバイザ**: [DSN-12: 第12節 (CLI 運用コマンド体系)](../../docs/designs/DSN-12-process_supervisor_and_arbiter.md#12-cli-運用コマンドリファレンスと運用プラクティス)
- **品質規程**: `.agents/AGENTS.md` (ゼロ外部依存, 相対パスリンク厳守, Xenon Rank A CC<=5, mypy --strict)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### (1) 新規作成ファイル
- [x] `manage.py`: ルートエントリポイント
- [x] `src/cli/__init__.py`: パッケージ初期化
- [x] `src/cli/base.py`: `BaseCommand` 抽象基底クラス
- [x] `src/cli/dispatcher.py`: コマンド解決 ＆ ディスパッチャー
- [x] `src/cli/formatter.py`: 純 Python ASCII 罫線テーブル整形エンジン
- [x] `src/cli/completer.py`: 純 Python `readline` 文脈依存 Tab 補完エンジン (`SQLCompleter`)
- [x] `src/cli/commands/__init__.py`: サブコマンドパッケージ
- [x] `src/cli/commands/dbshell.py`: 対話型データベースシェル REPL
- [x] `src/cli/commands/tables.py`: テーブル一覧表示
- [x] `src/cli/commands/inspect.py`: テーブル詳細スキーマインスペクション
- [x] `src/cli/commands/dbsync.py`: データベース自律補完・カタログ同期
- [x] `tests/cli/test_manage_dbshell.py`: CLI および REPL の単体・統合テスト
- [x] `tests/cli/test_sql_completer.py`: Tab キー入力補完エンジンの単体テスト

### (2) 変更ファイル
- [x] `Makefile`: `make dbshell` ターゲットの追加
- [x] `docs/issues/README.md`: Issue 台帳の更新

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/230-implement-manage-py-unified-cli-and-interactive-dbshell`

### Step 1: CLI コアフレームワーク (`src/cli/`)
1. `BaseCommand` 定義:
   - `add_arguments(parser: ArgumentParser)`
   - `handle(args: Namespace) -> int`
2. `CommandDispatcher`:
   - ルート `manage.py` から呼ばれ、サブコマンドを探索・ディスパッチ。
   - 引数なし実行時は利用可能なコマンド一覧とヘルプを表示。

### Step 2: ASCII テーブルフォーマッター (`src/cli/formatter.py`)
1. リスト辞書（`rows: List[Dict[str, Any]]`）から各列の最大文字幅を自動算定。
2. 罫線枠（`+---+---+`）とヘッダー、データを整然とレンダリング。
3. NULL 値および長文の安全な折り返し・切り詰め処理。

### Step 3: Tab 補完エンジン (`src/cli/completer.py`)
1. `SQLCompleter`:
   - キーワード、テーブル名、カラム名、メタコマンドの文脈自動判別。
   - `readline.set_completer` 連携。

### Step 4: `dbshell` コマンドの実装 (`src/cli/commands/dbshell.py`)
1. `SQLExecutor` を初期化し、標準テーブルを自動マウント（欠損テーブルのオンデマンド空初期化補完）：
   - `okf_papers` (USING file_plain_text LOCATION 'outputs/okf_papers')
   - `raw_papers` (USING file_plain_text LOCATION 'outputs/raw_data')
   - `processed_papers` (USING json_table LOCATION 'outputs/database/papers_catalog.json')
   - `pipeline_runs` (USING json_lines LOCATION 'outputs/database/pipeline_state.jsonl')
   - `cti_*`, `analytics_*` (バイナリ VDB)
2. `readline` ループによる REPL 実装（履歴、Tab補完、Ctrl+C/D 安全制御）。
3. セミコロン `;` でのクエリ終了判定、複数行入力サポート。
4. `-c` オプションによる非対話ワンライナー実行。

### Step 5: `tables` / `inspect` / `dbsync` コマンドの実装
1. `manage.py tables`: マウント済み全テーブルの形式と行数を一括表示。
2. `manage.py inspect <table_name>`: 指定テーブルのスキーマと先頭サンプルを表示。
3. `manage.py dbsync`: 実ファイルとカタログの差分スキャン・補完。

### Step 6: Makefile ターゲット追加とテスト
1. `make dbshell`: `PYTHONPATH=src .venv/bin/python manage.py dbshell` のショートカット。
2. `tests/cli/` 配下での自動テスト（`StringIO` モック、補完テスト）。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] **統合 CLI 動作**:
  - `python manage.py --help` で利用可能なサブコマンド一覧が正常に表示されること。
- [x] **dbshell 対話 ＆ ワンライナー動作**:
  - `python manage.py dbshell -c "SELECT COUNT(*) FROM okf_papers;"` が正常に実行され、行数が整形テーブルで出力されること。
  - 実ファイル Markdown 仮想テーブル (`okf_papers`) と JSON 台帳 (`processed_papers`) の透過 JOIN が `dbshell` 上で実行可能なこと。
  - `.tables`, `.schema`, `.quit`, `.sync` 等のメタコマンドが正しく動作すること。
  - Tab キー補完エンジン（`SQLCompleter`）がキーワード・テーブル・カラム・メタコマンドを適切に候補提示すること。
- [x] **テーブルインスペクション ＆ データベース補完**:
  - `python manage.py tables` で全テーブル情報が表示されること。
  - `python manage.py dbsync` で実ファイルとの差分補完・整合性チェックが動作すること。
- [x] **ゼロ外部依存 ＆ 品質基準**:
  - 新規コードが `mypy --strict` でエラー 0 件であること。
  - 全関数が Xenon **Rank A (CC <= 5)** を達成していること。
  - `make check_format` および `make test` が 100% PASS すること。

