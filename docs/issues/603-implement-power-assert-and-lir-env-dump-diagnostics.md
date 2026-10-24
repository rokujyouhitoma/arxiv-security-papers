---
ID: 603
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Power Assert 風アサーション式展開および LIR 変数解決失敗時のローカル環境（env）自動ダンプ機能の実装 (ID: 603)

## 1. 概要 / Summary
コンパイル時やテスト時において、アサーション違反や未束縛変数例外（`Unbound variable in LIR`）が発生した際、単に条件不成立やシンボル名が告げられるだけでは「なぜその条件が不成立だったのか」「環境に何が存在していたのか」が即座に把握できない。

本 Issue では、Power Assert の概念を導入し、アサーション失敗時に対象式および部分式の評価値をツリー状に自動展開するマクロを実装する。また、LIR 生成フェーズ（`lir-compile-variable` 等）において未束縛変数が検出された際、その時点で有効だったローカル変数バインディング（`env`）一覧と、タイポ候補（類似シンボル名）を提示するリッチな診断ダンプ機構を構築する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [LIR 命令セット仕様書](../../ulisp/docs/spec_lir.md)
- **関連 Issue**:
  - Issue 576: 軽量 IR Verifier フレームワークの導入による中間不変条件の機械的検証
  - Issue 593: LIR層: define-language L_lir_canonical の導入と lir_verifier 宣言的統合
  - Issue 597: IR Verifier 基盤の共通化・階層分離と LIR 検証パフォーマンス最適化

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) (`power-assert` マクロおよび診断フォーマッタの実装)
- [ ] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm) (`lir-compile-variable` における `env` ダンプフック)
- [ ] [ulisp/tests/passes/test_power_assert.scm](../../ulisp/tests/passes/test_power_assert.scm) (新規: Power Assert 単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/603-implement-power-assert-and-lir-env-dump-diagnostics`

1. **Power Assert マクロの設計と実装**:
   - `(power-assert (op arg1 arg2 ...))` 形式のマクロ。
   - 失敗時に各引数の評価値を捕捉し、以下のようにグラフィカルに展開出力：
     ```text
     Assertion Failed: (assq var env)
                        |    |   |
                        |    car ((ls . (param . -8)) (pred . (param . -16)))
                        #f
     ```
2. **LIR 未束縛変数時の有効環境ダンプ**:
   - `lir-compile-variable` で `(assq var env)` が `#f` だった場合、以下の情報を出力：
     - 未解決シンボル: `var`
     - 有効なローカル束縛一覧: `(ls -> param -8, pred -> param -16)`
     - 類似シンボル候補（レーベンシュタイン距離に基づく Did you mean サジェスト）
3. **コンパイラおよびテストスイートへの適用**:
   - コンパイラ検証用の内部アサーションに順次適用。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `power-assert` マクロが正常に動作し、失敗時に部分式の評価値が明確にインデント展開されること。
- [ ] LIR 変数解決失敗時に、有効な `env` の中身が一覧表示され、原因特定が容易になること。
- [ ] `make test_unit` および `bash ulisp/test.sh` が 100% PASS すること。
