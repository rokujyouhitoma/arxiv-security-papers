---
ID: 232
種別: Architecture / Refactor
優先度: High
ステータス: Closed (Completed)
---

# [ARCH] src/database からのドメイン・テーブル固有実装（DDL/カラム名/固定パス）の完全分離 (ID: 232)

## 1. 概要 / Summary

`src/database/` は、リレーショナル・ベクトル・グラフ・ファイルストレージを統合管理する**汎用データベースエンジン基盤**であるべきである。しかし、特定テーブル（`okf_papers`）や論文ドメイン固有の列名（`clean_id`, `arxiv_id`, `body_markdown`, `raw_text`, `raw_abstract`）、固定パス（`outputs/okf_papers`）がストレージエンジンおよびプランナー内部にハードコードされていた。

本 Issue では、これらドメイン固有実装を `src/database/` から完全に分離し、**スキーマ駆動（Schema-Driven）**および**DI（依存性の注入）**に基づく完全なドメイン中立基盤へリファクタリングする。

---

## 2. トレーサビリティ / Traceability

- 設計書: `docs/designs/DSN-24-unified_management_cli_and_interactive_database_shell.md`
- 関連Issue: Issue #229, Issue #230, Issue #231
- ガバナンス規約: `.agents/AGENTS.md` (6. Raw Data Preservation & Idempotency Rules)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/database/storage/plain_text_storage.py`](file:///workspace/arxiv-security-papers/src/database/storage/plain_text_storage.py): ドメイン固定カラム名・固定パスの撤廃、汎用主キー・動的フロントマター展開・ヘビー列設定の導入
- [x] [`src/database/storage/factory.py`](file:///workspace/arxiv-security-papers/src/database/storage/factory.py): デフォルト主キーの `"id"` 統一
- [x] [`src/database/storage/json_storage.py`](file:///workspace/arxiv-security-papers/src/database/storage/json_storage.py): デフォルト主キーの `"id"` 統一
- [x] [`src/database/planner/stats.py`](file:///workspace/arxiv-security-papers/src/database/planner/stats.py): カラム名ブラックリスト撤廃、データサイズベースの汎用統計サンプリング
- [x] [`src/database/sql/executor.py`](file:///workspace/arxiv-security-papers/src/database/sql/executor.py): DDL 指定の PRIMARY KEY カラムをストレージエンジン生成時に透過的に伝搬
- [x] [`tests/database/storage/test_plain_text_storage.py`](file:///workspace/arxiv-security-papers/tests/database/storage/test_plain_text_storage.py): 汎用ストレージ仕様（任意主キー・任意フロントマター属性）のテスト拡充

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/232-decouple-domain-specific-logic-from-database-core`

1. **`FileBackedPlainTextStorage` の完全汎用化 (`plain_text_storage.py`)**:
   - `clean_id` や `_is_cached_base_key` の固定タプル `("id", "clean_id", "file_path", "file_size_bytes", "updated_at")` を廃止し、`key in self._base` に基づく動的判定に変更。
   - `heavy_columns: Optional[Set[str]]`（デフォルト: `{"body", "content", "body_markdown", "raw_text", "raw_abstract", "text"}`）を導入し、`("body_markdown", "raw_text", "raw_abstract")` の固定列名タプルを全廃。
   - `load_header_for_record` での論文メタデータ固定展開（`arxiv_id`, `title_ja`, `security-paper`, `trust` 等）を全廃し、パースされた YAML フロントマター内の全属性を透過的・動的に展開 (`meta.update(frontmatter_dict)`)。
   - デフォルトパス `outputs/okf_papers` を撤廃し、`root_dir` または `workspace_dir` を基準とした汎用ディレクトリ走査に統一。
   - `_read_file_content` での `col_name == "body_markdown"` 判定を撤廃し、Markdown / YAML フロントマターの有無に基づく汎用本文切り出しに改定。
2. **`TableStats` (`stats.py`) のサンプリング判定汎用化**:
   - カラム名ブラックリスト `("body_markdown", "raw_text", "raw_abstract")` を撤廃。
   - `isinstance(val, (str, bytes)) and len(val) > 2048` のような**サイズ基準の汎用サンプリングガード** (`_is_sampleable_val`) に改定。
3. **`StorageEngineFactory` & `JsonTableStorage` のデフォルトPK汎用化**:
   - デフォルト主キーを `"clean_id"` から標準の `"id"` に統一。
   - `okf_papers` や `processed_papers` 等の主キー（`clean_id`）は、テーブル作成 DDL やストレージパラメータ経由で明示的に渡されるように連携。
4. **品質ゲートとテスト**:
   - `make check_format`, `make static_analysis` (xenon Rank A: CC <= 5, mypy --strict) を 100% 通過。
   - 既存および追加の全テストが PASS することを確認。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `src/database/` 配下にドメイン固有列名（`clean_id`, `arxiv_id`, `body_markdown`, `raw_text`, `raw_abstract` 等のハードコード判定）が存在しないこと。
- [x] `FileBackedPlainTextStorage` が任意のフロントマター属性および任意の主キー名・本文列名を扱えること。
- [x] `mypy --strict`, `xenon` Rank A (CC <= 5) 100% 準拠。
- [x] `pytest tests/database/` および `pytest tests/cli/` を含む全テストが PASS すること。
- [x] `python3 manage.py tables` および `python3 manage.py dbshell` が高速かつ正常に動作すること。
