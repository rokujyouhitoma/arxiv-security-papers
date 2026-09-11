---
ID: 252
種別: Documentation / Architecture
優先度: High
ステータス: Closed
---

# [DOC/ENH] ユーザーマニュアル (USR-01) のエンドユーザー向けと開発者向け (DEV-01) への分離・再編 (ID: 252)

## 1. 概要 / Summary
現在 `docs/manuals/USR-01-user_manual.md` に単一集約されているマニュアルについて、ペルソナごとの関心事（エンドユーザー／運用者 vs リポジトリ開発者／コントリビューター）が混在しているため、以下の2つのマニュアルへ分離・再編する。
1. **`[USR-01] ユーザーマニュアル (User Manual)`**: エンドユーザー、セキュリティアナリスト、運用者、AIエージェント利用者向け（Web UI操作、4大MCPサーバー連携、検索クエリ、日常の論文収集・スーパーバイザー運用、PIR管理・セキュリティ仮説等）。
2. **`[DEV-01] 開発者マニュアル (Developer Manual)`**: リポジトリ開発者、コントリビューター、AIコーディングエージェント（開発者ペルソナ）向け（`make setup` 仮想環境構築、`make test` テストスイート、`make check` / `make verify_quality` 品質ゲート、IR回帰検知ゲート、内部モジュール開発手順等）。

あわせて、文書管理台帳 `MNG-01` およびドキュメントポータル `docs/README.md` に新マニュアルを正式登録し、完全相対パスによる相互参照リンク網を確立する。

---

