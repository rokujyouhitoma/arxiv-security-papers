---
ID: 943
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Case A の C99 拡張：LIR 参照 VM の検査付き C インタプリタ実行可否検証と差分診断ハーネス構築 (ID: 943)

## 1. 概要 / Summary

ULisp が C99 および Lua 5.4.7 をコンパイル可能になったことで、$\mathrm{Interp}_C = \mathrm{Interp}_{\text{LIR}} \circ \mathrm{Comp}_C$ の関係から、LIR 参照 VM（`ulisp/vm/lir_interpreter.scm`）を追加の枠組みなしで「NULL ページアクセスや範囲外メモリアクセスをトラップする検査付き C インタプリタ（Miri に近い位置づけ）」として活用できる見込みがある。これにより、Lua 等の誤コンパイル時に原因がフロントエンド（C → LIR）にあるかバックエンド（LIR → x86-64）にあるかを切り分けられる。

現行の `lir_interpreter.scm` は `%call-indirect`、`__ulisp_setjmp`/`__ulisp_longjmp` フック、XMM レジスタ 16 本、`%inline-asm` インタプリタを既に部分実装しているが、C99 および Lua から生成される実際の LIR（`%call-indirect`、SSE2/XMM 命令、`setjmp` 等の inline asm、外部呼出）をどこまで完走できるかは未検証である。本 Issue では LIR VM の C99 命令網羅率を調査・拡張し、[#930](930-implement-c99-bounds-checking-sanitizer-mode.md) と整合した差分診断ハーネスを構築する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [DSN-33-13](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
  - [DSN-33-32](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [Issue #834](closed/834-implement-pure-scheme-lir-reference-vm-interpreter.md)
  - [Issue #930](930-implement-c99-bounds-checking-sanitizer-mode.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [lir_interpreter.scm](../../ulisp/vm/lir_interpreter.scm) (`%call-indirect`, XMM/SSE2 命令, `%inline-asm`, 外部呼出, メモリ境界トラップ)
- [ ] [c_driver.scm](../../ulisp/driver/c_driver.scm) (`--target=vm` 実行経路)
- [ ] [lower_to_lir.scm](../../ulisp/frontend_c/lower_to_lir.scm) (生成 LIR 命令セット照合)
- [ ] [Makefile](../../ulisp/Makefile) (C99 LIR VM 差分検証ターゲット)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/943-verify-and-extend-lir-vm-as-checked-c99-interpreter`

1. C99 テストスイートおよび Lua 5.4.7 の C TU から生成される LIR 命令（`%call-indirect`、XMM レジスタ命令、`setjmp` 用 `%inline-asm`、`va_list`、外部呼出等）を抽出し、`lir_interpreter.scm` での対応状況を調査・一覧化する。
2. 未対応命令・外部関数スタブ・NULL/範囲外トラップのギャップを解消し、C99 フロントエンド（LIR VM 実行）と x86-64 バックエンド（ネイティブ実行）の差分診断ハーネスを整備する（詳細手順は `polish-issue` にて精緻化する）。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] C99 / Lua 生成 LIR に対する `lir_interpreter.scm` の命令網羅マトリクスとギャップ対応が完了していること。
- [ ] 主要 C99 テストで LIR VM 実行とネイティブ x86-64 実行の差分検証が PASS し、NULL/範囲外アクセスが VM で決定論的にトラップされること（詳細ゲートは `polish-issue` 時に確定）。
