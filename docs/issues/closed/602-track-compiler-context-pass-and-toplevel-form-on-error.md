---
ID: 602
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] コンパイラ実行時における現在Nanopass・処理中トップレベル式・ソース位置のコンテキスト追跡とエラー診断ダンプの導入 (ID: 602)

## 1. 概要 / Summary

`ulisp_core.scm` のような数万行規模の巨大な結合ソースやマクロ展開後の大規模 AST を ULisp コンパイラ（ネイティブ実行系 `bin/ulisp-boot`、Gauche `gosh`、または Python `ilisp`）で処理する際、コンパイルエラー（例: `Unbound variable in LIR: car` や `nanopass-parse: invalid expression`）が発生しても、「どの Nanopass で」「どのトップレベル定義（`define` / `define-record-type` 等）の処理中か」「どの式（S式部分木）の評価中か」が一切出力されず、問題箇所の特定に多大な時間を要していた。

現状のコンパイラ基盤における問題点は以下の通りである：
1. **パス実行コンテキストの消失**:
   コンパイラパイプライン（Pass 010〜Pass 160）が直列実行される中で、例外発生時にどのパスが実行中であったかを保持する動的状態変数が存在しない。
2. **トップレベル関数・識別子の不可視性**:
   `025_top_level.scm` による `%program` 構造化後や `110_closure_convert.scm` のリフト後、各関数定義を個別コンパイルするループにおいて「現在どの関数（`*current-toplevel-name*`）をコンパイル中か」がエラーハンドラに伝播されない。
3. **エラー発生式の情報欠落**:
   `lir-compile-expr` や Nanopass 内の各ハンドラでエラーが検出された際、エラーメッセージと引数のみが表示され、原因となった部分式（`*current-form*`）や周辺文脈が失われる。
4. **`error` 手続きの原始的実装**:
   `ulisp/compiler/helpers.scm` における `(error msg val)` の定義が単に `(display msg) (display " ") (display val) (newline)` を行うのみであり、構造化診断や標準エラー出力（`current-error-port`）への出力分離、終了コード制御が未整備である。

本 Issue では、コンパイラ全体で共通利用可能な動的実行コンテキスト追跡機構（`*current-pass*`、`*current-toplevel-name*`、`*current-form*`）を導入し、`define-pass` DSL 展開部、パイプラインドライバ（`driver.scm`）、および LIR 生成パス（`130_lir.scm`）に自動追跡フックを統合する。
さらに、エラー発生時に視認性の高い枠線付き診断レポートを出力する `compiler-diagnostic-report` を実装し、デバッグおよび障害切り分けの生産性を劇的に向上させる。

---

## 2. トレーサビリティ / Traceability

- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (Section 3: Nanopass コンパイラパイプライン設計)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
  - [R7RS 例外仕様準拠ドキュメント](../../ulisp/docs/r7rs_specification_compliance.md) (Section 6.11: 例外処理と `error` 手続き)
