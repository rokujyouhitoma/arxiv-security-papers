---
ID: 953
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] x86-64 即値 `mov` の短縮符号化（`mov r32, imm32` / `xor r32, r32`）を `140` と `144a` の双方に適用 (ID: 953)

## 1. 概要 / Summary

`ulisp-boot` に 7 バイト符号化の `mov r64, imm32`（REX.W C7 /0）が 158,179 箇所ある。`0 <= imm < 2^32` なら 5 バイトの `mov r32, imm32`（上位 32bit ゼロ拡張）、0 なら `xor r32, r32` にできる（約 300KB 削減見込み）。

注意: `ulisp-boot` / `ulisp-cc` は `140_backend_x86_64.scm` が出力する GAS テキストを GNU `as` でアセンブルしているため、`144a_x86_assembler.scm` L1275-1282 の修正だけでは縮まない。`140`（GAS 経路）と `144a`（自前 ELF 経路: Lua/C99/musl）の両方を直す必要がある。`xor` はフラグを破壊するため、直後にフラグを使う位置では適用しない。

- 計測基準 (2026-11-25, Linux x86-64, `main` 3f838e355): `ulisp-boot` 13MB / `.text` 8.86MB / `.symtab`+`.strtab` 2.29MB / `mfence` 3,915 / `seto` 3,763 / `nop` 116,321 命令 615KB / `[rsp]` mov 書込 253,768・読出 262,656 / 7 バイト `mov r64, imm32` 158,179。`ulisp-cc` 16MB / `.text` 10.95MB / `.symtab`+`.strtab` 3.16MB / `mfence` 3,915 / `seto` 5,042。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (即値 mov 出力)
- [ ] [143_backend_x86_peephole.scm](../../ulisp/backend/143_backend_x86_peephole.scm) (`rule-x86-zero-xor` 拡張)
- [ ] [144a_x86_assembler.scm](../../ulisp/backend/144a_x86_assembler.scm) (L1275-1282 符号化)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `perf/953-short-immediate-mov-encoding`

1. `140` で非負 32bit 即値の 64bit レジスタ mov を 32bit レジスタ名で出力する。
2. `144a` の `mov r64, imm` 符号化で同条件時に `B8+r imm32` を選ぶ。
3. `rule-x86-zero-xor` のフラグ生存条件を確認・強化する。
4. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `objdump` で 7 バイト `mov r64, imm32`（非負値）が 90% 以上削減
- [ ] Lua 5.4.7 ビルド（`test_compile_lua.sh`）と C99 テストが PASS
- [ ] `make format` / `make static_analysis` / `make test`（または `make check`）が全 PASS
- [ ] `make -C ulisp bootstrap` で stage2 → stage3 の自己コンパイル不動点（SHA-256 一致）を維持
- [ ] 施策前後の計測（自己コンパイル時間中央値 5 回・ELF/`.text` サイズ・`objdump` 命令数）を Issue に記録
- [ ] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）
