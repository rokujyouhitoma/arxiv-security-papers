---
ID: 819
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large / SRFI 64 テストスイート標準ライブラリ (srfi 64) と拡張テストランナー・互換ブリッジの実装 (ID: 819)

## 1. 概要 / Summary
Scheme におけるユニットテストのデファクトスタンダードである **SRFI 64: A Scheme API for test suites** を ULisp 標準ライブラリ（`ulisp/lib/test.scm` および `ulisp/lib/srfi/64.sld`）として完全実装する。
テストのグループ化・階層化（`test-begin` / `test-end` / `test-group` / `test-group-with-cleanup`）、標準アサーションマクロ群（`test-equal`, `test-eqv`, `test-eq`, `test-approximate`, `test-assert`, `test-error`）、条件付きスキップ・期待される失敗（`test-skip`, `test-expect-fail`）、およびテストランナー（`test-runner`）のカスタマイズ機構を整備し、Gauche (`gosh`) や Chibi-Scheme 等の外部処理系とも 100% ポータブルに相互運用できるテスト基盤を確立する。

---

## 2. トレーサビリティ / Traceability
- [SRFI 64: A Scheme API for test suites](https://srfi.schemers.org/srfi-64/srfi-64.html)
- [ULisp R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md)
- [ULisp テストおよび検証ガイド](../../ulisp/docs/guide_testing.md)
- [DSN-33 ULisp 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/test.scm](../../ulisp/lib/test.scm) (新規作成: SRFI 64 ランナー・アサーション・集計コア実装)
- [ ] [ulisp/lib/srfi/64.sld](../../ulisp/lib/srfi/64.sld) (新規作成: `(srfi 64)` ライブラリ定義)
- [ ] [ulisp/frontend/010_library.scm](../../ulisp/frontend/010_library.scm) (`(srfi 64)` のインポート解決確認)
- [ ] [ulisp/tests/passes/common.scm](../../ulisp/tests/passes/common.scm) (既存 `assert-equal` / `assert-true` から SRFI 64 への後方互換ブリッジ整備)
- [ ] [ulisp/tests/test_srfi_64.scm](../../ulisp/tests/test_srfi_64.scm) (新規作成: SRFI 64 全機能の単体テストスイート)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_srfi_64` ターゲットおよび `lint_sexpr` への登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/819-implement-srfi-64-test-suites-library-and-custom-test-runners`

1. **テストランナー (`<test-runner>`) と動的パラメータ (`test-runner-current`, `test-runner-factory`) の実装**:
   - `ulisp/lib/parameter.scm` の `make-parameter` を活用し、Pass / Fail / XPass / XFail / Skip カウンタ、グループ階層スタック、および結果コールバック（`test-runner-on-test-end!`, `test-runner-on-group-begin!`, `test-runner-on-final!` 等）を保持する `<test-runner>` を実装する。
   - 標準コンソール出力ランナーに加え、CI 集計・TAP 出力および Power Assert 診断連携フックをサポートする。
2. **グループ化・階層化およびクリーンアップ構文の実装**:
   - `test-begin`, `test-end`, `test-group`, および `dynamic-wind` を用いた `test-group-with-cleanup` を実装し、複数テストファイルを結合実行した際にも名前空間・カウンタが衝突せずスイート別に集計されるようにする。
3. **標準アサーションマクロ群 (`syntax-rules`) とスキップ制御の実装**:
   - `test-assert`, `test-eq`, `test-eqv`, `test-equal`, `test-approximate`（Fixnum / `<ratnum>` / `<flonum>` / `<compnum>` の許容誤差比較）、`test-error`（`guard` / `with-exception-handler` による例外捕捉とエラー型検証）をマクロとして実装する。
   - `test-skip` および `test-expect-fail` によるマッチャ・カウント指定のスキップ／XFAIL 制御を実装する。
4. **単体テストと互換ブリッジの検証**:
   - `ulisp/tests/test_srfi_64.scm` を作成し、ULisp AOT バイナリおよびホスト処理系（`gosh` / `ilisp`）の双方で全アサーション・グループ・スキップ制御が動作することを検証する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(import (srfi 64))` により `test-begin`, `test-end`, `test-group`, `test-group-with-cleanup`, `test-assert`, `test-eq`, `test-eqv`, `test-equal`, `test-approximate`, `test-error`, `test-skip`, `test-expect-fail`, `test-runner-*` が利用可能であること。
- [ ] `make -C ulisp test_srfi_64` および `make -C ulisp test_r7rs_traceability lint_sexpr` が 100% PASS すること。
- [ ] ドキュメント内のすべてのリンクが相対パスで記述されていること。