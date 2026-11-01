---
ID: 654
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-11-01
---

# [FEAT/ENH] R7RS-large (SRFI 28) 基本フォーマット文字列手続き (format) の実装 (ID: 654)

## 1. 概要 / Summary
R7RS-large / SRFI 28 で規定されている基本文字列整形手続き `(format <format-string> <arg> ...)` を ULisp に実装する。
本手続きは `~a` / `~A` (display 形式), `~s` / `~S` (write 形式), `~%` (改行), `~~` (チルダ文字リテラル) などの標準フォーマット指定子を解釈し、整形された新しい文字列を生成・返却する。
これにより、テストコードのアサーションメッセージ、コンパイラ診断・エラー出力、CLI ログメッセージ等の構築を大幅に簡潔化し、R7RS-large 互換性を高める。

---

## 2. アーキテクチャと設計方針 / Architecture & Design Principles

### (1) 静的直接呼び出しの脱糖最適化 (Pass 030: `030_desugar.scm`)
- コンパイル時に `(format <fmt> <arg> ...)` の直接呼び出しを検出し、`(%format <fmt> (list <arg> ...))` へ脱糖。
- 引数が 0 個の場合 `(format)` はコンパイル時構文エラー（arity error）を送出。
- これにより、静的直接呼び出し時はコンパイラが固定2引数呼び出しとして最適化し、アロケーションと呼び出し規約オーバーヘッドを最小化する。

### (2) 第一級手続きオブジェクトとしての `format` (`ulisp/lib/format.scm`)
- `apply` や高階関数などの動的引数ディスパッチに対応するため、Pass 028 で安全に `%num-args` 分岐に脱糖される `case-lambda` を用いて第一級手続き `format` を定義する。
  ```scheme
  (define format
    (case-lambda
      ((fmt)
       (%format fmt '()))
      ((fmt a1)
       (%format fmt (list a1)))
      ((fmt a1 a2)
       (%format fmt (list a1 a2)))
      ((fmt a1 a2 a3)
       (%format fmt (list a1 a2 a3)))
      ((fmt a1 a2 a3 a4)
       (%format fmt (list a1 a2 a3 a4)))
      ((fmt a1 a2 a3 a4 . rest)
       (%format fmt (cons a1 (cons a2 (cons a3 (cons a4 rest))))))))
  ```

### (3) メモリ上文字列ポートを活用した高速パーサー (`%format`)
- `open-output-string` で開いたバッファポートへ書き出しを行い、走査完了後に `get-output-string` で文字列を抽出。
- `string-length` および `string-ref` によるインデックス走査でリストアロケーションを抑止。
- **SRFI 28 指定子の完全サポート**:
  - `~a` / `~A`: `(display (car objects) buffer)`
  - `~s` / `~S`: `(write (car objects) buffer)`
  - `~%`: `(newline buffer)`
  - `~~`: `(write-char #\~ buffer)`
- **エラー処理の厳格性 (SRFI 28 仕様準拠)**:
  - `format-string` が文字列でない場合: `(error "format: format-string must be a string" fmt)`
  - 末尾の孤立した `~`: `(error "format: illegal trailing escape character ~")`
  - 未知の指定子: `(error "format: illegal directive" directive)`
  - 引数不足 (Underflow): `(error "format: too few arguments" directive)`
  - 引数過剰 (Overflow): `(error "format: too many arguments" objects)`

### (4) ライブラリ構成とモジュール連携
- `ulisp/lib/format.scm`: コアフォーマッター `%format` および第一級手続き `format` を定義。
- `ulisp/lib/srfi/28.sld`: `(define-library (srfi 28) (export format) (import (scheme base)) (include "lib/format.scm"))`
- `ulisp/Makefile`: `ULISP_STD_LIBS` に `lib/format.scm` を登録し、全ランタイム・テストで透過的に利用可能にする。

---

## 3. セキュリティ・脅威分析 / Threat Modeling & Security Analysis

| 脅威カテゴリ (STRIDE) | 想定されるリスク | 対策・緩和策 |
| :--- | :--- | :--- |
| **Tampering / Injection** | 悪意のあるフォーマット指定子によるメモリ破壊やスタック改ざん | C 言語の `printf` と異なり、メモリ直接操作は一切行わず、Scheme レベルの文字列ポート (`display`/`write`) 経由でのみ出力。メモリ安全性が保証される。 |
| **Denial of Service (DoS)** | 末尾の `~` や境界外インデックス参照によるクラッシュ (SIGSEGV) | 文字列長 `len` と現在インデックス `i` の境界チェックを厳格化。`(+ i 1) >= len` の場合は即座に安全な例外を送出。 |
| **Type Confusion** | フォーマット文字列に数値やシンボルを渡すことによる型不整合 | 先頭で `(string? fmt)` による事前検証を行い、不正型入力時は即座に例外送出。 |
| **Argument Mismatch** | 引数個数の不一致（不足・過剰）による未定義動作 | 引数不足時および全指定子解釈後の余剰引数検出時に明示的例外を送出（SRFI 28 厳格準拠）。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

