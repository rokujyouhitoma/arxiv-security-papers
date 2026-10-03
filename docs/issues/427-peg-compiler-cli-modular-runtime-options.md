---
ID: 427
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] PEG AOT コンパイラにおける --no-runtime モジュール化と外部ランタイム共有の導入 (ID: 427)

## 1. 概要 / Summary

現在 `JSCodeGenerator`（`src/core/structures/peg_compiler/codegen_js.py`）は、生成する各 JavaScript ファイル内に約 390 行の Packrat PEG ランタイムエンジン（`Parser`, `ParseContext`, `PEGSyntaxError`, 各種コンビネータ）を自己内包（`embedded_runtime=True`）して出力している。
単一パーサーをスタンドアロンで動かす際には有用だが、今後複数の文法（CTI クエリ DSL、URL ルーター、Mermaid バリデーター、マークダウンブロック等）を同時にブラウザへ読み込む場合、同一のランタイムコードが複数回重複定義され、バンドルサイズ（`site/app-min.js`, `dashboard-min.js`）の肥大化およびメモリ冗長化の原因となる。

本 Issue では、CLI オプション `--no-runtime`（外部ランタイム参照モード）および `--runtime-only`（共通ランタイム抽出オプション）を導入し、ランタイムを `site/js/frameworks/peg-runtime.js` として独立モジュール化・配備する。
各生成パーサーは Node.js 環境（`require('./peg-runtime')`）またはブラウザ環境（`window.PEGRuntime` / `window.Application.frameworks.PEGRuntime`）から共通ランタイムをシームレスに再利用可能とする。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第13.8節 Phase 6 Web フロントエンド連携 ＆ JavaScript コードジェネレータ基盤仕様)
- **関連 Issue**:
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装
  - Issue #419: クライアントサイド CTI グラフクエリ DSL の AOT 生成とダッシュボード統合
  - Issue #421: クライアントサイドルーターの URL パス＆クエリ構文解析の PEG 化
  - Issue #423: `--ast-only` 汎用構文木生成オプションの導入
  - Issue #424: Warth '08 左再帰解消アルゴリズムの JavaScript コード生成移植
  - Issue #425: CharClass 文字コード範囲判定化と ReDoS 脆弱性の根絶
  - Issue #426: `PEGSyntaxError` 診断メタデータ拡充と `parseWithDiagnostics` 耐障害 API 実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/core/structures/peg_compiler/codegen_js.py`](../../src/core/structures/peg_compiler/codegen_js.py)（`embedded_runtime=False` 時の外部ランタイム解決ヘッダー注入、`generate_runtime_module()` 実装）
- [x] [`src/core/structures/peg_compiler/cli.py`](../../src/core/structures/peg_compiler/cli.py)（`--no-runtime`、`--runtime-only` オプションの追加とコンパイルハンドラ連携）
- [x] [`site/js/frameworks/peg-runtime.js`](../../site/js/frameworks/peg-runtime.js)（独立した共有 PEG ランタイムモジュール）
- [x] [`tests/test_peg_compiler_js.py`](../../tests/test_peg_compiler_js.py)（`--no-runtime` パーサー単体・複数共存・Node/ブラウザ両環境テスト）
- [x] [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)（第13.8節 仕様追記）

---

## 4. セキュリティ脅威分析と耐障害性 / Security & Resilience

1. **グローバルスコープ汚染・プロトタイプ汚染の防止**:
   - `peg-runtime.js` は即時実行関数式 (IIFE) 内にカプセル化され、エクスポート先のみ（`window.PEGRuntime`, `window.Application.frameworks.PEGRuntime`, `module.exports`）を厳格に限定。`Object.prototype` や組み込みオブジェクトの拡張は一切行わない。
2. **外部ランタイム未ロード時のフェイルセーフ**:
   - `--no-runtime` で生成されたパーサーの冒頭で、`PEGRuntime` の解決を試行。未ロードの場合は `PEGRuntime not found. Ensure peg-runtime.js is loaded before <ParserName>.` という明示的なエラーを即時投げてサイレントクラッシュや `TypeError: undefined is not a function` を防ぐ。
