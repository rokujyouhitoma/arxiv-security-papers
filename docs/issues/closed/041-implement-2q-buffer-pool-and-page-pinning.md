---
ID: 041
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-08-20
---

# [FEAT] 2Q バッファプール（スキャン汚染防止）と Pin/Unpin ページライフサイクル管理の実装 (ID: 041)

## 1. 概要 / Summary

[DSN-14 第4.3節 バッファプールとページ退避（LRU / CLOCK / 2Q）](../../designs/DSN-14-database_engine_architecture.md#43-バッファプールとページ退避lru--clock--2q) および マイルストーン1（コアストレージ堅牢化）に基づき、`src/database/pager.py` におけるページキャッシュを従来の単純 LRU から **「2Q（Two-Queue: $A1_{in}$ FIFO, $A1_{out}$ Ghost FIFO, $A_m$ LRU）バッファプール置換アルゴリズムおよび Pin/Unpin ページライフサイクル管理」** へ進化させた。

大規模論文データの全件走査（フルスキャン）や一括バックフィル実行時でも、高頻度アクセスされるインデックスや Hot Page がキャッシュから追放される「スキャン汚染（Scan Pollution）」を完全に防止し、クエリ処理中のページが安全にメモリ上に保持される Pin ガードを確立した。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../../designs/DSN-14-database_engine_architecture.md)
  - 4.3 バッファプールとページ退避 (LRU / CLOCK / 2Q)
  - 4.3.1 ページ置換アルゴリズム (Eviction Policies: 2Q vs LRU)
  - 4.3.2 ピン留め (Pinning) とダーティページフラッシュ (Steal/No-Force)
  - 15. 次世代実装ロードマップ マイルストーン 1
- 関連クローズド Issue:
  - [Issue 040: MVCC（多版同時実行制御）と SS2PL ロックマネージャ・デッドロック検知の実装](closed/040-implement-mvcc-and-ss2pl-transaction-manager.md)
  - [Issue 039: 追記型永続WALファイルとARIESクラッシュリカバリマネージャの実装](closed/039-implement-disk-persistent-wal-and-aries-recovery.md)
  - [Issue 038: スロット化ページ（Slotted-Page）バイナリストレージエンジンの実装](closed/038-implement-slotted-page-binary-storage-engine.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/database/buffer_pool.py](../../src/database/buffer_pool.py) (新規: 2Q ページ置換キュー $A1_{in}$, $A1_{out}$, $A_m$、Pin/Unpin 管理、Frame デスクリプタ)
- [x] [src/database/pager.py](../../src/database/pager.py) (変更: 2Q BufferPool 統合、`pin_page()`, `unpin_page()`, WAL-First 連携ダーティページ Eviction)
- [x] [src/database/__init__.py](../../src/database/__init__.py) (エクスポート更新: `BufferPool2Q`, `BufferFrame`, `BufferPoolError`)
- [x] [tests/database/test_buffer_pool_2q.py](../../tests/database/test_buffer_pool_2q.py) (新規: スキャン汚染耐性テスト、2Q 昇格・退避テスト、Pin/Unpin Eviction ガード、並行アクセステスト)

---

## 4. 実装成果 / Implementation Results

Target Branch: `feat/041-2q-buffer-pool`

### 4.1 2Q（Two-Queue）バッファプール設計 (`src/database/buffer_pool.py`)
- **3つのキュー構造**:
  1. **$A1_{in}$ (FIFO Queue, サイズ $K_{in} \approx 25\%$ of capacity)**: 初回アクセスされた新規ページを格納。$A1_{in}$ が $K_{in}$ を超えると、最も古いページを実メモリから破棄し $A1_{out}$ へ移動。
  2. **$A1_{out}$ (Ghost FIFO Queue, サイズ $K_{out} \approx 50\%$ of capacity)**: ページの実データは保持せず、`page_id` のみ（ゴースト）を記録。
  3. **$A_m$ (LRU Queue, 残り $75\%$ of capacity)**: $A1_{out}$ に存在する `page_id` が再度アクセスされた場合、高頻度 Hot ページとみなして $A_m$ に即時昇格。以降は LRU 順序で管理。
- **スキャン汚染耐性（Scan Resistance）**:
  - 1 回限りの大規模フルスキャン（全件走査）で読み込まれたページは $A1_{in}$ を通過して即座に破棄され、$A_m$ にある Hot なページ（インデックスルート等）を一切追い出さない。

### 4.2 Pin/Unpin ページライフサイクル管理
- **`BufferFrame` / `Page`**:
  - `pin()` / `unpin(is_dirty=False)` API による参照カウンタ（`pin_count`）の厳密管理。
  - `is_pinned()` によるクエリ実行中ページの保護。
  - `_evict_one()` において `pin_count == 0` のページのみを退避候補として選定。全ページが Pin されている場合は `BufferPoolError` を送出して安全にガード。

### 4.3 Pager への統合 (`src/database/pager.py`)
- `Pager` 内部の `PageCache` を `BufferPool2Q` で透過的に置き換え、下位互換性を 100% 維持。
- `pin_page(page_id)` / `unpin_page(page_id, is_dirty=False)` API を追加。
- ダーティページの退避時は Steal ポリシーに従い、WAL 先行書き込み（`PageLSN <= FlushedLSN`）を遵守。

---

## 5. 完了条件検証 (DoD Verification)

- [x] 2Q アルゴリズム（$A1_{in}$, $A1_{out}$, $A_m$）により、大量シーケンシャルスキャン後も Hot ページがキャッシュ内に保持されること（スキャン汚染耐性の実証）。
- [x] `pin_count > 0` のページがバッファプールから退避（Evict）されないことがテストで保証されること。
- [x] ダーティページの Eviction 時に Steal ポリシーに従い WAL が先行フラッシュされること。
- [x] `make check_format`, `make py_compile`, `make static_analysis` がエラー 0 件ですべて PASS すること。
- [x] 新規テストスイート（`tests/database/test_buffer_pool_2q.py`）が 100% PASS すること。
