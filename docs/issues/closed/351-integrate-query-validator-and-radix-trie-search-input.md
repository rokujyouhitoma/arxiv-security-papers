---
ID: 351
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-09-19
---

# [FEAT/ENH] `QueryValidator` & `RadixTrie`: 検索入力における PEG リアルタイム構文検証および 0ms プレフィックス補完の統合 (ID: 351)

## 1. 概要 / Summary
`site/app.js` の検索入力欄 (`searchInput`, `globalSearchInput`) に、`site/js/frameworks/query-validator.js` (PEG Lucene文法エンジン) および `site/js/frameworks/radix-trie.js` (圧縮プレフィックス木) を統合する。
ユーザーの入力中にリアルタイムでクエリ構文エラー（括弧の不一致、不正な演算子位置等）を可視化し、同時にセキュリティタグ、頻出カテゴリ、著者名の瞬時オートコンプリートサジェストを提供する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - [347-port-peg-query-validator-to-frontend-search-input.md](closed/347-port-peg-query-validator-to-frontend-search-input.md)
  - [345-port-radix-trie-to-frontend-instant-autocomplete.md](closed/345-port-radix-trie-to-frontend-instant-autocomplete.md)
  - [338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/app.js](../site/app.js) (検索入力イベントハンドラ、サジェストUI生成)
- [ ] [site/index.html](../site/index.html) (検索ボックスの構文エラー表示用コンテナ・スタイル)
- [ ] [site/css/](../site/css/) またはインラインスタイル (エラーバッジ・サジェストドロップダウン)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/351-integrate-query-validator-and-radix-trie`

1. **`QueryValidator` のリアルタイム検証**:
   - `searchInput` の `input` イベント（`Timing.debounce` 経由）で `QueryValidator.prototype.validate(val)` を呼び出す。
   - `isValid === false` の場合、入力枠にエラークラスを付与し、エラー位置（行・列）および `hint` をツールチップまたは下部バナーに表示。
   - 正しい構文または空文字列の場合は即座にエラー表示をクリア。
2. **`RadixTrie` の瞬時オートコンプリート**:
   - `/api/stats` または初回論文フェッチ時に、タグリスト・著者リスト・カテゴリを `RadixTrie` にインデックス。
   - 入力単語（キャレット位置のプレフィックス、または `tag:` / `author:` の後続語）に対して `searchPrefix(prefix, 5)` を実行。
   - キーボードナビゲーション（上下矢印キー、Enter）対応の軽量サジェストメニューを表示。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 不正なクエリ構文（例: `title:foo AND (`）入力時に、送信前段階でクライアント側エラーが表示されること。
- [ ] タグや著者の入力時に、`RadixTrie` から 0ms でプレフィックス候補がサジェストされること。
- [ ] Closure Compiler によるコンパイルがエラー 0 件で通過すること。
- [ ] 既存の全回帰テストが PASS すること。
