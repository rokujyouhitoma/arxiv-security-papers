---
ID: 599
種別: Feature
優先度: Medium
ステータス: Closed
完了日: 2026-10-25
---

# [FEAT/ENH] 汎用データフロー解析フレームワーク（半順序束・伝達関数・固定点反復エンジン）の導入 (ID: 599)

## 1. 概要 / Summary
ULisp コンパイラのフロントエンドおよび LIR 最適化層（Pass 040, 050, 060, 080, 090, 120, 132 等）において個別アドホックに実装されているデータ伝播・状態追跡・固定点反復ループを抽象化・共通フレームワーク化し、**「汎用データフロー解析エンジン（Generic Dataflow Analysis Framework / Monotone Framework）」** を導入する。

### 背景と課題:
1. **車輪の再発明と保守性**:
   - Pass 040 (自由変数解析), Pass 050 (定数畳み込み/到達可能性), Pass 060 (LVN), Pass 080 (型推論/アノテーション), Pass 090 (RTyper), Pass 120 (エスケープ・エイリアス解析), Pass 132 (SSA 活性解析) の各パスで、環境（alist）を引き回しながら状態を伝播させ、状態変化がなくなるまでループするロジックが個別手書きされている。
2. **収束性と正当性の保証**:
   - 単調性（Monotonicity）や停止性（Termination）の保証が各パスの実装者に委ねられており、エッジケースでの無限ループや固定点（Fixed-point）への到達漏れのリスクがある。
3. **コードベースの肥大化**:
   - 解析ロジックの本質（半順序束と伝達関数）以外のボイラープレート（走査順序制御・合流演算・終了判定・Worklistキュー管理）が各ファイルの大半を占めている。
4. **セルフホスティング制約との両立**:
   - ULisp 自らをコンパイルするセルフホスティングコンパイラとして、可変長引数（dot/rest-arg lambda）の不使用、トップレベル `set!` の抑制（cons cell パターン）、およびポータブル Scheme（Gauche, ILisp/Python, ULisp AOT）で決定論的かつ高速に動作する要件を満たす必要がある。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、16専門エージェントフレームワークに基づき、以下の重点専門領域からの設計レビューを統合して策定された。

- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - 形式的意味論（Kam & Ullman 1977, Kildall 1973, Nielson et al. "Principles of Program Analysis"）に基づく単調フレームワーク（Monotone Framework）の完全な半順序束（Semi-Lattice）仕様を定義。
  - Forward / Backward 解析の双方を同一の抽象 Worklist アルゴリズムで統一。
- **Systems Architect**:
  - `ulisp/compiler/dataflow.scm` を `COMPILER_BASE`（Pass Manager、IR Verifier と同列）に配置し、Frontend（AST）および Middle-End/Backend（LIR / CFG）双方から均一に呼び出し可能な共通抽象層として確立。
- **Software Quality Assurance Specialist (SQA)**:
  - 束演算（$\bot, \top, \sqsubseteq, \sqcup, \sqcap$）の代数法則（反射律・反対称律・推移律・結合律・可換律・吸収律）の単体テストを定義。
  - Worklist の停止性保証（Max Iteration ガードおよび単調性違反の検出）を必須品質ゲートに設定。
- **Information Security Specialist**:
  - 型推論やエスケープ解析の誤り（Soundness 破綻）による未検証スタック昇格や不正キャスト、メモリ破壊・未定義動作の防止を STRIDE/CWE 観点で評価。

---

## 3. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
  - [LIR 命令セット仕様書](../../ulisp/docs/spec_lir.md)
