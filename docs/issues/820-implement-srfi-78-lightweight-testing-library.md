---
ID: 820
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] SRFI 78 軽量テストライブラリ (srfi 78) の実装と SRFI 64 テストランナー・Power Assert 連携 (ID: 820)

## 1. 概要 / Summary
単一ファイルでの手軽な動作確認や、Nanopass コンパイラの各パス単体検証（S 式変換前後の AST 比較など）を直感的に記述できるよう、**SRFI 78: Lightweight testing** を ULisp 標準ライブラリ（`ulisp/lib/check.scm` および `ulisp/lib/srfi/78.sld`）として実装する。
`(check <expr> => <expected>)` や `(check <expr> (=> <equal-pred>) <expected>)` の矢印構文により、テスト名文字列を省略しつつ対象式自体を自己文書化し、さらに失敗時には [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) の Power Assert 診断と [Issue #819](819-implement-srfi-64-test-suites-library-and-custom-test-runners.md) の SRFI 64 `test-runner` へ自動連携する仕組みを提供する。

---

## 2. トレーサビリティ / Traceability
- [SRFI 78: Lightweight testing](https://srfi.schemers.org/srfi-78/srfi-78.html)
- [Issue #819 R7RS-large / SRFI 64 テストスイート標準ライブラリ (srfi 64) の実装](819-implement-srfi-64-test-suites-library-and-custom-test-runners.md)
- [ULisp R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md)
- [ULisp テストおよび検証ガイド](../../ulisp/docs/guide_testing.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/check.scm](../../ulisp/lib/check.scm) (新規作成: SRFI 78 `check`, `check-ec`, `check-report`, `check-set-mode!` 実装)
- [ ] [ulisp/lib/srfi/78.sld](../../ulisp/lib/srfi/78.sld) (新規作成: `(srfi 78)` ライブラリ定義)
- [ ] [ulisp/tests/test_srfi_78.scm](../../ulisp/tests/test_srfi_78.scm) (新規作成: SRFI 78 単体テストおよび SRFI 64 連携テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_srfi_78` ターゲットおよび `lint_sexpr` への登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/820-implement-srfi-78-lightweight-testing-library`

1. **SRFI 78 標準構文・手続きの実装**:
   - `(check <expr> => <expected>)` およびカスタム等価述語指定 `(check <expr> (=> <equal>) <expected>)` マクロを実装する。
   - `check-report`, `check-set-mode!`（`'off`, `'summary`, `'report-failed`, `'report` の 4 モード）、`check-reset!`, `check-passed?` を仕様通り実装する。
   - 反復内包表記による軽量チェック `check-ec` の基本構文をサポートする。
2. **SRFI 64 `test-runner` および Power Assert との統合**:
   - `test-runner-current` がアクティブな状態で `check` が呼ばれた場合、SRFI 64 ランナーのテスト結果カウンタへ自動集約するブリッジを実装する。
   - 失敗時のレポート出力において、式構造と評価結果を分かりやすく表示する診断出力を統合する。
3. **単体テストの追加**:
   - `ulisp/tests/test_srfi_78.scm` を作成し、全レポートモード、カスタム比較述語、および SRFI 64 との混在実行を検証する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(import (srfi 78))` により `check`, `check-ec`, `check-report`, `check-set-mode!`, `check-reset!`, `check-passed?` が仕様通り動作すること。
- [ ] `make -C ulisp test_srfi_78` および `make -C ulisp test_r7rs_traceability lint_sexpr` が 100% PASS すること。
- [ ] ドキュメント内のすべてのリンクが相対パスで記述されていること。