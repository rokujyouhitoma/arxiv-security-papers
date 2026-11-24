---
ID: 942
種別: Feature
優先度: High
ステータス: Closed (2026-11-25)
作成日: 2026-11-25
担当: Project Manager (PM), IT Specialist (PLC), Systems Architect, Software Development (SWD), Software Quality Assurance Specialist, Information Security Specialist
---

# [FEAT/ENH] 混合器 (mix) の完成：`specialize-or-widen` の `eval-in-stage-apply` 接続と第1二村射影実証・DSN-33-24 Phase I3 整合化 (ID: 942)

## 1. 概要・現状診断 / Context & Codebase Diagnosis

[eval_in_language.scm](../../../ulisp/compiler/eval_in_language.scm)（統合生成先: [compiler.scm](../../../ulisp/compiler.scm)）および [test_futamura_projection.scm](../../../ulisp/tests/test_futamura_projection.scm) の調査結果、真の混合器 (`mix`) による第1二村射影の完成に向けて、以下の 4 点の未接続・不足箇所が確認された（第2・第3射影の自己適用は本 Issue の対象外）：

1. **`eval-in-stage-apply` (`Later` 段) から `specialize-or-widen` への未接続**
   - `specialize-or-widen` ([eval_in_language.scm](../../../ulisp/compiler/eval_in_language.scm#L2069-L2090)) は [test_specialization_widening.scm](../../../ulisp/tests/test_specialization_widening.scm) から手組み `builder` クロージャ経由で呼び出されるのみで、`eval-in-stage-apply` ([eval_in_language.scm](../../../ulisp/compiler/eval_in_language.scm#L1316-L1353)) からは一切参照されていない。
   - 現行の `Later` 辞書パス（L1339–1346）では、トップレベルまたはステージ環境に束縛されたユーザー定義関数（例: `micro-interp-eval`）に対して少なくとも 1 つの静的引数・PSDS 引数が与えられても、無条件に残余呼び出し `(call-anf callee arg ...)` を出力してしまい、静的解釈展開が行われない。

2. **PSDS 値の `let`/`let*` 束縛伝搬とペア複合アクセサの未対応**
   - `eval-in-stage-let`（L1400–1408）および `eval-in-stage-let*`（L1450–1458）は `stage-val-pure-static?` のみを環境 `curr-env` へ直接束縛し、`stage-val-partially-static?`（PSDS メタペア）を動的扱いにしてしまうため、`micro-interp-eval` の `(let* ((b (car stack)) (a (cadr stack)) (stk (cddr stack))) ...)` や `(let ((entry (assq (cadr inst) env))) ...)` において `<stage-val>` が残余 AST (`let-anf`) へリークするか、コンパイル時分解が途切れる。
   - `eval-in-stage-apply-known-prim`（L1148–1184）では `car` / `cdr` のみが PSDS スパイン分解（`stage-car` / `stage-cdr`）に対応しており、`caar` / `cadr` / `cdar` / `cddr` / `caddr`（`IF-ZERO` で必須）の PSDS 分解および `caddr` 自体のプリミティブ登録（`stage-known-primitive?`, `stage-pure-effect-free?`, `ctfe-apply-primitive`, `now-dict-apply-prim-1`）が不足している。

3. **`eval-in-stage` における評価形式サポートのギャップ**
   - 未改変の Scheme インタプリタ `micro-interp-eval` をそのまま部分評価するには、`eval-in-stage`（L1503–1643）側で `(cond ...)`, `(and ...)`, `(or ...)`, 多式本体を含む `lambda` / `let` / `let*`、およびトップレベル `(define (fn params ...) body ...)` 登録（または `%stage-fn` 記述子の環境束縛）が必要である。

4. **テストおよび設計書ステータスとの乖離**
   - [test_futamura_projection.scm](../../../ulisp/tests/test_futamura_projection.scm)（L51–156）は未改変の `micro-interp-eval` を部分評価するのではなく、手書きの二段階変換器 `micro-bytecode->stage-poly` を呼んでおり、設計書 [DSN-33-24](../../designs/DSN-33-24-ulisp_futamura_projection_scheme_interpreter_synthesis_architecture.md#L509) §8.1 では `Phase I3` が「完了」と先行記載されている。なお、`assq` / `memq` が `stage-known-primitive?` と `stage-pure-effect-free?` に登録済みである点は実コードで確認済み。

---

## 2. トレーサビリティとセキュリティ分析 / Traceability & Security Analysis

- **関連資料・関連 Issue**:
  - [DSN-33-24 §8.1](../../designs/DSN-33-24-ulisp_futamura_projection_scheme_interpreter_synthesis_architecture.md#L503-L510)
  - [DSN-33-21](../../designs/DSN-33-21-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md)
  - [Issue #877](877-implement-specialization-memoization-and-widening-engine.md)（特殊化メモ化・上限・汎化エンジン）
  - [Issue #885](885-demonstrate-e2e-first-futamura-projection-on-micro-language.md)（Micro-Language 第1二村射影 E2E）
  - [Issue #892](892-implement-guest-frame-descriptor-and-local-slot-lowering.md)（Guest Frame Descriptor & `assq` スロット低下）
  - [Issue #895](895-implement-direct-cogen-driver-and-compiler-cli-generator.md)（Direct Cogen & `--cogen` CLI）
  - [Issue #937](937-design-dsn-33-24-futamura-scheme-interpreter-synthesis.md)（DSN-33-24 アーキテクチャ設計）

- **セキュリティ・健全性要件 (Security Requirements & Mitigations)**:
  - **CWE-400 (リソース枯渇 / 部分評価の無限展開)**: 動的ループや深い再帰を含むインタプリタを特殊化する際、`specialize-or-widen` の `*max-spec-instances*` (= 8)・`*max-spec-depth*` (= 4) による汎化 (`'widened`) フォールバック、ならびに `*ctfe-default-step-limit*` (= 10,000)・`*ctfe-default-depth-limit*` (= 256) の fuel/depth ガードを必ず経由させ、停止性とコンパイル時間の上界を保証する。
  - **CWE-703 (例外・未定義命令 / CSP 境界処理不備)**: 不正なバイトコードや動的分岐下の `(error ...)`・CSP 違反（`stage-csp-error?`）に遭遇した場合でもホストコンパイラをクラッシュさせず、`Later` 段の安全な残余コード化または構造化診断（`%stage-csp-error`）へフォールバックさせる。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [eval_in_language.scm](../../../ulisp/compiler/eval_in_language.scm) (`eval-in-stage-apply`, `eval-in-stage-let`, `eval-in-stage-let*`, `eval-in-stage`, `eval-in-stage-apply-known-prim`, `stage-known-primitive?`, `stage-pure-effect-free?`, `specialize-or-widen`, `eval-residual-anf-expr`)
- [x] [compiler.scm](../../../ulisp/compiler.scm) (`make -C ulisp compiler.scm` による統合再生成対象)
- [x] [test_futamura_projection.scm](../../../ulisp/tests/test_futamura_projection.scm) (未改変 `micro-interp-eval` 入力による真の mix 第1二村射影テスト追加、および手書き `micro-bytecode->stage-poly` オラクル・`cogen.scm` 意味等価性の双対検証)
- [x] [test_specialization_widening.scm](../../../ulisp/tests/test_specialization_widening.scm) (`eval-in-stage-apply` 経由の特殊化メモ化・キャッシュヒット・汎化回帰テスト追加)
- [x] [cogen.scm](../../../ulisp/workbench/cogen.scm) (双対検証対象・手書き維持)
- [x] [DSN-33-24](../../designs/DSN-33-24-ulisp_futamura_projection_scheme_interpreter_synthesis_architecture.md) (§8.1 `Phase I3` ステータスを一旦「部品完了・未接続」へ是正後、全実装・全ゲート完了時に「完了」へ同期)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/942-connect-specialize-or-widen-in-eval-in-stage-apply`

1. **`DSN-33-24` §8.1 ステータスの是正（着手時）**
   - [DSN-33-24](../../designs/DSN-33-24-ulisp_futamura_projection_scheme_interpreter_synthesis_architecture.md#L509) §8.1 の `Phase I3` 行のステータスを実態に合わせて「部品完了・未接続」（関連 Issue に `#942` を追記）へ一旦訂正する。

2. **PSDS 伝搬・プリミティブ・構文サポートの拡充 ([eval_in_language.scm](../../../ulisp/compiler/eval_in_language.scm))**
   - `caddr` を `stage-known-primitive?` (L983)、`stage-pure-effect-free?` (L1006)、`ctfe-apply-primitive` (L212 付近)、`now-dict-apply-prim-1` (L685 付近)、および `eval-residual-anf-expr` に追加する。
   - `eval-in-stage-apply-known-prim`（L1148–1160 付近）にて、`caar` / `cadr` / `cdar` / `cddr` / `caddr`（および 0 以上の整数・ペアに対する `assq` の PSDS キー探索）が PSDS 引数に対して `stage-car` / `stage-cdr` を合成して残余 `car`/`cdr` なしでスパイン簡約できるよう拡張する（`assq` の対象連想リストも静的部分と動的値の PSDS ペアを走査可能にする）。
   - `eval-in-stage-let` / `eval-in-stage-let*`（L1400, L1450）において、`stage-val-partially-static?` の束縛値も `stage-val-pure-static?` と同様にそのまま `curr-env` に保持し、残余 `let-anf` への `<stage-val>` 生出力を防ぐ。
   - `eval-in-stage` に `(cond ...)`, `(and ...)`, `(or ...)`、複数式ボディの `let`/`let*`/`lambda`、ならびに特殊化可能関数定義 `(%stage-fn params body env name)` を扱うディスパッチを追加する。

3. **`eval-in-stage-apply` (`Later` 段) から `specialize-or-widen` への接続 ([eval_in_language.scm](../../../ulisp/compiler/eval_in_language.scm))**
   - 現在アクティブな `<spec-memo-table>` と特殊化深度を保持するセル（`*active-spec-memo-cell*` / `*active-spec-body-cache-cell*` / `*active-spec-arg-sizes-cell*` および `with-spec-memo-table` / `get-last-spec-memo-table`）を追加する（uLisp セルフホスト規約に基づき `cons` セル＋`set-car!` を使用しトップレベル `set!` を避ける）。
   - `eval-in-stage-apply`（L1325–1346）にて `callee-sv` が `stage-val` (`%ctfe-closure`) であり、かつ `Later` 辞書・少なくとも 1 引数が静的または PSDS・メモ表がアクティブである場合、`specialize-or-widen` を呼び出す。
   - 非構造的再帰（数値カウントダウン・一般再帰）には `call-spec-depth = cur-depth` を渡し `*max-spec-depth* = 4` / `*max-spec-instances* = 8` で確実に `'widened` へフォールバックさせ、構造的リスト縮小（例：`micro-interp-eval` の命令列消費）には有限終了を阻害しないよう深さ制限と区別する。

4. **第1二村射影・特殊化汎化・双対検証テストの刷新**
   - [test_futamura_projection.scm](../../../ulisp/tests/test_futamura_projection.scm) に、**未改変の `micro-interp-eval` 定義（quoted AST）を `mix` (`eval-in-stage` Later 段 + `specialize-or-widen`) に直接渡して `prog-arith` / `prog-branch` を部分評価する新検証**を追加し、全オペコード消滅・`micro-bytecode->stage-poly` オラクル一致・インタプリタ直接実行一致・`cogen.scm` (`derive-cogen-compiler` + `lir-eval`) との意味等価性双対検証を実施する。
   - [test_specialization_widening.scm](../../../ulisp/tests/test_specialization_widening.scm) に、`eval-in-stage-apply` 経由の実プログラム部分評価におけるメモ化再利用（キャッシュヒット）および `*max-spec-instances*=8` / `*max-spec-depth*=4` 到達時の汎化フォールバック検証グループ (Group 6) を追加する。

5. **再生成・全ゲート検証・ドキュメント同期**
   - `make -C ulisp compiler.scm` で `ulisp/compiler.scm` を再生成し、全単体テスト・3 段階自己ホストブートストラップ・品質ゲートを通過後、[DSN-33-24](../../designs/DSN-33-24-ulisp_futamura_projection_scheme_interpreter_synthesis_architecture.md#L509) §8.1 `Phase I3` を「完了」へ同期する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `eval-in-stage-apply`（`Later` 段）が静的または PSDS 引数を伴うユーザー定義関数適用時に `specialize-or-widen` を経由し、メモ化・インスタンス上限 (`*max-spec-instances*` = 8)・深度上限 (`*max-spec-depth*` = 4) による汎化を動作させること（CWE-400）。
- [x] 未改変の `micro-interp-eval` に対する `mix` 部分評価結果において、残余コードにバイトコードオペコード記号（`PUSH-CONST`, `LOAD-VAR`, `ADD`, `SUB`, `MUL`, `IF-ZERO`, `HALT`）が 0 個（完全消滅）であること。
- [x] 未改変 `micro-interp-eval` の部分評価結果が、既存の手書き `micro-bytecode->stage-poly` オラクル・インタプリタ直接実行・`cogen.scm` (`derive-cogen-compiler` + `lir-eval`) との意味等価性双対検証に全テストケースで合格すること。
- [x] `make -C ulisp test_futamura_projection test_specialization_widening test_all_passes bootstrap_verify_modular` が 100% PASS（3段階自己コンパイル不動点 `stage2_*.s == stage3_*.s` 維持）すること。
- [x] `make py_compile check_format static_analysis` および `make -C ulisp lint_sexpr verify_zero_gauche` がエラー 0 件で PASS すること。
- [x] [DSN-33-24](../../designs/DSN-33-24-ulisp_futamura_projection_scheme_interpreter_synthesis_architecture.md#L509) §8.1 の `Phase I3` ステータスが実態と整合（作業開始時に「部品完了・未接続」へ訂正後、完了時に「完了」へ同期）され、全リンクが相対パスのみ（絶対パス 0 件）であること。

---

## 6. 検証結果 / Verification Results

- `make -C ulisp test_futamura_projection`: ALL PASSED (Group 1 linear + Group 2 branching unmodified `micro-interp-eval` specialization via `mix` + Group 3 dual verification with `derive-cogen-compiler` & `lir-eval`; 0 opcodes `PUSH-CONST`/`LOAD-VAR`/`ADD`/`SUB`/`MUL`/`IF-ZERO`/`HALT` remaining)
- `make -C ulisp test_specialization_widening`: ALL PASSED (Groups 1–5 + Group 6 end-to-end `eval-in-stage-apply` memoization reuse, `*max-spec-instances*=8`, and `*max-spec-depth*=4` widening)
- Stage & Partial Evaluation suites: `test_eval_in_language` (53/53), `test_stage_dict`, `test_psds_provenance`, `test_eval_in_stage`, `test_single_source_oracle`, `test_bta_lattice`, `test_speculative_trap_demotion`, `test_csp_boundary_validator`, `test_stage_poly_lower`, `test_stage_oracle`, `test_residual_anf_to_lir` ALL PASSED
- `make -C ulisp test_passes test_self_hosting_fixed_point lint_sexpr verify_zero_gauche`: ALL PASSED
- `make -C ulisp -j4 bootstrap_verify_modular`: 3-stage modular self-hosting fixed point (`stage2_*.s == stage3_*.s`) PASS across all 5 modular compiler units
- `make check_format py_compile static_analysis`: ALL PASSED (0 issues in 617 source files)
