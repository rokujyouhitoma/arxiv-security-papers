---
ID: 595
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] LIR層: define-pass による分岐融合・DCE・ピープホール最適化の宣言化 (ID: 595)

## 1. 概要 / Summary
現在、LIR 層の最適化（Pass 128 `lir/128_lir_branch_fusion.scm` など）は命令リストの手続き的な再帰トラバーサルやアドホックなパターンマッチングによって実装されている。
Issue 593 により `define-language L_lir_canonical` が導入されることで、LIR 命令列に対する自己変換パスを `define-pass` として宣言的に記述する土台が整う。

本 Issue では、分岐融合（Branch Fusion）、不要命令削除（Dead Code Elimination / DCE）、即値移動の冗長ロード削除（Redundant Load Elimination）などの LIR 最適化を `define-pass (L_lir_canonical -> L_lir_canonical)` として再構築・拡充する。これにより、LIR レベルでの最適化の安全性、保守性、およびトレーサビリティ（Pass ごとの S 式差分可視化）を大幅に向上させる。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
  - [LIR 命令セット仕様書](../../ulisp/docs/spec_lir.md)
- **関連 Issue**:
  - Issue 571: Pass 128 LIR 分岐融合 & 条件比較低レベル化
  - Issue 593: LIR層 `L_lir_canonical` の導入
  - 依存 Issue: Issue 593

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm) (シーケンス・スプライシング最適化マクロの確認)
- [ ] [ulisp/lir/128_lir_branch_fusion.scm](../../ulisp/lir/128_lir_branch_fusion.scm) (`define-pass` 化)
- [ ] [ulisp/lir/133_lir_peephole.scm](../../ulisp/lir/133_lir_peephole.scm) (新規: LIR ピープホール最適化・冗長命令削除)
- [ ] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm) (パイプラインドライバへの接続)
- [ ] [ulisp/tests/passes/test_128_lir_branch_fusion.scm](../../ulisp/tests/passes/test_128_lir_branch_fusion.scm) (単体テスト)
- [ ] [ulisp/tests/passes/test_133_lir_peephole.scm](../../ulisp/tests/passes/test_133_lir_peephole.scm) (新規テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/595-define-pass-lir-optimizations-and-peephole`

1. **Pass 128 分岐融合の `define-pass` 化**:
   - `L_lir_canonical` から `L_lir_canonical` への変換パスとして定義。
   - `((%cmp-op c1 c2) (%jump-if-false L1))` → `((%jump-cond (invert-cc cc) L1))` のようなパターンマッチングを `define-pass` の句として明確に宣言。
2. **新規 Pass 133: LIR ピープホール最適化 (`133_lir_peephole.scm`)**:
   - 冗長移動の削除: `((%mov reg1 reg2) (%mov reg2 reg1))` → `((%mov reg1 reg2))`
   - 未使用ラベル直後の無条件ジャンプの解消: `((%jump L1) (%label L1))` → `((%label L1))`
   - 即値自己演算の簡約: `((%add dst 0))` → `()`
3. **`trace-define-pass` による可観測性の確保**:
   - LIR 最適化の各段階での命令列変化をトレース可能にし、デバッグ効率を高める。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `128_lir_branch_fusion.scm` が `define-pass` 形式で再記述され、既存テストが全てパスすること。
- [ ] 新規ピープホール最適化（`133_lir_peephole.scm`）が導入され、生成される LIR 命令数が削減されること。
- [ ] 最適化前後で `validate-lir`（`L_lir_canonical?`）が常に 100% PASS し、不変条件が破られないこと。
- [ ] `make test_unit` および `bash ulisp/test.sh` が 100% PASS すること。
