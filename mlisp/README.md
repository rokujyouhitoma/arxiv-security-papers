# MLisp: Endogenous Meta-Tracing JIT via Delimited Continuations

MLisp（Meta-Lisp）は、Scheme の第一級限定継続（`shift`/`reset`）と同図像性を活かした **内因的メタトレーシング JIT（Endogenous Meta-Tracing JIT）** ツールチェーンです。

**【設計哲学: Pure Scheme 実装】**
C 言語の外部コンパイラやトランスパイラを極力排除し、内因的トレーサ、部分評価オプティマイザ、仮想化エスケープ解析、および x86-64 / AArch64 ダイレクト機械語エミッタに至る全層を **100% Scheme 自身で実装** します。

詳細なアーキテクチャ仕様は [docs/designs/DSN-34-mlisp_endogenous_meta_tracing_jit_architecture_specification.md](../docs/designs/DSN-34-mlisp_endogenous_meta_tracing_jit_architecture_specification.md) を参照してください。

---

## 1. ディレクトリ構成 (100% Pure Scheme)

- `core/`: 限定継続（`shift`/`reset`）コアおよびメタ循環評価器
  - `delimcc.scm`: ポータブル限定継続プリミティブ
- `tracer/`: 内因的 S 式トレース抽出器（`jit-merge-point`）
  - `tracer.scm`: メタトレーサ・ホットループ検知・トレース記録
  - `auto_instrument.scm`: ループ自動検知（Named `let`、自己末尾再帰）＆ `jit-merge-point` ゼロ侵入自動計装パス
- `optimizer/`: トレース部分評価・エスケープ解析・仮想オブジェクト縮退
- `bridge/`: トレースから ULisp LIR への変換アダプタ
- `emitter/`: **Pure Scheme 製ダイレクト機械語エミッタ**
  - `asm_x86_64.scm`: x86-64 バイトコードアセンブラ
  - `asm_aarch64.scm`: AArch64 バイトコードアセンブラ
- `runtime/`: JIT 実行時メモリバッファ（W^X 保護）およびネイティブディスパッチャ
  - `jit_buffer.scm`: 実行可能バッファ管理
- `tests/`: 単体・結合テストスイート
  - `test_delimcc.scm`: 限定継続セマンティクス検証テスト
  - `test_auto_instrument.scm`: ループ自動検知・自動計装検証テスト

---

## 2. 実行・テスト・ネイティブバイナリビルド方法

### A. JIT 内蔵型スタンドアロンワンバイナリ AOT ビルド (`make scheme-jit`)
RPython における PyPy+JIT の AOT コンパイル（`pypy-c` 生成）と同様に、ULisp の自己ホスティング AOT コンパイラ（Pass 0〜7）を用いて、MLisp のメタトレーサ・最適化エンジン・LIR ブリッジ・JIT ランタイムおよび言語インタプリタを丸ごとコンパイルし、**「JIT コンパイラを内蔵した単一自己完結バイナリ (`bin/scheme-jit`)」** を生成します。

```bash
# JIT 内蔵型スタンドアロンネイティブバイナリのビルド
make -C mlisp scheme-jit

# ビルドされたワンバイナリの直接実行（Python/外部依存なし、42KB〜106KB超軽量ELF）
./mlisp/bin/scheme-jit
# または Makefile 経由:
make -C mlisp run_scheme_jit
```

### B. RPython スタイル: TinyVM ワンバイナリ AOT ビルド (`make bin`)
ULisp の AOT コンパイラを利用して、TinyVM インタプリタをスタンドアロンな単一 Linux ELF バイナリに直接コンパイルします。

```bash
make -C mlisp bin
./mlisp/bin/tiny_vm
```

### C. インタラクティブ実動デモ (`make demo`)
TinyVM のバイトコード実行、JIT 生トレース自動合成、PE & Virtuals によるトレース最適化、ULisp Pass 6 LIR への変換、および自己適用メタ循環 Scheme 評価器の一連の流れを対話的に実行します。

```bash
make -C mlisp demo
```

### D. MLisp JIT 基盤による ULisp コンパイラのコンパイル (`make compile_ulisp`)
MLisp の内因的メタトレーシング JIT 基盤（`driver/compile_ulisp_runner.scm`）を用いて、ULisp の自己ホスティングコンパイラをコンパイルします。`ulisp` 側には一切の逆依存を持たせず、`mlisp/` 側で完全に完結します。

```bash
# MLisp JIT 基盤経由で ULisp コンパイラをビルド
make -C mlisp compile_ulisp
```

### E. ゼロ侵入型 自動 JIT 計装 (Auto-Instrumentation)
ULisp やユーザーが記述した純粋な Scheme コードに対して、手動で `jit-merge-point` を記述・汚染する必要はありません（Zero-Invasive）。
`mlisp/tracer/auto_instrument.scm` が AST 前処理層において Named `let` や自己末尾再帰関数を自動検出し、ループ先頭に `(jit-merge-point '<tag> (list <vars>...))` を透過的に自動注入します。

```scheme
;; ユーザーが書くコード（JIT アノテーションなし）:
(let loop ((i 0) (acc 0))
  (if (>= i 1000) acc (loop (+ i 1) (+ acc i))))

;; MLisp が自動展開する AST（透過的に JIT がフックされる）:
(let loop ((i 0) (acc 0))
  (jit-merge-point 'loop_0 (list i acc))
  (if (>= i 1000) acc (loop (+ i 1) (+ acc i))))
```

