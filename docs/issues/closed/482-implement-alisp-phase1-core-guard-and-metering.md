---
ID: 482
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] ALisp Phase 1: コア安全プリミティブ (with-fuel, define/c) と ILisp 評価器フック基盤の実装 (ID: 482)

## 1. 概要 / Summary
[DSN-32 第12.2節](../../docs/designs/DSN-32-ailisp_agent_lisp_architecture_specification.md) に基づき、次世代AIコーディングエージェント実行環境 **ALisp** の基盤フェーズ（Phase 1: MVP）を実装する。
ILisp コア（R7RS-small）の純粋性を一切汚染しない依存性逆転（DIP）アーキテクチャに従い、`ilisp.evaluator` に `StepInterceptor`（フック）を新設した上で、計算ステップ予算制御（`with-fuel`）および Lisp 述語関数による基本契約プログラミング（`define/c`）を提供する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-32: AILISP (ALisp + ILisp) 次世代AIコーディングエージェント実行環境包括的アーキテクチャ設計書](../../docs/designs/DSN-32-ailisp_agent_lisp_architecture_specification.md) (第 3 章, 第 5 章, 第 9.1 節, 第 12.2 節)
  - [DSN-31: ILISP R7RS コアアーキテクチャ包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md)
- **対象サブシステム**:
  - `alisp/core.py`
  - `alisp/metering.py`
  - `alisp/contracts/`
  - `ilisp/evaluator.py`
  - `ilisp/reader.py`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [alisp/__init__.py](../../alisp/__init__.py) (パッケージ初期化とパブリック API)
- [x] [alisp/core.py](../../alisp/core.py) (ALisp エントリポイント・StepHook 注入)
- [x] [alisp/metering.py](../../alisp/metering.py) (`FuelExhaustedException`, `FuelCounter`, `StepInterceptor`, `with-fuel`)
- [x] [alisp/contracts/__init__.py](../../alisp/contracts/__init__.py) (`define/c` マクロ展開・契約評価, `ContractViolationException`)
- [x] [alisp/contracts/predicates.py](../../alisp/contracts/predicates.py) (標準述語結合子 `and/c`, `or/c`, `not/c`, `any/c`, `none/c`)
- [x] [ilisp/evaluator.py](../../ilisp/evaluator.py) (`StepInterceptor` オプショナルフックスロット新設, `Evaluator` クラス)
- [x] [ilisp/reader.py](../../ilisp/reader.py) (`#:keyword` 記号リーダーサポート)
- [x] [Makefile](../../Makefile) (`PYTHON_SRCS` に `alisp` を追加)
- [x] [tests/alisp/test_phase1_metering_and_contracts.py](../../tests/alisp/test_phase1_metering_and_contracts.py) (単体・統合テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/482-implement-alisp-phase1-core-guard-and-metering`

1. **`ilisp/evaluator.py` 依存性逆転フック追加**:
   - `Evaluator` クラスにオプショナルな `step_hook: Optional[Callable[[], None]]` を受容するインターフェースを追加。
   - `_current_step_hook` モジュール変数および `StepHookContext` コンテキストマネージャを提供。
   - `eval_expr` の主ループ `while True:` 先頭で `if _current_step_hook is not None: _current_step_hook()` を呼び出し（オーバーヘッド最小化）。
   - マクロ展開時に `hasattr(fn, "transform")` をサポートし、ALisp のカスタムマクロ脱糖器を受容可能にする。
   - `ilisp/reader.py` において `#:keyword` 記号構文（例: `#:post`）の読み取りをサポート。

2. **`alisp/metering.py` の実装**:
   - `FuelExhaustedException(BaseException)` の定義（Scheme の `guard` 等で誤捕縛されず確実に大域脱出する制御例外）。
   - `FuelCounter` クラスの実装: ステップ減算、階層的予算委譲（Sub-budgeting: `child_fuel = min(requested, parent_remaining)`）、親スコープからの同時減算。
   - `StepInterceptor` 実装: `Callable[[], None]` を満たし、`with_fuel_scope(steps)` コンテキストマネージャにより燃料スコープのプッシュ/ポップを管理。
   - `WithFuelTransformer`: `(with-fuel <steps> <expr>...)` を `(%with-fuel <steps> (lambda () (begin <expr>...)))` へ脱糖。

3. **`alisp/contracts/` の実装**:
   - `ContractViolationException(Exception)` の定義: `blame` (:caller / :callee)、関数名、引数インデックス、期待値、実測値、および S式 diagnostic 変換メソッド。
   - `DefineContractTransformer`: `(define/c (fn (arg pred)...) [#:post post-pred] body...)` を事前・事後条件アサーション付きの `define` に脱糖。
   - 事前条件違反時は `blame: :caller`、事後条件違反時は `blame: :callee`。
   - `alisp/contracts/predicates.py`: 述語結合子 `and/c`, `or/c`, `not/c`, `any/c`, `none/c` を Python および Scheme 両面で提供。

4. **`alisp/core.py` および `alisp/__init__.py` の実装**:
   - `ALispEngine` クラス: 環境の初期化、ALisp プリミティブ・マクロの登録、StepInterceptor の注入、`.eval()` メソッド。
   - 簡易実行関数 `eval_alisp(code, env=None, fuel=None)` の提供。

5. **Makefile 品質ゲート更新**:
   - `PYTHON_SRCS` に `alisp` を含める。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 無限再帰コード（`(letrec ((f (lambda () (f)))) (f))`）が `(with-fuel 100 ...)` により確実に `FuelExhaustedException` で安全停止すること。
- [x] `define/c` で宣言された契約において、不正な引数（例: 正の整数が期待される箇所に負数）を渡した際に即座に契約違反例外が発生し、`blame: :caller` が特定されること。
- [x] `define/c` の事後条件違反において即座に契約違反例外が発生し、`blame: :callee` が特定されること。
- [x] ネストされた `with-fuel` による階層的予算委譲（Sub-budgeting）が正しく動作し、親の残余燃料が正しく消費されること。
- [x] `ilisp` 単体の R7RS-small 公式適合性テスト（407 テストケース, 1,233+ アサーション PASS / 0 FAIL）にリグレッションが 0 件であること。
- [x] `make format`, `make static_analysis`, `make test` が 100% PASS すること。
