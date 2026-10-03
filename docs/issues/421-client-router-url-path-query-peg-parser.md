---
ID: 421
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] クライアントサイドルーターの URL パス＆クエリ構文解析の PEG 化 (ID: 421)

## 1. 概要 / Summary

Web クライアントのシングルページアプリケーション（SPA）ルーティングを司る `site/js/frameworks/router.js` は、現在 `register(pattern, callback)` において正規表現文字列の連結（`"^\\/?" + pattern.replace(...)`）を構築し、クエリ文字列は `split('&')` と `split('=')` で単純分割している。
この実装は、パスパラメータ（`:id`、`:category`）、ワイルドカード（`*`）、および配列形式のクエリ（`?tags=zero-trust&tags=crypto`）や特殊文字エンコードのエッジケースでパース破綻や脆弱性を生じやすい。

本 Issue では、RFC 3986 および URL テンプレート構文に準拠した小型 PEG パーサーを導入し、ルーティングパターンのコンパイル、パスパラメータの型安全な抽出、および複合クエリ文字列の決定論的なデコードを実現する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第13節 Phase 6: Web フロントエンド連携 ＆ JavaScript コードジェネレータ基盤仕様)
- **関連 Issue**:
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装
  - Issue #418: マークダウン・ブロック構文解析 (MarkdownLexer) の PEG 化と頑健性向上
  - Issue #419: クライアントサイド CTI グラフクエリ DSL の AOT 生成とダッシュボード統合
  - Issue #420: 検索窓における Lucene PEG リアルタイム構文検証・エラーハイライト・オートコンプリートの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/frameworks/router.js`](../../site/js/frameworks/router.js)（URL パス＆クエリ PEG パースエンジンの統合）
- [ ] [`site/app-min.js`](../../site/app-min.js)（Closure Compiler ビルド成果物）
- [ ] [`site/dashboard-min.js`](../../site/dashboard-min.js)（Closure Compiler ビルド成果物）
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py)（ルーター単体・統合テスト）
- [ ] [`docs/issues/README.md`](README.md)（Issue 台帳ステータス更新）

---

## 4. セキュリティ分析 (STRIDE Threat Model) と防御策

| 脅威分類 | 潜在的リスク | 防御策 |
| :---: | --- | --- |
| **Spoofing** | 不正なハッシュ、ヌルバイト（`%00`）、不正なパーセントエンコーディングによる内部ルーティング偽装 | PEG 規則で許可文字セットを厳格に定義し、パスセグメントを正規化。 |
| **Tampering (HPP / Prototype Pollution)** | クエリパラメータ多重送信（HTTP Parameter Pollution）によるプロパティ上書き、および `__proto__` / `constructor` によるプロトタイプ汚染 | パラメータ辞書の格納時に `Object.create(null)` を採用、または予約プロパティ（`__proto__`, `constructor`, `prototype`）の書き込みを無視・隔離。同一キーの複数指定時は配列化して情報欠落を防止。 |
| **Repudiation** | ルートマッチング失敗時やフォールバック時の挙動不透明性 | `resolve(hash)` が成功・失敗を明確な boolean で返し、未登録ルート時には `defaultRoute` への安全なフォールバックを保証。 |
| **Information Disclosure** | 不正なパーセントエンコーディング（例: `%E0%A4%A`）に対する `decodeURIComponent` の例外（`URIError`）送出によるスタックトレース露出と SPA 停止 | 安全なデコードヘルパー（`safeDecode`）を実装し、例外発生時は元の生文字列を維持してフォールバック。 |
| **Denial of Service (ReDoS)** | 複雑なパターンや大量のクエリパラメータによる正規表現バックトラッキング | PEG による決定論的線形スキャン（$O(N)$）を行い、ReDoS を完全に排除。 |
| **Elevation of Privilege** | ディレクトリトラバーサル風のパスペナルティ（`../`）による画面遷移制約の迂回 | パスセグメント分割時に空セグメントや `.` / `..` 相対参照を安全に正規化・無効化。 |

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/421-client-router-url-path-query-peg-parser`

### 5.1 Route Pattern PEG コンパイラの実装 (`site/js/frameworks/router.js`)
1. **PEG 文法定義**:
   - `RoutePattern <- LeadingSlash? Segment ('/' Segment)* TrailingSlash?`
   - `Segment <- Param / Wildcard / Literal`
   - `Param <- ':' [a-zA-Z_][a-zA-Z0-9_]*`
   - `Wildcard <- '*' [a-zA-Z_][a-zA-Z0-9_]*`
   - `Literal <- [^/:*?#]+`
2. **コンパイル結果**:
   - パターン文字列からセグメント列 `[ { type: 'LITERAL', value: 'papers' }, { type: 'PARAM', name: 'id' } ]` を生成。
   - 高速マッチングのため、セグメント数および各セグメントの型に応じた抽出関数を構築。

### 5.2 Query String PEG パーサーの実装
1. **PEG 文法定義**:
   - `QueryString <- '?'? (Pair ('&' Pair)*)?`
   - `Pair <- Key ('=' Value)?`
   - `Key <- [^&=#]+`
   - `Value <- [^&#]*`
2. **セマンティックアクション**:
   - キーと値の双方に `safeDecode` を適用。
   - プロトタイプ汚染防止（`__proto__`, `constructor`, `prototype` は無視）。
   - 同一キーの重複時は自動配列化（例: `?tag=sec&tag=ai` → `{ tag: ['sec', 'ai'] }`）。
   - 値なしキー（例: `?compact`）は空文字列 `""`（または `true`）として格納。

### 5.3 コールバック引数と下位互換性
1. `callback(params, context)`:
   - 既存の `callback(params)` コード（`app.js` 等）を壊さないよう、第1引数 `params` にクエリパラメータとパスパラメータをマージした辞書を渡し、同時に `$pathParams`, `$queryParams`, `$path` を保持。

### 5.4 テスト & ビルド検証
1. `tests/web/test_frontend_frameworks.py`:
   - 通常ルートマッチング（`/papers`）
   - パスパラメータ抽出（`/papers/:id` -> `{ id: '2409.12345' }`）
   - ワイルドカード抽出（`/files/*path` -> `{ path: 'docs/test.pdf' }`）
   - クエリパラメータパース（単一キー、重複キー配列化、値なしキー）
   - 不正 URI エンコーディング（URIError 回避）
   - プロトタイプ汚染耐性（`?__proto__[polluted]=true`）
2. `scripts/compile_frontend.py`（Closure Compiler `strict=True`）の実行。
3. `make check`（フォーマット・静的解析）の PASS 確認。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `site/js/frameworks/router.js` のルートマッチングおよびクエリパースが PEG ベースで動作すること。
- [ ] パスパラメータ（`:id`）、ワイルドカード（`*`）、および重複クエリキー（配列化）が正確に抽出されること。
- [ ] 不正なパーセントエンコードやプロトタイプ汚染キー（`__proto__`）に対して例外クラッシュせず堅牢に処理されること。
- [ ] 既存のハッシュナビゲーション（`#papers`, `#trends`, `#product`, `#system`, `#database`, `#spiders`, `#mcp`）が回帰なく動作すること。
- [ ] `tests/web/test_frontend_frameworks.py` の自動テストが全件 PASS すること。
- [ ] `make build_js`（Google Closure Compiler `strict=True`）が 0 エラーで完了し、`site/app-min.js` および `site/dashboard-min.js` が生成されること。
- [ ] Xenon Rank A、flake8、mypy --strict src を 100% パスすること。

