---
ID: 422
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] Mermaid ダイアグラムのクライアント側事前構文検証およびフォールバックサニタイザーの実装 (ID: 422)

## 1. 概要 / Summary

Web コンソールおよびマークダウンビューア（`site/js/markdown_compiler.js`）では、レポートや論文サマリー内の Mermaid コードブロック（マインドマップ、フローチャート等）をレンダリングする際、コードをそのまま `mermaid.run()` に渡している。
このため、コード内に構文エラー（不正なノード名、エスケープされていない特殊文字、インデント不整合等）が含まれる場合、Mermaid エンジンが致命的な描画例外をスローし、画面上に巨大な赤文字の構文エラーブロックが表示され、ユーザー体験を損ねてしまう（Issue #415 での課題）。

本 Issue では、主要な Mermaid ダイアグラム構文（特に `mindmap`, `graph`, `flowchart`）に対する軽量な PEG 事前検証パーサー（Pre-validator / Sanitizer）を実装する。レンダリング直前に構文の健全性を判定し、不正な構文を安全にサニタイズ（エスケープ補正）、または親切なフォールバック表示（安全なプレビューとコード表示）を行う仕組みを構築する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第13節 Phase 6: Web フロントエンド連携 ＆ JavaScript コードジェネレータ基盤仕様)
- **関連 Issue**:
  - Issue #415: Mermaid mindmap 構文エラーの解消とトレンド分析マインドマップ描画の正常化
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装
  - Issue #418: マークダウン・ブロック構文解析 (MarkdownLexer) の PEG 化と頑健性向上
  - Issue #421: クライアントサイドルーターの URL パス＆クエリ構文解析の PEG 化

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/frameworks/mermaid-validator.js`](../../site/js/frameworks/mermaid-validator.js)（新規作成: Mermaid 軽量 PEG 事前構文検証＆サニタイザー）
- [ ] [`site/js/renderer.js`](../../site/js/renderer.js)（Mermaid ノード出力時の検証・サニタイズ・フォールバック構造）
- [ ] [`site/js/markdown_compiler.js`](../../site/js/markdown_compiler.js)（`renderMermaid` での堅牢な実行・例外隔離）
- [ ] [`scripts/compile_frontend.py`](../../scripts/compile_frontend.py)（`FRAMEWORK_SRCS` への登録）
- [ ] [`Makefile`](../../Makefile)（`JS_SRCS` への登録）
- [ ] [`site/app-min.js`](../../site/app-min.js) & [`site/dashboard-min.js`](../../site/dashboard-min.js)（Closure Compiler ビルド成果物）
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py)（Mermaid 事前検証およびサニタイズテスト）
- [ ] [`docs/issues/README.md`](README.md)（Issue 台帳ステータス更新）

---

## 4. セキュリティ分析 (STRIDE Threat Model) と防御策

| 脅威分類 | 潜在的リスク | 防御策 |
| :---: | --- | --- |
| **Spoofing** | 悪意あるラベルによるダイアグラム構造の偽装 | ノードラベル内の未クォート文字列を検出し、安全にダブルクォートでエスケープ・サニタイズ。 |
| **Tampering (XSS Injection)** | Mermaid ラベルやディレクティブを通じた DOM XSS / HTML インジェクション | サニタイザーにおいて `<script>` や危険な HTML エンティティを除去・エスケープし、フォールバック時も HTML エスケープされたテキストを表示。 |
| **Repudiation** | Mermaid レンダリング失敗の不透明性 | 不正構文を検知した場合は詳細な行番号・構文エラー理由（診断情報）をログおよびフォールバック UI に明示。 |
| **Information Disclosure** | `mermaid.run()` 内部エラーによるスタックトレースや内部メモリ構造の画面露出 | 事前検証により不正なコードを `mermaid.run()` に渡さず、例外送出を水際で遮断。 |
| **Denial of Service (ReDoS / UI Freeze)** | ネストの深い不正構文による Mermaid パーサーの無限ループや巨大エラー DOM 描画による UI 崩壊 | 単一パスの PEG パーサーによる高速事前検証（$O(N)$）を行い、構文破損時は即座にフォールバック表示に切り替え。 |
| **Elevation of Privilege** | Mermaid `securityLevel: loose` の悪用による特権実行 | サニタイザーによりクリックイベントハンドラ（`click` ディレクティブ）等の悪意ある定義を無力化。 |

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/422-mermaid-diagram-pre-validation-and-sanitizer`

