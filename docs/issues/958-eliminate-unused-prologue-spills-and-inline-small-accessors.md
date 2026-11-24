---
ID: 958
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/ENH] 関数入口の未使用 `r10` / `argc` スピル削除と小さなアクセサのインライン化（Scheme モード） (ID: 958)

## 1. 概要 / Summary

`140_backend_x86_64.scm` L2769 付近の関数入口で `mov [rsp-8], r10` と `argc` の保存を毎回行っているが、使われない関数が多い。#936 は C-TU モードのみ対処済み。

また `scope-node-children` のような小さなアクセサが「`_cell` 呼出 → `car`」で 1 回約 20 命令かかっている。`pass_inline_hotpath` / cp0 の閾値と対象を見直し、レコード系アクセサをインライン化する。

- 計測基準 (2026-11-25, Linux x86-64, `main` 3f838e355): `ulisp-boot` 13MB / `.text` 8.86MB / `.symtab`+`.strtab` 2.29MB / `mfence` 3,915 / `seto` 3,763 / `nop` 116,321 命令 615KB / `[rsp]` mov 書込 253,768・読出 262,656 / 7 バイト `mov r64, imm32` 158,179。`ulisp-cc` 16MB / `.text` 10.95MB / `.symtab`+`.strtab` 3.16MB / `mfence` 3,915 / `seto` 5,042。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）
  - [Issue #936](closed/936-hoist-c-tu-function-stack-frame-allocation-and-omit-managed-gc-call-setup.md)（C-TU モードでのプロローグ最適化）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (L2769 `emit-x86-function`)
- [ ] [pass_inline_hotpath.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inline_hotpath.scm) (インライン化パス)
- [ ] [050_cp0.scm](../../ulisp/frontend/050_cp0.scm) (インライン閾値)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `perf/958-prologue-spills-and-accessor-inlining`

1. 関数本体で `r10`（クロージャ環境）/ `argc` 参照の有無を解析し、未使用なら保存を省く。
2. 1〜2 プリミティブで構成される手続きをインライン候補とする規則を追加する。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 自己コンパイル時間の改善を計測で確認
- [ ] 可変長引数・クロージャ・`apply` 系テストが PASS
- [ ] `make format` / `make static_analysis` / `make test`（または `make check`）が全 PASS
- [ ] `make -C ulisp bootstrap` で stage2 → stage3 の自己コンパイル不動点（SHA-256 一致）を維持
- [ ] 施策前後の計測（自己コンパイル時間中央値 5 回・ELF/`.text` サイズ・`objdump` 命令数）を Issue に記録
- [ ] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）
