---
ID: 491
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ULisp Phase 5: 手続き呼び出し・末尾呼び出し最適化 (TCO)・第一級関数とフラットクロージャの実装 (ID: 491)

## 1. 概要 / Summary

[DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) に基づき、ULisp の Phase 5（Step 17〜20: 手続き呼び出し規約・末尾呼び出し最適化 TCO・静的自由変数解析・第一級関数 `lambda`・フラットクロージャ）を実装する。

Scheme 言語の核心である「第一級関数」と「スタックを消費しない末尾再帰（TCO）」をネイティブ x86-64 アセンブリで実現し、高階関数や無限ループ処理をネイティブマシン上で安全かつ高速に実行可能にする。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 2.2 節 レジスタ・スタックフレーム・ABI 規約, 第 3.5 節 末尾呼び出し最適化 TCO, 第 3.6 節 第一級関数とフラットクロージャ, 第 4 章 Phase 5)
  - [DSN-31: ILISP (Intelligence LISP) R7RS コアアーキテクチャ包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) (第 2.3 節 ハイブリッド末尾呼出最適化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (末尾位置コンテキスト `tail?`、`lambda` 抽出、自由変数解析、フラットクロージャヒープ割り当て、クロージャ間接呼び出し、引数上書きジャンプ TCO)
- [x] [ulisp/runtime.c](../../ulisp/runtime.c) (クロージャオブジェクト `#<procedure>` のプリント出力対応)
- [x] [ulisp/test.sh](../../ulisp/test.sh) (Phase 5 テストスイートの追加: 手続き呼出、高階関数、カウンタクロージャ、100万回末尾再帰 TCO 深度テスト)
- [x] [ulisp/README.md](../../ulisp/README.md) (ロードマップ進捗状況表の更新)
- [x] [docs/issues/README.md](../../docs/issues/README.md) (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/491-implement-ulisp-phase5-procedures-tco-and-closures`

1. **静的自由変数解析 (`free-vars`)**:
   - `(free-vars expr bound-vars)`:
     - 式 `expr` 内で参照される変数のうち、自身の引数や内部の `let` で定義されていない外部レキシカル変数のリストを抽出。
2. **フラットクロージャのヒープ表現 (Step 20)**:
   - `(lambda (x ...) body)`:
     - 自由変数リスト `(f1 f2 ... fn)` を決定。
     - コードラベル `.L_lambda_N` を生成し、ラムダ本体を独立した手続きコードとしてコンパイル蓄積（`*lambdas*` リスト）。
     - 評価時（実行時）:
       - バンプアロケータ `R12` から `(8 * (n + 1))` バイトを確保。
       - `[r12]` にコードポインタ `.L_lambda_N` を格納。
       - `[r12 + 8 * i]` に各キャプチャ変数の現在値をストア。
       - `lea rax, [r12 + 1]`（ヒープタグ `0x01`）を返し、`R12` を加算。
3. **手続き呼び出しとクロージャディスパッチ (Step 17 & 20)**:
   - `(proc arg1 arg2 ...)`:
     - 組み込みプリミティブ以外の式が演算子位置にある場合、一般手続き呼び出しとして処理。
     - 各実引数を評価してスタック（`[rsp + curr_si]`）に順次退避。
     - `proc` を評価して RAX（クロージャポインタ）を得る。
     - 非末尾呼び出しの場合:
       - スタックポインタをフレームサイズ分進め（`sub rsp, frame_size`）、`call [rax - 1]`。呼び出し後に `add rsp, frame_size`。
4. **末尾呼び出し最適化 TCO (Step 18)**:
   - `compile-expr` に `tail?` フラグを導入（`begin` の最後、`if` の then/else、関数本体の最外層が真）。
   - 末尾位置にある呼び出しにおいて:
     - 新たなスタックフレームを作らず、**現在のスタックフレームの引数スロット（`[rsp + 8 * (num_args - i)]`）に引数値を直接上書きコピー**。
     - `call` の代わりに `jmp [rax - 1]` を発行し、現在のフレームを再利用。
     - スタック消費量 $O(1)$ を保証。
5. **C ランタイム対応 (`runtime.c`)**:
   - ヒープオブジェクトの先頭がコードポインタ（実行可能セグメントのアドレス）であるかを判別し、`#<procedure>` として表示。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `((lambda (x) (+ x 1)) 41)` が 42 を返すこと。
- [x] 外部変数をキャプチャするクロージャ `(let ((a 10)) ((lambda (x) (+ a x)) 5))` が 15 を返すこと。
- [x] 高階関数（手続きを引数に取る関数、手続きを返す関数）が正しく動作すること。
- [x] 状態を持つクロージャ（`make-counter` 的な動作）が意図通り変数を保持すること。
- [x] **TCO 深度テスト**: 100万回以上の末尾再帰ループがスタックオーバーフロー（SIGSEGV）を起こさず即座に完走すること。
- [x] `./test.sh` で Phase 1〜5 の全テストがグリーンであること。
- [x] `ulisp/README.md` の進捗状況表で Phase 5 が完了として反映されていること。
