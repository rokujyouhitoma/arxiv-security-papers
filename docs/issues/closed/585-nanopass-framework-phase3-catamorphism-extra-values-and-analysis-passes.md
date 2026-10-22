---
ID: 585
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-10-22
---

# [FEAT/ARCH] Nanopass Framework DSL Phase 3: Catamorphism Extra Values (上流集約 / 下流伝播) と解析・最適化パス刷新 (ID: 585)

## 1. 概要 / Summary
Nanopass Framework DSL Phase 1 (Issue #581) および Phase 2 (Issue #584) では、構文変換（Transform Pass）を中心とした DSL 基盤（`define-language`, `define-pass`, `terminals`, `extends`, `guard`, `in-context`, `...`）を確立した。
しかし、実用的なコンパイラ最適化パイプラインには、構文の書き換えのみならず「親から子への文脈情報の伝播」と「子から親への解析結果の集約」を同時に行う **属性文法（Attribute Grammars）的な解析パス（Analysis Passes）** が不可欠である。

本 Issue（Phase 3）では、Catamorphism（再帰走査）における **Extra Values（多値・解析情報のアナライザ支援機構）** を Nanopass DSL にネイティブ実装した：
1. **下流伝播 (Downwards / Inherited Attributes)**:
   - スコープ環境（`env` / `bound`）、型注釈マップ、燃料（`fuel`）予算、Tailフラグ等を親から子ノードへ透過的に引き渡す機能。
2. **上流集約 (Upwards / Synthesized Attributes)**:
   - 式に含まれる「自由変数の集合（Free Variables）」や「副作用の有無（Purity/Effect）」などを子ノードの戻り値として親ノードに返却（単一値または多値 `values`）し、親側で自動畳み込み・スレッドする機構。
3. **純粋アナライザ構文 (`*`)**:
   - S 式の変形を行わず、解析値のみを返すパスを定義可能にする `(define-pass name : L_in (ir extra_in ...) -> * (extra_out ...))` 記法。

これにより、これまで手書きの複雑な走査ループで記述されていた解析・最適化パス群（Pass 040_analysis, Pass 050_cp0, Pass 100_contify）を Nanopass DSL の宣言的かつ型安全な構文規則へ全面刷新し、コード行数の大幅削減と不変条件の明示化を達成した。

---

## 2. トレーサビリティ / Traceability
- 先行研究系譜: Keep & Dybvig, "A Nanopass Framework for Commercial Compiler Development" (ICFP 2013 / Chez Scheme) Section 3 "Extra Return Values and Arguments"
- DSN-33 コンパイラアーキテクチャ仕様書 (第8章 最適化パス群)
- 関連 Issue:
  - [581-implement-nanopass-framework-dsl-and-migrate-compiler-passes.md](581-implement-nanopass-framework-dsl-and-migrate-compiler-passes.md) (Phase 1: コア DSL 基盤)
  - [584-nanopass-framework-phase2-ellipsis-subforms-and-normalization.md](584-nanopass-framework-phase2-ellipsis-subforms-and-normalization.md) (Phase 2: エリップシス・サブフォーム)
  - [586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks.md](../586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks.md) (Phase 4: AST Diff トレーサ・不変条件検証)
  - [576-implement-lightweight-ir-verifier-framework.md](576-implement-lightweight-ir-verifier-framework.md) (IR Verifier)
- 関連ファイル:
  - [ulisp/compiler/nanopass.scm](../../../ulisp/compiler/nanopass.scm)
  - [ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm)
  - [ulisp/passes/015_dsl_expander.scm](../../../ulisp/passes/015_dsl_expander.scm)
  - [ulisp/passes/040_analysis.scm](../../../ulisp/passes/040_analysis.scm)
  - [ulisp/passes/050_cp0.scm](../../../ulisp/passes/050_cp0.scm)
  - [ulisp/passes/100_contify.scm](../../../ulisp/passes/100_contify.scm)
  - [ulisp/tests/test_nanopass_framework.scm](../../../ulisp/tests/test_nanopass_framework.scm)

---

## 3. セキュリティ / 脅威モデル分析 (Threat Model)
- **静的スコープ・自由変数解析の健全性 (Analysis Soundness)**:
  - コンパイラにおけるスコープ解析・自由変数解析の誤り（偽陰性 / False Negative）は、本来クロージャにキャプチャされるべき変数の脱落を引き起こし、実行時の未束縛変数例外や不正メモリアクセス（SEGV / UAF 等の脆弱性）を誘発する。
  - **対策**: Nanopass DSL の自動 Catamorphism 合成により、ユーザーが言及しなかった未知の複合構文や拡張命令に対しても再帰走査が漏れなく自動適用され、解析の抜け穴（Escaped Variables）を構造的に排除。
- **無限再帰・スタックオーバーフローの防止**:
  - Catamorphism 走査中に自己参照型 AST や循環リストが侵入した場合のスタック枯渇リスク。
  - **対策**: 構文妥当性検証および深さ優先探索におけるペア不変条件チェックを徹底。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/nanopass.scm](../../../ulisp/compiler/nanopass.scm):
  - `nanopass-parse-pass-header`: `extra_in` および `extra_out`、純粋アナライザターゲット `*` の解析サポート。
  - `nanopass-parse-nt-clause`: 非終端記号ハンドラにおける追加引数・戻り値リストの解析。
  - `nanopass-build-rules-cascade`: `extra_in` 引数のハンドラ伝播および未マッチ時 Catamorphism への引数渡し。
  - `nanopass-expand-define-pass`: `lambda (ir extra_in ...)` 形式の多引数プロシージャ生成およびエントリー呼び出しの多値配線。
