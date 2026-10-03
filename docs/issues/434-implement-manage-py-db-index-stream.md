---
ID: 434
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] manage.py db-index データベース・ベクトル検索インデクス登録シンクの実装 (ID: 434)

## 1. 概要 / Summary
`REQ-FR-09` および `DSN-01 Section 5.2` のパイプライン第5ステージ（吸い込み口 / Sink）として、標準入力（stdin）から流れてきた構造化・要約済み論文レコード（JSON Lines）を受け取り、自前 4層データベース（`src/database`）のリレーショナルテーブルおよびベクトル検索エンジン（`src/search`）にバルク登録・インデックス化する `manage.py db-index` コマンドを実装する。

ストリームの末端として機能し、登録結果のサマリー（成功件数、スキップ件数、インデックス所要時間）を stdout または stderr に通知する。

---

## 2. トレーサビリティ / Traceability
- 要求仕様書: [docs/requirements/REQ-01-system_requirements.md](../requirements/REQ-01-system_requirements.md) (`REQ-FR-04`, `REQ-FR-09`)
- 基本設計書: [docs/designs/DSN-01-high_level_design.md](../designs/DSN-01-high_level_design.md) (`5.2 CLI Stream Pipeline Protocol`)
- 基底依存: Issue #429 (`src/cli/stream.py`), [src/database](file:///workspace/arxiv-security-papers/src/database), [src/search](file:///workspace/arxiv-security-papers/src/search)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/cli/commands/db_index.py` (新規作成: DbIndexCommand)
- [ ] `src/cli/registry.py` (db-index サブコマンドの登録)
- [ ] `tests/cli/commands/test_db_index.py` (新規単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/434-implement-manage-py-db-index-stream`

1. **`DbIndexCommand` の定義**:
   - `src/cli/commands/db_index.py` に `DbIndexCommand(BaseCommand)` を作成。
   - 引数オプション:
     - `--target` (`all`, `db`, `vector`, デフォルト: `all`)
     - `--batch-size` (コミットバッチサイズ、デフォルト: 50)
     - `--passthrough` (登録完了レコードをそのまま stdout に流すパイプ透過フラグ)
2. **ストレージ・インデックス連携**:
   - `StreamReader` で stdin からレコードを受信。
   - `src/database/` の `arxiv_papers` テーブルへ UPSERT。
   - `src/search/` の HNSW ベクトルインデックスおよび BM25 反転インデックスに登録。
3. **出力制御**:
   - `--passthrough` 指定時は各レコードを stdout にそのままパススルー。
   - 未指定時は最終登録統計（件数、所要時間）を JSON で stdout に 1 行出力。進捗ログは stderr へ出力。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `cat summary_papers.jsonl | python manage.py db-index` で、DB テーブルおよびベクトルインデックスに正常登録されること。
- [ ] `--passthrough` オプションにより、登録済みレコードを後続の Unix コマンドへ継続パイプできること。
- [ ] 単体テストがパスし、品質ゲートを満たすこと。