## 2. トレーサビリティ / Traceability
- **要求仕様**: [REQ-01 システム要求事項定義書](../requirements/REQ-01-system_requirements.md) (REQ-NFR-05 保守性・可読性)
- **管理台帳**: [MNG-01 文書管理台帳](../processes/MNG-01-document_ledger.md)
- **ポータル**: [docs/README.md](../README.md)
- **関連Issue**:
  - [Issue 189](closed/189-update-user-manual-commands.md) (ユーザーマニュアルのコマンド体系拡充)
  - [Issue 221](closed/221-unify-and-elevate-all-agent-definitions-to-gold-standard.md) (全15専門エージェント定義準拠化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [NEW] [docs/manuals/DEV-01-developer_manual.md](../manuals/DEV-01-developer_manual.md) (開発者向けマニュアル新設)
- [MODIFY] [docs/manuals/USR-01-user_manual.md](../manuals/USR-01-user_manual.md) (エンドユーザー・運用者向けに再編・開発者セクション移譲)
- [MODIFY] [docs/processes/MNG-01-document_ledger.md](../processes/MNG-01-document_ledger.md) (DEVプレフィックス定義および DEV-01 登録)
- [MODIFY] [docs/README.md](../README.md) (ドキュメントポータル 4. マニュアル一覧への追記)
- [MODIFY] [docs/issues/README.md](README.md) (Issue 252 進行中ステータス管理)

---

## 4. マルチエージェント審議・設計方針 (Multi-Agent Alignment)

1. **Project Manager (PM) / IT Strategist**:
   - 利用者ペルソナ（アナリスト・運用者）と開発者ペルソナ（エンジニア・CI/CD運用者）を明確に分離することで、ドキュメントの肥大化を防ぎ、双方のオンボーディングコストを劇的に低減。
2. **Software Quality Assurance Specialist (SQA) / Software Development (SWD)**:
   - 開発者が厳格な品質ゲート（`make check`, `make verify_quality`, radon/xenon, mypy strict, Closure Compiler 最適化）や各種テスト（高速ユニットテスト、高負荷DSN-14シナリオテスト、IR回帰テスト）を迷わず一発実行できるリファレンスを `DEV-01` に集約。
3. **UI/UX & Documentation Designer / Education Specialist**:
   - `USR-01` は直感的な操作・探索（Webポータル、Glassmorphic UI、CTI Graph、Schema View）に特化させ、用語説明を平易化。
   - `DEV-01` はリポジトリの内部構造・アーキテクチャ・データフロー・コマンドチートシートを体系化。
4. **Information Security Specialist (SEC) / Systems Auditor (AU)**:
   - ドキュメント内の機微情報（APIキー、固定認証トークン等）の非混入を検証。
   - すべての内部リンクが完全相対パス（Strict Relative Path）であることを監査。

---

## 5. 実装手順 / Implementation Plan
Target Branch: `feat/252-separate-user-and-developer-manuals`

### Step 1: `docs/manuals/DEV-01-developer_manual.md` の新規作成
開発者向け内容を体系化した完全日本語 Markdown ドキュメントを作成する。
- **第1章: 開発者向けアーキテクチャ ＆ リポジトリ構成**: `src/` 配下の各サブシステム（`pipeline`, `search`, `database`, `graph`, `ontology`, `mcp`, `web`, `supervisor`, `intelligence`）の責務とデータフロー
- **第2章: 開発環境セットアップ (`make setup`)**: Python 3.14+ 仮想環境構築、開発・テスト依存インストール、Gitフック登録、初期データ整合性チェック (`./manage.py tables`)、`make clean`
- **第3章: テストスイートの実行 ＆ TDD ガイド (`make test`)**:
  - `make test` (pytest 高速単体テスト)
  - `make test_scenarios` (DSN-14 耐障害性・高負荷テスト)
  - `make test_slow` (ストレステスト)
  - `make test_all` (カバレッジ80%以上全テスト)
  - `tests/test_all_mcp_servers.py` (MCPプロトコルテスト)
- **第4章: 静的解析・コード品質ゲート (`make check` / `verify_quality`)**:
  - `make format` / `make check_format` (isort, black, flake8)
  - `make static_analysis` (radon 循環的複雑度, xenon Grade A, mypy strict)
  - `make py_compile` (全Python構文コンパイル)
  - `make build_js` (Google Closure Compiler 最適化)
  - `make verify_quality` (総合品質検証ゲート)
- **第5章: 情報検索（IR）評価 ＆ CI 回帰防止ゲート**:
  - `make eval_search` (MAP, MRR, NDCG@K 精度評価)
  - `make ir_eval` (ベースライン更新)
  - `make check_ir_regression` (劣化3%以内遮断ゲート)
- **第6章: コンポーネント別 内部開発ガイド**:
  - PDF解析エンジンベンチマーク (`python -m pdf_engine.benchmark`)
  - W3C OWL 2.0 Turtle 生成 (`python -m ontology.turtle_engine`)
  - グラフDBバックフィル構築 (`python src/graph/cli.py build --backfill`)
  - MCPサーバー新規ツールの追加手順
- **第7章: 開発・ビルド・CI/CD コマンドリファレンス (Cheat Sheet)**: 開発者向け全 Makefile コマンド
- **第8章: 開発トラブルシューティング ＆ デバッグ**: mypy/xenonエラー解決、仮想環境リセット

### Step 2: `docs/manuals/USR-01-user_manual.md` の再編
- `make setup` の開発者依存関係説明、`make test` 全般、静的解析・品質ゲート、IR回帰テスト、内部エンジンベンチマーク等を `DEV-01` へのリンクに切り替え。
- エンドユーザー（アナリスト・運用者）向けに以下の構成へスリム化・洗練：
  - 1. システム概要・全体アーキテクチャ
  - 2. クイックスタート（利用者編: 前提環境、Web起動、MCP登録）
  - 3. 論文収集・ETL日常運用コマンド (`make pipeline`, バックフィル, CTI同期, スーパーバイザー)
  - 4. 自律型閉ループ・インテリジェンス統合システム (PIR管理, 仮説検証, サイクル実行)
  - 5. オントロジー (TBox) ＆ セキュリティ知識体系の参照
  - 6. プロパティグラフDB (ABox) ＆ CLI 探索クエリ (`causal:`, `ego:`, `cwe:`, `gap`, `path:`)
  - 7. セマンティック検索 ＆ RAG CLI (`make rag_query`)
  - 8. 戦略 KPI ＆ 脅威アナリティクス集計
  - 9. Web ポータル UI ＆ ダッシュボード (3大可視化モード操作ガイド)
  - 10. MCP エージェント連携ガイド (Claude Desktop, Cursor, Antigravity 登録とツール活用)
  - 11. 利用者向けコマンドリファレンス (Cheat Sheet)
  - 12. トラブルシューティング ＆ FAQ

### Step 3: 管理台帳・ポータル更新
- `docs/processes/MNG-01-document_ledger.md`: 分類プレフィックスに `DEV` を追記、台帳テーブルに `[DEV-01] 開発者マニュアル` を登録。`[USR-01]` の説明をユーザー向けに更新。
- `docs/README.md`: 「4. ユーザーマニュアル ＆ AI エージェント連携」に `[DEV-01] 開発者マニュアル` を追加。

### Step 4: 品質ゲート・相対リンク検証
- `make py_compile` 実行
- 相対リンクの存在確認とリンク切れ0件確認
- Conventional Commit でのコミットおよび Issue クローズ

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `docs/manuals/DEV-01-developer_manual.md` が作成され、開発者向け内容（`make setup`, `make test`, 品質ゲート, IR回帰テスト, 内部開発等）が網羅されていること
- [x] `docs/manuals/USR-01-user_manual.md` から開発者向け内部内容が分離され、エンドユーザー・アナリスト視点のマニュアルとして再編されていること
- [x] `docs/processes/MNG-01-document_ledger.md` に `DEV` プレフィックスおよび `[DEV-01]` が登録されていること
- [x] `docs/README.md` に `[DEV-01]` が追加され、ポータルから辿れること
- [x] 全ドキュメント内の内部リンクが 100% 正しい相対パスで記述されていること
- [x] `make py_compile` が 0 エラーで完了すること
- [x] Git コミットおよび Issue 252 のクローズが完了していること
