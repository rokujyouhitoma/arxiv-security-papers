---
ID: 841
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] コンパイラ本体ソースコードからの Gauche 固有 cond-expand 分岐の撤去と R7RS / ULisp 標準化 (ID: 841)

## 1. 概要 / Summary
現在、ULisp コンパイラ本体のソースコード中に、Gauche 固有の構文・キーワード引数（`:element-type :binary` や `nan?` / `infinite?`、手動 byte 出力ループ）を前提とした `(cond-expand (gauche ...) ...)` 節が 3 箇所残存している。
これにより、ビルド時の中間生成物（`ulisp/build/` 下のテストランナーやコンパイラファイル）に `(gauche ...)` が大量に複製・波及し、外部から見ると Gauche に必須依存しているような構造となっている。

本 Issue では、コンパイラ本体ソースからこれらの Gauche 固有分岐を完全に排除し、R7RS Small 仕様（`scheme.base`, `scheme.file`, `write-bytevector` 等）および ULisp 内蔵システムコール・プリミティブ（`sys-open`, `sys-read`, `write-bytevector` 等）へ統一・標準化する。

---

## 2. トレーサビリティ / Traceability
- **関連仕様・ドキュメント**:
  - `ulisp/docs/spec_pipeline.md` (自己完結型ツールチェイン・ゼロ外部依存仕様)
  - `ulisp/docs/guide_portable_build.md` (外部ホスト依存なしの純粋ビルド仕様)
  - R7RS Small (IEEE Std 1178-1990 / Revised^7 Report on the Algorithmic Language Scheme)
- **後続 Issue への依存関係**:
  - 本 Issue (841) は、Issue 844（中間生成物クリーンアップとゼロ Gauche 検証）の前提条件となる。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) (行 1961 付近: `sanitize-reader-form` 関数内の `cond-expand (gauche ...)` 節)
- [x] [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm) (行 23 付近: `write-elf64-bytevector` 関数内の `(gauche ...)` 節)
- [x] [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm) (行 856 付近: `read-binary-file-to-bytevector` 関数内の `(gauche ...)` 節)
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (`make compiler.scm` により上記変更が自動連結・反映されるバンドルソース)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/841-eliminate-gauche-cond-expand-branches`

1. **`ulisp/compiler/helpers.scm` の修正 (`sanitize-reader-form`)**:
   - 行 1960〜1974 の以下のコードを修正：
     ```scheme
     ;; 現状:
     (cond-expand
       (gauche
        (cond
          ((and (number? expr) (nan? expr))
           (string->symbol "+nan.0"))
          ((and (number? expr) (infinite? expr) (> expr 0))
           (string->symbol "+inf.0"))
          ((and (number? expr) (infinite? expr) (< expr 0))
           (string->symbol "-inf.0"))
          (else expr)))
       (else expr))
     ```
   - 修正案:
     Gauche 固有の条件分岐を削除し、R7RS `scheme.inexact` / 内蔵関数または標準の `expr` 返却へ一本化する（ULisp 内部ではリーダーおよび AST パスで浮動小数点リテラルを直接扱えるため、`(else expr)` の挙動で十分）。
2. **`ulisp/backend/144_backend_x86_elf.scm` の修正 (`write-elf64-bytevector`)**:
   - 行 23〜31 の `(gauche ...)` 節（`write-byte` と `flush` による手動ループ）を削除。
   - `write-bytevector` と `flush-output-port` による標準処理（`ulisp` 節および `else` 節の `binary-port?` ガード）のみを残す。
3. **`ulisp/backend/elf64_builder.scm` の修正 (`read-binary-file-to-bytevector`)**:
   - 行 855〜860 の `(gauche (call-with-input-file path ... :element-type :binary))` 節を削除。
   - すでに `else` 句に実装されている内蔵低レベルシステムコール（`sys-open`, `sys-lseek`, `sys-read`, `sys-close`）に一本化、または R7RS 標準 `open-binary-input-file` を用いたポータブル実装に整理。
4. **バンドルファイル同期**:
   - `cd ulisp && make compiler.scm` を実行し、ソースコード変更を `compiler.scm` に同期。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `git grep "(gauche" ulisp/compiler/helpers.scm ulisp/backend/` の実行結果が **0 件** であること。
- [x] `make -C ulisp compiler.scm` を実行し、`ulisp/compiler.scm` 内からも該当の `(gauche ...)` 節が消去されていること。
- [x] `make -C ulisp py_compile` および `make -C ulisp lint_sexpr` がエラー 0 件で通過すること。
- [x] ネイティブビルド（`make -C ulisp bin/ulisp-boot` 等）が既存の動作を壊さずに PASS すること。
