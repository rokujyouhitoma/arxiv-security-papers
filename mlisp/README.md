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
- `optimizer/`: トレース部分評価・エスケープ解析・仮想オブジェクト縮退
- `bridge/`: トレースから ULisp LIR への変換アダプタ
- `emitter/`: **Pure Scheme 製ダイレクト機械語エミッタ**
  - `asm_x86_64.scm`: x86-64 バイトコードアセンブラ
  - `asm_aarch64.scm`: AArch64 バイトコードアセンブラ
- `runtime/`: JIT 実行時メモリバッファ（W^X 保護）およびネイティブディスパッチャ
  - `jit_buffer.scm`: 実行可能バッファ管理
- `tests/`: 単体・結合テストスイート
  - `test_delimcc.scm`: 限定継続セマンティクス検証テスト

---

## 2. 実行・テスト・ネイティブバイナリビルド方法

### A. RPython スタイル: ワンバイナリ AOT ビルド (`make bin`)
RPython の `rpython target.py` と同様に、ULisp の AOT コンパイラを利用して、ターゲット言語処理系を **スタンドアロンな単一 Linux ELF バイナリ** に直接コンパイルします。

```bash
# スタンドアロンネイティブバイナリのビルド
make -C mlisp bin

# ビルドされたワンバイナリの直接実行（Python/外部依存なし）
./mlisp/bin/tiny_vm
```

### B. インタラクティブ実動デモ (`make demo`)
TinyVM のバイトコード実行、JIT 生トレース自動合成、PE & Virtuals によるトレース最適化、ULisp Pass 6 LIR への変換、および自己適用メタ循環 Scheme 評価器の一連の流れを対話的に実行します。

```bash
make -C mlisp demo
```

### C. 全テストスイートの実行 (`make test`)
```bash
# 全テスト（70項目）の一括実行
make -C mlisp test
```
