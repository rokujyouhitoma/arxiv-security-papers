---
ID: 979
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] LIR パス言語契約の是正（pass-130 -> L_lir_managed）と nanopass-language-compatible? 厳格化・旧 LIR 言語階層の整理 (ID: 979)

## 1. 概要 / Summary

コードベース調査の結果、LIR 層の言語検査およびパス定義に以下の 3 つの構造的不整合が存在することが確認された。本 Issue では **項番 2 → 1 → 3** の観点を一体的に是正し、パイプライン連続性検査の安全網を回復した。

1. **パス 130 の出力言語宣言の乖離（項番 2）**:
   - `ulisp/compiler/pass_manager.scm:1574-1578`（およびバンドル版 `ulisp/compiler.scm`）において、`pass-130-lir` の出力言語が `'L_lir_raw` と宣言されていたが、実際には `%managed-alloc` / `%managed-box` 等の managed 系命令を含む `L_lir_managed` 形式を出力しており、次段 `pass-131-lower-managed-dialect` の入力言語 `'L_lir_managed` と食い違っていた。
2. **LIR 言語互換性検査の形骸化（項番 1）**:
   - `ulisp/compiler/pass_manager.scm:902-913` の `nanopass-language-compatible?` が `{L_lir_core, L_lir_managed, L_lir_raw, L_lir_canonical}` の 4 言語を無条件にすべて相互互換（4×4 フルメッシュ）とみなしていた。そのため、`%managed-alloc` 等が残ったまま `L_lir_core` 向けパスやバックエンドに渡ってもパイプライン検証で検出できなかった。
3. **旧 LIR 言語階層の整理（項番 3）**:
   - `ulisp/lir/lir_lang.scm` に Issue #835 で導入された `L_lir_core` → `L_lir_managed` 階層と旧来の `L_lir_raw` → `L_lir_canonical` 階層が混在していた。パイプライン契約上の後続 LIR 最適化（`pass-133-lir-peephole`）の出力を `'L_lir_core` へ統一し、`L_lir_raw` → `L_lir_canonical` はレガシー検査・内部 `define-pass` 用スキーマ階層（パイプライン互換判定からは除外）として明記した。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [pass_manager.scm](../../../ulisp/compiler/pass_manager.scm)
  - [lir_lang.scm](../../../ulisp/lir/lir_lang.scm)
  - [lir_verifier.scm](../../../ulisp/lir/lir_verifier.scm)
  - [835-separate-core-machine-lir-from-managed-runtime-dialect.md](835-separate-core-machine-lir-from-managed-runtime-dialect.md)
  - [966-separate-mir-ssa-and-machine-lir-for-unified-middle-end.md](../966-separate-mir-ssa-and-machine-lir-for-unified-middle-end.md)

---

## 3. 脅威モデリングと安全性要件 / Threat Model & Safety Requirements

1. **未 Lowering 命令のバックエンド漏洩防止（CWE-704 / CWE-843）**:
   - `L_lir_managed`（GC アロケーション・ボックス化等の高水準ランタイム擬似命令を含む方言）が `pass-131-lower-managed-dialect` を経ずに `L_lir_core` / `L_lir_canonical` パスやネイティブバックエンドへ流入することを、`validate-pipeline-continuity-by-ids`（静的パイプライン検査）および `L_lir_canonical?`（Tier 1 構文検査）の双方で Fail-Closed 拒絶する。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [pass_manager.scm](../../../ulisp/compiler/pass_manager.scm) (`nanopass-language-compatible?`, `pass-130-lir`, `pass-133-lir-peephole`)