- [x] [ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm):
  - `nanopass-catamorphism-step`: `extra_in` を伴う再帰呼び出し、および純粋アナライザ (`*`) におけるアキュムレータスレッド走査。
  - `nanopass-try-clause`: パターン変数に加えてスコープ引数をハンドラへ安全に適用。
- [x] [ulisp/passes/040_analysis.scm](../../../ulisp/passes/040_analysis.scm):
  - `free-vars-acc`: Nanopass DSL (`(define-pass free-vars-acc : L_core (ir bound acc) -> * (acc) ...)`) 化。
  - `escapes?`: Nanopass DSL (`(define-pass analyze-escapes : L_core (ir var) -> * (escapes?) ...)`) 化。
  - `tail-calls-only?`: Nanopass DSL (`(define-pass tail-calls-only-impl : L_core (ir var tail?) -> * (ok?) ...)`) 化。
- [x] [ulisp/passes/050_cp0.scm](../../../ulisp/passes/050_cp0.scm):
  - `cp0-expr`: Nanopass DSL (`(define-pass cp0-opt : L_core (ir) -> L_core () ...)`) 化。
- [x] [ulisp/passes/100_contify.scm](../../../ulisp/passes/100_contify.scm):
  - `contify-calls`: Nanopass DSL (`(define-pass contify-subst : L_core (ir var) -> L_core () ...)`) 化。
