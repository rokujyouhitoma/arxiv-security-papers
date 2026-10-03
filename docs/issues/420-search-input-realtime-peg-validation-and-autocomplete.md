---
ID: 420
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] 検索窓における Lucene PEG リアルタイム構文検証・エラーハイライト・オートコンプリートの実装 (ID: 420)

## 1. 概要 / Summary

本リポジトリのフロントエンドには、Packrat PEG エンジンと Lucene 文法規則を備えた `site/js/frameworks/query-validator.js`（DSN-25 / DSN-04 準拠）が実装されているが、Web コンソール（`site/app.js`）の検索ボックス（`#searchInput`, `#globalSearchInput`）では Enter キー押下時にバックエンド API を呼び出すのみで、入力中のリアルタイムな構文診断・エラーハイライト・オートコンプリートが連動していない。
特に、現在 `app.js` 内で行われているバリデーション処理では `vResult.error.message` を参照しているが、`vResult.error` は文字列型であるため `undefined` となり「構文警告: 構文エラー」という無意味なツールチップしか表示されない不具合が存在する。

本 Issue では、ユーザーのタイピング時（`input` イベント）に `QueryValidator.validate()` および新設する `QueryValidator.suggest(queryString, cursorOffset)` をデバウンス実行し、PEG パーサーの到達位置（`calcLineCol`）と Levenshtein 診断情報を利用して、未終了引用符（`"..."`）や括弧の不整合（`(...)`）、不正な演算子（`AND`, `OR`, `NOT` の連続）をリアルタイムに視覚的フィードバック（警告バッジ・ガイダンスメッセージ）として表示し、構文補完候補（フィールド名、演算子、タイポ修正候補）をインタラクティブに提示・補完する UI 基盤を構築する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第7.2節 検索クエリパーサー、第13節 Phase 6 JavaScript コードジェネレータ基盤)
  - [`docs/designs/DSN-04-search_engine_and_platform.md`](../designs/DSN-04-search_engine_and_platform.md) (検索エンジン構文解析仕様)
- **関連 Issue**:
  - Issue #299: 検索クエリパーサーの宣言的 AOT 換装
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装
  - Issue #419: クライアントサイド CTI グラフクエリ DSL の AOT 生成とダッシュボード統合
  - Issue #426: JS 生成パーサーにおける PEGSyntaxError 診断情報拡充と parseWithDiagnostics API の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### フロントエンド JavaScript & スタイル
- [ ] [`site/js/frameworks/query-validator.js`](../../site/js/frameworks/query-validator.js)（`suggest(queryString, cursorOffset)` API および診断詳細構造化の追加）
- [ ] [`site/app.js`](../../site/app.js)（検索入力デバウンス検証、構文エラーバッジ/ヒント描画、オートコンプリートドロップダウン操作）
- [ ] [`site/index.html`](../../site/index.html)（検索入力コンテナの拡張: バッジおよびオートコンプリートドロップダウン用要素）
- [ ] [`site/css/style.css`](../../site/css/style.css)（構文エラーバッジ、警告ボーダー、オートコンプリート候補ドロップダウンのスタイリング）
- [ ] [`site/app-min.js`](../../site/app-min.js) & [`site/dashboard-min.js`](../../site/dashboard-min.js)（Closure Compiler ビルド成果物）

### テストスイート & ビルド
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py)（`QueryValidator.suggest` およびリアルタイム診断のテストケース追加）
- [ ] [`Makefile`](../../Makefile)（品質ゲート確認）

---

## 4. セキュリティ分析 (STRIDE Threat Model) と防御策

