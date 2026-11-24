---
ID: 952
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 配布用 `ulisp-boot` / `ulisp-cc` の strip と `.debug` 分離ファイル化 (ID: 952)

## 1. 概要 / Summary

`ulisp-boot` は `.symtab` 1,621,800B + `.strtab` 775,873B（計 2.29MB, ローカルシンボル 59,581 個）、`ulisp-cc` は計 3.16MB をシンボル表が占める。実行時に `symbol->string` が参照する `ulisp_symtab_sec`（アロケート対象セクション）は strip の影響を受けない。

ただし品質ゲートには `nm bin/ulisp-boot` を用いる検査があるため、未 strip 版または `objcopy --only-keep-debug` による `.debug` ファイルを保持したうえで、配布用バイナリのみ strip する。

- 計測基準 (2026-11-25, Linux x86-64, `main` 3f838e355): `ulisp-boot` 13MB / `.text` 8.86MB / `.symtab`+`.strtab` 2.29MB / `mfence` 3,915 / `seto` 3,763 / `nop` 116,321 命令 615KB / `[rsp]` mov 書込 253,768・読出 262,656 / 7 バイト `mov r64, imm32` 158,179。`ulisp-cc` 16MB / `.text` 10.95MB / `.symtab`+`.strtab` 3.16MB / `mfence` 3,915 / `seto` 5,042。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）
  - [Issue #932](closed/932-build-native-aot-ulisp-cc-compiler-driver-binary.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [Makefile](../../ulisp/Makefile) (`bin/ulisp-boot` / `bin/ulisp-cc` リンクレシピ・`nm` 検査)
- [ ] [bin/](../../ulisp/bin) (生成物)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `perf/952-strip-release-binaries`

1. リンク後に `objcopy --only-keep-debug` で `*.debug` を生成し、`strip --strip-all` と `--add-gnu-debuglink` を適用する。
2. `nm` を用いる既存ゲートを未 strip 中間成果物または `.debug` 参照に切り替える。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp-boot` −2.2MB 以上、`ulisp-cc` −3.0MB 以上のファイルサイズ削減
- [ ] strip 後のバイナリで `symbol->string`・エラーメッセージ・自己コンパイルが正常動作
- [ ] `make format` / `make static_analysis` / `make test`（または `make check`）が全 PASS
- [ ] `make -C ulisp bootstrap` で stage2 → stage3 の自己コンパイル不動点（SHA-256 一致）を維持
- [ ] 施策前後の計測（自己コンパイル時間中央値 5 回・ELF/`.text` サイズ・`objdump` 命令数）を Issue に記録
- [ ] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）
