# ULisp パイプライン・Nanopass 詳細仕様書

本ドキュメントは、ULisp コンパイラ内部の各 Nanopass の役割、入出力データ構造、およびパス間で維持される不変条件（Invariants）を定義する。

正典アーキテクチャ仕様書: [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 1. パイプライン全体像 (Pipeline Overview)

ULisp は Chez Scheme に着想を得た**直列 Nanopass アーキテクチャ**を採用している。各パスは単一の責務のみを持ち、前段のパスが出力した S 式木を次の S 式木へと決定論的に変換する。

```text
[入力: Scheme ソースコード文字列]
      │
      ▼ (lib/reader.scm)
[Raw S-expressions] (forms)
      │
      ▼ Pass 1: rewrite-top-level & desugar-all (passes/01_desugar.scm)
[Canonical Core Scheme AST]
      │
      ▼ Pass 3: cp0-optimize (passes/03_cp0.scm)
[Optimized Core Scheme AST]
      │
      ▼ Pass 4: anf-all (passes/04_anf.scm)
[A-Normal Form (ANF) AST]
      │
      ▼ Pass 5: closure-convert (passes/05_closure_convert.scm)
[Flat %program / %function AST]
      │
      ▼ Pass 6: generate-lir (passes/06_lir.scm - Issue #502)
[Low-Level IR (LIR) Instructions]
      │
      ▼ Pass 7: compile-backend (passes/07_backend_x86_64.scm)
[x86-64 GNU Assembler Text]
```

---

## 2. 各パスの詳細仕様 (Pass Specifications)

### Pass 0: 共通述語・ヘルパー (`passes/00_helpers.scm`)
- **責務**: 全パス共通の述語、リスト走査、一意シンボル/ラベル生成ルーチンの提供。
- **主要手続き**:
  - `atomic-expr?`: シンボル、数値、真偽値、文字、空リスト、`quote` リテラルの判定。
  - `pure-prim?`: 副作用のない純粋プリミティブ（`+`, `-`, `*`, `car`, `cdr` 等）の判定。
  - `closure-prim?`: `%make-closure`, `%closure-ref`, `%closure-set!` の判定。
  - `unique-label`: アセンブリラベル生成。

### Pass 1: 構文脱糖 (`passes/01_desugar.scm`)
- **入力**: ユーザー記述の任意の高水準 Scheme 式リスト。
- **出力**: 最小限の Canonical Core Scheme AST。
- **変換内容**:
  - `rewrite-top-level`: トップレベルの `(define ...)` 群を単一の `(letrec (...) body)` に巻き上げる。
  - `desugar-all`: `cond`, `case`, `let*`, `named-let`, `and`, `or`, `string-append`, `list` を基本構文（`if`, `let`, `letrec`, `lambda`, `begin`, 基本プリミティブ）へ展開。
- **不変条件**: 本パス以降、複合構文糖は完全に消滅し、構文木にはコア 6 構文のみが存在する。

### Pass 2: 静的スコープ・自由変数解析 (`passes/02_analysis.scm`)
- **入力**: Canonical Core Scheme AST。
- **出力**: 式内の自由変数リスト（`free-vars`）。
- **責務**:
  - 現在のレキシカル環境 `bound` を考慮しながら、式 `expr` が参照している未束縛の自由変数の集合を正確に算出。
  - `quote` 内のシンボル参照（`string->symbol` 呼び出し）を透過的に検出。

### Pass 3: CP0 ソースレベル最適化 (`passes/03_cp0.scm`)
- **入力**: Canonical Core Scheme AST。
- **出力**: 最適化された Core Scheme AST。
- **最適化内容**:
  1. **定数畳み込み (Constant Folding)**: 静的に確定可能な基本演算（`(+ 1 2)` $\to$ `3`, `(* 6 7)` $\to$ `42`, `(not #f)` $\to$ `#t` 等）のボトムアップ事前評価。
  2. **自明分岐剪定 (Dead Branch Pruning)**: `(if #t then else)` $\to$ `then`, `(if #f then else)` $\to$ `else` の静的剪定。
  3. **自明 begin 平坦化**: ネストした `begin` の結合、単一式 `begin` の解除。
  4. **不要束縛削除 (Dead Let Elimination)**: 副作用のない純粋式を束縛する `let` のうち、本体で参照されない未使用変数の安全な削除。
- **不変条件**: プログラムの意味論および副作用の発生順序が 100% 保持される。

### Pass 4: ANF 正規化 (`passes/04_anf.scm`)
- **入力**: 最適化済み Core Scheme AST。
- **出力**: A-Normal Form（3番地コード形式）AST。
- **変換内容**:
  - 二項演算や関数適用の引数位置にある複合式を、一時変数束縛 `(let ((%t0 ...)) ...)` へ持ち上げる。
  - **Scoped Temporary Variable Pool (`%t0`〜`%t8`)**: セルフホスティング時の `string->symbol` ヒープアロケーションをゼロにするため、ネスト深さに応じた固定予約シンボルを割り当てる。
- **不変条件**: すべての関数呼び出し・プリミティブ適用の引数はアトミックな値（シンボルまたは即値）のみとなる。

### Pass 5: 明示的クロージャ変換 (`passes/05_closure_convert.scm`)
- **入力**: ANF AST。
- **出力**: 平坦化されたプログラム表現 `(%program (%functions (%function label params body) ...) main-expr)`。
- **変換内容**:
  - **Lambda Lifting**: ネストした無名 `lambda` をすべてトップレベルの `%function` 定義へ持ち上げる。
  - **Flat Closures**: 自由変数を環境タプルとしてキャプチャする `%make-closure` の生成。
  - **明示的環境参照**: キャプチャされた変数へのアクセスを `(%closure-ref %self index)` へ置換。
  - **相互再帰の平坦化**: `letrec` を初期 `%make-closure` 生成と `%closure-set!` によるバックパッチシーケンスへ正規化。
- **不変条件**: ネストした `lambda` および `letrec` は完全に消滅し、すべての手続きはフラットな独立定義となる。

### Pass 6: 低レベル IR (LIR) 生成 (`passes/06_lir.scm`)
- **入力**: フラットな `%program` 表現。
- **出力**: ターゲット非依存の 3 番地 LIR 命令列。
- **詳細**: [lir_specification.md](lir_specification.md) 参照。

### Pass 7: バックエンドコード生成 (`passes/07_backend_x86_64.scm`)
- **入力**: 3 番地 LIR 命令列。
- **出力**: x86-64 GNU アセンブリテキスト。
- **責務**:
  - LIR 命令をネイティブ命令（`mov`, `add`, `cmp`, `jmp`, `call`, `ret`）へ 1 対 1 マッピング。
  - ABI 準拠のプロローグ・エピローグ生成およびヒープポインタ（`r12`）の整合性維持。

### Pass 8: コンパイルドライバ (`passes/08_driver.scm`)
- **入力**: 標準入力からの S 式ストリーム。
- **出力**: 標準出力へのアセンブリ出力。
- **パイプライン結合**:
  ```scheme
  (let ((forms (read-all-forms)))
    (if (not (null? forms))
        (let* ((ast0 (rewrite-top-level forms))
               (ast1 (desugar-all ast0))
               (ast2 (cp0-optimize ast1))
               (ast3 (anf-all ast2))
               (ast4 (closure-convert ast3))
               (lir  (generate-lir ast4)))
          (emit-assembly lir))))
  ```
