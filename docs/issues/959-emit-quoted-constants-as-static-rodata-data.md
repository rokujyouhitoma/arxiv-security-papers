---
ID: 959
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/ENH] quote 定数の静的データ化（`ulisp_mod_init_*` 実行時構築の廃止と `.rodata` / `.data` 配置） (ID: 959)

## 1. 概要 / Summary

`ulisp_mod_init_compiler_base` / `ulisp_mod_init_frontend_passes` / `ulisp_mod_init_lir_passes` 等のモジュール初期化関数が、quote 定数（リスト・ベクタ・文字列）を実行時に cons で組み立てている（`ulisp_mod_init_lir_passes` だけで約 54KB）。リンク時に確定する静的オブジェクトとして `.rodata`（不変）/ `.data`（GC 書き込みバリア対象）に配置すれば、コードサイズと起動時間の双方を削減できる。

#944（値表現の単一情報源化）のタグ・ヘッダ仕様と整合させる必要がある。

- 計測基準 (2026-11-25, Linux x86-64, `main` 3f838e355): `ulisp-boot` 13MB / `.text` 8.86MB / `.symtab`+`.strtab` 2.29MB / `mfence` 3,915 / `seto` 3,763 / `nop` 116,321 命令 615KB / `[rsp]` mov 書込 253,768・読出 262,656 / 7 バイト `mov r64, imm32` 158,179。`ulisp-cc` 16MB / `.text` 10.95MB / `.symtab`+`.strtab` 3.16MB / `mfence` 3,915 / `seto` 5,042。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）
  - [Issue #944](944-unify-host-and-guest-value-representation-via-define-value-repr.md)（値表現仕様の整合）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (定数データ出力)
- [ ] [value_repr.scm](../../ulisp/compiler/value_repr.scm) (タグ / ヘッダ表現)
- [ ] [gc.scm](../../ulisp/runtime/gc.scm) (静的オブジェクトの GC 扱い)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `perf/959-static-quoted-constants`

1. quote 定数を静的レイアウトで出力し、シンボルは `ulisp_symtab_sec` 参照で再配置する。
2. GC が静的領域を移動・解放しないよう境界判定を追加する。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp_mod_init_*` の合計サイズが 50% 以上削減
- [ ] 起動時間・自己コンパイル時間を計測で確認
- [ ] `make format` / `make static_analysis` / `make test`（または `make check`）が全 PASS
- [ ] `make -C ulisp bootstrap` で stage2 → stage3 の自己コンパイル不動点（SHA-256 一致）を維持
- [ ] 施策前後の計測（自己コンパイル時間中央値 5 回・ELF/`.text` サイズ・`objdump` 命令数）を Issue に記録
- [ ] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）
