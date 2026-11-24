---
ID: 961
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/ENH] Scheme 経路の LIR への linear scan レジスタ割り付け導入（スタック退避中心コード生成の解消） (ID: 961)

## 1. 概要 / Summary

`ulisp-boot` の `.text` の約 58% が `mov` であり、`[rsp-N]` への書き込み 253,768・読み出し 262,656 が大半を占める。現在は全値をスタックスロットに置いて出し入れしており、Braun SSA（`132_lir_braun_ssa.scm`）はC99 経路でのみ使われている。LIR 上に linear scan レジスタ割り付けを導入すれば、速度・サイズの双方で最大の効果が見込める。

改修規模が最大のため、#951〜#958 の効果計測後に着手判断する。GC ルート（スタックマップ）とレジスタ割り付けの整合が主な設計課題となる。

- 計測基準 (2026-11-25, Linux x86-64, `main` 3f838e355): `ulisp-boot` 13MB / `.text` 8.86MB / `.symtab`+`.strtab` 2.29MB / `mfence` 3,915 / `seto` 3,763 / `nop` 116,321 命令 615KB / `[rsp]` mov 書込 253,768・読出 262,656 / 7 バイト `mov r64, imm32` 158,179。`ulisp-cc` 16MB / `.text` 10.95MB / `.symtab`+`.strtab` 3.16MB / `mfence` 3,915 / `seto` 5,042。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）
  - [Issue #934](closed/934-implement-temporary-stack-spill-dead-store-elimination-and-expr-register-forwarding.md)（C-TU モードでの一時スピル DSE / レジスタ転送）
  - #951〜#958（前段の効果計測）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm) (SSA 構築の流用検討)
- [ ] [lir/ 新規パス](../../ulisp/lir) (linear scan)
- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)
- [ ] [150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm)
- [ ] [gc.scm](../../ulisp/runtime/gc.scm) (GC スタックマップ)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `perf/961-linear-scan-register-allocation`

1. Scheme LIR を SSA 化（Braun SSA の適用範囲拡大）し、生存区間を計算する。
2. callee-saved レジスタを用いた linear scan と、GC セーフポイントでのスピル / スタックマップ生成を実装する。
3. 段階導入（葉関数のみ → 全関数）とフラグでの無効化手段を用意する。
4. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `[rsp]` mov 命令数が 50% 以上削減
- [ ] 自己コンパイル時間が 20% 以上改善
- [ ] GC ストレステスト・`test_fuzz_lir`・差分テストが PASS
- [ ] `make format` / `make static_analysis` / `make test`（または `make check`）が全 PASS
- [ ] `make -C ulisp bootstrap` で stage2 → stage3 の自己コンパイル不動点（SHA-256 一致）を維持
- [ ] 施策前後の計測（自己コンパイル時間中央値 5 回・ELF/`.text` サイズ・`objdump` 命令数）を Issue に記録
- [ ] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）
