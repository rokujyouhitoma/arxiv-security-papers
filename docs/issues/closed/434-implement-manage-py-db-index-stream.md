---
ID: 434
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-10-04
---

# [FEAT] manage.py db-index データベース・ベクトル検索インデクス登録シンクの実装 (ID: 434)

## 1. 概要 / Summary
`REQ-FR-09` および `DSN-01 Section 5.2` のパイプライン第5ステージ（吸い込み口 / Sink）として、標準入力（stdin）から流れてきた構造化・要約済み論文レコード（JSON Lines）を受け取り、自前 4層データベース（`src/database`）のリレーショナルテーブルおよびベクトル検索エンジン（`src/search`）にバルク登録・インデックス化する `manage.py db-index` コマンドを `src/cli/commands/db_index.py` に実装した。

ストリームの末端として機能し、登録結果のサマリー（成功件数、所要時間）を stdout または stderr に通知するほか、`--passthrough` オプションによる後続パイプ連携も可能とした。

---

## 2. トレーサビリティ / Traceability
- 要求仕様書: [docs/requirements/REQ-01-system_requirements.md](../../requirements/REQ-01-system_requirements.md) (`REQ-FR-04`, `REQ-FR-09`)
- 基本設計書: [docs/designs/DSN-01-high_level_design.md](../../designs/DSN-01-high_level_design.md) (`5.2 CLI Stream Pipeline Protocol`)
- 基底依存: Issue #429 (`src/cli/stream.py`), [src/database](../../src/database), [src/search](../../src/search)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/cli/commands/db_index.py` (新規作成: DbIndexCommand)
- [x] `src/cli/registry.py` (db-index サブコマンドの登録)
- [x] `tests/cli/commands/test_db_index.py` (新規単体テスト)
- [x] `docs/issues/README.md` (Issue台帳の更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/434-implement-manage-py-db-index-stream`

1. **`DbIndexCommand` の定義**:
   - `src/cli/commands/db_index.py` に `DbIndexCommand(BaseCommand)` を作成。
   - 引数オプション:
     - `-t`, `--target` (`all`, `db`, `vector`, デフォルト: `all`)
     - `-p`, `--passthrough` (登録完了レコードをそのまま stdout に流すパイプ透過フラグ)
     - `--on-error` (`skip` または `abort`, デフォルト: `skip`)
2. **ストレージ・インデックス連携**:
   - `StreamReader` で stdin からレコードを受信。
   - `outputs/database/papers_catalog.json` へのアトミックな UPSERT。
3. **出力制御**:
   - `--passthrough` 指定時は各レコードを stdout にそのままパススルー。
   - 未指定時は最終登録統計（件数、所要時間）を JSON で stdout に 1 行出力。進捗ログは stderr へ出力。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `cat summary_papers.jsonl | python manage.py db-index` で、DB テーブルおよびカタログに正常登録されること。
- [x] `--passthrough` オプションにより、登録済みレコードを後続の Unix コマンドへ継続パイプできること。
- [x] 単体テストがパスし、品質ゲート（Xenon Rank A, Mypy Strict, Flake8）を満たすこと。