- **関連 Issue**:
  - Issue #585: [Nanopass Framework DSL Phase 3: Catamorphism Extra Values と解析・最適化パス刷新](closed/585-nanopass-framework-phase3-catamorphism-extra-values-and-analysis-passes.md)
  - Issue #578: [Pass 110/120/130 の連携による非エスケープオブジェクトのスタック配置最適化](closed/578-coordinate-closure-escape-and-lir-stack-allocation-pipeline.md)
  - Issue #597: [IR Verifier 基盤の共通化・階層分離と LIR 検証パフォーマンス最適化](closed/597-unify-ir-verifier-framework-and-optimize-lir-performance.md)
  - Issue #598: [統一 Pass Manager の導入によるパイプライン制御・最適化レベルスケジューリング・観測性の一元化](closed/598-implement-unified-compiler-pass-manager.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/dataflow.scm](../../ulisp/compiler/dataflow.scm) (新規: 汎用データフロー解析エンジン・束抽象基盤)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`COMPILER_BASE` への `compiler/dataflow.scm` 追加およびテストターゲット定義)
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (Makefile 結合ターゲット自動再生成)
- [x] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm) (Nanopass AST 検証エラー時アルティ修正 & %program 対応)
- [x] [ulisp/frontend/120_alias_escape.scm](../../ulisp/frontend/120_alias_escape.scm) (エスケープ解析・TBAAの共通データフロー束・伝達関数移行)
- [x] [ulisp/tests/test_dataflow.scm](../../ulisp/tests/test_dataflow.scm) (新規: 束演算・Worklist・Forward/Backward解析単体テスト)
- [x] [docs/issues/closed/599-implement-generic-dataflow-analysis-framework.md](closed/599-implement-generic-dataflow-analysis-framework.md) (本設計書)
- [x] [docs/issues/README.md](README.md) (Issue 管理台帳のステータス更新)

---

## 5. 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

コンパイラの最適化パスにおけるデータフロー解析の不完全性や誤判定は、生成されるネイティブコードのメモリ安全性・健全性を根本から脅かす。STRIDE および CWE 観点での脅威分析を実施し、防護要件を策定する。

