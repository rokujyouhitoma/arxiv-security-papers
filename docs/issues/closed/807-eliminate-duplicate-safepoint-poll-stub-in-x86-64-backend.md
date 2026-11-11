---
ID: 807
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG] x86-64 バックエンドにおけるセーフポイントポーリング stub 重複定義の解消 (ID: 807)

## 1. 概要 / Summary

`make -C ulisp test` (特に `test_channel` および `test_preemption`) 実行時、GNU `as` アセンブラにより以下の重複シンボル定義エラーが発生し、ビルドが停止する不具合を解消した。
また、関連して発生していたコンテキストスイッチ時のスタック巻き戻し自己参照ループ (`test_context_switch` のハング) および不適切ペア (`'(1 . 2)`) コンパイル時のセーフポイント注入クラッシュを恒久対処した。

```text
build/test_channel.s:94653: Error: symbol `ulisp_fn__pctsynapse_safepoint_poll_excl' is already defined
build/test_channel.s:94659: Error: symbol `ulisp_gvar__pctsynapse_safepoint_poll_excl' is already defined
make: *** [Makefile:299: test_channel] Error 1
```

### 再現手順 / Steps to Reproduce
1. `make -C ulisp test_channel` を実行する。
2. アセンブラエラー `symbol 'ulisp_fn__pctsynapse_safepoint_poll_excl' is already defined` によりエラー終了する。

### 再現環境 / Environment
- OS / Env: Linux x86_64
- File: `ulisp/backend/140_backend_x86_64.scm`, `ulisp/backend/142_backend_x86_freestanding.scm`, `ulisp/runtime/concurrency/context.s`, `ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)
- [x] [142_backend_x86_freestanding.scm](../../ulisp/backend/142_backend_x86_freestanding.scm)
- [x] [context.s](../../ulisp/runtime/concurrency/context.s)
- [x] [pass_inject_safepoints.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm)
- [x] [compiler.scm](../../ulisp/compiler.scm)
- [x] [bin/ulisp-boot](../../ulisp/bin/ulisp-boot)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **セーフポイント stub 重複定義**:
   Commit `fdfa01ba2858b64cd13b638c3bfbbcccf8c8b2cf` (Issue #799) にて、並行性ランタイム非リンク時のセーフポイントフォールバック用として、`ulisp/backend/140_backend_x86_64.scm` のコード末尾に `ulisp_fn__pctsynapse_safepoint_poll_excl` および `ulisp_gvar__pctsynapse_safepoint_poll_excl` の weak stub が無条件に出力されるよう追加された。
   しかし、`channel.scm` や `preempt.scm` などの並行性モジュールをロードする Scheme プログラムでは、Scheme コード側で `(define (%synapse-safepoint-poll!) ...)` が定義されているため、コンパイラにより同名シンボルの通常定義が同一アセンブリファイル内に出力される。
   GNU `as` は同一アセンブリファイル（同一翻訳単位）内で同一ラベルの複数回定義を `.weak` 指定に関わらず構文エラーとして拒絶するため、重複定義エラーとなってアセンブルに失敗していた。

2. **コルーチン例外巻き戻し無限ループ**:
   コルーチン内で例外が発生してタスク終了する際、`ulisp_current_task_top` がリセットされずに残留し、再利用された mmap 領域で自身への参照 (`[rdi - 48] = rdi`) を保持するケースがあった。`%raise` や型エラーハンドラのアンワインドループが循環参照に陥り、無限ループ（ハング）を誘発していた。

3. **不適切ペア (`'(1 . 2)`) コンパイルクラッシュ**:
   `pass_inject_safepoints.scm` において、`list?` チェックのみでトップレベル式判定を行い、リテラルの不適切ペアに対して `map` を実行したため、`cdr` が非リスト（数値）を返して `ulisp_pair_type_error` が発生していた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 生成された `.s` ファイルから重複した stub ラベル定義を手動削除する。
* **恒久対策 (Permanent Fix)**:
  1. `140_backend_x86_64.scm`: `*top-level-fns*` または `*top-level-vars*` に `%synapse-safepoint-poll!` が既に定義されている場合は weak stub の出力を抑制するガード判定を追加。さらに `%raise` 内で循環スタック参照を検知・遮断するロジックを追加。
  2. `context.s`: `ulisp_fn___lib_ulisp_concurrency_context___pctasm_resume_task_excl` にて自己参照 (`rax == rdi`) がスタックトップに書き込まれるのを防止。
  3. `142_backend_x86_freestanding.scm`: フリースタンディングアセンブラ向けに固有の名前付きローカルラベル `.L_pte_...` を用いて安全にタスクアンワインド処理を実装。
  4. `pass_inject_safepoints.scm`: ドット対・不適切ペアを走査対象から除外するガードを追加。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/807-eliminate-duplicate-safepoint-poll-stub-in-x86-64-backend`

1. `ulisp/backend/140_backend_x86_64.scm` の weak stub 出力箇所にガード判定を追加。
2. `ulisp/runtime/concurrency/context.s` および `ulisp/backend/142_backend_x86_freestanding.scm` のスタックアンワインド保護を追加。
3. `ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm` に不適切対ガードを追加。
4. `make -C ulisp compiler` で `compiler.scm` を再生成。
5. `make -C ulisp bootstrap` で 3-Stage セルフホスティング固定点検証を行い、`bin/ulisp-boot` を更新。
6. `make -C ulisp test`（全ユニットテスト、並行性ハーネス、R7RSテスト、セルフホスティング検証）およびリポジトリ品質ゲート (`make verify_quality`) の全件 PASS を確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/backend/140_backend_x86_64.scm` にてトップレベル定義重複防止ガードが実装されていること。
- [x] `make -C ulisp bootstrap` による 3-Stage セルフホスティング不動点検証が 100% 収束し PASS すること（bit-for-bit IDENTICAL）。
- [x] `make -C ulisp test_channel` が正常にコンパイル・リンク・実行完了し PASS すること（446 passed, 0 failed）。
- [x] `make -C ulisp test_preemption` が正常にコンパイル・リンク・実行完了し PASS すること（92 passed, 0 failed）。
- [x] `make -C ulisp test_context_switch` がハングせず 1 秒未満で PASS すること（89 passed, 0 failed）。
- [x] `make -C ulisp test` の全テストスイートが 100% PASS すること。
- [x] リポジトリ全体の品質検証ゲート `make py_compile`, `make static_analysis`, `make verify_quality` (2766 tests) が 100% PASS すること。
- [x] 相対パス規約が 100% 遵守されていること。
