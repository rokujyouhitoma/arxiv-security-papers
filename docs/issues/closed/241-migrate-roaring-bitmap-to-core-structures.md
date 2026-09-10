---
ID: 241
種別: Architecture / Refactor
優先度: High
ステータス: Closed (Completed)
担当エージェント: Systems Architect / Software Development (SWD) / Software Quality Assurance Specialist
---

# [ARCH/CORE] Roaring Bitmap データ構造の src/core/structures/roaring_bitmap.py への共通化・昇格と直接参照への刷新 (ID: 241)

## 1. 概要 / Summary

Issue #239 において `src/search/core/index/roaring_bitmap.py` に実装された 32-bit Pure-Python Roaring Bitmap を、検索エンジン専用コンポーネントからプロジェクト全体の共通コア基盤 [`src/core/structures/roaring_bitmap.py`](file:///workspace/arxiv-security-papers/src/core/structures/roaring_bitmap.py) へ移動・昇格する。

ユーザー指示に基づき、旧パス `src/search/core/index/roaring_bitmap.py` への後方互換用エイリアス・ラッパー（古いインポートパスの転送定義）は一切設置せず、完全に削除した。
検索エンジン（`src/search/core/index/__init__.py`, `src/search/core/store/segment.py`, `src/search/engine/index/__init__.py`）およびテストスイートを含むすべての参照元を `from core.structures.roaring_bitmap import RoaringBitmap` へ直接インポートする形へ完全に統一・刷新した。

