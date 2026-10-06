---
ID: 488
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ULisp Phase 2: スタック管理・二項演算 (+, -, *)・局所変数 (let) の実装 (ID: 488)

## 1. 概要 / Summary

[DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) に基づき、ULisp の Phase 2（Step 5〜8: スタックフレーム管理・二項算術演算・算術比較・局所変数 `let` と変数シャドウイング）を実装する。

式評価中の退避領域およびローカル変数を格納するスタック（`[rsp - offset]`）機構を導入し、コンパイル時環境（Compile-time Environment: 連想リスト）による変数解決とシャドウイングを実現する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 2.2 節 レジスタ・スタックフレーム・ABI 規約, 第 3.2 節 局所変数とスタックマッピング, 第 4 章 Phase 2)
  - [DSN-31: ILISP (Intelligence LISP) R7RS コアアーキテクチャ包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) (第 2.5 節 レキシカル環境)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (スタックオフセット `si` 管理、二項演算、算術比較、`let` 評価、環境連想リスト)
- [x] [ulisp/test.sh](../../ulisp/test.sh) (Step 5〜8 の自動テストアサーション群の拡充)
- [x] [ulisp/README.md](../../ulisp/README.md) (ロードマップ進捗状況表の更新)
- [x] [docs/issues/README.md](../../docs/issues/README.md) (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/488-implement-ulisp-phase2-stack-and-local-variables`

1. **コンパイラシグネチャのスタック・環境対応 (`si`, `env`)**:
   - `(compile-expr expr si env)` にシグネチャを拡張。
   - `si`: 現在利用可能なスタックインデックス（バイトオフセット。初期値 `-8`）。
   - `env`: 変数名からスタックオフセットへの連想リスト `((var . -8) (var2 . -16) ...)`。
2. **Step 5: 二項算術演算 (`+`, `-`)**:
   - `(+ e1 e2)`:
     - `e1` を `(compile-expr e1 si env)` で評価（結果は RAX）。
     - RAX をスタックに退避: `mov [rsp + si], rax`。
     - `e2` を `(compile-expr e2 (- si 8) env)` で評価（結果は RAX）。
     - スタックから退避値を加算: `add rax, [rsp + si]`（Fixnum は下位 2bit が `00` なので直接加算可能）。
   - `(- e1 e2)`:
     - `e1` を評価して退避。`e2` を評価して RAX へ。
     - `mov rdx, [rsp + si]`, `sub rdx, rax`, `mov rax, rdx`。
3. **Step 6: 多項・乗算および比較演算 (`*`, `=`, `<`, `<=`, `>`, `>=`)**:
   - `(* e1 e2)`:
     - `e1` を退避、`e2` を評価。
     - タグ補正: `sar rax, 2`, `imul rax, [rsp + si]`（Fixnum の積）。
   - 比較演算 (`=`, `<`, `<=`, `>`, `>=`):
     - `e1` を退避、`e2` を評価。
     - `cmp [rsp + si], rax` を実行し、条件コード（`sete`, `setl`, `setle`, `setg`, `setge`）と `emit-boolean` で `#t`/`#f` を出力。
4. **Step 7: 局所変数 (`let` 式)**:
   - `(let ((x e1) ...) body)`:
     - 各バインディング `(var expr)` を順次評価し、`[rsp + curr_si]` に格納。
     - 新しい束縛 `(cons var curr_si)` を環境 `env` の先頭に追加。
     - 拡張された環境と進めた `si` の下で `body` を評価。
   - シンボル参照:
     - `expr` がシンボル（変数名）の場合、`env` から探索して対応するオフセットを `mov rax, [rsp + offset]` でロード。
5. **Step 8: ネストした `let` 式と変数シャドウイング**:
   - `(let ((x 1)) (let ((x (+ x 2))) (+ x x)))`:
     - 連想リストの `assq` により内側の `x` が外側の `x` を正しくシャドウイングすることを確認。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `(+ 1 2)`, `(- 10 3)`, `(* 6 7)` などの二項算術演算が正しく動作すること。
- [x] 算術比較 (`(= 3 3)`, `(< 2 5)`, `(>= 10 20)` 等) が `#t` / `#f` を正しく返すこと。
- [x] 単一 `let` およびネストした `let` による変数バインディングと計算が正しく機能すること。
- [x] 同名変数のシャドウイング（内側の `let` で外側の変数を再定義・参照）が破綻なく動作すること。
- [x] `./test.sh` ですべての新規テストおよび既存 Phase 1 テストが全件 PASS すること。
- [x] `ulisp/README.md` の進捗状況表で Phase 2 が完了として反映されていること。
