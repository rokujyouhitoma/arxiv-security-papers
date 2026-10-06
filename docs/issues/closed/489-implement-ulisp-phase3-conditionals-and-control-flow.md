---
ID: 489
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ULisp Phase 3: 条件分岐 (if)・論理脱糖 (and, or, not)・複文 (begin) の実装 (ID: 489)

## 1. 概要 / Summary

[DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) に基づき、ULisp の Phase 3（Step 9〜11: ラベル生成・条件ジャンプ `if`・短絡評価論理脱糖 `and`/`or`/`not`・シーケンス実行 `begin`）を実装する。

Scheme の標準真偽セマンティクス（`#f` のみ偽、0 や `'()` を含む他はすべて真）を厳密に保証し、ジャンプ命令（`je`, `jmp`）による制御フローを確立する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 3.3 節 条件分岐と論理演算の脱糖, 第 4 章 Phase 3)
  - [DSN-31: ILISP (Intelligence LISP) R7RS コアアーキテクチャ包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) (第 2.1 節 言語コアの最小直交性)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (ラベル連番生成、`if` 条件分岐コード生成、`and`/`or` 脱糖マクロ、`not` 判定、`begin` 順次評価)
- [x] [ulisp/test.sh](../../ulisp/test.sh) (Phase 3 テストスイートの追加: 条件分岐、短絡評価、真偽規則、シーケンス)
- [x] [ulisp/README.md](../../ulisp/README.md) (ロードマップ進捗状況表の更新)
- [x] [docs/issues/README.md](../../docs/issues/README.md) (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/489-implement-ulisp-phase3-conditionals-and-control-flow`

1. **決定論的ラベル生成器 (`unique-label`)**:
   - カウンタによる一意ラベル生成: `.Lelse_0`, `.Lend_0`。
   - 不動点検証（セルフホスト）を阻害しない決定論的連番を使用。
2. **Step 9: 条件分岐 (`if` 式)**:
   - `(if test then else)`:
     - `test` を評価（結果は RAX）。
     - `cmp rax, 0x2F`（`#f` との比較）。
     - `je .Lelse_N`。
     - `then` を評価。
     - `jmp .Lend_N`。
     - `.Lelse_N:`
     - `else` を評価。
     - `.Lend_N:`
   - 1分岐形式 `(if test then)` の場合は `else` 時に `#f` を返す。
3. **Step 10: 論理演算の脱糖 (`and`, `or`, `not`)**:
   - `(and ...)`:
     - `(and)` $\to$ `#t`
     - `(and e1)` $\to$ `e1`
     - `(and e1 e2 ...)` $\to$ `(if e1 (and e2 ...) #f)`（短絡評価）
   - `(or ...)`:
     - `(or)` $\to$ `#f`
     - `(or e1)` $\to$ `e1`
     - `(or e1 e2 ...)` $\to$ `(let ((tmp e1)) (if tmp tmp (or e2 ...)))`（短絡評価かつ一度のみ評価）
   - `(not e)`:
     - `e` を評価 $\to$ `cmp rax, 0x2F` $\to$ `sete al` $\to$ `emit-boolean`。
4. **Step 11: 複文 (`begin` 式)**:
   - `(begin e1 e2 ...)`:
     - `e1`, `e2`, ... を先頭から順次評価し、最後の式の評価結果を RAX に保持したまま脱出。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `(if #t 1 2)` が 1、`(if #f 1 2)` が 2 を返すこと。
- [x] Scheme の真偽規則に従い、`0` や `'()` が条件式で「真」として扱われること（`(if 0 'yes 'no)` $\to$ `yes`）。
- [x] `and` および `or` の短絡評価（偽/真が確定した時点で後続を評価しない）が正しく動作すること。
- [x] `not` 演算が Scheme 規則通り反転すること。
- [x] `begin` 式で先行する式が評価され、最後の式の値が返ること。
- [x] `./test.sh` で Phase 1〜3 の全テストがグリーンであること。
- [x] `ulisp/README.md` の進捗状況表で Phase 3 が完了として反映されていること。
