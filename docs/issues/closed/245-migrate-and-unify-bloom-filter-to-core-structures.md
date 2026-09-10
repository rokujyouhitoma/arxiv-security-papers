---
ID: 245
種別: Architecture / Refactor
優先度: High
ステータス: Closed
担当エージェント: Software Development (SWD) / Systems Architect
完了日: 2026-09-11
---

# [REFACTOR/CORE] ブルームフィルターの共通コア基盤 (src/core/structures/bloom_filter.py) への昇格・一元化と spider / database 重複コードの刷新 (ID: 245)

## 1. 概要 / Summary

現在、クローラ層 [`src/spider/core/bloom.py`](../../src/spider/core/bloom.py)（URL 訪問済み判定用 `BloomFilter` / `ScalableBloomFilter`）およびデータベース層 [`src/database/lsm/bloom_filter.py`](../../src/database/lsm/bloom_filter.py)（LSM-Tree SSTable の不要ディスク I/O スキップ用 `BloomFilter`）の 2 箇所に、ブルームフィルターが独立して二重実装されていた。

ハッシュ計算手法（Double Hashing: Kirsch-Mitzenmacher 技法）やビット配列管理、バイナリシリアライゼーションの仕様が乖離していたため、これを Roaring Bitmap と同様に共通コア層 [`src/core/structures/bloom_filter.py`](../../src/core/structures/bloom_filter.py) へ昇格・一元化した。

標準ライブラリ（`hashlib`, `math`, `struct`）のみを用いたゼロ外部依存の高性能 `BloomFilter` および自動スケーリング対応 `ScalableBloomFilter` を提供し、`src/spider/`、`src/database/`、および将来の検索エンジン・キャッシュ層から直接参照・利用可能にした。

---

## 2. トレーサビリティ / Traceability

- **設計書**: [`docs/designs/DSN-14-database_engine_architecture.md`](../designs/DSN-14-database_engine_architecture.md), [`docs/designs/DSN-04-search_engine_architecture.md`](../designs/DSN-04-search_engine_architecture.md)
- **関連 Issue**:
  - [`docs/issues/closed/241-migrate-roaring-bitmap-to-core-structures.md`](241-migrate-roaring-bitmap-to-core-structures.md)（Roaring Bitmap 共通化）
- **学術・技術参照**:
  - Bloom, B. H. (1970). "Space/time trade-offs in hash coding with allowable errors", *CACM*.
  - Kirsch, A., & Mitzenmacher, M. (2008). "Less hashing, same performance: Building a better Bloom filter", *Random Structures & Algorithms*.
  - Almeida, P. S., et al. (2007). "Scalable Bloom Filters", *Information Processing Letters*.

---

## 3. 脅威モデルとセキュリティ分析 (STRIDE / Threat Model)