- [x] [ulisp/tests/test_nanopass_framework.scm](../../../ulisp/tests/test_nanopass_framework.scm):
  - Extra Values（下流伝播 `inherited`、上流集約 `synthesized`、純粋アナライザ `*`）の包括的単体テスト。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/585-nanopass-framework-phase3-catamorphism-extra-values-and-analysis-passes`

### Step 1: Extra Values 構文解析器の拡張 (`ulisp/compiler/nanopass.scm`)
1. `nanopass-parse-pass-header`:
   - `(define-pass name : L_in (ir extra_in ...) -> L_out (extra_out ...) clauses ...)`
   - `(define-pass name : L_in (ir extra_in ...) -> * (extra_out ...) clauses ...)`
   - 入力変数リスト `(ir extra_in ...)` および出力変数リスト `(extra_out ...)` を抽出。
2. `nanopass-parse-nt-clause`:
   - `(NT : NT_in (ir extra_in ...) -> NT_out (extra_out ...) rules ...)`
   - `(NT : NT_in (ir extra_in ...) -> * (extra_out ...) rules ...)`
   - 非終端記号ハンドラのシグネチャを抽出し、引数リスト `(ir extra_in ...)` を確定。
3. `nanopass-expand-define-pass`:
   - 生成するプロシージャ定義を `(define (name ir extra_in ...) (letrec (...) (entry ir extra_in ...)))` へ拡張。

### Step 2: Catamorphism 走査エンジンへの多引数・集約伝播の組み込み (`ulisp/compiler/nanopass_meta.scm`)
1. `nanopass-catamorphism-step`:
   - シグネチャを `(nanopass-catamorphism-step lang-in lang-out nt-name ir recurse-fn extra-args extra-out)` に拡張。
   - `lang-out` が `*` の場合:
     - ユーザーがハンドラを定義しなかった節について各部分式を走査。
     - アキュムレータ方式（`extra-args` の末尾要素をアキュムレータとして各子ノードへスレッド）により安全にフォールスルー集約。
     - アトム（非ペア）ノード遭遇時はアキュムレータを保存（`extra-out` があればアキュムレータを返却、純粋クエリなら `#f`）。
   - `lang-out` が非終端記号（例: `Expr`）の場合:
     - 子ノードを `(apply recurse-fn (cons child extra-args))` で再帰走査し、親ノードの S 式を再構築。

### Step 3: DSL 単体テストスイートの拡充 (`ulisp/tests/test_nanopass_framework.scm`)
1. 下流伝播テスト: `(define-pass test-inherited-depth : L_test_src (ir depth) -> L_test_src () ...)`
2. 上流集約テスト: `(define-pass test-count-symbols : L_test_src (ir acc) -> * (acc) ...)`
3. 複合解析テスト: `(define-pass test-analyze-frees : L_test_src (ir bound acc) -> * (acc) ...)`

### Step 4: パイプライン解析・最適化パスの Nanopass DSL 移行
1. **Pass 040 (`040_analysis.scm`)**:
   - `free-vars-acc` を `define-pass free-vars-acc` で再実装。
   - `escapes?` を `define-pass analyze-escapes` で再実装。
   - `tail-calls-only?` を `define-pass tail-calls-only-impl` で再実装。
2. **Pass 050 (`050_cp0.scm`)**:
   - `cp0-expr` を `define-pass cp0-opt` で再実装。
3. **Pass 100 (`100_contify.scm`)**:
   - `contify-calls` を `define-pass contify-subst` で再実装。

### Step 5: 品質検証 & ブートストラップ固定点確認
1. 単体テスト: `make -C ulisp test_nanopass` (34/34 PASS)
2. パス別テスト: `make -C ulisp test_passes` (33/33 1:1 tests + 147 integration tests PASS)
3. ネイティブAOTテスト: `make -C ulisp test_aot` (Phase 1-7 ALL PASS)
4. 3-Stage Bootstrap: `make -C ulisp bootstrap_verify` (Stage 2 vs Stage 3 bit-for-bit identical FIXED-POINT PASS)

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `define-pass` で下流伝播引数 (`extra_in ...`) および上流集約多値 (`extra_out ...`) が透過的に扱えること
- [x] 純粋アナライザターゲット `*` がサポートされ、S 式を出力しない解析専用パスが定義できること
- [x] 未指定節に対する Catamorphism 走査コードが属性の自動伝播・集約を正しく行うこと
- [x] Pass 040 (`040_analysis.scm`), Pass 050 (`050_cp0.scm`), Pass 100 (`100_contify.scm`) が Nanopass DSL で書き直され、正しく動作すること
- [x] `make -C ulisp test_nanopass` が全 PASS すること
- [x] 全パス単体テスト（`make -C ulisp test_passes`）が 100% PASS すること
- [x] 3-Stage Bootstrap 固定点検証（`make -C ulisp bootstrap_verify`）が 100% PASS すること
- [x] 相対パスのみを使用し、絶対パスが含まれないこと
