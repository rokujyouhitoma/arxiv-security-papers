---
ID: 573
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] LIR パス (130_lir.scm) の機能責務別ナノパス分割（即値・プリミティブ・ABI呼出・ランタイム機能） (ID: 573)

## 1. 概要 / Summary
現在 `ulisp/passes/130_lir.scm` は 1,721 行 (73KB) に達する最大のメガパスとなっており、即値解決、環境管理、基本プリミティブ命令選択、クロージャ生成、スタック割り当て、継続呼び出し・in-place シャッフルループ、制御構文、多値・例外・call/cc 等の多様な責務が一体化している。
本 Issue では、Nanopass コンパイラ設計思想に基づき、`130_lir.scm` を責務別のモジュール/パス群に分割（`130_lir_core.scm`, `131_lir_primitives.scm`, `132_lir_call_abi.scm`, `133_lir_closures.scm`, `134_lir_control.scm`, `135_lir_continuation.scm`, `136_lir_runtime.scm` 等）し、認知的負荷の低減と各責務ごとの独立テスト・保守性を確立する。

---

## 2. トレーサビリティ / Traceability
- Nanopass Framework 原則
- DSN-33 コンパイラアーキテクチャ仕様
- `ulisp/docs/lir_specification.md`
- 関連資料: [ulisp/passes/130_lir.scm](../../ulisp/passes/130_lir.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/130_lir.scm](../../ulisp/passes/130_lir.scm) (分割・リファクタリング)
- [ ] [ulisp/passes/130_lir_core.scm](../../ulisp/passes/130_lir_core.scm) (即値・環境・変数解決)
- [ ] [ulisp/passes/131_lir_primitives.scm](../../ulisp/passes/131_lir_primitives.scm) (プリミティブ命令選択)
- [ ] [ulisp/passes/132_lir_call_abi.scm](../../ulisp/passes/132_lir_call_abi.scm) (呼び出し・末尾呼び出しABI)
- [ ] [ulisp/passes/133_lir_closures.scm](../../ulisp/passes/133_lir_closures.scm) (クロージャ・スタック割り当て)
- [ ] [ulisp/passes/134_lir_control.scm](../../ulisp/passes/134_lir_control.scm) (制御構文・基本ブロック)
- [ ] [ulisp/passes/135_lir_continuation.scm](../../ulisp/passes/135_lir_continuation.scm) (継続ジャンプ・in-placeシャッフル)
- [ ] [ulisp/passes/136_lir_runtime.scm](../../ulisp/passes/136_lir_runtime.scm) (多値・例外・call/cc)
- [ ] [ulisp/tests/passes/](../../ulisp/tests/passes/) (対応する分割テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`PASSES_LIB` リスト更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/573-nanopass-decomposition-of-lir-pass-130`

1. `130_lir.scm` の内部関数群の依存関係グラフを整理
2. コア基盤（変数解決・即値エンコード）と各論（プリミティブ選択、制御構文、ランタイム機能）の境界を定義
3. 順次モジュールを切り出し、コンパイル・テストの一貫性を確認
4. 各サブモジュールに対応する単体テストを配備
5. 自己ホストコンパイラ (`ulisp-boot` / `scheme-stage1`) でのブートストラップ動作を検証

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `130_lir.scm` が責務別の明確なサブパス/モジュールに分割され、単一ファイルの行数が大幅に削減されていること
- [ ] 既存の全テストスイートおよびベンチマークが 100% 正常に動作すること
- [ ] `make test` および自己ホストブートストラップが完全に成功すること
