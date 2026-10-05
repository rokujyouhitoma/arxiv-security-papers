---
ID: 482
種別: Feature
優先度: High
ステータス: Open (New)
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

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [alisp/__init__.py](../../alisp/__init__.py) (パッケージ初期化とパブリック API)
- [ ] [alisp/core.py](../../alisp/core.py) (ALisp エントリポイント・StepHook 注入)
- [ ] [alisp/metering.py](../../alisp/metering.py) (`FuelExhaustedException`, `StepInterceptor` 実装, `with-fuel`)
- [ ] [alisp/contracts/__init__.py](../../alisp/contracts/__init__.py) (`define/c` マクロ展開・契約評価)
- [ ] [alisp/contracts/predicates.py](../../alisp/contracts/predicates.py) (標準述語結合子 `and/c`, `or/c`, `not/c`)
- [ ] [ilisp/evaluator.py](../../ilisp/evaluator.py) (`StepInterceptor` オプショナルフックスロット新設)
- [ ] [tests/alisp/test_phase1_metering_and_contracts.py](../../tests/alisp/test_phase1_metering_and_contracts.py) (単体・統合テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/482-implement-alisp-phase1-core-guard-and-metering`

1. **`ilisp/evaluator.py` 依存性逆転フック追加**:
   - `Evaluator` クラスにオプショナルな `step_hook: Optional[Callable[[], None]]` を受容するインターフェースを追加。
   - `eval_expr` またはディスパッチループ内で `if self.step_hook: self.step_hook()` を呼び出す（オーバーヘッド最小化）。
   - `ilisp` 単体テスト（R7RS 1,233 件 PASS）が無傷であることを確認。
2. **`alisp/metering.py` の実装**:
   - `FuelExhaustedException` 例外クラスの定義。
   - ステップごとに残量を減算し、0 到達時に例外を送出する `FuelCounter` / `StepInterceptor` 実装。
   - `(with-fuel <steps> <expr>)` 構文の評価・脱糖サポート。
3. **`alisp/contracts/` の実装**:
   - `define/c` 構文マクロの実装。関数の引数評価時（Pre-condition）およびリターン時（Post-condition）に述語を評価。
   - 事前条件違反時に `blame: :caller`、事後条件違反時に `blame: :callee` を判定する基本機構。
   - 述語結合子 `and/c`, `or/c`, `not/c` の実装。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 無限再帰コード（`(letrec ((f (lambda () (f)))) (f))`）が `(with-fuel 100 ...)` により確実に `FuelExhaustedException` で安全停止すること。
- [ ] `define/c` で宣言された契約において、不正な引数（例: 正の整数が期待される箇所に負数）を渡した際に即座に契約違反例外が発生すること。
- [ ] `ilisp` 単体の R7RS-small 公式適合性テスト（1,233 PASS / 0 FAIL）にリグレッションが 0 件であること。
- [ ] `make format`, `make static_analysis`, `make test` が 100% PASS すること。
