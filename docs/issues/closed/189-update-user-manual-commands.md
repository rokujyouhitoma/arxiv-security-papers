---
ID: 189
種別: Documentation
優先度: Normal
ステータス: Closed
---

# [DOC] [USR-01] ユーザーマニュアルのコマンド体系網羅的拡充とオントロジー・グラフDB操作ガイド追記 (ID: 189)

## 1. 概要 / Summary
`arxiv-security-papers` プロジェクトにおいて、オントロジー（TBox: W3C OWL 2.0 / Turtle）生成、プロパティグラフDB（ABox: CTI Graph / 因果連鎖 / 具現化エビデンス）、Web ダッシュボード（Schema View / CTI Graph）、閉ループ自律インテリジェンス、スーパーバイザー、MCP サーバー群、アナリティクス集計など、実行可能コマンドや運用機能が大幅に拡張された。
これに伴い、ユーザーおよび AI コーディングエージェントが迷わず全サブシステムを操作できるよう、`docs/manuals/USR-01-user_manual.md` に最新のコマンド（オントロジー出力、グラフDBバックフィル、CLIクエリ、Web表示モード等）をもれなく体系的に反映・更新する。併せて CLI 側のエントリポイント（`turtle_engine.py`, `graph/cli.py`）を拡充する。

---

## 2. トレーサビリティ / Traceability
- 関連要求: [REQ-DOC-01](../../docs/requirements/REQ-01-system_requirements.md)
- 管理台帳: [MNG-01 文書管理台帳](../../docs/processes/MNG-01-document_ledger.md)
- 設計仕様: [DSN-22 セキュリティオントロジー W3C 仕様書](../../docs/designs/DSN-22-security_and_threat_ontology_w3c_specification.md)
- 関連Issue: [Issue 187](187-implement-ontology-tbox-graph-ingestion-and-schema-view.md), [Issue 188](188-integrate-causal-reified-entities-into-paper-abox-graph.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [docs/manuals/USR-01-user_manual.md](../../docs/manuals/USR-01-user_manual.md) (ユーザーマニュアル全面拡充・コマンド網羅)
- [x] [src/ontology/turtle_engine.py](../../src/ontology/turtle_engine.py) (Turtle 生成 CLI エントリポイント)
- [x] [src/graph/cli.py](../../src/graph/cli.py) (グラフDB CLI `query` サブコマンドおよび `--backfill`, `--stats` オプション)
- [x] [docs/processes/MNG-01-document_ledger.md](../../docs/processes/MNG-01-document_ledger.md) (文書台帳更新)
- [x] [docs/issues/README.md](README.md) (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/189-update-user-manual-commands`

1. **オントロジー生成 & グラフDB運用コマンドの追加**:
   - W3C OWL Turtle (`.ttl`) 生成コマンド (`python -m ontology.turtle_engine [--output ... | --stdout]`)
   - グラフDBバックフィル構築 (`python src/graph/cli.py build --backfill`)
   - グラフDB統計・検証 (`python src/graph/cli.py show --stats`)
   - グラフDB CLIクエリ実行 (`python src/graph/cli.py query "<expr>"`)
2. **Web ダッシュボード可視化モード（3大ビュー）の操作ガイド追記**:
   - `🌐 Context Mesh`（意味的類似度網）
   - `🛡️ CTI Graph`（ATT&CK/CWE/Impact/Evidence 実データ網・マルチセレクトフィルター）
   - `📐 Schema View`（W3C OWL TBox メタモデルスキーマ）
3. **包括的 CLI & Makefile コマンド一覧リファレンス (Cheat Sheet)**:
   - セットアップ、パイプライン、検索/ベクトルDB、オントロジー/グラフDB、Web/MCP、スーパーバイザー、品質管理の全コマンドを網羅。
4. **マニュアル及び管理台帳の同期**:
   - `USR-01-user_manual.md` および `MNG-01-document_ledger.md` を最新仕様に更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `docs/manuals/USR-01-user_manual.md` にオントロジー・グラフDB関連コマンドが体系的に追記されていること。
- [x] Web ダッシュボードの操作方法（Schema View / CTI Graph / フィルター）が記載されていること。
- [x] 相対パスリンクが正常に機能していること。
- [x] `docs/issues/README.md` に Issue #189 が登録・管理されていること。
- [x] 品質ゲート（`isort`, `black`, `flake8`, `mypy --strict`, `py_compile`）が 100% PASS すること。
