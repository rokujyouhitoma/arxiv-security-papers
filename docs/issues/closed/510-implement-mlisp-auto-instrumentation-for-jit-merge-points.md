---
ID: 510
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT/ENH] MLisp によるループ構文の自動検知と jit-merge-point 自動計装機能の実装 (ID: 510)

## 1. 概要 / Summary
ユーザーコード（ULisp や純粋な Scheme スクリプト）に対して手動で `jit-merge-point` を記述することなく、MLisp 側のコンパイル・評価前処理パス（AST リライタ）においてループ構文（Named `let`、自己末尾再帰 `define`）を静的に自動検知し、ループ先頭に `(jit-merge-point ...)` を透過的に自動注入（Auto-Instrumentation）する機能を実装する。
これにより、ユーザーコード側を 1 行も修正（汚染）することなく、RPython 以上のゼロ侵入（Zero-Invasive）かつ透過的な JIT 実行を可能とする。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-34: MLisp 内因的メタトレーシング JIT アーキテクチャ仕様書 §2.2 トレース抽出プロトコル](../designs/DSN-34-mlisp_endogenous_meta_tracing_jit_architecture_specification.md)
- 関連 Issue: [Issue 509: MLisp JIT 実行基盤による ULisp コンパイラ (compiler.scm) のコンパイルと自己ホスティングバイナリ出力](closed/509-compile-ulisp-compiler-via-mlisp-jit.md)
- 関連 Issue: [Issue 507: 限定継続（shift/reset）とULisp LIRに基づく内因的メタトレーシングJITツールチェーン (MLisp) の実装](closed/507-implement-mlisp-endogenous-meta-tracing-jit.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [mlisp/tracer/auto_instrument.scm](../../mlisp/tracer/auto_instrument.scm) (新規作成: ループ自動検知・計装モジュール)
- [x] [mlisp/tests/test_auto_instrument.scm](../../mlisp/tests/test_auto_instrument.scm) (新規作成: 自動計装単体・結合テスト)
- [x] [mlisp/Makefile](../../mlisp/Makefile) (`test_auto_instrument` ターゲット追加および `test` スイート統合)
- [x] [mlisp/README.md](../../mlisp/README.md) (自動計装機能の仕様と動作例の記載)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/510-auto-instrument-jit-merge-points`

1. **AST 自動計装モジュールの設計・実装 (`mlisp/tracer/auto_instrument.scm`)**:
   - `auto-instrument-form` / `auto-instrument-forms`: S 式を再帰的にトラバースする純粋 Scheme 関数。
   - **Named `let` の検知**:
     `((eq? (car form) 'let) (symbol? (cadr form)))` の形式を検出し、本体の先頭に `(jit-merge-point '<unique-loop-tag> (list <vars>...))` を挿入。
   - **自己末尾再帰 `define` の検知**:
     `(define (func-name params...) body...)` において、`body` 内の末尾位置（tail position）に `func-name` への再帰呼び出しが存在するかを `tail-recursive?` で検査し、該当する場合に関数本体の先頭に `(jit-merge-point 'func-name (list params...))` を挿入。
   - **二重計装の防止（冪等性）**:
     既に本体先頭に `jit-merge-point` が明示されている場合は重複挿入を行わない。
   - **部分式の再帰走査**:
     `lambda`, 通常の `let`/`let*`/`letrec`, `if`, `begin`, `cond` などの部分式を完全に再帰処理し、セマンティクスを不変に維持。

2. **包括的テストスイートの作成 (`mlisp/tests/test_auto_instrument.scm`)**:
   - 単体テスト: Named `let` の計装、自己末尾再帰 `define` の計装、非再帰関数の非変更、多重ループの個別タグ計装、既存計装の冪等性。
   - 統合テスト: 手動 `jit-merge-point` の一切ない純粋な Scheme ループコードを入力とし、自動計装を経て MLisp メタトレーサがホットループを検知・トレース生成・PE 最適化・LIR 変換まで透過的に完遂することを実証。

3. **ビルドパイプライン統合 & 品質ゲート**:
   - `mlisp/Makefile` に `build/test_auto_instrument_runner.scm` および `test_auto_instrument` ターゲットを追加。
   - `make -C mlisp test` および全品質ゲート（`make py_compile`, `make static_analysis`）の 100% PASS を確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `mlisp/tracer/auto_instrument.scm` が 100% Pure Scheme で実装されていること
- [x] 手動の `jit-merge-point` を一切含まない Named `let` および末尾再帰 `define` に対して、正しく `(jit-merge-point ...)` が自動注入されること
- [x] 既に計装済みのコードや通常の非ループ構文に対して誤検知・二重計装が発生しないこと
- [x] 自動計装された Scheme ループが MLisp JIT（トレーサ・最適化器）によって実行時に正常にトレース抽出・最適化されること
- [x] `make -C mlisp test` に `test_auto_instrument` が組み込まれ、全テストが 100% PASS すること

---

## 6. 検証結果 / Verification Results
1. **100% Pure Scheme 自動計装モジュール (`auto_instrument.scm`)**:
   - Named `let` および末尾再帰 `define` を再帰的に走査・検出し、ループ先頭に `(jit-merge-point '<tag> (list <vars>...))` を自動注入。
   - 既存の `jit-merge-point` に対する二重挿入を防止（冪等性確保）。
2. **包括的テストスイート (`test_auto_instrument.scm`)**:
   - Named `let` 計装、末尾再帰 `define` 計装、非再帰関数の非改変（誤検知ゼロ）、標準 `let` の非改変、二重計装防止、多重ループの個別タグ生成の全項目を検証（PASS）。
   - JIT ヒントのない純粋な Scheme ループ（`sim-loop`）を評価し、トレーサが自動でループを検知・ホットコンパイル（`*TRACER-STATE-COMPILED*`）することを実証（PASS）。
3. **ビルド・テストスイート統合**:
   - `mlisp/Makefile`: `test_auto_instrument` ターゲット追加。
   - `make -C mlisp test`: 全 94 項目 100% PASS。

