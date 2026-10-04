# ILISP セルフホスティング・ブートストラップ連鎖仕様書 (Bootstrap Specification)

本ドキュメントは、ILISP が「ホスト言語（Python）への依存から脱却し、ILISP自身でILISPコンパイラをコンパイルする」ための **3段階ブートストラップ（Self-Hosting Bootstrap Chain）** および不動点検証の技術仕様を規定します。

---

## 1. ブートストラップ連鎖（T-Diagram）

```text
[Stage-0: Python Host]
  compiler.py (Python) ──コンパイル──> compiler.ilisp ──出力──> ilisp_stage1.c
                                                                     │ (gcc -O3)
                                                                     ▼
                                                              ilisp-stage1 (Native)

[Stage-1: ILISP-in-ILISP]
  ilisp-stage1 (Native) ──コンパイル──> compiler.ilisp ──出力──> ilisp_stage2.c
                                                                     │ (gcc -O3)
                                                                     ▼
                                                              ilisp-stage2 (Native)

[Stage-2: 不動点検証 (Fixed-Point Verification)]
  diff -u ilisp_stage1.c ilisp_stage2.c  ===>  差分 0 (完全一致)
```

---

## 2. 各ステージの役割と要件

### Stage-0: Python ホスト版ブートストラップ (`ilisp.compiler`)
- **実装言語**: Pure Python 3.10+
- **役割**:
  - ILISP の最初のコードを評価し、開発サイクルの迅速な試行錯誤を支える。
  - `compiler.ilisp` をパースし、最初の C言語コード `ilisp_stage1.c` を生成する。
- **制約**:
  - Stage-0 の内部 AST は、ILISP のデータ型（`Cons`, `Symbol`, `Vector` 等）と 1:1 に写像できるシンプルなデータ構造とする。

### Stage-1: 自己記述コンパイラ (`ilisp/compiler.ilisp`)
- **実装言語**: 100% ILISP (R7RS-small Scheme)
- **役割**:
  - ILISP 自身の文法で書かれた完全なコンパイラロジック（Reader、マクロ展開器、コード生成器）。
  - `ilisp-stage1` 実行ファイルによって自身をコンパイルし、`ilisp_stage2.c` を出力する。

### Stage-2: 不動点到達と完全自立 (`ilisp-stage2`)
- **役割**:
  - `ilisp_stage1.c` と `ilisp_stage2.c` が同一であることを証明し、コンパイラが完全に決定論的（Deterministic）かつ自己充足していることを機械的に保証する。
  - この時点で、Python なしで完全に自立した単一バイナリ配布が可能となる。

---

## 3. 不動点検証テスト (`test_bootstrap.py`)

本リポジトリの [DSN-25 (Packrat PEG Engine)](../../docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md) で確立されたセルフホスティング検証パターンに準拠し、以下の自動テストを CI/CD で実行します：

1. `compiler.py` を用いて `compiler.ilisp` を Cコード `stage1.c` へ変換。
2. `gcc -O2 stage1.c -o ilisp_stage1` でビルド。
3. `./ilisp_stage1 compiler.ilisp -o stage2.c` を実行。
4. `assert file_content("stage1.c") == file_content("stage2.c")` を検証。
