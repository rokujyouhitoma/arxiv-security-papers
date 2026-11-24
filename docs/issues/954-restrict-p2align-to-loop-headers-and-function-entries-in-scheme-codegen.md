---
ID: 954
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Scheme コード生成における内部ラベル `.p2align` の削減（ループ先頭・関数入口限定） (ID: 954)

## 1. 概要 / Summary

`ulisp-boot` の `.text` に nop が 116,321 命令・615,243B（6.6%）含まれる。発生源は関数毎の `.p2align 4`（`140_backend_x86_64.scm` L2769）に加え、`.add_slow` / `.add_done` 等の内部ラベルに付与される `(%p2align 4)`（L886, L897, L2412, L2415）。#933 は C-TU モードのみ対処済みで、Scheme モードは未対応。

slow path ラベルや合流ラベルの整列は不要であり、ループのバックエッジ先頭のみ整列すれば十分である。

- 計測基準 (2026-11-25, Linux x86-64, `main` 3f838e355): `ulisp-boot` 13MB / `.text` 8.86MB / `.symtab`+`.strtab` 2.29MB / `mfence` 3,915 / `seto` 3,763 / `nop` 116,321 命令 615KB / `[rsp]` mov 書込 253,768・読出 262,656 / 7 バイト `mov r64, imm32` 158,179。`ulisp-cc` 16MB / `.text` 10.95MB / `.symtab`+`.strtab` 3.16MB / `mfence` 3,915 / `seto` 5,042。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）
  - [Issue #933](closed/933-eliminate-intraprocedural-label-p2align-nop-bloat-and-enable-short-jumps.md)（C-TU モードでの `.p2align` 削減）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (L886/897/2412/2415/2769)
- [ ] [143_backend_x86_peephole.scm](../../ulisp/backend/143_backend_x86_peephole.scm) (`rule-x86-jump-p2align-next-label`)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `perf/954-restrict-p2align-scheme-codegen`

1. slow path / done ラベルへの `%p2align` 付与を除去する。
2. ループヘッダ判定（バックエッジ先）にのみ整列を残す。関数入口の整列幅（16 → 8 等）は計測で決定する。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] nop バイト数 615KB → 200KB 以下
- [ ] 自己コンパイル時間が悪化しない（±2% 以内または改善）
- [ ] `make format` / `make static_analysis` / `make test`（または `make check`）が全 PASS
- [ ] `make -C ulisp bootstrap` で stage2 → stage3 の自己コンパイル不動点（SHA-256 一致）を維持
- [ ] 施策前後の計測（自己コンパイル時間中央値 5 回・ELF/`.text` サイズ・`objdump` 命令数）を Issue に記録
- [ ] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）
