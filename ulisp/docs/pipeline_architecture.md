# ULisp パイプライン・Nanopass 詳細仕様書

本ドキュメントは、ULisp コンパイラ内部の各 Nanopass の役割、入出力データ構造、最適化パス、およびパス間で維持される不変条件（Invariants）を定義する。

- 正典アーキテクチャ仕様書: [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- 関連仕様書:
  - [LIR 命令セット仕様書](lir_specification.md)
  - [継続・dynamic-wind 仕様書](continuations_and_unwin```text
[入力: Scheme ソースコード forms / ディレクティブ (!target, !gc)]
      │
      ▼ (compiler/driver.scm: extract-directives-and-forms)
      │
      ▼ Pass 010: desugar-libraries-and-imports (passes/010_library.scm)
[R7RS Libraries Desugared]
      │
      ▼ Pass 015: expand-dsl-forms (passes/015_dsl_expander.scm - Issue #587)
[Nanopass DSL Expanded S-expressions]
      │
      ▼ Pass 020: expand-macros-in-forms (passes/020_macro_expander.scm)
[Macro-Expanded S-expressions]
      │
      ▼ Pass 025: rewrite-top-level (passes/025_top_level.scm)
[Hoisted Top-Level %program AST]
      │
      ▼ Pass 030: desugar-all (passes/030_desugar.scm)
[Canonical Core Scheme AST]
      │
      ▼ Pass 050: cp0-optimize (passes/050_cp0.scm)
[Optimized Core Scheme AST (Constant Folding, DCE)]
      │
      ▼ Pass 060: lvn-all (passes/060_lvn.scm - Issue #521)
[LVN GVN Optimized AST (Local Value Numbering / Accessor Memoization)]
      │
      ▼ Pass 070: anf-all (passes/070_anf.scm)
[A-Normal Form (ANF) 3-Address AST]
      │
      ▼ Pass 080: annotate-all (passes/080_annotator.scm - Issue #517)
[Type-Annotated AST (Abstract Interpretation)]
      │
      ▼ Pass 090: rtyper-all (passes/090_rtyper.scm - Issue #518)
[Unboxed / Typed LIR-Ready AST (RType Inference)]
      │
      ▼ Pass 100: contify-all (passes/100_contify.scm - Issue #522)
[Contified AST (Known-Call to Direct Jumps / Closure Elimination)]
      │
      ▼ Pass 110: closure-convert (passes/110_closure_convert.scm)
[Flat %program / %function AST (Lambda Lifting, Env Tuples)]
      │
      ▼ Pass 120: alias-escape-all (passes/120_alias_escape.scm - Issue #525)
[TBAA & Escape Analyzed AST (Stack Allocation Candidates)]
      │
      ▼ Pass 128: lir-branch-fusion (passes/128_lir_branch_fusion.scm - Issue #571)
[Fused Condition Lowering & Flag-Based Branch Jumps]
      │
      ▼ Pass 130/131/132: generate-lir (passes/130_lir.scm, 131_lir_safepoint.scm, 132_lir_braun_ssa.scm)
[Low-Level IR (LIR) 3-Address Instructions & SSA CFG]
      │
      ├───────────────────────┬───────────────────────┐
      ▼                       ▼                       ▼
 Pass 140 (x86-64)       Pass 160 (C99)          Pass 150 (AArch64)
 [x86_64 GNU Asm]        [ANSI C99 / Wasm]       [AArch64 GNU Asm]
```

---

## 2. 各パスの詳細仕様 (Pass Specifications)

### 基盤: コンパイラユーティリティ & 述語 (`compiler/helpers.scm`, `compiler/primitives.scm`)
- **責務**: 全パス共通の述語、アキュムレータ、一意シンボル/ラベル生成ルーチンの提供。
- **主要機能**:
  - `atomic-expr?`, `pure-prim?`, `closure-prim?`, `type-predicate-op?`
  - `unique-label`, `unique-symbol`, `set-diff`, `set-union`
  - ビットマスク・型タグ定数（Fixnum, Pair, Closure, String, Vector, Continuation）

### Pass 010: R7RS ライブラリ構文脱糖 (`passes/010_library.scm`)
- **責務**: `define-library`, `import`, `export` の解析と静的名前空間プレフィックス化。

### Pass 015: Nanopass DSL 手続き型展開器 (`passes/015_dsl_expander.scm` - Issue #587)
- **責務**: `define-language`, `define-pass`, `define-parser`, `define-unparser` の手続き型展開、およびホスト専用 `define-macro` の除去。
- **不変条件**: 本パス通過後、DSL 構文およびホスト専用マクロはすべて標準 Scheme 構文（`define`, `lambda` 等）へ展開され、下流のマクロ展開器（Pass 020）へ純粋な式列として渡される。

### Pass 020: 衛生的マクロ展開器 (`passes/020_macro_expander.scm`)
- **責務**: `define-syntax` / `syntax-rules` によるコンパイル時マクロ定義の評価と AST 展開。
- **不変条件**: 本パス通過後、ユーザー定義マクロはすべて基本構文へ置換される。

### Pass 025: トップレベル定義巻き上げ (`passes/025_top_level.scm` - Issue #570)
- **責務**:
  - `rewrite-top-level`: トップレベル `(define ...)` および `(define-record-type ...)` 群を解析し、単一の正規化された `(%program unique-defs body)` へ巻き上げる。

### Pass 030: 構文脱糖 (`passes/030_desugar.scm`)
- **責務**:
  - `desugar-all`: `cond`, `case`, `let*`, `named-let`, `and`, `or`, `begin`, `values`, `guard` 等を高水準構文から Core 構文（`if`, `let`, `letrec`, `lambda`, 基本プリミティブ）へ展開。
  - `%raw-call/cc`: ファーストクラス継続プリミティブの透過的パイプライン伝搬。

### Pass 040: 静的スコープ・高速自由変数解析 (`passes/040_analysis.scm`)
- **責務**: 式内の自由変数集合（`free-vars`）の正確な算出。ビットセットおよび順序付きリストによる高速集合演算（Issue #529）。
- **エスケープ解析**: 関数が外部へエスケープするか、直接呼び出し（Contification）可能かを判定。

### Pass 050: CP0 ソースレベル最適化 (`passes/050_cp0.scm`)
- **責務**:
  1. **定数畳み込み (Constant Folding)**: 四則演算、ビット演算、論理述語のボトムアップ事前計算。
  2. **自明分岐剪定 (Dead Branch Pruning)**: `(if #t ...)` / `(if #f ...)` の静的剪定。
  3. **自明 begin 平坦化**: ネストした `begin` 式の解除。
  4. **不要束縛削除 (Dead Let Elimination)**: 未使用な純粋束縛の削除。

### Pass 060: ローカル値番号付け LVN (`passes/060_lvn.scm` - Issue #521)
- **責務**: 基本ブロック内における共通部分式除去（CSE）およびペア・クロージャアクセサ（`car`, `cdr`, `%closure-ref`）のメモ化・冗長ロード削除。

### Pass 070: ANF 正規化 (`passes/070_anf.scm`)
- **責務**: 式を 3 番地コード形式（A-Normal Form）へ平坦化。
- **Scoped Temporary Variable Pool (`%t0`〜`%t8`)**: セルフホスティング時のシンボルアロケーションを抑制。

### Pass 080: 抽象解釈型アノテータ (`passes/080_annotator.scm` - Issue #517)
- **責務**: 式ごとの型・値域制約（Fixnum, Boolean, Pair, Non-Null）を抽象解釈により推論し、型アノテーションタグを付与。

### Pass 090: RType 推論 & アンボクシング (`passes/090_rtyper.scm` - Issue #518)
- **責務**: RPython 型推論エンジンに準拠し、純粋な数値演算ループにおいて Tagged Pointer のタグ付け/外しを省略（Raw Integer 演算の選定）。

### Pass 100: Contification & クロージャ除去 (`passes/100_contify.scm` - Issue #522)
- **責務**: エスケープしない既知のローカル関数呼び出しを、ヒープクロージャアロケーションを伴わない直接ジャンプ（継続化）へ最適化。

### Pass 110: 明示的クロージャ変換 (`passes/110_closure_convert.scm`)
- **責務**:
  - **Lambda Lifting**: ネストした無名 `lambda` をトップレベルの `%function` へ巻き上げ。
  - **Flat Closures**: 自由変数を環境タプルとしてキャプチャする `%make-closure` の生成。
  - **相互再帰の正規化**: `letrec` を初期化と `%closure-set!` バックパッチシーケンスへ平坦化。

### Pass 120: TBAA & エスケープ解析 (`passes/120_alias_escape.scm` - Issue #525)
- **責務**: 型ベースのエイリアス解析（TBAA）とローカルオブジェクトのエスケープ解析。短命オブジェクトのスタック配置最適化の判定。

### Pass 128: LIR 分岐融合 & 条件比較低レベル化 (`passes/128_lir_branch_fusion.scm` - Issue #571)
- **責務**:
  - `if` 条件式における比較述語（`=`, `<`, `>`, `<=`, `>=`, `eq?`, `eqv?`, `zero?`, `null?`, `pair?`, `boolean?`, `symbol?`, `string?`, `vector?`, `bytevector?`, `port?`, `procedure?`, `promise?` 等）を直接 LIR 条件分岐命令 (`%jump-cond cc label`) へ直接融合。
  - 中間ブール値（`#t`/`#f`）のヒープ・レジスタアロケーション（`%set-boolean`）および無駄な再判定ジャンプ（`%jump-if-false`）を完全に排除。
  - `lir-cmp-false-cc`, `lir-cmp-true-cc`, `extract-fused-cmp-int`, `lir-compile-fused-cmp-cond`, `lir-compile-fused-cmp` の独立モジュール化。

### Pass 130 / 131 / 132: 低レベル IR (LIR) 生成 & SSA
- **`130_lir.scm`**: 機械抽象 3 番地 LIR 命令列の生成、命令選択、環境追跡。
- **`131_lir_safepoint.scm`**: GC Safepoint 追跡・スタックマップビットマップ生成。
- **`132_lir_braun_ssa.scm`**: Braun et al. (2013) オンザフライ SSA 構築 & ブロック引数エンジン。

### Pass 140 / 141 / 142 / 150 / 160: マルチターゲットコード生成
- **`140_backend_x86_64.scm`**: x86-64 GNU アセンブラテキスト生成。LIR命令選択、プロローグ/エピローグ、`%capture-cc` スタック退避および `ulisp_continuation_invoke` スタック復元。
- **`141_backend_x86_gc.scm`**: x86-64 インラインGCコレクタ (`emit-gc-collector`) および OOM パニックルーチン生成。
- **`142_backend_x86_freestanding.scm`**: ベアメタル環境向けフリースタンディングランタイムルーチン (`emit-freestanding-runtime`) 生成。
- **`150_backend_aarch64.scm`**: AArch64 (ARM64) GNU アセンブラテキスト生成。
- **`160_backend_c.scm`**: ANSI C99 ソースコード生成。`setjmp` / `longjmp` 連携。


