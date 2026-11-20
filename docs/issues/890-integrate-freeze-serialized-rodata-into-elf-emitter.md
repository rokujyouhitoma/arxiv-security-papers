---
ID: 890
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] freeze-serialize-to-rodata 直列化データと elf.scm (.rodata) の実リンカ配線 (ID: 890)

## 1. 概要 / Summary
DSN-33-03 §7.3, §8.1 (Phase P5), DSN-33-02 §8.4 および DSN-33 §11.1 に基づき、`sbi.scm` の `freeze-serialize-to-rodata` で生成された循環グラフ・定数データ構造の直列化バイナリを、AOT バックエンド（`elf.scm`）の `.rodata` セクション実データとして直接注入し、機械語からゼロコスト RIP 相対アドレッシング（`[rip + symbol_rodata]`）でアクセス可能にする実リンカ配線を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §7.3 (.rodata 肥大化ガード)](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#73-境界データ変換freeze-循環グラフ直列化-rodata-上限チェック)
  - [DSN-33-02 §8.4 (ELF 統合拡張)](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md#84-dsn-33-03-ステージ多相メタコンパイラとの-lirelf-統合拡張phase-p5)
  - [DSN-33 §11.1 (ELF .rodata 実配線)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md#111-dsn-33-03-ステージ多相メタコンパイラ統合phase-p5-issues-887891)
- 関連 Issue: #883 (Freeze Graph Serialization), #884 (Data Plane Tag Stripping)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/elf.scm](../../ulisp/compiler/elf.scm)
- [ ] [ulisp/compiler/sbi.scm](../../ulisp/compiler/sbi.scm)
- [ ] [ulisp/tests/test_elf_sections_and_reloc.scm](../../ulisp/tests/test_elf_sections_and_reloc.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/890-integrate-freeze-serialized-rodata-into-elf-emitter`

1. `elf.scm` の ELF セクション生成処理において、`freeze-serialize-to-rodata` で出力されたバイト列を `.rodata` セクションヘッダおよびペイロードバッファへ追記するインターフェース `elf-emit-rodata-payload!` を追加。
2. 循環参照や自己言及シンボルの再配置（Relocation Entry）を生成し、実行時デシリアライズコストなしで C/ネイティブポインタとして解決。
3. ELF バイナリ生成テストで `.rodata` セクションにデータが正しく配置され、RIP 相対アクセス可能であることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `freeze-serialize-to-rodata` のバイナリ出力が生成 ELF ファイルの `.rodata` セクションに正しく格納されること。
- [ ] `*max-rodata-size*` (64MB) を超過した場合に `E-RODATA-OVERFLOW` で安全にビルド中断されること。
- [ ] `make test_elf_sections_and_reloc` が 100% PASS すること。
