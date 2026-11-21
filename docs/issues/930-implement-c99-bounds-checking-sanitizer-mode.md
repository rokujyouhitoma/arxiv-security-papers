---
ID: 930
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] C99 配列境界検査・NULL ポインタ参照トラップ自動注入モード (`--sanitize-bounds`) の実装 (ID: 930)

## 1. 概要 / Summary
型付き C AST（[DSN-33-11](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)）と Core Machine LIR（[DSN-33-13](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)）を活用し、コンパイル時フラグ `--sanitize-bounds` 指定時に、固定長配列の境界外アクセスおよび NULL ポインタ間接参照を検知して診断情報（Source Span #824）付きで安全にトラップ停止させるメモリ安全境界検査モードを実装する（Step S9 / T18）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §6.1, §6.4](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
- 前提基盤 Issue: #824 (Source Span), #833 (Diagnostic), #919, #925

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/driver/c_driver.scm` (`--sanitize-bounds` CLI オプション追加)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` (境界検査ガードおよび NULL チェック LIR トラップ自動注入)
- [ ] `ulisp/tests/test_c99_bounds_sanitizer.sh` (新規: 正常アクセス通過 & 境界外アクセス/NULL 参照の安全トラップ検証)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/930-implement-c99-bounds-checking-sanitizer`

1. `c_driver.scm` に `--sanitize-bounds` フラグを追加し、`lower_to_lir.scm` へ検査モードを有効化して渡す。
2. 既知サイズ配列 `arr[N]` への添字アクセス時に `(%uge index N)` チェックを、またポインタ逆参照 `*p` / `p->m` 時に `(%eq p 0)` チェックを LIR レベルで自動注入し、違反時にファイル名・行番号（Span）を出力して即時終了（`abort` / `exit` syscall）させる。
3. `--sanitize-bounds` を有効にしてビルドした Lua テストスイートが正常ケースで誤検知せず完走し、意図的なバッファオーバーフローテストで確実にトラップされることを確認する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `--sanitize-bounds` 有効時、配列境界外アクセスおよび NULL ポインタ参照が確実にトラップ・エラー報告されること。
- [ ] `--sanitize-bounds` 無効時は追加のオーバーヘッド（チェック命令）が一切出力されないこと。
- [ ] `--sanitize-bounds` 有効版の Lua で正常系テストスイートが誤検知なく完走すること。
