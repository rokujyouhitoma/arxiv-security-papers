---
ID: 602
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] コンパイラ実行時における現在Nanopass・処理中トップレベル式・ソース位置のコンテキスト追跡とエラー診断ダンプの導入 (ID: 602)

## 1. 概要 / Summary
`ulisp_core.scm` のような数万行規模の巨大な結合ソースをネイティブコンパイラで処理する際、コンパイルエラー（例: `Unbound variable in LIR: car`）が発生しても「どの Nanopass で」「どのトップレベル定義（`define` / `define-syntax`）の処理中か」「どのソース位置か」が一切出力されない。

本 Issue では、コンパイラパイプライン全体に動的実行コンテキスト（`*current-pass*`、`*current-toplevel-form*`、`*current-expr*`）を追跡・保持する仕組みを導入する。これにより、コンパイラ内部で例外や未束縛エラーが発生した瞬間に、該当する Pass 名や問題の関数定義を自動的に標準エラー出力に診断レポートとしてダンプし、デバッグ効率を劇的に改善する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
- **関連 Issue**:
  - Issue 586: Nanopass Framework DSL Phase 4: パイプライン統御・AST Diff トレーサおよび不変条件 Verifier 自動フック統合
  - Issue 598: 統一 Pass Manager の導入によるパイプライン制御・最適化レベルスケジューリング・観測性の一元化

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm) (`define-pass` 実行時の現在パス名設定フック)
- [ ] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) (コンテキスト変数および `error` 関数の診断ダンプ統合)
- [ ] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm) (LIR 生成時のエラー呼び出しにおけるコンテキスト参照)
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm) (トップレベルループでの `*current-toplevel-form*` 更新)
- [ ] [ulisp/tests/passes/test_000_compiler_diagnostics.scm](../../ulisp/tests/passes/test_000_compiler_diagnostics.scm) (コンテキスト付きエラー出力テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/602-track-compiler-context-pass-and-toplevel-form-on-error`

1. **コンパイラコンテキストパラメータの定義**:
   - `*current-pass*`: 現在実行中の Nanopass 名（例: `"Pass 130: LIR Generation"`）。
   - `*current-toplevel-name*`: 現在コンパイル中の関数名またはトップレベル識別子。
   - `*current-form*`: 現在走査中の AST 部分木。
2. **`define-pass` およびパイプラインドライバへのフック統合**:
   - 各 Pass の入り口で `*current-pass*` を自動設定。
   - トップレベル式のコンパイルループで `*current-toplevel-name*` を更新。
3. **`compiler-diagnostic-report` 関数の実装**:
   - エラー発生時、通常のメッセージに加えて以下のような明瞭なコンテキスト枠を出力：
     ```text
     ======================================================================
     [COMPILER ERROR] Compilation aborted in Pass 130 (LIR Generation)
     ======================================================================
     Target Symbol : 'car'
     Toplevel Form : (define (my-filter pred ls) ...)
     Current Expr  : (car ls)
     ======================================================================
     ```
4. **テストスイートの作成**:
   - 故意に未定義変数を参照させた際の診断メッセージ出力を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] コンパイラ内で例外が発生した際、現在実行中の Nanopass 番号・名前、および処理中のトップレベル式が標準エラーに出力されること。
- [ ] 既存のコンパイル速度へのオーバーヘッドが 2% 未満であること。
- [ ] `make test_unit` および `bash ulisp/test.sh` が 100% PASS すること。
