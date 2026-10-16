# ULisp パイプライン・Nanopass 詳細仕様書

本ドキュメントは、ULisp コンパイラ内部の各 Nanopass の役割、入出力データ構造、最適化パス、およびパス間で維持される不変条件（Invariants）を定義する。

- 正典アーキテクチャ仕様書: [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- 関連仕様書:
  - [LIR 命令セット仕様書](lir_specification.md)
  - [継続・dynamic-wind 仕様書](continuations_and_unwind.md)
  - [テストおよび検証ガイド](testing_guide.md)

---

## 1. パイプライン全体像 (Pipeline Architecture Overview)

ULisp は Chez Scheme および RPython に着想を得た**直列 Nanopass アーキテクチャ**を採用している。各パスは単一の明確な責務のみを持ち、前段のパスが出力した S 式木を次の S 式木へと決定論的に変換する。

```text
[入力: Scheme ソースコード forms / ディレクティブ (!target, !gc)]
      │
      ▼ (passes/08_driver.scm: extract-directives-and-forms)
      │
      ▼ Pass 0b: expand-macros-in-forms (passes/00b_macro_expander.scm)
[Macro-Expanded S-expressions]
      │
      ▼ Pass 1: rewrite-top-level & desugar-all (passes/01_desugar.scm)
[Canonical Core Scheme AST]
      │
      ▼ Pass 3: cp0-optimize (passes/03_cp0.scm)
[Optimized Core Scheme AST (Constant Folding, DCE)]
      │
      ▼ Pass 3b: lvn-all (passes/03b_lvn.scm - Issue #521)
[LVN GVN Optimized AST (Local Value Numbering / Accessor Memoization)]
      │
      ▼ Pass 4: anf-all (passes/04_anf.scm)
[A-Normal Form (ANF) 3-Address AST]
      │
      ▼ Pass 4b: annotate-all (passes/04b_annotator.scm - Issue #517)
[Type-Annotated AST (Abstract Interpretation)]
      │
      ▼ Pass 5b: rtyper-all (passes/05b_rtyper.scm - Issue #518)
[Unboxed / Typed LIR-Ready AST (RType Inference)]
      │
      ▼ Pass 4c: contify-all (passes/04c_contify.scm - Issue #522)
[Contified AST (Known-Call to Direct Jumps / Closure Elimination)]
      │
      ▼ Pass 5: closure-convert (passes/05_closure_convert.scm)
[Flat %program / %function AST (Lambda Lifting, Env Tuples)]
      │
      ▼ Pass 6b: alias-escape-all (passes/06b_alias_escape.scm - Issue #525)
[TBAA & Escape Analyzed AST (Stack Allocation Candidates)]
      │
      ▼ Pass 6: generate-lir (passes/06_lir.scm - Issue #502, #538, #540)
[Low-Level IR (LIR) 3-Address Instructions]
      │
      ├───────────────────────┬───────────────────────┐
      ▼                       ▼                       ▼
 Pass 7 (x86-64)         Pass 7b (C99)           Pass 7c (AArch64)
 [x86_64 GNU Asm]        [ANSI C99 / Wasm]       [AArch64 GNU Asm]
```

---

## 2. 各パスの詳細仕様 (Pass Specifications)

### Pass 0: 共通述語・ヘルパー (`passes/00_helpers.scm`)
- **責務**: 全パス共通の述語、アキュムレータ、一意シンボル/ラベル生成ルーチンの提供。
- **主要機能**:
  - `atomic-expr?`, `pure-prim?`, `closure-prim?`
  - `unique-label`, `unique-var`
  - ビットマスク・型タグ定数（Fixnum, Pair, Closure, String, Vector, Continuation）

### Pass 0b: メタサーキュラー・マクロ展開器 (`passes/00b_macro_expander.scm`)
- **責務**: `define-macro` によるコンパイル時マクロ定義の評価と AST 展開。
- **不変条件**: 本パス通過後、ユーザー定義マクロはすべて基本構文へ置換される。

### Pass 1: 構文脱糖 (`passes/01_desugar.scm`)
- **責務**:
  - `rewrite-top-level`: トップレベル `(define ...)` 群を単一の `(letrec (...) body)` に巻き上げる。
  - `desugar-all`: `cond`, `case`, `let*`, `named-let`, `and`, `or`, `begin`, `values`, `guard` 等を高水準構文から Core 構文（`if`, `let`, `letrec`, `lambda`, 基本プリミティブ）へ展開。
  - `%raw-call/cc`: ファーストクラス継続プリミティブの透過的パイプライン伝搬。

### Pass 2: 静的スコープ・高速自由変数解析 (`passes/02_analysis.scm`)
- **責務**: 式内の自由変数集合（`free-vars`）の正確な算出。ビットセットおよび順序付きリストによる高速集合演算（Issue #529）。
- **エスケープ解析**: 関数が外部へエスケープするか、直接呼び出し（Contification）可能かを判定。

### Pass 3: CP0 ソースレベル最適化 (`passes/03_cp0.scm`)
- **責務**:
  1. **定数畳み込み (Constant Folding)**: 四則演算、ビット演算、論理述語のボトムアップ事前計算。
  2. **自明分岐剪定 (Dead Branch Pruning)**: `(if #t ...)` / `(if #f ...)` の静的剪定。
  3. **自明 begin 平坦化**: ネストした `begin` 式の解除。
  4. **不要束縛削除 (Dead Let Elimination)**: 未使用な純粋束縛の削除。

### Pass 3b: ローカル値番号付け LVN (`passes/03b_lvn.scm` - Issue #521)
- **責務**: 基本ブロック内における共通部分式除去（CSE）およびペア・クロージャアクセサ（`car`, `cdr`, `%closure-ref`）のメモ化・冗長ロード削除。

### Pass 4: ANF 正規化 (`passes/04_anf.scm`)
- **責務**: 式を 3 番地コード形式（A-Normal Form）へ平坦化。
- **Scoped Temporary Variable Pool (`%t0`〜`%t8`)**: セルフホスティング時のシンボルアロケーションを抑制。

### Pass 4b: 抽象解釈型アノテータ (`passes/04b_annotator.scm` - Issue #517)
- **責務**: 式ごとの型・値域制約（Fixnum, Boolean, Pair, Non-Null）を抽象解釈により推論し、型アノテーションタグを付与。

### Pass 5b: RType 推論 & アンボクシング (`passes/05b_rtyper.scm` - Issue #518)
- **責務**: RPython 型推論エンジンに準拠し、純粋な数値演算ループにおいて Tagged Pointer のタグ付け/外しを省略（Raw Integer 演算の選定）。

### Pass 4c: Contification & クロージャ除去 (`passes/04c_contify.scm` - Issue #522)
- **責務**: エスケープしない既知のローカル関数呼び出しを、ヒープクロージャアロケーションを伴わない直接ジャンプ（継続化）へ最適化。

### Pass 5: 明示的クロージャ変換 (`passes/05_closure_convert.scm`)
- **責務**:
  - **Lambda Lifting**: ネストした無名 `lambda` をトップレベルの `%function` へ巻き上げ。
  - **Flat Closures**: 自由変数を環境タプルとしてキャプチャする `%make-closure` の生成。
  - **相互再帰の正規化**: `letrec` を初期化と `%closure-set!` バックパッチシーケンスへ平坦化。

### Pass 6b: TBAA & エスケープ解析 (`passes/06b_alias_escape.scm` - Issue #525)
- **責務**: 型ベースのエイリアス解析（TBAA）とローカルオブジェクトのエスケープ解析。短命オブジェクトのスタック配置最適化の判定。

### Pass 6: 低レベル IR (LIR) 生成 (`passes/06_lir.scm`)
- **責務**:
  - 機械抽象 3 番地 LIR 命令列の生成。
  - **ファーストクラス継続 LIR 展開**: `%raw-call/cc` からの継続オブジェクト割当、復帰ラベル `.Lcc_ret_XXXX` 生成、レシーバ呼び出し。
  - **多値 LIR 展開**: `values` レシーバへのゼロヒープ多値伝搬。
  - **GC 制御**: `%get-rsp`, `%get-heap-ptr`, `%set-heap-ptr!`, `%get-gc-state-ptr` の展開。

### Pass 7 / 7b / 7c: マルチターゲットコード生成
- **`07_backend_x86_64.scm`**: x86-64 GNU アセンブラテキスト生成。`%capture-cc` スタック退避および `ulisp_continuation_invoke` スタック復元。
- **`07_backend_c.scm`**: ANSI C99 ソースコード生成。`setjmp` / `longjmp` 連携。
- **`07_backend_aarch64.scm`**: AArch64 (ARM64) GNU アセンブラテキスト生成。