- **関連 Issue**:
  - [Issue 586: Nanopass Framework DSL Phase 4: パイプライン統御・AST Diff トレーサおよび不変条件 Verifier 自動フック統合](closed/586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks.md)
  - [Issue 598: 統一 Pass Manager の導入によるパイプライン制御・最適化レベルスケジューリング・観測性の一元化](598-implement-unified-compiler-pass-manager.md)
  - [Issue 601: ネイティブランタイムにおけるシンボル名表示の復元および未捕捉例外メッセージの構造化整形](closed/601-restore-symbol-printing-and-format-unhandled-exceptions.md)
  - [Issue 603: Power Assert 風アサーション式展開および LIR 変数解決失敗時のローカル環境（env）自動ダンプ機能の実装](603-implement-power-assert-and-lir-env-dump-diagnostics.md)
  - [Issue 604: コンパイラ実行時のコールスタック追跡（Call Stack Traceback）および未捕捉例外時のバックトレース表示機能の実装](604-implement-call-stack-traceback-for-compiler-exceptions.md)
  - [Issue 606: ビルド時 cat 結合の廃止と R7RS include 構文によるソース位置（ファイル名・行番号）追跡基盤の導入](606-replace-cat-bundle-with-r7rs-include-and-source-tracking.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm)
  - コンパイラコンテキスト大域変数（`*current-pass*`, `*current-toplevel-name*`, `*current-form*`, `*compiler-in-error*`）の cons セルベース定義
  - アクセサ・ミューテータ（`current-pass`, `set-current-pass!`, `current-toplevel-name`, `set-current-toplevel-name!`, `current-form`, `set-current-form!`, `reset-compiler-context!`）
  - 巨大 AST に対する安全な診断用式切り詰め関数（`truncate-expr-for-diagnostics`）
  - 構造化診断ダンプ関数（`compiler-diagnostic-report`）の実装
  - 汎用 `error` 手続きの強化（診断ダンプ統合、二重エラー再帰防止ガード、適正リストシグネチャ `(error msg val)` 保持）
- [x] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
  - `nanopass-expand-define-pass-with-trace` におけるパス入口での `(set-current-pass! '<name>)` 自動挿入フック
- [x] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm)
  - `compile-to-lir` および `compile-backend` において、`define-pass` 以外の既存関数型パス呼び出し（`desugar-libraries-and-imports`, `expand-dsl-forms`, `generate-lir`, `emit-x86-64` 等）の直前で `*current-pass*` を明示的に設定
- [x] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm)
  - `generate-lir` におけるトップレベル関数ループでの `*current-toplevel-name*` 更新（関数ラベル名または `%main`）
  - `lir-compile-expr` の先頭での `(set-current-form! expr)` 追跡フック
  - `lir-compile-variable` の未束縛変数例外呼び出し時における文脈情報担保
- [x] [ulisp/frontend/025_top_level.scm](../../ulisp/frontend/025_top_level.scm)
  - `rewrite-top-level` におけるトップレベル定義走査時のコンテキスト初期化および `*current-toplevel-name*`, `*current-form*` 追跡
- [x] [ulisp/tests/passes/test_000_compiler_diagnostics.scm](../../ulisp/tests/passes/test_000_compiler_diagnostics.scm)
  - コンテキスト追跡、式切り詰め、エラー診断ダンプ出力の単体・結合テスト
- [x] [ulisp/Makefile](../../ulisp/Makefile)
  - `NANOPASS_TESTS` への `test_000_compiler_diagnostics.scm` 登録

---

## 4. 脅威モデルとセキュリティ・堅牢性要件 / Threat Model & Security Requirements

1. **エラー報告時の無限再帰・スタック枯渇防止 (CWE-674 / CWE-835)**:
   - 診断レポート出力処理（`compiler-diagnostic-report`）の実行中に例外や内部エラーが発生した場合、`error` 手続きが再帰呼出しされて無限ループ・SEGV を引き起こす危険がある。
   - **対策**: `*compiler-in-error*`（cons セル真偽値フラグ）を設け、一度診断ダンプに入った後の再入（Reentrancy）を検知した場合は最小限のメッセージ（`*** Recursive compiler error aborted ***`）のみを出力して直ちに停止・復帰するフェイルセーフを設ける。
2. **巨大 AST 展開によるメモリ枯渇および DoS 防止 (CWE-400 Resource Exhaustion)**:
   - `ulisp_core.scm` のような数万行のソースでは、トップレベル式や関数本体の AST が数万ノードに及ぶ場合がある。これを診断レポートでナイーブに `write` すると端末フリーズやメモリ枯渇が発生する。
   - **対策**: `truncate-expr-for-diagnostics` により、AST 出力時の最大ネスト深度（例: 深度 3 まで）およびリスト要素数（例: 最大 5 要素まで、以降は `...`）に制限を課し、最大出力文字数を一定範囲（数百バイト以内）に安全に制限する。