### F. AOT コンパイラ＋動的 JIT 統合ワンバイナリ (`make ulisp-jit`)
ULisp の Nanopass AOT コンパイラ（Pass 0〜7）と MLisp の動的 JIT エンジン（Tracer, PE, Virtuals, LIR Bridge, JIT Buffer）を統合した単一自己完結 ELF バイナリ `bin/ulisp-jit`（約 501 KB）を生成します。

- **JIT 動的評価モード**: 通常の Scheme 式を入力すると、ループを自動検知してネイティブ JIT ディスパッチします。
- **AOT コンパイルモード**: `(!compile)` または `(!target ...)` を先頭に付与すると、ULisp Nanopass AOT パイプラインが起動し、GNU x86-64 / C / AArch64 アセンブリを出力します。

```bash
# ulisp-jit ネイティブワンバイナリのビルド
make -C mlisp ulisp-jit

# [1] JIT 動的評価モードでの実行
echo "(let loop ((i 0) (sum 0)) (if (< i 10) (loop (+ i 1) (+ sum i)) sum))" | ./mlisp/bin/ulisp-jit

# [2] AOT コンパイルモードでの実行 (fact 5 = 120)
printf "(!compile)\n(define (fact n) (if (<= n 1) 1 (* n (fact (- n 1)))))\n(fact 5)\n" > test_fact.scm
./mlisp/bin/ulisp-jit test_fact.scm > test_fact.s
gcc -no-pie -O2 ../ulisp/runtime.c test_fact.s -o test_fact && ./test_fact # => 120

# 実行検証ターゲット (Makefile)
make -C mlisp run_ulisp_jit
```

詳細な実測ベンチマーク（`ulisp/build/scheme-stage2` との性能比較・フットプリント・スループット）は [benchmarks/README.md](benchmarks/README.md) を参照してください。

**実行結果:**
```text
==================================================================
       ULisp-JIT: Standalone Scheme VM with Automatic JIT         
               Powered by MLisp Meta-Tracing Engine               
==================================================================
[JIT] Hot loop detected! Recording trace: loop_0
[JIT] Compiled and installed native trace for loop: loop_0

=> Result: 45
==================================================================
 [JIT Stats] Dispatched Native JIT Loops: 8
==================================================================
```

### H. 全テストスイートの実行 (`make test`)
```bash
# 全テスト（94項目）の一括実行
make -C mlisp test
```

---

## 3. ULisp と MLisp のアーキテクチャ境界と分離発展方針

ULisp（静的 AOT コンパイラ基盤）と MLisp（動的 JIT 実行環境）は、**「統合せず、明確に分離したまま独立して発展させる」** 方針を確立しています。

### (1) 役割と責務の住み分け（PyPy / RPython モデルとの整合）
```text
┌────────────────────────────────────────────────────────┐
│  ULisp: "Underlying Lisp" (静的 AOT コンパイラ基盤)      │
│  - 役割: C言語コンパイラ (GCC) / RPython AOT 変換系に相当 │
│  - 性質: ステートレス、純粋関数型、決定論的             │
│  - 責務: Nanopass パイプライン、セルフホスティング不動点保証 │
└──────────────────────────┬─────────────────────────────┘
                           │ 単方向依存 (MLisp -> ULisp のみ許可)
                           ▼
┌────────────────────────────────────────────────────────┐
│  MLisp: "Meta Lisp" (動的 JIT 実行環境 / 言語 VM)       │
│  - 役割: Python (PyPy) や Node.js (V8) ランタイム VM 相当 │
│  - 性質: ステートフル、動的、投機的最適化               │
│  - 責務: インタプリタ、メタトレーサ、PE、JITバッファ管理    │
└────────────────────────────────────────────────────────┘
```

### (2) なぜ統合せず別々に進化させるのか？
1. **ULisp の不動点保証（`diff stage2.s stage3.s == 0`）の保護**:
   ULisp は自己ホスティングコンパイラとして極小かつ副作用のない純粋関数型パイプラインを維持しています。JIT の動的状態（W^X 実行可能メモリ、キャッシュ、投機的ガード）を ULisp に混入させないことで、100% 決定論的なコード生成の信頼性を永久に担保します。
2. **MLisp のアグレッシブな機能拡張の自由度**:
   ULisp を汚すことなく、MLisp 側でインラインキャッシュ、トレースツリー、JIT デオプティマイゼーション（Bailout）、高機能対話型 REPL などの先端的な動的最適化を独立して自由に実験・導入できます。
3. **単方向依存ルール（One-Way Dependency Invariant）**:
   - `mlisp` が `ulisp` のコード（`lib/` や `passes/`）を読み取り専用で利用することは許可。
   - `ulisp` が `mlisp` に依存することは**厳格に禁止（逆依存 0 件）**。

### (3) それぞれの今後の進化軸
- **`ulisp/` の発展**: 型推論（フロー解析）、SIMD/ベクトル最適化、バックエンド（WebAssembly / RISC-V）の拡充。
- **`mlisp/` の発展**: 多相的インラインキャッシュ、JIT プロファイラ、動的トレース結合、対話型言語機能の拡張。