| 脅威カテゴリ (STRIDE) | 潜在リスク | 緩和策・セキュリティ要件 |
| :--- | :--- | :--- |
| **Denial of Service (DoS)** | 巨大または不正な `capacity` / `error_rate` 引数によるメモリ枯渇、またはハッシュ衝突誘発攻撃 | `capacity` のバリデーション（`capacity > 0`）、`error_rate` の範囲バリデーション（`0 < error_rate < 1`）、Double Hashing での SHA-256 奇数ステップシードによる均一分散を保証。 |
| **Tampering** | SSTable 復元時におけるバイナリペイロードの切り詰めやビット長ヘッダー改竄 | `from_bytes` でヘッダー境界長検査（最小 6 バイト）およびペイロード長整合性を検証し、不正バイナリを `ValueError` で安全に拒絶。 |
| **Information Disclosure** | ブルームフィルターのビット配列解析による格納キーの逆算・漏洩リスク | 暗号学的 SHA-256 ハッシュ関数とモジュロ射影による不可逆不可視性を担保。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/core/structures/bloom_filter.py`](../../src/core/structures/bloom_filter.py) (新規):
  - `BloomFilter`: SHA-256 Double Hashing、誤検知率（FPP）自動ビット配列計算、`add() -> bool`、`contains()`、`to_bytes()` / `from_bytes()`
  - `ScalableBloomFilter`: 幾何級数多段ブルームフィルター（自動キャパシティスケール）
- [x] [`src/core/structures/__init__.py`](../../src/core/structures/__init__.py):
  - `BloomFilter`, `ScalableBloomFilter` のエクスポート
- [x] [`src/spider/core/bloom.py`](../../src/spider/core/bloom.py):
  - `src/core/structures/bloom_filter` からの直接インポート・再エクスポート
- [x] [`src/database/lsm/bloom_filter.py`](../../src/database/lsm/bloom_filter.py):
  - `src/core/structures/bloom_filter` の `BloomFilter` を直接再エクスポート
- [x] [`tests/core/test_bloom_filter.py`](../../tests/core/test_bloom_filter.py) (新規):
  - 共通コア `BloomFilter` および `ScalableBloomFilter` の包括的単体テスト（FPP精度、シリアライズ、スケーリング）
- [x] [`tests/spider/test_spider_core.py`](../../tests/spider/test_spider_core.py), [`tests/database/lsm/test_lsm_tree.py`](../../tests/database/lsm/test_lsm_tree.py):
  - 既存テストの回帰検証（全件 PASS）

---

## 5. 実装方針 / Implementation Plan

Target Branch: `refactor/245-migrate-and-unify-bloom-filter-to-core-structures`

### Step 1: 共通コア `src/core/structures/bloom_filter.py` の実装
- `BloomFilter` の統一:
  - 初期化: `def __init__(self, capacity: int = 1000, error_rate: float = 0.01, expected_items: Optional[int] = None, fp_rate: Optional[float] = None, ...)`
  - ハッシュ: 高速 SHA-256 Kirsch-Mitzenmacher Double Hashing。
  - 操作: `add(key: str) -> bool`, `contains(key: str) -> bool`, `__contains__(key: str) -> bool`, `__len__() -> int`, `clear() -> None`。
  - シリアライズ: `to_bytes() -> bytes`, `from_bytes(data: bytes, ...) -> BloomFilter`。
- `ScalableBloomFilter` の統一:
  - `initial_capacity: int = 10000`, `error_rate: float = 0.0001`, `scale_factor: int = 2`。
  - 容量飽和時に自動で新段フィルターを追加。

### Step 2: 各コンポーネントの移行
- `src/core/structures/__init__.py` に `BloomFilter`, `ScalableBloomFilter` を登録。
- `src/spider/core/bloom.py` を共通コアからの直接インポートに更新。
- `src/database/lsm/bloom_filter.py` を共通コアからの直接インポートに更新。

### Step 3: 包括的テストと品質ゲート検証
- `tests/core/test_bloom_filter.py` を新規作成（FPP実測、シリアライズ復元、境界値、破損ヘッダー検知）。
- スパイダーおよび LSM-Tree の既存テスト（全件）の実行と PASS 確認。
- `make check_format`、Xenon Rank A、`mypy --strict` 0 エラーの完全クリア。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `src/core/structures/bloom_filter.py` に `BloomFilter` および `ScalableBloomFilter` が実装されていること。
- [x] `src/spider/` および `src/database/lsm/` の重複実装が解消され、共通コアを参照していること。
- [x] 誤検知率（False Positive Rate）が指定された理論値（FPP < 1% 等）に収まり、False Negative が 0 件であることがテストで実証されること。
- [x] バイナリシリアライゼーション（`to_bytes` / `from_bytes`）のラウンドトリップが破損検知を含め正常に動作すること。
- [x] 既存のスパイダーおよび LSM-Tree の全テストが 100% PASS すること（リグレッション 0 件）。
- [x] Xenon Rank A (CC <= 4)、`mypy --strict` 0 エラー、フォーマッタ 100% 合格であること。