また、Roaring Bitmap 本体の包括的単体テストを [`tests/core/test_roaring_bitmap.py`](file:///workspace/arxiv-security-papers/tests/core/test_roaring_bitmap.py) へ移動・配置し、コア共通データ構造としての回帰検証体制を確立した。

---

## 2. トレーサビリティ / Traceability

- **前提 Issue**: [`docs/issues/closed/239-implement-roaring-bitmap-for-search-deletion-bitset.md`](file:///workspace/arxiv-security-papers/docs/issues/closed/239-implement-roaring-bitmap-for-search-deletion-bitset.md)
- **後続 Issue**:
  - [`docs/issues/242-apply-roaring-bitmap-to-mvcc-transaction-snapshots.md`](file:///workspace/arxiv-security-papers/docs/issues/242-apply-roaring-bitmap-to-mvcc-transaction-snapshots.md)
  - [`docs/issues/243-apply-roaring-bitmap-to-search-filter-cache.md`](file:///workspace/arxiv-security-papers/docs/issues/243-apply-roaring-bitmap-to-search-filter-cache.md)
  - [`docs/issues/244-implement-roaring-bitmap-index-for-database-storage.md`](file:///workspace/arxiv-security-papers/docs/issues/244-implement-roaring-bitmap-index-for-database-storage.md)
- **設計書**: [`docs/designs/DSN-04-search_engine_architecture.md`](file:///workspace/arxiv-security-papers/docs/designs/DSN-04-search_engine_architecture.md)
- **コア基盤アーキテクチャ**: [`src/core/`](file:///workspace/arxiv-security-papers/src/core/)（`src/core/hsm/` と並ぶ共通データ構造層 `src/core/structures/` の確立）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/core/structures/__init__.py`](file:///workspace/arxiv-security-papers/src/core/structures/__init__.py) (新規):
  - `core.structures` パッケージ初期化および `RoaringBitmap`、コンテナクラスのエクスポート
- [x] [`src/core/structures/roaring_bitmap.py`](file:///workspace/arxiv-security-papers/src/core/structures/roaring_bitmap.py) (新規・移動):
  - `src/search/core/index/roaring_bitmap.py` から移動した Roaring Bitmap コア実装（Pure Python 3.14）
- [x] [`src/search/core/index/roaring_bitmap.py`](file:///workspace/arxiv-security-papers/src/search/core/index/roaring_bitmap.py) (削除):
  - 旧ファイルを完全削除（ラッパーなし）
- [x] [`src/search/core/index/__init__.py`](file:///workspace/arxiv-security-papers/src/search/core/index/__init__.py):
  - `from core.structures.roaring_bitmap import RoaringBitmap` へ更新
- [x] [`src/search/core/store/segment.py`](file:///workspace/arxiv-security-papers/src/search/core/store/segment.py):
  - `from core.structures.roaring_bitmap import RoaringBitmap` へ更新
- [x] [`src/search/engine/index/__init__.py`](file:///workspace/arxiv-security-papers/src/search/engine/index/__init__.py):
  - `from core.structures.roaring_bitmap import RoaringBitmap` へ更新
- [x] [`tests/core/test_roaring_bitmap.py`](file:///workspace/arxiv-security-papers/tests/core/test_roaring_bitmap.py) (新規・移動):
  - コアデータ構造としての単体テストスイート（15テスト）
- [x] [`tests/search/test_roaring_bitmap.py`](file:///workspace/arxiv-security-papers/tests/search/test_roaring_bitmap.py) (削除・移動):
  - `tests/core/test_roaring_bitmap.py` へ移動完了

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/241-migrate-roaring-bitmap-to-core-structures`

### Step 1: `src/core/structures/` パッケージの作成
- `src/core/structures/` ディレクトリを作成。
- `src/core/structures/__init__.py` を作成し、RoaringBitmap およびコンテナクラスをエクスポート。

### Step 2: Roaring Bitmap ファイルの移動
- `src/search/core/index/roaring_bitmap.py` を `src/core/structures/roaring_bitmap.py` へ移動。
- `src/search/core/index/roaring_bitmap.py` は完全削除（ラッパーを置かない）。

### Step 3: 検索エンジン参照元の直接インポート更新
- `src/search/core/index/__init__.py`, `src/search/core/store/segment.py`, `src/search/engine/index/__init__.py` の参照元を直接 `core.structures.roaring_bitmap` へ更新。

### Step 4: 単体テストの移動と検証
- `tests/search/test_roaring_bitmap.py` を `tests/core/test_roaring_bitmap.py` へ移動。
- 全テストおよび品質ゲート（Xenon Rank A, mypy --strict）を検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `src/core/structures/roaring_bitmap.py` に Roaring Bitmap の全実装が配置されていること。
- [x] `src/core/structures/__init__.py` で公開シンボルが適切にエクスポートされていること。
- [x] 旧パス `src/search/core/index/roaring_bitmap.py` が削除され、不要な後方互換ラッパーが残存していないこと。
- [x] 検索エンジンの全参照箇所が `core.structures.roaring_bitmap` を直接インポートして透過的に動作すること。
- [x] `tests/core/test_roaring_bitmap.py`（15件全件 PASS）および全検索テスト（91件全件 PASS、計106件）がリグレッションなしで合格すること。
- [x] Xenon Rank A (CC $\le 4$)、`mypy --strict` 0 エラー、フォーマッタ 100% 合格であること。

---

## 6. 実装完了と検証結果 / Resolution & Verification

### 6.1 実装内容
1. **共通データ構造パッケージの新設**:
   - `src/core/structures/` を作成し、`src/core/structures/__init__.py` で `RoaringBitmap`, `Container`, `ArrayContainer`, `BitmapContainer`, `RunContainer` 等の公開シンボルをエクスポート。
2. **コアファイル配置と旧ファイル削除**:
   - `src/search/core/index/roaring_bitmap.py` を `src/core/structures/roaring_bitmap.py` へ移動。後方互換エイリアスは設置せず旧パスを完全削除。
3. **検索エンジンの直接インポート統一**:
   - `src/search/core/index/__init__.py`
   - `src/search/core/store/segment.py`
   - `src/search/engine/index/__init__.py`
   全ファイルで `from core.structures.roaring_bitmap import RoaringBitmap` を直接参照するよう刷新。
4. **テストスイートの配置適正化**:
   - `tests/search/test_roaring_bitmap.py` を `tests/core/test_roaring_bitmap.py` へ移動し、`tests/core/` 配下の共通テストとして位置づけ。

### 6.2 品質ゲート検証
- **単体テスト**: `tests/core/test_roaring_bitmap.py` 15 件全件 PASS。
- **検索リグレッション**: `tests/search/` 91 件全件 PASS（ノーリグレッション確認）。
- **型検査**: `mypy --strict src/core/structures/ tests/core/test_roaring_bitmap.py` エラー 0 件。
- **循環的複雑度**: `xenon --max-absolute A` 全モジュール Rank A 達成。
- **コード規約**: `isort`, `black`, `flake8` 100% 合格。
