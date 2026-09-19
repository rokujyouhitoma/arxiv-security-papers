---
ID: 345
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] RadixTrie: src/core/structures/radix_trie.py の JS 移植と 0ms 検索サジェスト (ID: 345)

## 1. 概要 / Summary

バックエンド `src/core/structures/radix_trie.py` で実装されている共通接頭辞圧縮基数木（Radix Trie / Patricia Tree）を、Web フロントエンド向け純粋 JavaScript モジュール `site/js/frameworks/radix-trie.js` に移植・実装する。

コンソールの検索入力バー（`#searchInput`, `#globalSearchInput`）において、数千件の MITRE ATT&CK テクニック ID（`T1059`, `T1566` 等）、CVE/CWE 番号、セキュリティカテゴリタグ、著者名に対して、サーバー問い合わせを行わずに 0ms（キー入力追従）でインクリメンタルな前方一致サジェスト候補を展開する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-27: モジュール型 Web フロントエンド・フレームワーク ＆ クライアントアーキテクチャ設計仕様書](../designs/DSN-27-modular_frontend_framework_and_client_architecture.md) (セクション 6.3, 8)
  - [DSN-02: 全体低位アーキテクチャ設計書 (共通データ構造基盤)](../designs/DSN-02-low_level_design.md)
  - [DSN-04: 2層検索エンジン & プラットフォーム設計書](../designs/DSN-04-search_engine_and_platform.md)
  - [DSN-21: エンタープライズ統合デザインシステム ＆ クラウドコンソール UI 包括設計書](../designs/DSN-21-enterprise_design_system_and_unified_console.md)
- 移植元コード:
  - `src/core/structures/radix_trie.py`
- 関連 Issue:
  - [Issue 338: Webフロントエンド設計・アーキテクチャの刷新と yuzora frameworks の統合](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/frameworks/radix-trie.js`](../../site/js/frameworks/radix-trie.js) (新規)
- [ ] [`site/externs.js`](../../site/externs.js) (`RadixTrieInterface` 型定義追加)
- [ ] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [ ] [`site/app.js`](../../site/app.js) (検索サジェスト UI との連動)
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (テストケース追加)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/345-port-radix-trie-to-frontend-instant-autocomplete`

1. **`RadixTrie` クラスの設計と実装**:
   - ノード構造: `prefix`, `value`, `isLeaf`, `children` (Map 構造)
   - メソッド: `insert(key, value)`, `search(key)`, `searchPrefix(prefix, limit = 10)`, `delete(key)`, `size()`
   - 接頭辞の分割（Edge Splitting）とマージ（Edge Merging）アルゴリズム
   - Prototype Pollution 防御（内部 Map の厳格使用）
2. **Closure Compiler 適合**:
   - `site/externs.js` に `RadixTrie` の型定義を追加
3. **UI 統合**:
   - `TimingUtils.debounce` と組み合わせ、検索バー入力時に即座に候補ドロップダウンを描画

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `site/js/frameworks/radix-trie.js` が実装され、JSDoc 型アノテーションが付与されていること
- [ ] `src/core/structures/radix_trie.py` と同等の接頭辞圧縮・部分一致抽出ロジックが成立していること
- [ ] `site/externs.js` に型定義が追加され、`make build_js` で警告 0 件であること
- [ ] 5,000 件の語彙に対するプレフィックス検索が 1ms 未満で完了すること
- [ ] `tests/web/test_frontend_frameworks.py` にテストが追加され 100% PASS すること
- [ ] `make verify_quality` が完全通過すること
