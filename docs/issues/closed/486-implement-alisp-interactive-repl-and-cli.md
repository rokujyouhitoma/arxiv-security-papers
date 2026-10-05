---
ID: 486
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] ALisp 対話型 REPL (alisp.repl, python -m alisp) および CLI 実行インターフェースの実装 (ID: 486)

## 1. 概要 / Summary
ALisp（Agent Lisp）環境を対話型（REPL: Read-Eval-Print Loop）およびコマンドラインインターフェース（CLI）から直接操作・検証できる実行環境を提供する。
複数行にわたる括弧の自動バランシング、ステップ燃料消費監視（`FuelExhaustedException` の安全な捕捉とフォーマット表示）、契約違反診断（`ContractViolationException` および S式 diagnostic の表示）、ならびにスクリプトファイル実行・ワンライナー評価（`-e` オプション）をサポートする。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-32: AILISP (ALisp + ILisp) 次世代AIコーディングエージェント実行環境包括的アーキテクチャ設計書](../../docs/designs/DSN-32-ailisp_agent_lisp_architecture_specification.md) (第 3 章, 第 5 章, 第 9 節)
  - [DSN-31: ILISP R7RS コアアーキテクチャ包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md)
- **対象サブシステム**:
  - `alisp/repl.py`
  - `alisp/__main__.py`
  - `alisp/__init__.py`
  - `tests/alisp/test_repl.py`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [alisp/repl.py](../../alisp/repl.py) (REPL ループ, コマンドライン引数パーサー, エラー・診断出力ハンドラ)
- [x] [alisp/__main__.py](../../alisp/__main__.py) (`python -m alisp` エントリポイント)
- [x] [alisp/__init__.py](../../alisp/__init__.py) (`repl` 関数のエクスポート)
- [x] [tests/alisp/test_repl.py](../../tests/alisp/test_repl.py) (CLI 実行および REPL 挙動の自動テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/486-implement-alisp-interactive-repl-and-cli`

1. **`alisp/repl.py` の実装**:
   - `repl(engine=None, default_fuel=None)`: 対話型ループ。括弧の開閉数追跡による複数行入力対応。
   - `_handle_repl_eval`: `FuelExhaustedException` を捕捉して REPL プロセスを落とさず `[FuelExhausted]` を表示。
   - `ContractViolationException` を捕捉して `[ContractViolation]` および `e.to_diagnostic()` S式を表示。
   - `main()`: `argparse` による CLI パーサー (`file`, `-e/--eval`, `--fuel` オプション)。
2. **`alisp/__main__.py` の実装**:
   - `python -m alisp` で直接起動可能にする。
3. **`alisp/__init__.py` の同期**:
   - パブリック API として `repl` を `__all__` に含める。
4. **テストスイート拡充**:
   - `tests/alisp/test_repl.py` を追加し、`-e` による式評価、燃料枯渇時の非ゼロ終了コード、契約違反時の診断出力、および `repl()` の入出力シミュレーションを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `python -m alisp -e "(+ 1 2)"` で `3` が正しく標準出力されること。
- [x] `python -m alisp -e "(with-fuel 10 (letrec ((f (lambda () (f)))) (f)))"` でプロセスがクラッシュせず `[FuelExhausted]` メッセージと非ゼロ終了コードで終了すること。
- [x] `python -m alisp -e "(begin (define/c (f (x number?)) x) (f 'bad))"` で契約違反メッセージが出力され非ゼロ終了コードで終了すること。
- [x] `python -m alisp` または `alisp.repl()` で対話型 REPL が起動し、複数行括弧バランシング、`(exit)` による正常終了ができること。
- [x] `make check_format`, `make py_compile`, `make static_analysis`, `make test` が 100% PASS すること。
