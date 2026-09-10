---
ID: 244
種別: Feature / Performance
優先度: Medium
ステータス: Open (New)
担当エージェント: Database / Data Infrastructure Specialist / Software Development (SWD)
---

# [FEAT/DB] src/database における Roaring Bitmap を用いた低カーディナリティ列向け Bitmap Index およびタプル死活管理の実装 (ID: 244)

## 1. 概要 / Summary

自作DBMS基盤 `src/database/` において、低カーディナリティカラム（セキュリティカテゴリ、ステータスフラグ、重要度レベル等）の超高速等値・範囲検索を実現する **Bitmap Index（Roaring Bitmap バックエンド）** および、ストレージ層におけるタプル死活管理（Tombstone / Visibility Map）を実装する。

ClickHouse や Oracle Database のビットマップインデックスと同様に、各カラム値に対応するタプル ID（RowID / RID）の集合を [`src/core/structures/roaring_bitmap.py`](file:///workspace/arxiv-security-papers/src/core/structures/roaring_bitmap.py) で保持し、複合検索条件（例: `WHERE severity = 'CRITICAL' AND status = 'OPEN'`）をビット積（`&`）で一括評価可能にする。また、物理削除前の論理削除フラグ管理にも Roaring Bitmap を適用し、VACUUM プロセスを高速化する。

---

## 2. トレーサビリティ / Traceability

- **前提 Issue**: [`docs/issues/241-migrate-roaring-bitmap-to-core-structures.md`](file:///workspace/arxiv-security-papers/docs/issues/241-migrate-roaring-bitmap-to-core-structures.md)
- **設計書**: [`docs/designs/DSN-14-database_engine_architecture.md`](file:///workspace/arxiv-security-papers/docs/designs/DSN-14-database_engine_architecture.md)
- **学術・技術参照**:
  - O'Neil, P., & Quass, D. (1997). "Improved query performance with variant indexes", *ACM SIGMOD Record*.

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/database/index/bitmap_index.py`](file:///workspace/arxiv-security-papers/src/database/index/bitmap_index.py) (新規):
  - `RoaringBitmapIndex`: 値ごとの RoaringBitmap マッピングおよび複合クエリ結合ロジック
- [ ] [`src/database/index/__init__.py`](file:///workspace/arxiv-security-papers/src/database/index/__init__.py):
  - `RoaringBitmapIndex` のエクスポート
- [ ] [`src/database/storage/`](file:///workspace/arxiv-security-papers/src/database/storage/):
  - テーブルの RowID 削除フラグ（Tombstone）管理への Roaring Bitmap 統合
- [ ] [`tests/database/test_bitmap_index.py`](file:///workspace/arxiv-security-papers/tests/database/) (新規):
  - ビットマップインデックスの作成、追加、削除、複合ビット積クエリの検証

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/244-implement-roaring-bitmap-index-for-database-storage`

1. **RoaringBitmapIndex クラスの実装**:
   - `Dict[Any, RoaringBitmap]` によるキー値ごとの RowID ビットセット管理。
   - `lookup(val: Any) -> RoaringBitmap`
   - `multi_lookup(conditions: List[Tuple[str, Any]]) -> RoaringBitmap` による高速ビット積（`&`）評価。
2. **ストレージ層への統合**:
   - 挿入時に各カラムインデックスに RowID を `add()`。
   - 削除（Tombstone）時に `tombstone_bitmap.add(row_id)`。
3. **テスト・品質検証**:
   - B-tree との検索速度・メモリ比較、Xenon Rank A、`mypy --strict` 検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `src/database/index/bitmap_index.py` に `RoaringBitmapIndex` が実装され、等値・複合検索がビット演算で行えること。
- [ ] 低カーディナリティ列の検索において、フルテーブルスキャンと比較して大幅な高速化が達成されること。
- [ ] 新規単体テストが作成され、全件 PASS すること。
- [ ] Xenon Rank A、`mypy --strict` 0 エラー、フォーマッタ 100% 合格であること。
