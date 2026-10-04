# ILISP セルフホスティング・ブートストラップ連鎖仕様書 (Bootstrap Specification)

本ドキュメントは、ILISP が「ホスト言語（Python）への依存から脱却し、ILISP自身でILISPコンパイラをコンパイルする」ための **Kernel ILISP 最小仕様**、**3段階ブートストラップ（Self-Hosting Bootstrap Chain）**、および不動点検証の技術仕様を規定します。

---

## 1. 3段階開発ロードマップとブートストラップの位置付け

ILISP の開発は、外部依存と不確実性を最小化するため、以下の 3 段階に分けて進行します（詳細は [DSN-31](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) 参照）：

1. **Phase 1: Kernel ILISP 最小構成（現行マイルストーン）**
   - **目的**: 外部依存ゼロ（純粋 Python 標準ライブラリのみ）で動作する最小のコア言語基盤の確立。
   - **構成**: 手書き再帰下降 Reader（`SourceLocation` 保持）、最小 S式 AST、Tree-walk 評価器、基本環境フレーム、コア基本式（6個）とプリミティブ（23個）、原始的マクロ（`define-macro` / 基本 `syntax-rules`）、対話型 REPL、基本 Python 相互運用。
2. **Phase 2: Advanced Macro & Transpiler (セルフホスティング期)**
   - **目的**: Stage-0 (Python) から Stage-1 (C99 AOT) へのトランスパイルと完全不動点検証の達成、Scope Sets 衛生的マクロの実装。
3. **Phase 3: Extreme Performance & VM (超高速・並行実行期)**
   - **目的**: Rust Standalone Bytecode VM (Backend C) による No-GIL 並行実行、NaN-Boxing、PyO3 ネイティブ拡張の提供。

---

## 2. セルフホスティング・ブートストラップ連鎖（T-Diagram）

```text
[Stage-0: Python Host (Phase 2)]
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

## 3. Kernel ILISP（最小ブートストラップ核）仕様

Stage-1 の自己ホストコンパイラ（`compiler.ilisp`）および Phase 1 最小評価器において、未実装の高度なマクロや複素数演算に依存した「鶏と卵」の循環デバッグを回避するため、使用可能な言語機能を **「Kernel ILISP」** として厳格に制限・凍結します。

### 3.1 6大基本式 (Special Forms)
すべての構文は以下の 6 つの基本式のみで構成されます：
1. **変数参照**: `x`
2. **定数クォート**: `(quote datum)` または `'datum`
3. **手続き抽象**: `(lambda (param ...) body ...)`
4. **条件分岐**: `(if test then else)`
5. **破壊的代入**: `(set! var expr)` （※静的代入解析により変更対象変数を `Cell` に昇格）
6. **逐次実行**: `(begin expr ...)`

### 3.2 必須コアプリミティブ (23個)
- **ペア・リスト操作**: `cons`, `car`, `cdr`, `pair?`, `null?`, `list` （※Python シーケンスは `SequenceView` で $O(1)$ ゼロコピー走査）
- **シンボル・文字列**: `symbol?`, `symbol->string`, `string?`, `string-append`, `string=?`
- **等価性・真偽値**: `eq?`, `eqv?`, `boolean?`, `not`
- **整数基本演算**: `+`, `-`, `*`, `quotient`, `remainder`, `=`, `<`, `>`
- **入出力基本**: `read-char`, `write-char`, `peek-char`, `eof-object?`

### 3.3 リーダーと制御構造の制約
- **手書き再帰下降リーダー**: PEG 等の外部依存を排し、約 300 行の純粋 Python リーダーで正確なソース位置（`file`, `line`, `col`）を AST に記録。
- `let`, `cond`, `and`, `or`, `when`, `unless` は、マクロまたは **コンパイラフロントエンドで `lambda` と `if` への直接脱糖（Desugaring）** として処理する。
- 反復ループはすべて **自己末尾再帰関数（Self Tail-Recursive Function）** で記述する（ハイブリッド TCO によりスタックゼロ消費でループ実行）。

---

## 4. 各ステージの役割と要件

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

## 5. 不動点検証テスト (`test_bootstrap.py`)

本リポジトリの [DSN-25 (Packrat PEG Engine)](../../docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md) で確立されたセルフホスティング検証パターンに準拠し、以下の自動テストを CI/CD で実行します：

1. `compiler.py` を用いて `compiler.ilisp` を Cコード `stage1.c` へ変換。
2. `clang -O3 stage1.c -o ilisp_stage1` でビルド。
3. `./ilisp_stage1 compiler.ilisp -o stage2.c` を実行。
4. `assert file_content("stage1.c") == file_content("stage2.c")` を検証（差分 0 バイト）。

---

## 6. 関連ドキュメント体系

- [README.md](README.md): ILISP 概要・クイックスタート・3本柱アーキテクチャ
- [SPEC_R7RS.md](SPEC_R7RS.md): R7RS-small 全203機能の仕様準拠マトリクス & chibi-scheme 公式テスト 100% 適合検証レポート
- [PYTHON_INTEROP.md](PYTHON_INTEROP.md): Python 双方向ゼロコピー相互運用・SequenceView・双方向呼出仕様
- [MACROS_AND_CONDITIONS.md](MACROS_AND_CONDITIONS.md): Scope Sets マクロ & 現場復帰コンディション & テストハーネス仕様
- [DSN-31 包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md): ILISP R7RS コアアーキテクチャ包括設計仕様書
