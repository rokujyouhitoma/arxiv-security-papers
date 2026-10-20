---
ID: 576
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] 軽量 IR Verifier（Pass Checker）フレームワークの導入による中間不変条件の機械的検証 (ID: 576)

## 1. 概要 / Summary
uLisp は手書き Nanopass 構成を採用しており、多数のパス（010〜160）によって段階的に AST/IR を低水準化している。しかし、専用の Nanopass Framework DSL（`define-language` 等）を持たないため、各パスの出力が「満たすべき不変条件（Invariants）」や「除去されたはずの禁止構文」を機械的に検証する機構が存在しなかった。
その結果、あるパスが未変換の構文を残存させたり不正な中間表現を生成した場合に、数パス先の後段（LIR 生成やバックエンドコード生成、最悪の場合は実行時 SEGV）で初めて破綻が発覚し、原因特定コストが肥大化していた。

本 Issue では、コンパイラの主要 IR 境界（Pass 030 Desugar 後、Pass 070 ANF 後、Pass 110 Closure Convert 後、Pass 131 Safepoint 後、Pass 132 Braun SSA 後）に挿入可能な軽量 IR Verifier（Pass Checker）フレームワークを設計・導入する。これにより、中間表現の契約違反をパス直後で 100% 局所検知・通報するセーフティネットを確立する。

---

## 2. トレーサビリティ / Traceability
- 先行研究系譜: Nanopass Compiler Framework (Keep & Dybvig, 2013) の入力/出力言語不変条件検証
- 先行研究系譜: Translation Validation & IR Well-formedness (Pnueli et al., CompCert)
- DSN-33 コンパイラアーキテクチャ仕様
- 関連ファイル:
  - [ulisp/compiler.scm](../../ulisp/compiler.scm)
  - [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm)
  - [ulisp/passes/070_anf.scm](../../ulisp/passes/070_anf.scm)
  - [ulisp/passes/110_closure_convert.scm](../../ulisp/passes/110_closure_convert.scm)
  - [ulisp/passes/131_lir_safepoint.scm](../../ulisp/passes/131_lir_safepoint.scm)
  - [ulisp/passes/132_lir_braun_ssa.scm](../../ulisp/passes/132_lir_braun_ssa.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/verifier.scm](../../ulisp/compiler/verifier.scm) (新規: IR 不変条件検証述語・エラーレポート基盤)
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (`verifier.scm` のインクルードおよび `run-pass-with-verifier` フック導入)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`COMPILER_BASE` への `verifier.scm` 追加および `test_verifier` ターゲット新設)
- [x] [ulisp/tests/test_verifier.scm](../../ulisp/tests/test_verifier.scm) (新規: 正常系および不正 AST 検出の単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/576-implement-lightweight-ir-verifier-framework`

1. **IR 検証述語群の実装 (`ulisp/compiler/verifier.scm`)**:
   - `verify-desugared-ast (ast)`:
     - `cond`, `case`, `and`, `or`, `let*`, `named-let`, `let-values`, `guard`, `parameterize` 等の糖衣構文が残存していないことを全木走査で確認。
   - `verify-anf-ast (ast)`:
     - 関数適用 `(f a1 a2 ...)` や組込み命令の引数がすべて「変数」または「即値リテラル」であり、複合式のネストがないことを検証。
   - `verify-closure-ast (ast)`:
     - ラムダ本体内の自由変数がすべて明示的な環境引数（`%env`）経由の参照に置換されていることを確認。
   - `verify-lir-safepoint (lir)`:
     - GC 可能地点（ヒープアロケーションおよび非末尾関数呼出し）に、スタックマップ復元用ルート集合注釈（`#:safepoint-roots`）が正しく付与されていることを確認。
   - `verify-ssa-ast (lir)`:
     - SSA 値の定義が一意であること、支配関係違反や未定義参照が存在しないことを検証。
2. **検証フックとエラー通報機構の統合 (`ulisp/compiler.scm`)**:
   - 環境変数 `ULISP_VERIFY=1` またはコマンドラインオプション `--verify` 指定時に、各パスの実行直後に対応する `verify-*` を呼び出す。
   - 違反検出時は、違反パス番号・ノード位置・期待される契約・実際の不正式を整形出力して実行を安全に中断（Fail-Fast）。
3. **Makefile 連携とテスト整備**:
   - `ulisp/Makefile` の `COMPILER_BASE` に `compiler/verifier.scm` を登録。
   - `test_verifier.scm` を新設し、故意に不正構文（例: desugar 後の残存 `cond` 等）を注入して Verifier が正しく捕捉できるかを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `compiler/verifier.scm` が新設され、主要 5 段階（Desugar, ANF, Closure, Safepoint, SSA）の検証関数が実装されていること
- [ ] 不正な構文・構造を含む AST を注入した際に、Verifier が期待通りエラーを捕捉・通報すること
- [ ] `ULISP_VERIFY=1` を有効にした状態で既存の `make -C ulisp test_all_passes`（全27パス）が 100% PASS すること
- [ ] 既存の AOT テストスイート（`make -C ulisp test_aot`）がデグレードなく正常動作すること
- [ ] 相対パスのみを使用し、絶対パスが含まれないこと