| 脅威分類 (STRIDE / CWE) | 脅威シナリオ | 影響度 | 対策要件 (Mitigation Requirements) |
| :--- | :--- | :---: | :--- |
| **改ざん / 不正変形 (Tampering / CWE-697)** | エスケープ解析や定数伝播の合流演算（Join）で過度に楽観的な判定を行い、エスケープするオブジェクトを非エスケープと誤認してスタック昇格させてしまい、ダングリングポインタ・スタック破壊を招く。 | Critical | 保守的近似（Safe/Sound Approximation）の原則を厳格化。Join は常に安全側（エスケープあり、Top/Unknown）に倒す半順序束を設計。 |
| **サービス拒否 (DoS / CWE-400 / CWE-674)** | 循環参照や無限高さの束（Infinite Height Lattice）において固定点反復が収束せず、コンパイラが無限ループ・メモリ枯渇に陥る。 | High | 1. 束の高さが有限であること、または Widening 演算を提供すること。<br>2. Worklist エンジンに最大反復上限（`*dataflow-max-iterations*`）を設け、超過時は安全なフォールバック状態（Conservative Top）を返却または明示的エラーを通知する。 |
| **整合性破綻 (CWE-843)** | 型推論パスにおいて異なる型の伝達が不整合を起こし、実行時型安全チェックの誤った除去を誘発する。 | High | 束の単調性（$x \sqsubseteq y \implies f(x) \sqsubseteq f(y)$）を遵守し、伝達関数が常に単調非減少であることを検証可能にする。 |

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/599-implement-generic-dataflow-analysis-framework`

### 6.1 半順序束（Lattice）抽象の設計 (`ulisp/compiler/dataflow.scm`)
1. **Lattice レコード構造**:
   ```scheme
   (make-lattice name bottom top leq? join meet)
   (lattice? obj)
   (lattice-name l)
   (lattice-bottom l)
   (lattice-top l)
   (lattice-leq? l a b)
   (lattice-join l a b)
   (lattice-meet l a b)
   ```
2. **標準ビルドイン束**:
   - `(make-boolean-lattice)`: $\bot = \#f, \top = \#t, \sqsubseteq = (\implies), \sqcup = (\lor), \sqcap = (\land)$
   - `(make-flat-lattice name)`: 任意定数用。$\bot$, $\top$, 各要素 $c$。異なる要素の合流は $\top$。
   - `(make-powerset-lattice universe-list)`: 集合束。$\bot = '()$, $\sqcup = \cup$, $\sqcap = \cap$, $\sqsubseteq = \subseteq$。
   - `(make-map-lattice val-lattice)`: 変数環境 $Var \to L$。未束縛変数は $\bot$、合流時はキーごとの $val-lattice$ 合流。

### 6.2 Dataflow Problem & Worklist 固定点反復エンジン
1. **Dataflow Problem 宣言**:
   ```scheme
   (make-dataflow-problem
     name          ; symbol
     direction     ; 'forward | 'backward
     lattice       ; lattice record
     boundary-val  ; entry / exit ノード初期値
     init-val      ; その他全ノード初期値 (通常 bottom)
     transfer-fn   ; (lambda (node in-state) -> out-state)
   )
   ```
2. **Worklist アルゴリズム**:
   - CFG またはノード集合と隣接関係（`preds-fn`, `succs-fn`）を受け取り、入出力状態テーブルを計算。
   - 状態変化がなくなるまで Worklist キューを消費し、単調固定点（MFP: Monotone Framework / Maximum Fixed Point）を導出。
   - セルフホスティング対応: リストによるシンプルなキュー管理と副作用の極小化。

### 6.3 既存解析パスのリファクタリング
- `ulisp/frontend/120_alias_escape.scm` のエスケープ解析ロジックを、汎用データフローの Powerset/Boolean 束と伝達関数を用いた構造に段階移行。
- 既存のテスト結果と完全に一致し、セマンティクス破壊が一切ないことを確認。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] 汎用データフローエンジン `ulisp/compiler/dataflow.scm` が新規作成され、`COMPILER_BASE` に統合されていること
- [x] 半順序束抽象（Lattice）および基本束（Flat, Powerset, Map, Boolean）が実装されていること
- [x] Forward / Backward 解析の双方が同一の Worklist アルゴリズムで正しく動作すること
- [x] 反復回数制限（Safety Iteration Limit）による無限ループ防止策が組み込まれていること
- [x] 単体テストスイート `ulisp/tests/test_dataflow.scm` が新規作成され、全テスト項目が PASS すること
- [x] 既存の解析パス（Pass 120 等）との親和性・等価性が検証されていること
- [x] 全品質ゲート（`make check_format`, `make static_analysis`, `make py_compile`, ULisp 単体テスト群）が 100% PASS すること

---

## 8. 実装成果と品質検証結果 / Implementation Results & Quality Verification

### 8.1 実装成果物一覧
1. **汎用データフロー解析エンジン・束抽象基盤 (`ulisp/compiler/dataflow.scm`)**:
   - 半順序束（Lattice）抽象レコード（`bottom`, `top`, `leq?`, `join`, `meet`）の定義
   - 標準束ファクトリ群の実装:
     - `make-boolean-lattice`: 真偽値束
     - `make-flat-lattice`: フラット定数伝播束
     - `make-powerset-lattice`: べき集合束
     - `make-map-lattice`: 変数環境束 ($Var \to Lattice$)
     - `make-product-lattice`: 直積束 ($L_1 \times L_2$)
   - 単調フレームワーク（Monotone Framework）Worklist 固定点反復エンジン (`dataflow-analyze`):
     - Forward / Backward 解析の統一反復ディスパッチ
     - 安全反復上限（`*dataflow-max-iterations*`）による停止性保証 (CWE-400/CWE-674 対策)
     - セルフホスティング制約（可変長引数不使用、トップレベル `set!` 抑制）の 100% 遵守
2. **Pass 120 リファクタリング (`ulisp/frontend/120_alias_escape.scm`)**:
   - `collect-escaped-vars` を `make-powerset-lattice` および `lattice-join` を用いた構造に移行し、意味論の完全一致を保証。
3. **Nanopass 検証エンジンの堅牢化 (`ulisp/compiler/nanopass_meta.scm`)**:
   - `%program` 形式 AST ノードのマッチング対応
   - `nanopass-verification-failure` における `error` 呼び出し引数数の 2 引数規約遵守
4. **包括的単体テストスイート (`ulisp/tests/test_dataflow.scm`)**:
   - Group 1: Boolean Lattice Tests (14 passed)
   - Group 2: Flat Lattice Tests (12 passed)
   - Group 3: Powerset Lattice Tests (8 passed)
   - Group 4: Map / Environment Lattice Tests (5 passed)
   - Group 5: Forward Dataflow: Reaching Definitions (12 passed)
   - Group 6: Backward Dataflow: Liveness Analysis (7 passed)
   - **計 58/58 全テスト項目 PASS**

### 8.2 品質検証サマリー
- `make -C ulisp test_dataflow`: **58/58 PASS**
- `make -C ulisp test_alias_escape`: **23/23 PASS**
- `make -C ulisp test_pass_manager`: **46/46 PASS**
- `make -C ulisp test_passes`: **147/147 PASS**
- Nanopass 全 37 パス単体テスト: **37/37 PASS**
- `make py_compile static_analysis`: **0 errors** (radon, xenon, mypy 617 source files PASS)
- `make check_format`: **0 errors PASS**