- [x] [compiler.scm](../../../ulisp/compiler.scm) (`make -C ulisp compiler` による再生成)
- [x] [lir_lang.scm](../../../ulisp/lir/lir_lang.scm) (`L_lir_core` / `L_lir_managed` 現役階層と `L_lir_raw` / `L_lir_canonical` レガシー階層の明確化)
- [x] [lir_verifier.scm](../../../ulisp/lir/lir_verifier.scm) (`L_lir_canonical?` Tier-1 スキーマ検査との互換維持確認)
- [x] [128_lir_branch_fusion.scm](../../../ulisp/lir/128_lir_branch_fusion.scm)
- [x] [133_lir_peephole.scm](../../../ulisp/lir/133_lir_peephole.scm)
- [x] [test_pass_manager.scm](../../../ulisp/tests/test_pass_manager.scm) (`Group 12: Strict LIR Dialect Compatibility` 追加)
- [x] [test_lir_dialect_separation.scm](../../../ulisp/tests/test_lir_dialect_separation.scm) (`5.6b`〜`5.6d` 検証追加)
- [x] [test_inline_asm.scm](../../../ulisp/tests/test_inline_asm.scm)
- [x] [test_ir_serialization.scm](../../../ulisp/tests/test_ir_serialization.scm)

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/979-tighten-lir-language-compatibility`

### Phase 1: Pass 130 / Pass 133 言語契約の統一（項番 2）
1. [pass_manager.scm](../../../ulisp/compiler/pass_manager.scm#L1568-L1591) における `pass-130-lir` の出力言語宣言を `'L_lir_raw` から `'L_lir_managed` へ修正し、`pass-131-lower-managed-dialect` の入力 `'L_lir_managed` と一致させた。
2. 同箇所で `pass-133-lir-peephole` の出力言語宣言を `'L_lir_canonical` から `'L_lir_core` へ統一し、`pass-131` 以降の全 LIR 最適化パス（`pass-132-c99-mem2reg`, `pass-128-lir-branch-fusion`, `pass-133-lir-peephole`）および `run-c99-o2-fixpoint-pipeline` が `'L_lir_core` 上で閉じて遷移するようにした。

### Phase 2: `L_lir_raw` / `L_lir_canonical` レガシー階層の明確化（項番 3）
1. [lir_lang.scm](../../../ulisp/lir/lir_lang.scm) のヘッダおよびセクション見出しを更新し、現役パイプライン階層（`L_lir_managed` → `L_lir_core`）と、Tier-1 汎用 LIR スキーマ検証（`L_lir_canonical?`）および内部 `define-pass` / 既存レガシーテスト向けの旧階層（`L_lir_raw` → `L_lir_canonical`）の責務境界を明文化した。

### Phase 3: `nanopass-language-compatible?` の厳格化（項番 1）
1. [pass_manager.scm](../../../ulisp/compiler/pass_manager.scm#L902-L910) の `nanopass-language-compatible?` から LIR 4 言語の無条件互換節を削除した。
2. これにより `L_lir_managed` → `L_lir_core`、`L_lir_core` → `L_lir_managed`、`L_lir_raw` → `L_lir_core`、`L_lir_managed` → `L_lir_canonical` の暗黙遷移が `#f` となり、`pass-131-lower-managed-dialect` を欠いた不正パイプラインを `check-pipeline-continuity-by-ids` / `validate-pipeline-continuity-by-ids` が即座に拒否する。

### Phase 4: バンドル再生成・単体テスト拡充
1. `make -C ulisp compiler` で [compiler.scm](../../../ulisp/compiler.scm) を再生成した。
2. [test_pass_manager.scm](../../../ulisp/tests/test_pass_manager.scm#L681-L711)（Group 12: 12 項目）および [test_lir_dialect_separation.scm](../../../ulisp/tests/test_lir_dialect_separation.scm#L390-L398) に LIR 言語契約・厳格互換判定・不正パイプライン拒否の回帰テストを追加した。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `pass-130-lir` の出力言語が `'L_lir_managed` に是正され、`pass-131-lower-managed-dialect` と整合していること。
- [x] `pass-133-lir-peephole` 含む現役 LIR 最適化パスの入出力が `'L_lir_core` に統一され、旧 `L_lir_raw` / `L_lir_canonical` の位置付けが明確化されていること。
- [x] `nanopass-language-compatible?` が `L_lir_managed` → `L_lir_core` / `L_lir_canonical` および `L_lir_raw` → `L_lir_core` の直接遷移を `#f` として拒否することが自動テストで検証されていること。
- [x] `make -C ulisp compiler test_pass_manager test_lir_dialect_separation test_nanopass test_all_passes test_lir_verifier test_inline_asm test_ir_serialization test_c99_int_lowering test_c99_funcptr_and_switch_cfg test_residual_anf_to_lir` および `make check_format && make static_analysis` が全 PASS すること。