3. **自己ホスティング・AOT ビルド非破壊性の保証 (DSN-33 Conformance)**:
   - LIR コンパイラはトップレベルの直接 `set!` 変数をサポートせず、大域可変状態は cons セル（`(cons val '())`）を介して `set-car!` で管理する必要がある。
   - **対策**: `*current-pass*`、`*current-toplevel-name*`、`*current-form*` の全コンテキスト変数を cons セルとして定義し、フリースタンディング実行系および 3-Stage Bootstrap においてもバイナリ再コンパイルが正常完走することを保証する。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/602-track-compiler-context-pass-and-toplevel-form-on-error`

### Step 1: コンパイラコンテキストパラメータと診断エンジンの実装 (`helpers.scm`)

1. `ulisp/compiler/helpers.scm` に以下の大域状態変数およびアクセサを定義：
   ```scheme
   ;;; Compiler Execution Context (cons cells to prevent top-level set! in LIR/AOT)
   (define *current-pass* (cons 'none '()))
   (define *current-toplevel-name* (cons 'none '()))
   (define *current-form* (cons 'none '()))
   (define *compiler-in-error* (cons #f '()))

   (define (current-pass) (car *current-pass*))
   (define (set-current-pass! name) (set-car! *current-pass* name))

   (define (current-toplevel-name) (car *current-toplevel-name*))
   (define (set-current-toplevel-name! name) (set-car! *current-toplevel-name* name))

   (define (current-form) (car *current-form*))
   (define (set-current-form! form) (set-car! *current-form* form))

   (define (reset-compiler-context!)
     (set-car! *current-pass* 'none)
     (set-car! *current-toplevel-name* 'none)
     (set-car! *current-form* 'none)
     (set-car! *compiler-in-error* #f))
   ```

2. 診断用式の安全な切り詰めルーチン `truncate-expr-for-diagnostics` の実装：
   - 深度リミット（`max-depth = 3`）および要素数リミット（`max-len = 5`）を設けて、深い S 式や巨大なリストを `(define (func x) (let (...) ...))` のように安全に要約。
3. `compiler-diagnostic-report` 関数の新設：
   - 以下の構造化ヘッダ付きレイアウトで標準出力／エラー出力へ診断情報をダンプ：
     ```text
     ======================================================================
     [COMPILER ERROR] Compilation aborted in Pass: <current-pass>
     ======================================================================
       Target / Irritant : <irritants>
       Toplevel Form     : <current-toplevel-name>
       Current Expr      : <truncated-current-form>
       Message           : <msg>
     ======================================================================
     ```
4. `(define (error msg . rest))` の改修：
   - 可変長引数（`rest`）に対応。
   - `*compiler-in-error*` ガードを適用した上で `compiler-diagnostic-report` を呼び出す。
   - 戻り値として `(if (pair? rest) (car rest) #f)` を返しつつ、テスト環境での互換性を維持。

### Step 2: Nanopass DSL およびコンパイラドライバへの現在パス追跡フック統合 (`nanopass.scm`, `driver.scm`)

1. `ulisp/compiler/nanopass.scm` の `nanopass-expand-define-pass-with-trace` を改修：
   - 生成される手続き本体の `letrec` 先頭に `(set-current-pass! (quote ,name))` を挿入。
2. `ulisp/compiler/driver.scm` の `compile-to-lir` および `compile-backend` を改修：
   - 各パスの呼び出し直前で明示的にパス識別子を設定：
     - `ast010`: `(set-current-pass! 'pass-010-library)`
     - `ast015`: `(set-current-pass! 'pass-015-dsl-expander)`
     - `ast020`: `(set-current-pass! 'pass-020-macro-expander)`
     - `ast025`: `(set-current-pass! 'pass-025-top-level)`
     - `ast030`: `(set-current-pass! 'pass-030-desugar)`
     - `ast050`: `(set-current-pass! 'pass-050-cp0)`
     - `ast060`: `(set-current-pass! 'pass-060-lvn)`
     - `ast070`: `(set-current-pass! 'pass-070-anf)`
     - `ast080`: `(set-current-pass! 'pass-080-annotator)`
     - `ast090`: `(set-current-pass! 'pass-090-rtyper)`
     - `ast100`: `(set-current-pass! 'pass-100-contify)`
     - `ast110`: `(set-current-pass! 'pass-110-closure-convert)`
     - `ast120`: `(set-current-pass! 'pass-120-alias-escape)`
     - `lir130`: `(set-current-pass! 'pass-130-lir)`
     - `lir128`: `(set-current-pass! 'pass-128-lir-branch-fusion)`
     - `lir133`: `(set-current-pass! 'pass-133-lir-peephole)`
     - `compile-backend`: `(set-current-pass! (string->symbol (string-append "backend-" (symbol->string target))))`

### Step 3: トップレベル式名および現在式の追跡 (`130_lir.scm`)

1. `ulisp/lir/130_lir.scm` の `generate-lir` を改修：
   - `main-expr` のコンパイル直前: `(set-current-toplevel-name! '%main)`
   - `funcs` の各関数コンパイル（`lir-compile-function`）直前: `(set-current-toplevel-name! (cadr fn))`
2. `lir-compile-expr` の先頭に式トラッキングを追加：
   ```scheme
   (define (lir-compile-expr expr si env tail?)
     (if (pair? expr)
         (set-current-form! expr))
     ...)
   ```
3. `lir-compile-variable` における未束縛変数エラー発生時：
   - 現在の `*current-toplevel-name*` および `*current-form*` が保持されているため、自動的に診断レポートへどの関数のどの式で未束縛変数が発生したかが明記される。

### Step 4: 単体テスト・統合テストスイートの構築 (`test_000_compiler_diagnostics.scm`)

1. `ulisp/tests/passes/test_000_compiler_diagnostics.scm` を新設：
   - コンテキスト設定・リセットのテスト（`set-current-pass!`, `current-pass`, `reset-compiler-context!`）。
   - 式切り詰め関数 `truncate-expr-for-diagnostics` のテスト（巨大リスト、深層ネスト、アトム）。
   - 診断レポート出力形式の検証（意図的な未定義シンボル参照によるエラーキャプチャとダンプ検証）。
   - 多重エラー時の再入ガード（`*compiler-in-error*`）の動作確認。
2. `ulisp/Makefile` の `NANOPASS_TESTS` リスト先頭に `tests/passes/test_000_compiler_diagnostics.scm` を追加。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/compiler/helpers.scm` に `*current-pass*`, `*current-toplevel-name*`, `*current-form*`, `compiler-diagnostic-report` が実装されていること。
- [x] `define-pass` で定義された Nanopass および `driver.scm` のパイプライン実行時に、現在パス名が自動追跡されること。
- [x] LIR 生成時に関数名（`*current-toplevel-name*`）および現在コンパイル中の部分式（`*current-form*`）が追跡されること。
- [x] 未束縛変数や無効構文が発生した際、枠線付きの構造化コンパイラ診断ダンプ（パス名、トップレベル定義、現在式、エラーメッセージ）が出力されること。
- [x] 巨大な AST や深いネスト構造に対しても `truncate-expr-for-diagnostics` により安全に要約表示され、クラッシュやフリーズが発生しないこと。
- [x] 二重エラー発生時でも無限再帰に陥らずフェイルセーフに停止すること。
- [x] 新規テストスイート `ulisp/tests/passes/test_000_compiler_diagnostics.scm` が 100% PASS すること。
- [x] 既存のコンパイル速度へのオーバーヘッドが 2% 未満であること。
- [x] `make test_passes` および `bash ulisp/test.sh` が 100% PASS すること。
