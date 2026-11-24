---
ID: 955
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 算術 fast path の短縮：オーバーフロー分岐の `jo` 融合と定数オペランドのタグ検査畳み込み (ID: 955)

## 1. 概要 / Summary

`+` / `-` / `*` は `140_backend_x86_64.scm` L1508-1550 で `add; seto dl; movzx rdx, dl` を出し、`129_lir_primitives.scm` L53-73, L428-479 側で `cmp rdx, 0; jne slow` を続けるため 4 命令になる（`ulisp-boot` で `seto` 3,763、`ulisp-cc` で 5,042）。`jo slow` 1 命令にできる。

また片方のオペランドが既知の fixnum 定数でも `mov rdx, rax; or rdx, [..]; and rdx, 3; cmp; jne` のタグ検査が実行時に残っている。定数側はコンパイル時に検査を省ける。

- 計測基準 (2026-11-25, Linux x86-64, `main` 3f838e355): `ulisp-boot` 13MB / `.text` 8.86MB / `.symtab`+`.strtab` 2.29MB / `mfence` 3,915 / `seto` 3,763 / `nop` 116,321 命令 615KB / `[rsp]` mov 書込 253,768・読出 262,656 / 7 バイト `mov r64, imm32` 158,179。`ulisp-cc` 16MB / `.text` 10.95MB / `.symtab`+`.strtab` 3.16MB / `mfence` 3,915 / `seto` 5,042。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）
  - [Issue #935](closed/935-optimize-variable-bit-shift-cl-codegen-and-redundant-sign-zero-extension-folding.md)（C-TU モードでのシフト・拡張畳み込み）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [128_lir_branch_fusion.scm](../../ulisp/lir/128_lir_branch_fusion.scm) (overflow + cmp + jne の融合)
- [ ] [129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm) (L53-73, L428-479)
- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (L1508-1550)
- [ ] [150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm) (同等命令（`b.vs`）)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `perf/955-fuse-overflow-branch-and-fold-tag-checks`

1. LIR に `%add-overflow-branch` 等の融合命令（または `128` での融合規則）を追加する。
2. x86-64 は `jo`、AArch64 は `adds` + `b.vs` に展開する。LIR インタプリタ・C バックエンドにも対応を追加する。
3. 定数 fixnum オペランドのタグ検査を `129` の生成時に省略する。
4. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp-boot` の `seto` 3,763 → 0（融合不可の箇所を除く）
- [ ] `test_lir_overflow_and_unsigned` / `test_numeric_tower` / bignum 昇格テストが PASS
- [ ] `make format` / `make static_analysis` / `make test`（または `make check`）が全 PASS
- [ ] `make -C ulisp bootstrap` で stage2 → stage3 の自己コンパイル不動点（SHA-256 一致）を維持
- [ ] 施策前後の計測（自己コンパイル時間中央値 5 回・ELF/`.text` サイズ・`objdump` 命令数）を Issue に記録
- [ ] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）
