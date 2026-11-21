---
ID: 927
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] C ヘッダ用 `.sbi` プリコンパイル済みヘッダ (PCH) および mem2reg 反復最適化によるビルド高速化 (ID: 927)

## 1. 概要 / Summary
巨大な標準ヘッダ群（`musl` ヘッダや `lua.h`/`lstate.h` 等）を翻訳単位ごとにゼロから再解析するコンパイル時間ボトルネックを解消するため、`.sbi` シリアライザ（Issue #839 [sbi.scm](../../ulisp/compiler/sbi.scm)）を C99 AST/マクロ表・PCH スナップショットへ適用する（Phase S6 / Task T15）。さらに、PassManager 解析キャッシュ無効化機構（Issue #840 [pass_manager.scm](../../ulisp/compiler/pass_manager.scm)）上で mem2reg・ピープホール・分岐融合の反復最適化パイプライン（`-O2`）を有効化し、生成バイナリの実行性能も向上させる。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §5.1, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §5](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-13 §4.2, §4.3](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤（実装済・先行）:
  - `#839`: `.sbi` シリアライズ（[ulisp/compiler/sbi.scm](../../ulisp/compiler/sbi.scm)）
  - `#840`: PassManager キャッシュ無効化（[ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm)）
  - `#914`: C99 CPP（[ulisp/frontend_c/preprocessor.scm](../../ulisp/frontend_c/preprocessor.scm), [[#914]](closed/914-implement-pure-scheme-c99-preprocessor-cpp.md)）
  - `#925`: Lua 一括ビルド（[[#925]](925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md)）
- 後続連携 Issue:
  - [[#928]](928-compile-musl-libc-with-ulisp-and-migrate-to-pass-144-elf-linker.md) (`musl` 大規模ビルド), [[#929]](929-implement-ddc-diverse-double-compiling-determinism-verification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/sbi.scm](../../ulisp/compiler/sbi.scm) (C99 `.sbi` PCH スナップショット直列化 ＆ SHA-256 整合検証)
- [ ] [ulisp/frontend_c/preprocessor.scm](../../ulisp/frontend_c/preprocessor.scm) ＆ `ulisp/driver/c_driver.scm` (`-emit-pch` / `-include-pch <file.sbi>` ＆ `-O2` パイプライン統合)
- [ ] `ulisp/tests/test_c99_pch_and_opt.sh` (新規: PCH 有無 `.o` ビット一致 ＆ `-O2` ベンチマーク・回帰テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_c99_pch_opt` ターゲットおよび `test` 集約への登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/927-implement-c-pch-and-iterative-mem2reg`

### 4.1 `.sbi` プリコンパイル済みヘッダ (PCH) スナップショット
1. **シリアライズ対象**:
   - `<cpp-context>` のマクロ定義表・インクルードガードキャッシュ（#914）、`<scope-manager>` 束縛環境（`Binding ID` 採番位置含む #837）、確定済み `<c-struct-layout>` 表（#918）、およびヘッダ由来の `L_c_typed` 宣言リスト。
2. **改ざん・陳腐化防止**:
   - ヘッダ入力と `-D`/`-I` オプションの決定論的ダイジェストを `.sbi` ヘッダに埋め込み、条件不一致時は安全にフォールバック再コンパイルする（再読込ターゲット: 5ms 以内）。

### 4.2 `-O2` 反復最適化ループ (`pass_manager.scm` #840)
1. **最適化シーケンス**:
   - [132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm) (`mem2reg`) → [133_lir_peephole.scm](../../ulisp/lir/133_lir_peephole.scm)（定数畳み込み・冗長移動除去） → [128_lir_branch_fusion.scm](../../ulisp/lir/128_lir_branch_fusion.scm)（分岐簡約・デッドブロック除去）を不動点収束または上限反復回数まで自動再計算（解析キャッシュ無効化 #840 活用）。
2. **診断コード (`diagnostic.scm` #833)**:
   - `"C99-PCH-001"`（PCH バージョン／マクロ定義不一致警告）, `"C99-PCH-002"`（破損 `.sbi` 読み込みエラー）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] PCH を用いた場合と用いない場合でコンパイル結果のオブジェクトファイル（`.o`）がビット単位で 100% 一致すること。
- [ ] Lua 5.x 全 33 ファイルのクリーンビルド時間が設計目標水準（数秒以内）へ大幅に短縮されること。
- [ ] `-O2` 反復最適化パイプライン適用後も Lua 公式テストスイート（#926）が全件 PASS すること。
