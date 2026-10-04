# ILISP セルフホスティング・ブートストラップ連鎖仕様書 (Bootstrap Specification)

本ドキュメントは、ILISP が「ホスト言語（Python）への依存から脱却し、ILISP自身でILISPコンパイラをコンパイルする」ための **Kernel ILISP 最小仕様**、**3段階ブートストラップ（Self-Hosting Bootstrap Chain）**、および不動点検証の技術仕様を規定します。

---

## 1. ブートストラップ連鎖（T-Diagram）

```text
[Stage-0: Python Host]
  compiler.py (Python) ──コンパイル──> compiler.ilisp (Kernel) ──出力──> ilisp_stage1.c
                                                                               │ (clang/gcc -O3)
                                                                               ▼
                                                                        ilisp-stage1 (Native)

[Stage-1: ILISP-in-ILISP]
  ilisp-stage1 (Native) ──コンパイル──> compiler.ilisp (Kernel) ──出力──> ilisp_stage2.c
                                                                               │ (clang/gcc -O3)
                                                                               ▼
                                                                        ilisp-stage2 (Native)

[Stage-2: 不動点検証 (Fixed-Point Verification)]
  diff -u ilisp_stage1.c ilisp_stage2.c  ===>  差分 0 (完全一致)
```

---

## 2. Kernel ILISP（最小ブートストラップ核）仕様

Stage-1 の自己ホストコンパイラ（`compiler.ilisp`）を記述するにあたり、未実装の高度なマクロや複素数演算に依存した「鶏と卵」の循環デバッグを回避するため、使用可能な言語機能を **「Kernel ILISP」** として厳格に制限・凍結します。

### 2.1 6大基本式 (Special Forms)
すべての構文は以下の 6 つの基本式のみで構成されます：
1. **変数参照**: `x`
2. **定数クォート**: `(quote datum)` または `'datum`
3. **手続き抽象**: `(lambda (param ...) body ...)`
4. **条件分岐**: `(if test then else)`
5. **破壊的代入**: `(set! var expr)`
6. **逐次実行**: `(begin expr ...)`

### 2.2 必須コアプリミティブ
- **ペア・リスト操作**: `cons`, `car`, `cdr`, `pair?`, `null?`, `list`
- **シンボル・文字列**: `symbol?`, `symbol->string`, `string?`, `string-append`, `string=?`
- **等価性・真偽値**: `eq?`, `eqv?`, `boolean?`, `not`
- **整数基本演算**: `+`, `-`, `*`, `quotient`, `remainder`, `=`, `<`, `>`
- **入出力基本**: `read-char`, `write-char`, `peek-char`, `eof-object?`

### 2.3 制御構造の制約
- `let`, `cond`, `and`, `or`, `when` は、マクロではなく **コンパイラフロントエンドで `lambda` と `if` への直接脱糖（Desugaring）** として処理する。
- 反復ループはすべて **自己末尾再帰関数（Self Tail-Recursive Function）** で記述する。

---

## 3. 各ステージの役割と要件

### Stage-0: Python ホスト版ブートストラップ (`ilisp.compiler`)
- **実装言語**: Pure Python 3.10+
- **役割**:
  - ILISP の最初のコードを評価し、開発サイクルの迅速な試行錯誤を支える。
  - `compiler.ilisp`（Kernel ILISP）をパースし、最初の C99 コード `ilisp_stage1.c` を生成する。
- **制約**:
  - Stage-0 の内部 AST は、ILISP のデータ型（`Cons`, `Symbol`, `Vector` 等）と 1:1 に写像できるシンプルなデータ構造とする。

### Stage-1: 自己記述コンパイラ (`ilisp/compiler.ilisp`)
- **実装言語**: 100% Kernel ILISP
- **役割**:
  - ILISP 自身の文法で書かれた完全なコンパイラロジック（Reader、脱糖器、C99 コード生成器）。
  - `ilisp-stage1` 実行ファイルによって自身をコンパイルし、`ilisp_stage2.c` を出力する。
  - 出力される C99 コードは自己完結型 ARC（参照カウント）を含み、外部ライブラリ依存ゼロを保証。

### Stage-2: 不動点到達と完全自立 (`ilisp-stage2`)
- **役割**:
  - `ilisp_stage1.c` と `ilisp_stage2.c` が同一であることを証明し、コンパイラが完全に決定論的（Deterministic）かつ自己充足していることを機械的に保証する。
  - `clang -O3` でビルドすることで、Clang/LLVM の最高峰最適化パスが適用された極小ネイティブ単一バイナリが完成する。
  - この時点で、Python なしで完全に自立した単一バイナリ配布が可能となる。

---

## 4. 不動点検証テスト (`test_bootstrap.py`)

本リポジトリの [DSN-25 (Packrat PEG Engine)](../../docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md) で確立されたセルフホスティング検証パターンに準拠し、以下の自動テストを CI/CD で実行します：

1. `compiler.py` を用いて `compiler.ilisp` を Cコード `stage1.c` へ変換。
2. `clang -O3 stage1.c -o ilisp_stage1` でビルド。
3. `./ilisp_stage1 compiler.ilisp -o stage2.c` を実行。
4. `assert file_content("stage1.c") == file_content("stage2.c")` を検証（差分 0 バイト）。