Target Branch: `feat/654-implement-srfi-28-basic-format-string`

- [x] [ulisp/lib/format.scm](../../ulisp/lib/format.scm) (新規モジュール: `%format` および `format` 手続き)
- [x] [ulisp/lib/srfi/28.sld](../../ulisp/lib/srfi/28.sld) (新規ライブラリ: SRFI 28 定義)
- [x] [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm) (`format` の静的呼び出し脱糖規則追加)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`ULISP_STD_LIBS` 登録、`test_format` ターゲット、`lint_sexpr`、`test` 統合)
- [x] [ulisp/tests/test_format.scm](../../ulisp/tests/test_format.scm) (新規テストスイート: 5グループ 31項目 100% PASS)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (SRFI 28 ステータスを `◎` に更新)

---

## 5. 実装手順 / Implementation Steps

### Step 1: コアフォーマッターの実装 (`ulisp/lib/format.scm`)
- `(%format fmt-str args)` の実装:
  - `string?` 検査
  - `open-output-string` でバッファ確保
  - `string-ref` によるループ走査
  - `~a`, `~A`, `~s`, `~S`, `~%`, `~~` の分岐処理
  - 引数リストの消費と過不足バリデーション
  - `get-output-string` で結果文字列返却
- `case-lambda` による第一級手続き `format` の定義

### Step 2: Pass 030 (`030_desugar.scm`) での直接呼び出し脱糖
- `desugar-format` ヘルパーを定義:
  - `(format)` -> `(error "format: too few arguments (requires format-string)")`
  - `(format fmt . args)` -> `(%format ,fmt (list ,@args))`
- `desugar-all` のディスパッチテーブルに `((format . ,args) ...)` を追加

### Step 3: SRFI 28 ライブラリ定義 (`ulisp/lib/srfi/28.sld`)
- `(define-library (srfi 28) (export format) (import (scheme base)) (include "lib/format.scm"))` を作成

### Step 4: テストスイートの作成 (`ulisp/tests/test_format.scm`)
- **Group 1**: 引数なし基本フォーマット (`(format "hello world")` -> `"hello world"`)
- **Group 2**: `~%` 改行および `~~` チルダ文字 (`(format "line1~%line2~~")` -> `"line1\nline2~"`)
- **Group 3**: `~a` / `~A` (display) による文字列・数値・シンボル・リストの埋め込み
- **Group 4**: `~s` / `~S` (write) によるクォート文字列・S式の埋め込み比較 (`~a` との相違確認)
- **Group 5**: 動的呼び出し (`apply format ...`) およびエラーハンドリング（引数不足・過剰・不正指定子）

### Step 5: Makefile への統合とビルド検証
- `ulisp/Makefile` の `ULISP_STD_LIBS` に `lib/format.scm` を追加。
- `test_format` ターゲットを追加し、`test` に組み込み。
- `make lint_sexpr` で全 S 式括弧整合性を確認。
- `make test_format` および既存テストの実行。

### Step 6: 3-Stage Bootstrap 検証と R7RS ドキュメント更新
- `./bootstrap.sh` による 3-Stage ブートストラップおよび Stage 2/3 出力固定点検証。
- `ulisp/docs/ref_r7rs_compliance.md` の SRFI 28 を `◎` に更新。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/lib/format.scm` にて `%format` および `format` が正しく定義されていること。
- [x] `(format "Result: ~a, S-expr: ~s~%" 42 '(a b))` が期待通りの文字列を出力すること。
- [x] `ulisp/lib/srfi/28.sld` が作成され、`(import (srfi 28))` で透過的に利用できること。
- [x] Pass 030 で `format` の直接呼び出しが `(%format ...)` にインライン脱糖されること。
- [x] `make test_format` が 100% PASS すること。
- [x] 全回帰テスト (`make test`) が 100% PASS すること。
- [x] `./bootstrap.sh` がエラーなく完走し、Stage 2 と Stage 3 の出力が完全一致すること。
- [x] `make check_format` および `make static_analysis` がエラー 0 件で PASS すること。
- [x] `ref_r7rs_compliance.md` の SRFI 28 ステータスが `◎` に更新されていること。
- [x] Issue ファイルが `docs/issues/closed/` に移動され、台帳が更新されていること。
