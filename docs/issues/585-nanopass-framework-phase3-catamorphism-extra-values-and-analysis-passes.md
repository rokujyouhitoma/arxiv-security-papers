---
ID: 585
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ARCH] Nanopass Framework DSL Phase 3: Catamorphism Extra Values (上流集約 / 下流伝播) と解析・最適化パス刷新 (ID: 585)

## 1. 概要 / Summary
Nanopass Framework DSL Phase 1 (Issue #581) および Phase 2 (Issue #584) では、構文変換（Transform Pass）を中心とした DSL 基盤とエリップシス・サブフォーム機構を確立する。
しかし、実用的なコンパイラ最適化パイプラインには、構文の書き換えのみならず「親から子への文脈情報の伝播」と「子から親への解析結果の集約」を同時に行う **属性文法（Attribute Grammars）的な解析パス（Analysis Passes）** が不可欠である。

本 Issue（Phase 3）では、Catamorphism（再帰走査）における **Extra Values（多値・解析情報のアナライザ支援機構）** を Nanopass DSL にネイティブ実装する：
1. **下流伝播 (Downwards / Inherited Attributes)**:
   - スコープ環境（`env`）、型注釈マップ、燃料（`fuel`）予算、Capability トークンを親から子ノードへ透過的に引き渡す機能。
2. **上流集約 (Upwards / Synthesized Attributes)**:
   - 式に含まれる「自由変数の集合（Free Variables）」や「副作用の有無（Purity/Effect）」などを子ノードの戻り値として親ノードに多値（`values`）返却し、親側で自動畳み込み（`set-union`, `or`）する機構。

これにより、これまで手書きの複雑な走査ループで記述されていた解析・最適化パス群（Pass 040_analysis, Pass 050_cp0, Pass 060_lvn, Pass 100_contify, Pass 120_alias_escape）を、Nanopass DSL の宣言的かつ型安全な構文規則へ全面刷新する。

---

## 2. トレーサビリティ / Traceability
- 先行研究系譜: Keep & Dybvig, "A Nanopass Framework for Commercial Compiler Development" (ICFP 2013 / Chez Scheme)
- DSN-33 コンパイラアーキテクチャ仕様
- 関連 Issue:
  - [581-implement-nanopass-framework-dsl-and-migrate-compiler-passes.md](581-implement-nanopass-framework-dsl-and-migrate-compiler-passes.md) (Phase 1)
  - [584-nanopass-framework-phase2-ellipsis-subforms-and-normalization.md](584-nanopass-framework-phase2-ellipsis-subforms-and-normalization.md) (Phase 2)
  - [586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks.md](586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks.md) (Phase 4)
- 関連ファイル:
  - [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
  - [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
  - [ulisp/passes/040_analysis.scm](../../ulisp/passes/040_analysis.scm)
  - [ulisp/passes/050_cp0.scm](../../ulisp/passes/050_cp0.scm)
  - [ulisp/passes/060_lvn.scm](../../ulisp/passes/060_lvn.scm)
  - [ulisp/passes/100_contify.scm](../../ulisp/passes/100_contify.scm)
  - [ulisp/passes/120_alias_escape.scm](../../ulisp/passes/120_alias_escape.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm) (Extra Values 構文 `(Expr (ir env) -> Expr (free-vars))` のマクロ展開サポート)
- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm) (未オーバーライド節における多値自動合成・伝播 Catamorphism エンジン)
- [ ] [ulisp/passes/040_analysis.scm](../../ulisp/passes/040_analysis.scm) (自由変数解析の Nanopass 化)
- [ ] [ulisp/passes/050_cp0.scm](../../ulisp/passes/050_cp0.scm) (CP0 最適化パスの Nanopass 化)
- [ ] [ulisp/passes/060_lvn.scm](../../ulisp/passes/060_lvn.scm) (局所値ナンバリングの Nanopass 化)
- [ ] [ulisp/passes/100_contify.scm](../../ulisp/passes/100_contify.scm) (Contification 脱クロージャ解析の Nanopass 化)
- [ ] [ulisp/passes/120_alias_escape.scm](../../ulisp/passes/120_alias_escape.scm) (エスケープ・エイリアス解析の Nanopass 化)
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm) (Extra Values 多値伝播テストの追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/585-nanopass-framework-phase3-catamorphism-extra-values-and-analysis-passes`

1. **Extra Values シグネチャ解析とマクロ展開**:
   - `define-pass` のヘッダー記法において、`(pass-name : L_src (ir extra_in ...) -> L_dst (extra_out ...))` を解析。
   - 非終端記号ハンドラ間でも `(Expr : Expr (e env) -> Expr (free-vars))` のように各節の入出力引数をバインド。
2. **デフォルト Catamorphism の多値自動配線**:
   - ユーザーがパターン節で言及しなかった構文について、子ノードの `extra_in` の伝播と `extra_out` の結合（Monoid 演算: 例として集合なら `set-union`、リストなら `append`、ブールなら `or`）を行う合成コードを自動生成。
3. **解析パスの段階的載せ替え**:
   - `040_analysis.scm`（自由変数解析）を Extra Values 構文で書き直し、50% 以上のコード行数削減を達成。
   - `050_cp0.scm`, `060_lvn.scm`, `100_contify.scm`, `120_alias_escape.scm` を順次 Nanopass DSL に移行。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `define-pass` で下流伝播引数および上流集約多値（`values`）が透過的に扱えること
- [ ] デフォルトの Catamorphism 走査コードが属性の自動集約を正しく行えること
- [ ] Pass 040, 050, 060, 100, 120 が Nanopass DSL で書き直され、正しく動作すること
- [ ] 全パス単体テスト（`make -C ulisp test_all_passes`）および 3-Stage Bootstrap 固定点検証（`make -C ulisp bootstrap_verify`）が 100% PASS すること
- [ ] 相対パスのみを使用し、絶対パスが含まれないこと
