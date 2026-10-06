---
ID: 490
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ULisp Phase 4: バンプアロケータ・リスト (cons, car, cdr, pair?)・破壊的代入・quote 構文の実装 (ID: 490)

## 1. 概要 / Summary

[DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) に基づき、ULisp の Phase 4（Step 12〜16: バンプアロケータ・ヒープポインタ・ペア生成とアクセサ `cons`/`car`/`cdr`/`pair?`・破壊的代入 `set-car!`/`set-cdr!`・クォート `quote` 式・ポインタ等値述語 `eq?`）を実装する。

ヒープポインタ（下位 2bit = `01`）による Tagged Pointer メモリ表現を実体化し、外部 GC に依存しない 128MB バンプアロケータにより、複合データ構造（リスト）の生成・探索・変更をネイティブ x86-64 で実現する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 2.1 節 Tagged Pointer, 第 2.3 節 ゼロGC・バンプアロケータ, 第 3.4 節 ペアとリストプリミティブ, 第 4 章 Phase 4)
  - [DSN-31: ILISP (Intelligence LISP) R7RS コアアーキテクチャ包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) (第 2.1 節, 第 3.2 節)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/runtime.c](../../ulisp/runtime.c) (128MB ヒープ領域の確保、引数渡しの拡張、再帰的ペア・リスト構造のプリント出力)
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (R12 バンプポインタ管理、`cons`/`car`/`cdr`/`pair?` コード生成、`set-car!`/`set-cdr!`、`quote` 脱糖、`eq?`)
- [x] [ulisp/test.sh](../../ulisp/test.sh) (Phase 4 テストスイートの追加: リスト生成、アクセサ、深いリスト、破壊的代入、quote リテラル、eq?、大量アロケーション)
- [x] [ulisp/README.md](../../ulisp/README.md) (ロードマップ進捗状況表の更新)
- [x] [docs/issues/README.md](../../docs/issues/README.md) (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/490-implement-ulisp-phase4-heap-memory-and-data-structures`

1. **C ランタイム拡張 (`runtime.c`)**:
   - 128MB のヒープバッファを `malloc(128 * 1024 * 1024)` で確保。
   - `scheme_entry(char *heap_base)` のシグネチャにし、第 1 引数（RDI レジスタ）経由でヒープアドレスを渡す。
   - `print_scheme_value` にヒープペア（タグ `(val & 3) == 1`）の再帰的プリントルーチンを追加（`(1 2 3)` や `(1 . 2)` などの Scheme 標準リスト書式）。
2. **Step 12: バンプアロケータポインタ (`R12`)**:
   - `scheme_entry` のプロローグで `push r12`、`mov r12, rdi`。エピローグで `pop r12`。
   - `R12` を 16 バイト単位でインクリメントしてアロケート。
3. **Step 13: ペアプリミティブ (`cons`, `car`, `cdr`, `pair?`)**:
   - `(cons e1 e2)`:
     - `e1`, `e2` を順次評価してスタック退避。
     - `[r12]` に `e1`、`[r12 + 8]` に `e2` をストア。
     - `lea rax, [r12 + 1]`（タグ `0x01` 付与）を RAX へ。
     - `add r12, 16`。
   - `(car p)` / `(cdr p)`:
     - `p` を評価し、タグ `0x01` を解除して `[rax - 1]` / `[rax + 7]` からロード。
   - `(pair? x)`:
     - `x` を評価し、`and al, 3` $\to$ `cmp al, 1` $\to$ `emit-boolean`。
4. **Step 14: 破壊的代入 (`set-car!`, `set-cdr!`)**:
   - `p` を評価して退避、`val` を評価。
   - `mov rdx, [rsp + si]`
   - `mov [rdx - 1], rax` (set-car!) / `mov [rdx + 7], rax` (set-cdr!)。
   - 戻り値として `'()`（`0x3F`）を RAX にセット。
5. **Step 15: クォート構文 (`quote`)**:
   - `(quote datum)`:
     - アトム（整数、真偽値、文字、空リスト）は即値出力。
     - ペア `'(a b ...)` はコンパイラ内部で `(cons (quote a) (quote (b ...)))` に再帰的脱糖してコード生成。
6. **Step 16: ポインタ等値判定 (`eq?`)**:
   - `(eq? e1 e2)`:
     - `e1` を退避、`e2` を評価。
     - `cmp [rsp + si], rax` $\to$ `sete al` $\to$ `emit-boolean`。
     - 即値だけでなく、同一ヒープアドレスを指すペア同士の等値性を $O(1)$ で判定。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `(cons 1 2)` が `(1 . 2)`、`(cons 1 (cons 2 '()))` が `(1 2)` を出力すること。
- [x] `(car (cons 1 2))` が 1、`(cdr (cons 1 2))` が 2 を返すこと。
- [x] `pair?` がペアに対して `#t`、即値や空リストに対して `#f` を返すこと。
- [x] `set-car!` および `set-cdr!` による破壊的変更がその後の `car`/`cdr` で読み取れること。
- [x] `'(1 2 3)`、`'((1 2) (3 4))` などのネストした `quote` リストが正しく構築・表示されること。
- [x] `eq?` が同一ポインタ（同一ペア）で `#t`、別個に生成されたペアで `#f` を返すこと。
- [x] `./test.sh` で Phase 1〜4 の全テストがグリーンであること。
- [x] `ulisp/README.md` の進捗状況表で Phase 4 が完了として反映されていること。
