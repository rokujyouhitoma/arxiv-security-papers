---
ID: 599
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 汎用データフロー解析フレームワーク（半順序束・伝達関数・固定点反復エンジン）の導入 (ID: 599)

## 1. 概要 / Summary
ULisp フロントエンドおよび LIR 最適化層（Pass 040, 050, 060, 080, 090, 120 等）で個別アドホックに実装されているデータ伝播・状態追跡・反復ループを共通フレームワーク化し、**「汎用データフロー解析エンジン（Generic Dataflow Analysis Framework）」** を導入する。

### 背景と課題:
1. **車輪の再発明と保守性**:
   - Pass 040 (自由変数解析), Pass 050 (定数畳み込み), Pass 060 (LVN), Pass 080 (抽象解釈・型推論), Pass 090 (RTyper), Pass 120 (エスケープ解析) の各パスで、環境（alist）を引き回しながら値や型を伝播させ、変化がなくなるまでループするロジックが個別手書きされている。
2. **収束性と正当性の保証**:
   - 単調性（Monotonicity）や停止性（Termination）の保証が各パスの実装者に委ねられており、エッジケースでの無限ループや固定点（Fixed-point）への到達漏れのリスクがある。
3. **コードベースの肥大化**:
   - 解析ロジックの本質（束と伝達関数）以外のボイラープレート（走査・合流・終了判定）が各ファイルの大半を占めている。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - Issue #585: [Nanopass Framework DSL Phase 3: Catamorphism Extra Values と解析・最適化パス刷新](closed/585-nanopass-framework-phase3-catamorphism-extra-values-and-analysis-passes.md)
  - Issue #578: [Pass 110/120/130 の連携による非エスケープオブジェクトのスタック配置最適化](closed/578-coordinate-closure-escape-and-lir-stack-allocation-pipeline.md)
  - Issue #597: [IR Verifier 基盤の共通化・階層分離と LIR 検証パフォーマンス最適化](597-unify-ir-verifier-framework-and-optimize-lir-performance.md)
- 関連仕様書:
  - [ulisp/docs/spec_pipeline.md](../../ulisp/docs/spec_pipeline.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/dataflow.scm](../../ulisp/compiler/dataflow.scm) (新規: 汎用データフロー解析・固定点エンジン)
- [ ] [ulisp/frontend/040_analysis.scm](../../ulisp/frontend/040_analysis.scm) (自由変数・静的解析の共通エンジン移行)
- [ ] [ulisp/frontend/050_cp0.scm](../../ulisp/frontend/050_cp0.scm) (定数伝播・不要コード削除の共通エンジン移行)
- [ ] [ulisp/frontend/080_annotator.scm](../../ulisp/frontend/080_annotator.scm) (抽象解釈・型推論の共通エンジン移行)
- [ ] [ulisp/frontend/120_alias_escape.scm](../../ulisp/frontend/120_alias_escape.scm) (エスケープ解析の共通エンジン移行)
- [ ] [ulisp/tests/test_dataflow.scm](../../ulisp/tests/test_dataflow.scm) (新規: 束演算・伝達関数・収束性検証テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/599-implement-generic-dataflow-analysis-framework`

1. **半順序束（Lattice）抽象の確立**:
   - `Bottom` ($\bot$), `Top` ($\top$), 順序比較述語 `(lattice-leq? a b)`, 合流演算 `(lattice-join a b)`, 交差演算 `(lattice-meet a b)` をカプセル化するデータ構造・述語群を整備。
2. **Worklist アルゴリズムによる汎用固定点反復エンジン**:
   - Forward / Backward 解析の双方に対応。
   - CFG または AST ノードを対象とする Worklist キュー駆動の伝達関数（Transfer Function）評価。
   - 状態変化がなくなった時点で自動停止する単調固定点（Monotone Framework）保証。
3. **既存パスの段階的リファクタリング**:
   - まずエスケープ解析（Pass 120）および定数畳み込み（Pass 050）を共通エンジンへ移行し、コード量削減と正当性を実証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 汎用データフローエンジンが構築され、Forward / Backward 解析の双方が統一APIで実行できること
- [ ] 最低1つ以上の既存解析パス（Pass 120 または Pass 050）が共通データフローエンジンを用いてリファクタリングされ、出力の等価性が保たれること
- [ ] 固定点反復が有限回で確実に収束し、無限ループに陥らない単調性が保証されること
- [ ] 既存の全テストスイート（`make test`）が 100% PASS すること
