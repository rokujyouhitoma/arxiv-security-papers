---
ID: 346
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] ARCCache: src/core/structures/arc_cache.py の JS 移植と適応型キャッシュ (ID: 346)

## 1. 概要 / Summary

バックエンド `src/core/structures/arc_cache.py` で実装されている適応型置換キャッシュ（Adaptive Replacement Cache, ARC）アルゴリズム（Megiddo & Modha, FAST '03 準拠）を、Web フロントエンド向け純粋 JavaScript モジュール `site/js/frameworks/arc-cache.js` に完全移植・実装する。

論文一覧の連続スクロール閲覧やグラフノードのホバー巡回において、頻繁に参照される論文メタデータや OKF Markdown ドキュメントを高ヒット率で保持しつつ、スキャン耐性（大規模一覧のスクロール時にも常連データがパージされない特性）を実現し、クライアントメモリ上限（デフォルト 128 件）を厳格に順守する。

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

- [x] [`site/js/frameworks/arc-cache.js`](../../site/js/frameworks/arc-cache.js) (新規実装)
- [x] [`site/externs.js`](../../site/externs.js) (`ARCCacheInterface` 型定義追加)
- [x] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [x] [`site/js/frameworks/api-client.js`](../../site/js/frameworks/api-client.js) (キャッシュ連携のサポート)
- [x] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (テストケース追加)
- [x] [`docs/issues/README.md`](README.md) (台帳更新)

---

## 4. セキュリティ考慮事項 / Security Analysis & Threat Modeling

1. **メモリ枯渇 (DoS) の防止**:
   - `capacity` 引数について $1 \le c \le 1,000,000$ の境界値ガードを施し、不正な極大値や負数・NaN の注入によるブラウザクラッシュ（OOM）を防止する。
   - $T_1 \cup T_2$ のエントリ総数は常に $\le c$、ゴースト $B_1 \cup B_2$ を含めた追跡総数は常に $\le 2c$ に厳格にクリップする。
2. **キャッシュポイズニング & プロトタイプ汚染の防止**:
   - 内部データストアにプレーンオブジェクト `{}` ではなく native `Map` を使用することで、`__proto__` や `constructor` などのプロトタイプ汚染脆弱性を原理的に排除する。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/346-port-arc-cache-to-frontend-metadata-caching`

1. **`ARCCache` クラスの設計と実装 (`site/js/frameworks/arc-cache.js`)**:
   - 内部状態:
     - `capacity` (クランプされたキャッシュ容量 $c$)
     - `p` (適応ターゲットサイズ $p \in [0, c]$)
     - `t1`: $T_1$ (Recency / 1回のみ参照されたアクティブキャッシュ) - native `Map`
     - `t2`: $T_2$ (Frequency / 複数回参照されたアクティブキャッシュ) - native `Map`
     - `b1`: $B_1$ (Ghost Recency / $T_1$ から追放されたキー履歴) - native `Map`
     - `b2`: $B_2$ (Ghost Frequency / $T_2$ から追放されたキー履歴) - native `Map`
     - `_hits`, `_misses`: 統計カウンタ
   - ヘルパー関数:
     - `popLru_(map)`: `map.keys().next().value` を取得して削除し、キーを返す ($O(1)$)
     - `shouldEvictT1_(t1Len, p, inB2)`
     - `stepReplace_(t1, t2, b1, b2, p, capacity, inB2)`
     - `pruneB1IfFull_(t1Len, b1, capacity)`
     - `pruneB2IfFull_(total, b2, capacity)`
     - `pruneGhostForMiss_(t1, t2, b1, b2, capacity)`
   - パブリック API:
     - `get(key, defaultValue = null)`: $T_1$ ヒット時は $T_2$ へ昇格、$T_2$ ヒット時は末尾へ移動。ミス時は `_misses` カウント。
     - `set(key, value)` / `put(key, value)`: 冪等な登録・更新。$B_1$ / $B_2$ ヒット時の $p$ 適応調整ロジック（$\Delta = \max(1, |B_2| / |B_1|)$ 等）および `replace` の発火。
     - `has(key)`: $T_1$ または $T_2$ に存在するか
     - `delete(key)`: $T_1, T_2, B_1, B_2$ から完全除去
     - `clear()`: 状態全リセット
     - `size()`: $T_1 + T_2$ のサイズ
     - `keys()`: アクティブキーの配列
     - `getStats()`: `{ hits, misses, hitRatio, p, capacity, t1Size, t2Size, b1Size, b2Size }`
2. **`ApiClient` へのオプション連携 (`site/js/frameworks/api-client.js`)**:
   - `ApiClient` のコンストラクタで optional `cache` 引数を受領可能にし、`get()` 呼び出し時に `cache` が指定されていれば自動取得・自動保存をサポート。
3. **Closure Compiler 型定義 (`site/externs.js`)**:
   - `ARCCacheInterface` を追加し、全パブリックメソッドを extern 定義。
4. **ビルドパイプライン統合 (`Makefile`)**:
   - `JS_SRCS` に `site/js/frameworks/arc-cache.js` を追加。
   - `make build_js` による難読化・最小化バンドル生成。
5. **ユニットテストと品質検証 (`tests/web/test_frontend_frameworks.py`)**:
   - Node.js サブプロセスを用いた ARC キャッシュの動作検証:
     - 基本的な get/put/delete/clear
     - $T_1$ から $T_2$ へのプロモーション
     - スキャン耐性（Scan Resistance）の検証: 常連データを $T_2$ に入れた後、大容量のワンショットスキャンを流しても常連データが残ることを確認
     - $p$ の適応学習（Recency 偏重 vs Frequency 偏重）の検証

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `site/js/frameworks/arc-cache.js` が実装され、JSDoc 型アノテーションが付与されていること
- [x] ARC アルゴリズムの 4 リスト管理と $p$ の動的適応が数学的・論理的に正確であること
- [x] `site/externs.js` に型定義が追加され、`make build_js` で警告 0 件であること
- [x] LRU 単体に比べてスキャンアクセス時のキャッシュヒット率が有意に維持されること
- [x] `tests/web/test_frontend_frameworks.py` にテストが追加され 100% PASS すること
- [x] `make check_format` および `make static_analysis` が完全通過すること


