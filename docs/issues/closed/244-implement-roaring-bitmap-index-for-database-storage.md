---
ID: 244
種別: Feature / Performance
優先度: Medium
ステータス: Closed (Completed)
担当エージェント: Database / Data Infrastructure Specialist / Software Development (SWD)
---

# [FEAT/DB] src/database における Roaring Bitmap を用いた低カーディナリティ列向け Bitmap Index およびタプル死活管理の実装 (ID: 244)

## 1. 概要 / Summary

自作DBMS基盤 `src/database/` において、低カーディナリティカラム（セキュリティカテゴリ、ステータスフラグ、重要度レベル等）の超高速等値・範囲検索を実現する **Bitmap Index（Roaring Bitmap バックエンド）** および、ストレージ層におけるタプル死活管理（Tombstone / Visibility Map）を実装する。

ClickHouse や Oracle Database のビットマップインデックスと同様に、各カラム値に対応するタプル ID（RowID / RID）の集合を [`src/core/structures/roaring_bitmap.py`](file:///workspace/arxiv-security-papers/src/core/structures/roaring_bitmap.py) で保持し、複合検索条件（例: `WHERE severity = 'CRITICAL' AND status = 'OPEN'`）をビット積（`&`）で一括評価可能にする。また、物理削除前の論理削除フラグ管理にも Roaring Bitmap を適用し、VACUUM プロセスおよび可視性判定（Visibility Map）を高速化する。

---

## 2. トレーサビリティ / Traceability

- **前提 Issue**: [`docs/issues/241-migrate-roaring-bitmap-to-core-structures.md`](file:///workspace/arxiv-security-papers/docs/issues/241-migrate-roaring-bitmap-to-core-structures.md)
- **関連 Issue**: [`docs/issues/242-apply-roaring-bitmap-to-mvcc-transaction-snapshots.md`](file:///workspace/arxiv-security-papers/docs/issues/242-apply-roaring-bitmap-to-mvcc-transaction-snapshots.md), [`docs/issues/243-apply-roaring-bitmap-to-search-filter-cache.md`](file:///workspace/arxiv-security-papers/docs/issues/closed/243-apply-roaring-bitmap-to-search-filter-cache.md)
- **設計書**: [`docs/designs/DSN-14-database_engine_architecture.md`](file:///workspace/arxiv-security-papers/docs/designs/DSN-14-database_engine_architecture.md)
- **学術・技術参照**:
  - O'Neil, P., & Quass, D. (1997). "Improved query performance with variant indexes", *ACM SIGMOD Record*.
  - Wu, K., et al. (2006). "On the performance of bitmap indices for high-cardinality attributes", *VLDB*.

---

## 3. 脅威モデルとセキュリティ分析 (STRIDE / Threat Model)

| 脅威カテゴリ (STRIDE) | 潜在リスク | 緩和策・セキュリティ要件 |
| :--- | :--- | :--- |
| **Denial of Service (DoS)** | 高カーディナリティ値（一意ID等）に対する無秩序なビットマップ生成によるメモリ肥大化 | `cardinality_threshold`（デフォルト 10,000）を設け、許容カーディナリティ超過時の警告またはインデックス更新制限を実施。Roaring Bitmap コンテナ（Array/Run/Bitmap）による圧縮を徹底。 |
| **Information Disclosure** | 削除済み（Tombstone）タプルの RowID がビットマップインデックス検索結果に残留し、死活情報が漏洩するリスク | `VisibilityMap` によるビット差分（`index_result - tombstone_bitmap`）を徹底し、削除済み RowID がクエリ結果に一切出現しないことを保証。 |
| **Tampering** | インデックスのバイナリシリアライズ / デシリアライズ時のヘッダー改変やバイト列破壊 | マジックバイト（`BMIDX01`）検証、チェックサム、および長さ境界検査を実施し、不正バイナリを `ValueError` で安全に拒絶。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/database/index/bitmap_index.py`](file:///workspace/arxiv-security-papers/src/database/index/bitmap_index.py) (新規):
  - `RoaringBitmapIndex`: 単一カラムの低カーディナリティ値ごとの `RoaringBitmap` マッピング、等値検索 (`get`)、IN 検索 (`get_in`)、複合条件評価 (`eval_and`, `eval_or`, `eval_not`)、シリアライズ/デシリアライズ
  - `TableBitmapIndexes`: テーブル単位で複数カラムのビットマップインデックスを一括管理するマネージャ
- [x] [`src/database/storage/visibility_map.py`](file:///workspace/arxiv-security-papers/src/database/storage/visibility_map.py) (新規):
  - `VisibilityMap`: Roaring Bitmap を用いたタプルの可視性・生死（Live / Tombstone）追跡、VACUUM 前後の一括更新
- [x] [`src/database/index/__init__.py`](file:///workspace/arxiv-security-papers/src/database/index/__init__.py):
  - `RoaringBitmapIndex`, `TableBitmapIndexes` の公開
- [x] [`src/database/storage/__init__.py`](file:///workspace/arxiv-security-papers/src/database/storage/__init__.py):
  - `VisibilityMap` の公開
- [x] [`src/database/__init__.py`](file:///workspace/arxiv-security-papers/src/database/__init__.py):
  - ルートパッケージからのエクスポート整備
- [x] [`tests/database/test_bitmap_index.py`](file:///workspace/arxiv-security-papers/tests/database/test_bitmap_index.py) (新規):
  - ビットマップインデックスの単一・複合クエリ、VisibilityMap 連携、永続化、メモリ効率のテスト

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/244-implement-roaring-bitmap-index-for-database-storage`

### Step 1: `RoaringBitmapIndex` & `TableBitmapIndexes` の実装
- `src/database/index/bitmap_index.py`:
  - `RoaringBitmapIndex`: `column_name: str`, `_bitmaps: Dict[Any, RoaringBitmap]`
  - `insert(val: Any, row_id: int) -> None`
  - `delete(val: Any, row_id: int) -> None`
  - `lookup(val: Any) -> RoaringBitmap`
  - `lookup_in(values: Iterable[Any]) -> RoaringBitmap`
  - `all_rows() -> RoaringBitmap`
  - `to_bytes() -> bytes` / `from_bytes(data: bytes) -> RoaringBitmapIndex`
  - `TableBitmapIndexes`: 複数列インデックスの保持と複合クエリ（AND / OR / NOT）のビット演算一括解決

### Step 2: `VisibilityMap` の実装
- `src/database/storage/visibility_map.py`:
  - `VisibilityMap`: `_live_rows: RoaringBitmap`, `_tombstones: RoaringBitmap`
  - `mark_inserted(row_id: int) -> None`
  - `mark_deleted(row_id: int) -> None`
  - `is_visible(row_id: int) -> bool`
  - `filter_visible(candidates: RoaringBitmap) -> RoaringBitmap`（`candidates - self._tombstones`）
  - `vacuum_compact(retained_rows: RoaringBitmap) -> None`

### Step 3: パッケージ公開と統合
- `src/database/index/__init__.py`, `src/database/storage/__init__.py`, `src/database/__init__.py` にクラスを登録。
- Xenon Rank A（CC <= 4）を満たすクリーンな関数設計。

### Step 4: 単体テストと品質検証
- `tests/database/test_bitmap_index.py`:
  - 等値検索、IN検索、複合条件（AND/OR/NOT）の正確性
  - `VisibilityMap` との組み合わせによる論理削除タプルの完全除外
  - バイナリシリアライゼーションのラウンドトリップ
  - `make check_format`、`xenon`、`mypy --strict` の完全合格

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `RoaringBitmapIndex` が低カーディナリティ列の値を Roaring Bitmap で管理し、ビット積・ビット和で高速評価できること。
- [x] `VisibilityMap` がタプルの生死を Roaring Bitmap で追跡し、削除済み RowID を瞬時にフィルタリングできること。
- [x] バイナリシリアライゼーション（`to_bytes` / `from_bytes`）が改竄検知を含めて正常に動作すること。
- [x] `tests/database/test_bitmap_index.py` が新規作成され、全ケース PASS すること。
- [x] 既存の全データベーステスト（LSM, B-tree, MVCC, SQL, Storage）にリグレッションが発生しないこと。
- [x] Xenon Rank A (CC <= 4)、`mypy --strict` 0 エラー、フォーマッタ 100% 合格であること。

