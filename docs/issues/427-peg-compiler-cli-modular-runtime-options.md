---
ID: 427
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] PEG AOT コンパイラにおける --no-runtime モジュール化と外部ランタイム共有の導入 (ID: 427)

## 1. 概要 / Summary

現在 `JSCodeGenerator`（`src/core/structures/peg_compiler/codegen_js.py`）は、生成する各 JavaScript ファイル内に約 250 行の Packrat PEG ランタイムエンジン（`Parser`, `ParseContext`, 各種コンビネータ）を自己内包（`embedded_runtime`）して出力している。
単一のパーサーをスタンドアロンで動かす際には有用だが、今後複数の文法（CTI クエリ、URL ルーター、Mermaid バリデーター、マークダウンブロック等）を同時にブラウザへ読み込む場合、同一のランタイムコードが複数回重複定義され、バンドルサイズ（`site/app-min.js`, `dashboard-min.js`）の増大およびメモリ冗長化の原因となる。

本 Issue では、CLI オプション `--no-runtime`（外部ランタイム参照モード）を導入し、ランタイムを `site/js/frameworks/peg-runtime.js` として一度だけ独立モジュール化し、各生成パーサーがグローバルまたはモジュールインポート経由で共通ランタイムを再利用可能とするモジュール化アーキテクチャを確立する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第13節 Phase 6 Web フロントエンド連携 ＆ JavaScript コードジェネレータ基盤仕様)
- **関連 Issue**:
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装
  - Issue #419: クライアントサイド CTI グラフクエリ DSL の AOT 生成とダッシュボード統合
  - Issue #421: クライアントサイドルーターの URL パス＆クエリ構文解析の PEG 化

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/core/structures/peg_compiler/codegen_js.py`](../../src/core/structures/peg_compiler/codegen_js.py)（`--no-runtime` / 外部ランタイム参照コードの出力制御）
- [ ] [`src/core/structures/peg_compiler/cli.py`](../../src/core/structures/peg_compiler/cli.py)（`--no-runtime` CLI オプションの統合）
- [ ] [`site/js/frameworks/peg-runtime.js`](../../site/js/frameworks/peg-runtime.js)（独立した共有 PEG ランタイムモジュール）
- [ ] [`tests/test_peg_compiler_js.py`](../../tests/test_peg_compiler_js.py)（ランタイム分離パーサーの結合テスト）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/427-peg-compiler-cli-modular-runtime-options`

1. **`site/js/frameworks/peg-runtime.js` の抽出**:
   - `JSCodeGenerator` の内蔵ランタイムを UMD 互換の共有ライブラリとして単独出力・配備。
2. **`JSCodeGenerator` の `--no-runtime` 制御**:
   - `embedded_runtime=False` の場合、ランタイムクラス・コンビネータ関数群を出力せず、`global.PEGRuntime`（または `require('./peg-runtime')`）からコンビネータを参照するヘッダーを出力。
3. **CLI 連携**:
   - `python -m src.core.structures.peg_compiler ... --no-runtime` をサポート。
4. **テスト検証**:
   - 共通ランタイムを読み込んだ環境下で、`--no-runtime` で出力された複数のパーサーが競合なく軽量に動作することを検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] CLI オプション `--no-runtime` が指定された場合、ランタイムを含まないパーサー定義のみの軽量 JS コードが出力されること。
- [ ] 共有ランタイム `site/js/frameworks/peg-runtime.js` を介してパーサーが正常に動作すること。
- [ ] 既存の自己内蔵モード（デフォルト `--embedded-runtime`）の互換性が 100% 維持されること。
- [ ] Xenon Rank A、flake8、mypy --strict をクリアすること。
- [ ] 単体・回帰テストが 100% PASS すること。