3. **ReDoS / Warth 左再帰 / 診断 API の完全継承**:
   - ランタイム分離後も Issue 424 (左再帰), Issue 425 (CharClass 文字コード直接比較), Issue 426 (`parseWithDiagnostics`) の機能が完全に共有ランタイムに包含され、全パーサーで一元的にセキュアな実行が担保される。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/427-peg-compiler-cli-modular-runtime-options`

1. **`JSCodeGenerator.generate_runtime_module()` の実装**:
   - `_build_embedded_runtime()` で定義されているランタイムクラス群およびコンビネータ関数群を抽出し、UMD 形式（Node `module.exports` + Browser `global.PEGRuntime`）のスタンドアロン JS 文字列として返却する静的/インスタンスメソッドを配備。
2. **`JSCodeGenerator.generate()` における外部ランタイム解決ヘッダーの実装**:
   - `self.embedded_runtime is False` の場合、ランタイムクラス・コンビネータ関数群を全削除し、以下の解像ロジックを出力：
     ```javascript
     // --- Section 1: External Packrat PEG Runtime Resolution ---
     var runtime = (typeof require === 'function' && typeof module !== 'undefined' && module.exports)
       ? (function() {
           try { return require('./peg-runtime'); } catch(e) {
             return (typeof global !== 'undefined' && global.PEGRuntime) || (typeof window !== 'undefined' && window.PEGRuntime);
           }
         })()
       : ((typeof window !== 'undefined' && window.PEGRuntime) || (typeof global !== 'undefined' && global.PEGRuntime));
     if (!runtime) {
       throw new Error('PEGRuntime not found. Ensure peg-runtime.js is loaded before ' + ...);
     }
     var ParseResult = runtime.ParseResult;
     var PEGSyntaxError = runtime.PEGSyntaxError;
     var ParseContext = runtime.ParseContext;
     var Parser = runtime.Parser;
     var lit = runtime.lit, reg = runtime.reg, seq = runtime.seq, choice = runtime.choice;
     var star = runtime.star, plus = runtime.plus, opt = runtime.opt;
     var andPred = runtime.andPred, notPred = runtime.notPred, cut = runtime.cut;
     var anyChar = runtime.anyChar, charClass = runtime.charClass;
     ```
3. **`cli.py` の拡張**:
   - `--no-runtime`: `compile_grammar_to_code(..., embedded_runtime=False)` をトリガー。
   - `--runtime-only`: 入力ファイルなし（または任意）で共有ランタイムコードを `-o` または標準出力に直接出力。
4. **`site/js/frameworks/peg-runtime.js` の生成・配置**:
   - `JSCodeGenerator.generate_runtime_module()` を用いて `site/js/frameworks/peg-runtime.js` を生成・配備。
5. **テストの実装**:
   - `tests/test_peg_compiler_js.py` に以下を検証するテストを追加：
     - `test_generate_runtime_module`: スタンドアロンランタイムの UMD 構造と各エクスポートシンボルの存在確認。
     - `test_compile_no_runtime_mode`: `--no-runtime` 時のファイルサイズ削減（自己内蔵時と比較して大幅に軽量化）と構文妥当性。
     - `test_node_execution_with_shared_runtime`: `peg-runtime.js` を参照するパーサー（Node.js 環境）でのパース成功および `parseWithDiagnostics` 正常稼働。
6. **品質ゲート & 設計書同期**:
   - `xenon` Rank A、`flake8`、`mypy --strict src` 全パス。
   - [DSN-25](file:///workspace/arxiv-security-papers/docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md) に第13.8節を追記。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] CLI オプション `--no-runtime` が指定された場合、ランタイムを含まないパーサー定義のみの軽量 JS コードが出力されること（行数が約 60% 削減）。
- [x] スタンドアロン共有ランタイム `site/js/frameworks/peg-runtime.js` が生成され、UMD 形式でエクスポートされること。
- [x] 共有ランタイムを事前ロードした Node.js およびブラウザ模擬環境下で、複数パーサーが正常にパース・診断できること。
- [x] 既存の自己内包モード（デフォルト）の挙動および互換性が 100% 維持されること。
- [x] Xenon Rank A（$CC \le 4$）、flake8、mypy --strict src が 100% PASS すること。
- [x] 全テストが PASS すること。