| 脅威分類 | 潜在的リスク | 防御策 |
| :---: | --- | --- |
| **Spoofing** | 悪意ある入力によるサジェスト偽装 | フィールド名およびキーワードはホワイトリスト（`title:`, `author:`, `abstract:`, `category:`, `tags:`, `year:`, `AND`, `OR`, `NOT`）からのみ生成。 |
| **Tampering** | クライアント側 DOM の不正操作 | エラーメッセージおよび補完候補の描画に `textContent` を厳格適用し、innerHTML インジェクション・XSS を完全排除。 |
| **Repudiation** | 構文エラー発生時の不透明性 | 正確なエラー位置（行・列）、期待されるトークン群、および Levenshtein 近傍候補を明示。 |
| **Information Disclosure** | 内部スタックトレースの漏洩 | エラー発生時はサニタイズされた `PEGSyntaxError` メッセージと行桁情報のみを UI 表示。 |
| **Denial of Service (ReDoS)** | 長大入力・正規表現爆発による UI 凍結 | 入力文字数を `MAX_INPUT_LENGTH` (8192) で制限、Packrat PEG の線形時間 $O(N)$ パース保証、150ms デバウンス。 |
| **Elevation of Privilege** | 特権昇格 / スクリプト実行 | スクリプトタグやイベントハンドラーを含まない純粋なテキスト補完のみを許可。 |

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/420-search-input-realtime-peg-validation-and-autocomplete`

### 5.1 `query-validator.js` の補完・診断 API 拡充
1. **`QueryValidator.prototype.suggest(queryString, cursorOffset)` の実装**:
   - カーソル直前の単語（またはプレフィックス）を解析。
   - フィールド名プレフィックス（`tit` → `title:`, `auth` → `author:`, `cat` → `category:` 等）の補完候補を生成。
   - 既知のフィールド名のタイポに対して Levenshtein 距離 $\le 2$ の修正候補（例: `authr:` → `author:`）を推薦。
   - 演算子補完（`AN` → `AND`, `O` → `OR`, `NO` → `NOT`）。
   - 未閉じクォート（`"..."`）や未閉じ括弧（`(...)`）が検知された場合、閉じトークン（`"` や `)`）の補完アクションを提示。
2. **`QueryValidator.prototype.validate(queryString)` の不具合修正**:
   - `error` プロパティの文字列型と `error.message` 参照の不整合を解消（オブジェクト `{ message: string, line, col, ... }` または明瞭なフォーマット済みメッセージを提供）。

### 5.2 UI & イベントハンドラ統合 (`site/app.js` & `site/index.html`)
1. **HTML 構造の拡張 (`site/index.html`)**:
   - `.inline-search-box` 内に入力補完用バッジ `#searchSyntaxBadge` および候補ドロップダウン `#searchAutocompleteDropdown` を配置。
2. **`site/app.js` でのデバウンス監視**:
   - `#searchInput` 入力時、150ms のデバウンスで `QueryValidator.validate()` および `suggest()` を実行。
   - 構文エラー時: 入力枠の赤ハイライト、`#searchSyntaxBadge` に直感的なエラーメッセージと解決ヒントを表示。
   - 補完候補がある場合: `#searchAutocompleteDropdown` を表示し、上下キー（`ArrowUp`, `ArrowDown`）、`Enter`、`Tab` またはマウスクリックで安全に挿入・置換。
   - 有効クエリまたは入力空時: バッジ・ドロップダウンを非表示にし、通常状態へ復元。

### 5.3 スタイリング (`site/css/style.css`)
1. 検索入力枠のエラー警告ボーダーおよびアニメーション。
2. 構文エラーバッジ（警告アイコン付き、ツールチップ風）。
3. オートコンプリートドロップダウン（ダークテーマ・すりガラス風・選択中のハイライト）。

### 5.4 テスト & ビルド検証
1. `tests/web/test_frontend_frameworks.py` に `test_query_validator_suggest_and_diagnostics` を追加。
2. `make build_js`（Google Closure Compiler）による 0 エラービルドを検証。
3. `make check`（フォーマット、静的解析、全テスト）の 100% PASS を確認。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `QueryValidator.prototype.suggest(queryString, cursorOffset)` が実装され、フィールド名補完・演算子補完・Levenshtein タイポ推薦・未閉じ記号補完が機能すること。
- [ ] `site/app.js` において `#searchInput` の入力時にデバウンスでリアルタイム構文検証が行われ、エラー時に直感的なバッジ・ガイダンスが表示されること。
- [ ] オートコンプリート候補ドロップダウンが表示され、キーボード（上下キー、Enter、Tab）およびクリックでクエリに反映されること。
- [ ] `make build_js`（Google Closure Compiler）が 0 エラーで完了し、`site/app-min.js` が正常に生成されること。
- [ ] `tests/web/test_frontend_frameworks.py` の自動テストが全件 PASS すること。
- [ ] Xenon Rank A、flake8、mypy --strict src を 100% パスすること。
