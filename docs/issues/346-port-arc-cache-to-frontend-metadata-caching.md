---
ID: 346
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] ARCCache: src/core/structures/arc_cache.py の JS 移植と適応型キャッシュ (ID: 346)

## 1. 概要 / Summary

バックエンド `src/core/structures/arc_cache.py` で実装されている適応型置換キャッシュ（Adaptive Replacement Cache, ARC）アルゴリズムを、Web フロントエンド向け純粋 JavaScript モジュール `site/js/frameworks/arc-cache.js` に移植・実装する。

論文一覧の連続閲覧やグラフノードのホバー巡回において、頻繁に参照される論文メタデータや OKF Markdown ドキュメントを高ヒット率で保持しつつ、スキャン耐性（大規模一覧のスクロール時にも常連データがパージされない特性）を実現し、クライアントメモリ上限（デフォルト 100 件）を厳格に順守する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-27: モジュール型 Web フロントエンド・フレームワーク ＆ クライアントアーキテクチャ設計仕様書](../designs/DSN-27-modular_frontend_framework_and_client_architecture.md) (セクション 6.4, 8)
  - [DSN-02: 全体低位アーキテクチャ設計書 (共通データ構造基盤)](../designs/DSN-02-low_level_design.md)
  - [DSN-09: API Gateway ＆ UI プレゼンテーション包括設計書](../designs/DSN-09-web_gateway_and_presentation.md)
- 移植元コード:
  - `src/core/structures/arc_cache.py`
- 関連 Issue:
  - [Issue 338: Webフロントエンド設計・アーキテクチャの刷新と yuzora frameworks の統合](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/frameworks/arc-cache.js`](../../site/js/frameworks/arc-cache.js) (新規)
- [ ] [`site/externs.js`](../../site/externs.js) (`ARCCacheInterface` 型定義追加)
- [ ] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [ ] [`site/js/frameworks/api-client.js`](../../site/js/frameworks/api-client.js) (キャッシュ連携)
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (テストケース追加)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/346-port-arc-cache-to-frontend-metadata-caching`

1. **`ARCCache` クラスの設計と実装**:
   - 内部状態: 容量 $c$、ターゲットサイズ $p$、4つの双方向連結リスト（$T_1$: 最近参照, $T_2$: 頻出参照, $B_1$: $T_1$ 履歴ゴースト, $B_2$: $T_2$ 履歴ゴースト）
   - メソッド: `get(key)`, `set(key, value)`, `has(key)`, `clear()`, `size()`, `getStats()` (hit, miss, evictions)
   - ゴーストキャッシュヒット時の $p$ 適応学習ロジック（$\Delta = \max(1, |B_2| / |B_1|)$ または $\Delta = \max(1, |B_1| / |B_2|)$）
2. **Closure Compiler 適合**:
   - `site/externs.js` に `ARCCache` の型定義を追加
3. **`ApiClient` への組み込み**:
   - `/api/paper?id=...` のフェッチ結果を自動キャッシュし、重複通信を撲滅

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `site/js/frameworks/arc-cache.js` が実装され、JSDoc 型アノテーションが付与されていること
- [ ] ARC アルゴリズムの 4 リスト管理と $p$ の動的適応が数学的に正確であること
- [ ] `site/externs.js` に型定義が追加され、`make build_js` で警告 0 件であること
- [ ] LRU 単体に比べてスキャンアクセス時のキャッシュヒット率が有意に向上すること
- [ ] `tests/web/test_frontend_frameworks.py` にテストが追加され 100% PASS すること
- [ ] `make verify_quality` が完全通過すること
