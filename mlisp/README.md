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
MLisp の内因的メタトレーシング JIT 基盤（`driver/compile_ulisp_runner.scm`）を用いて、ULisp の自己ホスティングコンパイラ（`ulisp/build/ulisp_core.scm`）を丸ごとコンパイルし、スタンドアロンネイティブバイナリ `ulisp/build/scheme-from-mlisp` を生成します。
これにより、Python（ILisp）に依存していた Stage 1 ブートストラップコンパイラを MLisp 実行基盤へと置き換え、完全な自己ホスティング循環コンパイルを実証します。

```bash
# MLisp JIT 基盤経由で ULisp コンパイラをネイティブコンパイル
make -C mlisp compile_ulisp

# 生成されたネイティブコンパイラバイナリの動作検証
make -C ulisp run_mlisp_stage
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

### F. 全テストスイートの実行 (`make test`)
```bash
# 全テスト（94項目）の一括実行
make -C mlisp test
```
