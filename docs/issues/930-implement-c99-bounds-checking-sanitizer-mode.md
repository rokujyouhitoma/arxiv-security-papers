---
ID: 930
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] C99 配列境界検査・NULL ポインタ参照トラップ自動注入モード (`--sanitize-bounds`) の実装 (ID: 930)

## 1. 概要 / Summary
型付き C AST（`L_c_typed` / [DSN-33-11](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)）と Core Machine LIR（[DSN-33-13](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)）を活用し、コンパイル時フラグ `--sanitize-bounds` 指定時に、固定長配列の境界外アクセス（OOB）および NULL ポインタ間接参照（CWE-119 / CWE-476）を検知して `<source-span>`（#824）位置情報付きで安全にトラップ停止させるメモリ安全境界検査モードを実装する（Phase S9 / Task T18）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §6.1, §6.4](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
- 前提基盤（実装済・先行）:
  - `#824`: `<source-span>`（[ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm)）
  - `#833`: 統合診断レポート（[ulisp/compiler/diagnostic.scm](../../ulisp/compiler/diagnostic.scm)）
  - `#919`: ポインタ演算 ＆ 配列退化（[[#919]](919-implement-c99-pointer-scaling-array-decay-and-escape-analysis.md)）
  - `#925`: Lua 一括ビルド（[[#925]](closed/925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md)）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/driver/c_driver.scm` (`--sanitize-bounds` CLI オプションおよび LIR 計測フラグ伝播)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` (境界検査・NULL 参照チェック ＆ `__ulisp_san_trap` コール自動注入)
- [ ] `ulisp/tests/test_c99_bounds_sanitizer.sh` (新規: 正常系通過 ＆ OOB/NULL トラップ・診断コード・ゼロオーバーヘッド検証)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_c99_bounds_sanitizer` ターゲット追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/930-implement-c99-bounds-checking-sanitizer`

### 4.1 境界検査 ＆ NULL 逆参照トラップ注入仕様
1. **固定長配列境界チェック (`CWE-119`)**:
   - `lower_to_lir.scm` においてコンパイル時定数サイズ `N` が判明している配列 `arr[N]` への添字アクセス `arr[idx]` に対し、`(%icmp-uge (%sext idx 'i64) N)`（符号なし比較で負添字も同時に一括検知！）ガード分岐を注入。違反時はファイル名・行・列・要素上限（`.rodata` 定数）を引数に `__ulisp_san_trap("C99-SAN-001", file, line, col)` を呼び出す。
2. **NULL ポインタ逆参照チェック (`CWE-476`)**:
   - ポインタ逆参照 `*p`, `p->field`, `p[i]` の前に `(%icmp-eq ptr 0)` チェックを注入し、NULL の場合は `__ulisp_san_trap("C99-SAN-002", file, line, col)` へ分岐。
3. **トラップランタイム ＆ ゼロオーバーヘッド保証**:
   - `__ulisp_san_trap` は `stderr` (fd 2) へ `[ulisp-sanitizer] error[<code>]: ... at <file>:<line>:<col>\n` を書き込み、`exit(134)`（`SIGABRT` 相当）で即時安全停止（端末制御文字サニタイズ済み）。
   - `--sanitize-bounds` 未指定時は上記検査分岐を **1 命令も生成しない**。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `--sanitize-bounds` 有効時、配列境界外アクセス（正方向超過および負インデックス）および NULL ポインタ参照が確実にトラップ・位置情報付きエラー報告されること。
- [ ] `--sanitize-bounds` 無効時は追加のチェック命令が一切出力されないこと（未指定時とのコード差分 0）。
- [ ] `--sanitize-bounds` 有効版の Lua バイナリで正常系公式テストスイート（#926）が誤検知なく完走し、`make -C ulisp test_c99_bounds_sanitizer` が PASS すること。