### 5.1 Mermaid 軽量 PEG バリデーターの実装 (`site/js/frameworks/mermaid-validator.js`)
1. **対応ダイアグラム種別の判定**:
   - `mindmap`, `graph` (TD, LR, etc.), `flowchart`, `sequenceDiagram`, `classDiagram`, `stateDiagram`
2. **mindmap PEG 構文規則**:
   - 行先頭のインデントスペース（偶数個推奨）、ルート宣言 `root((...))` または `root[...]`、子ノード定義。
   - 特殊文字（括弧 `()`, `[]`, `{}`）を含むラベルがダブルクォートで囲まれていない場合の自動検出と補正。
3. **graph / flowchart PEG 構文規則**:
   - ヘッダーディレクティブ行（`graph TD`, `flowchart LR` 等）。
   - ノードステートメント: `NodeId[Label]`, `NodeId((Label))`, `NodeId{Label}`。
   - 接続エッジ: `-->`, `---`, `-.->`, `==>`。
4. **サニタイズ API**:
   - `MermaidValidator.validate(code)`: `{ valid: boolean, diagramType: string, error: ?string, line: number }`
   - `MermaidValidator.sanitize(code)`: 構文エラーを修正した安全なコード文字列を返却（修正不能な場合は `null`）。

### 5.2 `renderer.js` および `markdown_compiler.js` への統合
1. `renderer.js`:
   - `case 'MERMAID':` において、`MermaidValidator.validate(ev.code)` を実行。
   - 構文エラーの場合、`MermaidValidator.sanitize(ev.code)` を試行。
   - サニタイズ成功ならサニタイズ済みコードを描画対象とし、サニタイズ不能なら赤文字エラーを出さず、整然とした `<div class="md-mermaid-fallback">`（エラーバッジ + コードプレビュー）を出力。
2. `markdown_compiler.js`:
   - `renderMermaid()` 内で各 `.mermaid` 要素を個別に `try-catch` 実行し、1 つのダイアグラムの失敗が他のダイアグラムや全体のレンダリングを停止させないよう隔離。

### 5.3 テスト & ビルド検証
1. `tests/web/test_frontend_frameworks.py`:
   - 正常なマインドマップ、正常なフローチャートのパース成功検証。
   - ラベルに括弧を含む未クォート構文の自動サニタイズ検証。
   - 不正なディレクティブや壊れた構文のフォールバック検知検証。
2. `scripts/compile_frontend.py`（Closure Compiler `strict=True`）の実行。
3. `make check`（フォーマット・静的解析・全テスト）の PASS 確認。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `site/js/frameworks/mermaid-validator.js` が実装され、主要な Mermaid 構文の事前検証および自動サニタイズが動作すること。
- [ ] 不正な構文が与えられた場合でも、Mermaid の巨大な赤文字構文エラーが出ず、洗練されたフォールバック表示またはサニタイズ描画が行われること。
- [ ] `renderer.js` および `markdown_compiler.js` にて各ダイアグラムの例外が個別に隔離されること。
- [ ] `tests/web/test_frontend_frameworks.py` の自動テストが全件 PASS すること。
- [ ] `make build_js`（Google Closure Compiler `strict=True`）が 0 エラーで完了し、`site/app-min.js` および `site/dashboard-min.js` が生成されること。
- [ ] Xenon Rank A、flake8、mypy --strict src を 100% パスすること。

