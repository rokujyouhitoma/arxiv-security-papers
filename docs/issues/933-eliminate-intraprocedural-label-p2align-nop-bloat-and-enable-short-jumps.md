---
ID: 933
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 関数内ローカルラベルの過剰 .p2align 4 (13万 NOP) 廃止と Pass 144a 短距離ジャンプ最適化によるバイナリサイズ削減 (ID: 933)

## 1. 概要 / Summary

[Issue #925](closed/925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) でビルドした無改変 Lua 5.4.7 バイナリ (`ulisp/build/lua_ulisp`: 1,048,592 B) と GCC リファレンス (`ulisp/build/lua_gcc`: 313,904 B) のセクション・命令内訳を比較した結果、データ領域（`.rodata` / `.data` / `.bss`）は GCC とほぼ同一である一方、`.text` セクション（934,881 B / 322,305 命令）の **40.4% に相当する 130,175 命令（約 130 KB）が `.p2align 4` による `nop` パディング**で占められていることが判明した。

現行の [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) は、関数エントリだけでなく関数内のすべてのローカル分岐ラベル（`if`/`else`、短絡評価 `&&`/`||`、三項演算子 `?:`、`switch` case 等）の直前に無条件で `.p2align 4`（16 バイト境界アライン）を発行している。これを関数先頭のみ 16B アラインとし、関数内ローカルラベルの不要な `.p2align 4` を廃止（および [144a_x86_assembler.scm](../../ulisp/backend/144a_x86_assembler.scm) の短距離ジャンプ緩和と連携）することで、`lua_ulisp` のバイナリサイズを即座に約 130〜160 KB 削減し、命令キャッシュ (I-cache) 効率を向上させる。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-33-13](../../docs/designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
  - [DSN-33-32](../../docs/designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
- 関連 Issue:
  - [#925](closed/925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md) (Lua 5.4.7 全 33 TU ビルドパイプライン ＆ バイナリサイズ実測契機)
  - [#934](934-implement-temporary-stack-spill-dead-store-elimination-and-expr-register-forwarding.md) (一時スタックスピル DSE)
  - [#935](935-optimize-variable-bit-shift-cl-codegen-and-redundant-sign-zero-extension-folding.md) (変数シフト `%cl` 化 ＆ 冗長拡張畳み込み)
  - [#936](936-hoist-c-tu-function-stack-frame-allocation-and-omit-managed-gc-call-setup.md) (プロローグ一括フレーム確保 ＆ `xor r10` 廃止)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)（`c-tu` モードおよび関数内ローカルラベル `(%label)` / `(%block)` における `.p2align 4` 発行条件の適正化）
- [ ] [ulisp/backend/143_backend_x86_peephole.scm](../../ulisp/backend/143_backend_x86_peephole.scm)（ラベル直前アラインメント変更に伴う Peephole ルール整合確認）
- [ ] [ulisp/backend/144a_x86_assembler.scm](../../ulisp/backend/144a_x86_assembler.scm)（ローカルラベル間の短距離分岐エンコーディング確認）
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm)（再生成）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/933-eliminate-intraprocedural-label-p2align-nop-bloat`

1. `140_backend_x86_64.scm` において、Managed GC のタグ付き継続リターンアドレス境界（16B アライン必須のサスペンド/リジュームラベル等）と、`c-tu` / 通常の関数内ローカル分岐ラベル（`.L_c99_*` 等）を明確に区別し、後者では `.p2align 4` を出力しないようにする。
2. 既存の Managed GC / 限定継続 / AOT テストおよび C99 全テスト・`compile_lua` を実行し、リグレッション 0 件と `lua_ulisp` の `.text` / `nop` 削減量を実測検証する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `c-tu` 関数内ローカルラベルの不要な `.p2align 4` が除去され、`ulisp/build/lua_ulisp` 内の `nop` 命令数が 90% 以上削減（約 130 KB 縮小）されること。
- [ ] `make -C ulisp compile_lua` および全 C99 / Managed GC / Pass 回帰テストが 100% PASS すること。
