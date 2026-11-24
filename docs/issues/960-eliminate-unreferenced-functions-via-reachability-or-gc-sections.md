---
ID: 960
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/ENH] 未参照関数の削除（到達可能性解析または関数毎セクション + `--gc-sections`） (ID: 960)

## 1. 概要 / Summary

`ulisp-boot` には `ulisp_fn_*` が 3,702 個あり（すべて weak シンボル `W`）、約 675 個がコードから参照されていない（データ表・`ulisp_gvar_*` 経由の参照有無は要確認）。現状は単一の `.text` に配置されているため `ld --gc-sections` は効かない。関数毎セクション（`.text.ulisp_fn_*`）出力か、コンパイラ側の到達可能性解析が必要。

- 計測基準 (2026-11-25, Linux x86-64, `main` 3f838e355): `ulisp-boot` 13MB / `.text` 8.86MB / `.symtab`+`.strtab` 2.29MB / `mfence` 3,915 / `seto` 3,763 / `nop` 116,321 命令 615KB / `[rsp]` mov 書込 253,768・読出 262,656 / 7 バイト `mov r64, imm32` 158,179。`ulisp-cc` 16MB / `.text` 10.95MB / `.symtab`+`.strtab` 3.16MB / `mfence` 3,915 / `seto` 5,042。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (セクション指定)
- [ ] [Makefile](../../ulisp/Makefile) (`LDFLAGS`（L14）)
- [ ] [144 自前リンカ](../../ulisp/backend) (gc-sections 相当)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `perf/960-dead-function-elimination`

1. 未参照関数を `nm` / 再配置情報で正確に列挙し、`ulisp_gvar_*` / `eval` 経由の動的参照を除外条件として整理する。
2. 関数毎セクション出力と `--gc-sections`、または whole-program 到達可能性解析のどちらかを選定・実装する。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 未参照関数の除去による `.text` 削減量を記録
- [ ] `eval` / REPL / 動的参照テストが PASS
- [ ] `make format` / `make static_analysis` / `make test`（または `make check`）が全 PASS
- [ ] `make -C ulisp bootstrap` で stage2 → stage3 の自己コンパイル不動点（SHA-256 一致）を維持
- [ ] 施策前後の計測（自己コンパイル時間中央値 5 回・ELF/`.text` サイズ・`objdump` 命令数）を Issue に記録
- [ ] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）
