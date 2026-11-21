---
ID: 927
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] C ヘッダ用 `.sbi` プリコンパイル済みヘッダ (PCH) および mem2reg 反復最適化によるビルド高速化 (ID: 927)

## 1. 概要 / Summary
巨大な標準ヘッダ群（`musl` ヘッダや `lua.h`/`lstate.h` 等）を翻訳単位ごとにゼロから再解析するコンパイル時間ボトルネックを解消するため、`.sbi` シリアライザ（Issue #839）を C99 AST/マクロ表・PCH スナップショットへ適用する（Step S6 / T15）。さらに、PassManager 解析キャッシュ無効化機構（Issue #840）上で mem2reg・ピープホール・分岐融合の反復最適化パイプラインを有効化し、生成バイナリの実行性能も向上させる。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §5.1, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §5](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-13 §4.2, §4.3](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤 Issue: #839 (`.sbi` シリアライズ), #840 (PassManager キャッシュ), #925

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/sbi.scm](../../ulisp/compiler/sbi.scm) (C99 マクロ辞書・`L_c_typed` ヘッダ AST・Binding ID 永続化)
- [ ] `ulisp/frontend_c/preprocessor.scm` / `ulisp/driver/c_driver.scm` (`-include-pch` / 自動 PCH キャッシュ対応)
- [ ] `ulisp/tests/test_c99_pch_and_opt.sh` (新規: PCH 一致性 ＆ ビルド速度ベンチマーク)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/927-implement-c-pch-and-iterative-mem2reg`

1. C99 ヘッダ（`stdio.h`, `stdlib.h`, `lua.h` 等）のプリプロセス済みマクロテーブル・Binding スコープ・確定済み構造体レイアウトを `.sbi` バイナリ形式で永続化し、5ms 以内でメモリへ復元できるようにする。
2. PCH 有効時と無効時で生成される Core Machine LIR および ELF オブジェクトファイルがビットレベルで同一であることを検証する。
3. `Pass 132 Braun SSA` $\to$ `Pass 133 LIR Peephole` $\to$ 分岐融合・不要ストア除去の反復最適化ループを `c_driver.scm` の `-O2` モードとして接続する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] PCH を用いた場合と用いない場合でコンパイル結果のオブジェクトファイル（`.o`）が 100% 一致すること。
- [ ] Lua 5.x 全 33 ファイルのクリーンビルド時間が大幅に短縮（設計目標の数秒以内水準）されること。
- [ ] `-O2` 最適化パイプライン適用後も Lua 公式テストスイートが全件 PASS すること。
