---
ID: 945
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Lua 5.4.7 ビルド 60 秒のフェーズ別内訳プロファイリングとアセンブラ往復コスト定量化 (ID: 945)

## 1. 概要 / Summary

ULisp による Lua 5.4.7（`.text` 約 445 KB、33 TU）の一括コンパイルに約 60 秒を要しているが、フェーズ別の時間内訳が実測・記録されていない。C99 字句解析を生成する PEG は既にクロージャへの変換（`ulisp/peg/compiler/codegen.scm`）で段階化済みであり対象外だが、アセンブラのテキスト往復（x86-64 アセンブリ文字列出力 → Pass 144a 再パース）は依然残存しており、コードサイズの大きい Lua では支配的コストになっている可能性がある。

Linux x86-64 実機上で `ulisp-boot`（および進行中の [#932](932-build-native-aot-ulisp-cc-compiler-driver-binary.md) による `ulisp-cc` ネイティブ AOT バイナリ）の実行により、フェーズ別時間内訳を再現可能に計測・定量化し、次期高速化対象を判断するためのエビデンスを整備する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [DSN-33-32](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-41](../designs/DSN-33-41-ulisp_ilisp_aot_jit_continuous_benchmarking_framework.md)
  - [Issue #925](closed/925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md)
  - [Issue #932](932-build-native-aot-ulisp-cc-compiler-driver-binary.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [c_driver.scm](../../ulisp/driver/c_driver.scm) (フェーズ別タイムスタンプ計測フック)
- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (アセンブリテキスト生成・再パース区間計測)
- [ ] [test_compile_lua.sh](../../ulisp/tests/test_compile_lua.sh) (Lua 33 TU ビルドプロファイル実行)
- [ ] [Makefile](../../ulisp/Makefile) (計測用ターゲット)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/945-profile-lua-547-build-phase-breakdown`

1. `c_driver.scm` にコンパイル各段階（CPP / Parse / Sema / LIR Lower / Opt / Asm テキスト生成＆再パース / Link）の所要時間を計測・出力するプロファイリングオプションを追加する。
2. Linux x86-64 環境で Lua 5.4.7 全 33 TU ビルドを計測し、アセンブラテキスト往復を含む各フェーズの比率レポートを記録する（詳細手順は `polish-issue` にて精緻化する）。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] Linux x86-64 上で Lua 5.4.7 全 33 TU のフェーズ別時間内訳が再現可能に計測・出力されること。
- [ ] アセンブラテキスト往復の所要時間比率が定量化され、次の最適化優先度を判断できるレポートが得られていること（詳細ゲートは `polish-issue` 時に確定）。
