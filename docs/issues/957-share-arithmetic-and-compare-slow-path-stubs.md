---
ID: 957
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/ENH] 算術・比較 slow path のインライン展開廃止と共有スタブ化 (ID: 957)

## 1. 概要 / Summary

`129_lir_primitives.scm` の `lir-emit-bin-slow-call!` は、汎用算術・比較の slow path（bignum/flonum へのフォールバック呼び出し）を呼び出し箇所ごとにインライン展開している（`cmp_br` 3,142、`add` 1,797、`sub` 1,481 箇所など）。オペランドを固定レジスタに置いて共有スタブを呼ぶ形にすれば、数百 KB 削減が見込める。

- 計測基準 (2026-11-25, Linux x86-64, `main` 3f838e355): `ulisp-boot` 13MB / `.text` 8.86MB / `.symtab`+`.strtab` 2.29MB / `mfence` 3,915 / `seto` 3,763 / `nop` 116,321 命令 615KB / `[rsp]` mov 書込 253,768・読出 262,656 / 7 バイト `mov r64, imm32` 158,179。`ulisp-cc` 16MB / `.text` 10.95MB / `.symtab`+`.strtab` 3.16MB / `mfence` 3,915 / `seto` 5,042。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）
  - [Issue #955](955-fuse-overflow-branch-to-jo-and-fold-constant-tag-checks.md)（前提）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm) (`lir-emit-bin-slow-call!`)
- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (スタブ出力)
- [ ] [150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm) (スタブ出力)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `perf/957-shared-slow-path-stubs`

1. 演算種別ごとの共有スタブ（`ulisp_slow_add` 等）をモジュール毎またはランタイムに 1 つ出力する。
2. 呼び出し側は `call stub` + 結果受け取りのみに縮小する（呼び出し規約・GC ルート保存を設計）。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `.text` が 200KB 以上削減
- [ ] GC ストレステスト・数値塔テストが PASS
- [ ] `make format` / `make static_analysis` / `make test`（または `make check`）が全 PASS
- [ ] `make -C ulisp bootstrap` で stage2 → stage3 の自己コンパイル不動点（SHA-256 一致）を維持
- [ ] 施策前後の計測（自己コンパイル時間中央値 5 回・ELF/`.text` サイズ・`objdump` 命令数）を Issue に記録
- [ ] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）
