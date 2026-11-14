---
ID: 822
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] 既存テストスイート (267箇所の重複 assert-*) の SRFI 64 統一・引数順序是正および仕様準拠ドキュメント更新 (ID: 822)

## 1. 概要 / Summary

現在 `ulisp/tests/` および `tests/concurrency/` 内の各テストファイルに個別定義されている **267 箇所の `(define (assert-...))` 重複ボイラープレート** を整理し、3 パターンに分裂している `assert-equal` の引数順序（① `(label expected actual)`、② `(name actual expected)`、③ `(actual expected msg)`）を [Issue #819](closed/819-implement-srfi-64-test-suites-library-and-custom-test-runners.md) で確立した **SRFI 64 (`test-equal`, `test-assert`, `test-approximate`, `test-error`)** へ段階的に統一する。

あわせて、以下の課題を包括的に解決する:
1. **Nanopass 結合テストハーネスの刷新**: [ulisp/Makefile](../../ulisp/Makefile) のバッチ結合テスト（`test_all_passes`）において、全 39 パスのテストファイルが個別に `*diag-tests-run*` や `assert-equal` 等を再定義してトップレベルシンボル衝突と集計の分断を引き起こしている問題を、[ulisp/tests/passes/common.scm](../../ulisp/tests/passes/common.scm) による共通ハーネス導入と `(test-begin "pass-XXX")` / `(test-end "pass-XXX")` 階層グループ化により一掃する。
2. **引数順序逆転による誤検知・混乱の根絶**: `test_srfi1.scm`, `test_char.scm`, `test_file_port.scm`, `test_string_to_number.scm` 等の Pattern B `(name actual expected)`、および `test_record.scm`, `test_case_lambda.scm`, `tests/concurrency/test_*.scm` 等の Pattern C `(actual expected msg)` を SRFI 64 標準形式 `(test-equal [name] expected actual)`（または `(assert-equal label expected actual)`）へ是正し、エラー発生時の Expected / Actual 逆転表示を解消する。
3. **特殊アサーションの標準化**: [ulisp/tests/test_numeric_tower.scm](../../ulisp/tests/test_numeric_tower.scm) の独自 `assert-approx` を `test-approximate` へ置換し、[ulisp/tests/test_exceptions.scm](../../ulisp/tests/test_exceptions.scm) の手動 `guard` 例外テストを `test-error` へ置き換える。[ulisp/lib/stdlib_macros.scm](../../ulisp/lib/stdlib_macros.scm) に SRFI 64 テスト構文群を組み込み、事前コンパイル済み標準ライブラリ（`ulisp_stdlib.o`）とリンクするテストでも SRFI 64 構文を即時利用可能とする。
4. **仕様準拠ドキュメントとテスト体系ガイドの更新**: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) の最新 Issue 追従・クローズド Issue リンク拡充、および [guide_testing.md](../../ulisp/docs/guide_testing.md) における SRFI 64（総合ユニットテスト）、SRFI 78（軽量式評価テスト）、SRFI 252（プロパティベーステスト）の 3 大フレームワーク使い分けガイドを整備する。

---

## 2. トレーサビリティ / Traceability

- [SRFI 64: A Scheme API for Test Suites](https://srfi.schemers.org/srfi-64/srfi-64.html)
- [SRFI 78: Lightweight testing](https://srfi.schemers.org/srfi-78/srfi-78.html)
- [SRFI 252: Property Testing](https://srfi.schemers.org/srfi-252/srfi-252.html)
- [Issue #818 Makefile テストランナー RUN_SCHEME の Gauche (gosh) 優先化とモジュラー並列ブートストラップ検証の統合](closed/818-prioritize-gauche-in-test-runner-and-enable-modular-parallel-bootstrap-verify.md)
- [Issue #819 R7RS-large / SRFI 64 テストスイート標準ライブラリ (srfi 64) の実装](closed/819-implement-srfi-64-test-suites-library-and-custom-test-runners.md)
- [Issue #820 R7RS-large / SRFI 78 軽量テストライブラリ (srfi 78) の実装](closed/820-implement-srfi-78-lightweight-testing-library.md)
- [Issue #821 R7RS-large / SRFI 252 プロパティベーステストライブラリ (srfi 252) の実装](closed/821-implement-srfi-252-property-based-testing-library.md)
- [ULisp R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md)
- [ULisp テストおよび検証ガイド](../../ulisp/docs/guide_testing.md)
- [DSN-33 ULisp 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 既存更新ファイル
- [ ] [ulisp/tests/passes/common.scm](../../ulisp/tests/passes/common.scm) (SRFI 64 互換アサーション群・階層グループ runner・統合レポーティング機構の提供)
- [ ] [ulisp/tests/passes/](../../ulisp/tests/passes/) (全 39 パス単体テストの 98 箇所に及ぶ重複 `assert-*` 定義削除と `(test-begin "pass-XXX")` ... `(test-end "pass-XXX")` 階層化)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_all_passes` および個別パス単体テストターゲットにおける `common.scm` 統合、標準テストターゲットの整理)
- [ ] [ulisp/lib/stdlib_macros.scm](../../ulisp/lib/stdlib_macros.scm) (SRFI 64 マクロ群 `test-begin`, `test-end`, `test-assert`, `test-equal`, `test-approximate`, `test-error` の組み込み)
- [ ] [ulisp/tests/test_numeric_tower.scm](../../ulisp/tests/test_numeric_tower.scm) (`assert-approx` から SRFI 64 `test-approximate` への完全移行)
- [ ] [ulisp/tests/test_exceptions.scm](../../ulisp/tests/test_exceptions.scm) (独自 `test` / `equal?` から SRFI 64 `test-equal` / `test-error` への移行)
- [ ] [ulisp/tests/test_srfi1.scm](../../ulisp/tests/test_srfi1.scm), [ulisp/tests/test_char.scm](../../ulisp/tests/test_char.scm), [ulisp/tests/test_file_port.scm](../../ulisp/tests/test_file_port.scm), [ulisp/tests/test_string_to_number.scm](../../ulisp/tests/test_string_to_number.scm) (Pattern B 引数順序是正: `(name actual expected)` -> `(assert-equal name expected actual)`)
- [ ] [ulisp/tests/test_record.scm](../../ulisp/tests/test_record.scm), [ulisp/tests/test_case_lambda.scm](../../ulisp/tests/test_case_lambda.scm), [ulisp/tests/test_scheme_runtime.scm](../../ulisp/tests/test_scheme_runtime.scm) (Pattern C 引数順序是正: `(actual expected msg)` -> `(assert-equal msg expected actual)`)
- [ ] [tests/concurrency/](../../tests/concurrency/) (並行性テスト群 17 ファイルの重複 `assert-equal` / `assert-true` の引数順序是正・共通化)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (SRFI 64 / SRFI 78 / SRFI 252 および Issue #819-#822 のクローズド Issue 追従・準拠記述更新)
- [ ] [ulisp/docs/guide_testing.md](../../ulisp/docs/guide_testing.md) (SRFI 64 / SRFI 78 / SRFI 252 の役割分担・選択指針・標準コードパターンの追記)
- [ ] [scripts/verify_r7rs_traceability.py](../../scripts/verify_r7rs_traceability.py) (クローズド Issue 監査リストの同期)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳のステータス同期)

---

## 4. セキュリティ要件と堅牢性 / Security & Robustness Considerations

1. **引数順序の逆転によるバグ隠蔽・誤修正防止 (CWE-682 / CWE-710)**:
   - `assert-equal` の引数が `(actual expected msg)` や `(name actual expected)` と混在していると、テスト失敗時にコンソールに「Expected: 100, Got: 0」と表示されるべき事象が「Expected: 0, Got: 100」と逆に表示される。
   - これにより、開発者がテストの期待値と実装の戻り値を誤認し、実装側を誤って不正な値へ修正してしまう重大な回帰リスク（Regression Masking）が存在する。
   - *対策*: プロジェクト全体の `assert-equal` を SRFI 64 `(test-equal [name] expected actual)` と同一の「期待値が先、実測値が後」の順序へ完全統一する。
2. **例外テストの安全な捕捉と例外漏れ防止 (CWE-754 / CWE-391)**:
   - 各テストで独自に `(guard (e (else ...)) ...)` を書くと、予期しないシステム例外（セグメンテーション違反や未定義シンボル参照）まで無差別に正常系として呑み込んでしまい、潜在バグが見逃される恐れがある。
   - *対策*: SRFI 64 の `test-error` を使用し、期待されるエラー型述語（`error-object?` やカスタム述語）の検証を厳密化する。
3. **トップレベル名前空間の汚染とテスト間干渉の排除 (CWE-400 / CWE-770)**:
   - `Makefile` の `cat build/compiler_passes.scm $(NANOPASS_TESTS) > build/test_all_passes_batch_runner.scm` で 39 ファイルを単一スクリプトに結合する際、各ファイルが同一名の大域変数（`*diag-tests-run*`, `assert-equal`）を上書き定義しているため、前のテストのカウンターが破壊されたり、定義順序依存の非決定的な実行結果が生じる。
   - *対策*: `tests/passes/common.scm` に共通テストランナーとアサーションを局所集約し、各パスを `(test-begin "pass-XXX")` ... `(test-end "pass-XXX")` でグループ化することで、テスト間の変数衝突をゼロにし、全パス横断の総テスト数・成功数・失敗数を正確に集計可能とする。
4. **DRY 原則の徹底と保守性向上 (CWE-1047 / CWE-710)**:
   - 267 箇所に散在するボイラープレートを共通ライブラリ・ハーネスへ集約することで、テスト基盤の改修コストを削減し、コードの可読性と一貫性を劇的に高める。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `refactor/822-unify-existing-test-suites-to-srfi-64-and-update-compliance-docs`

### フェーズ 1: Nanopass 共通テストハーネス (`ulisp/tests/passes/common.scm`) の拡充と `Makefile` 統合
1. **`ulisp/tests/passes/common.scm` の改修**:
   - SRFI 64 / SRFI 78 互換のアサーション・グループ制御を定義:
     - `(test-begin suite-name)`: パス名でグループ開始。グループ別カウンターの初期化。
     - `(test-end suite-name)`: パス名でグループ終了。グループ別結果のサマリー出力。
     - `(test-assert [label] expr)` / `(assert-true label expr)`
     - `(test-equal [label] expected actual)` / `(assert-equal label expected actual)`
     - `(assert-false label expr)`: 偽値表明。
     - `(assert-expand label expr expected)`: Pass 015 / Pass 020 用のマクロ・構文糖衣展開検証。
     - `(assert-report)`: 全パス合計の実行数・成功数・失敗数の総合レポート出力とゼロ終了（失敗時 `(exit 1)`）。
2. **`ulisp/Makefile` の `NANOPASS_TESTS` バッチランナー改修**:
   - `test_all_passes` において `common.scm` を先頭に結合:
     ```makefile
     cat build/compiler_passes.scm tests/passes/common.scm $(NANOPASS_TESTS) > build/test_all_passes_batch_runner.scm
     ```
   - 個別パス単体テストターゲット（`test_extern_symbols`, `test_power_assert`, `test_traceback` 等）でも `tests/passes/common.scm` を結合対象に含め、単体・バッチの双方で等しく動作可能とする。

### フェーズ 2: Nanopass 39 パステストの重複 `assert-*` 削除とグループ化
1. `ulisp/tests/passes/test_*.scm` (全 39 ファイル) を走査し、各ファイルの先頭にある `(define *xxx-tests-run* ...)`, `(define (assert-true ...))`, `(define (assert-equal ...))` などの 98 箇所のボイラープレート定義を完全削除。
2. 各テストの先頭に `(test-begin "pass-XXX")`、末尾に `(test-end "pass-XXX")` を配置し、階層的テストグループとして構造化。
3. `make -C ulisp test_all_passes` を実行し、全 39 パスのテストが 1 件も欠落することなく 100% PASS することを確認。

### フェーズ 3: 引数順序逆転テスト（Pattern B / Pattern C）の是正と並行性テストの標準化
1. **Pattern B 是正 (`(name actual expected)` -> `(assert-equal name expected actual)`)**:
   - `ulisp/tests/test_char.scm`
   - `ulisp/tests/test_file_port.scm`
   - `ulisp/tests/test_string_to_number.scm`
   - `ulisp/tests/test_srfi1.scm`
   - `ulisp/tests/test_pass_manager.scm`
   - 引数の第 2 引数（実測値）と第 3 引数（期待値）を入れ替え、SRFI 64 標準順序（Expected が先、Actual が後）に統一。
2. **Pattern C 是正 (`(actual expected msg)` -> `(assert-equal msg expected actual)`)**:
   - `ulisp/tests/test_record.scm`
   - `ulisp/tests/test_case_lambda.scm`
   - `ulisp/tests/test_scheme_runtime.scm`
   - 引数順序を `(msg expected actual)` へ整流化。
3. **`tests/concurrency/` の重複定義整理**:
   - `tests/concurrency/test_*.scm` (全 17 ファイル) に個別定義されている `assert-equal actual expected msg` を `assert-equal msg expected actual` に統一、または共通ハーネス（`tests/concurrency/concurrency_harness.scm`）経由の提供へ移行。

### フェーズ 4: 特殊アサーションの標準化 (`test_numeric_tower.scm`, `test_exceptions.scm`)
1. **`ulisp/lib/stdlib_macros.scm` への SRFI 64 構文組み込み**:
   - `test-begin`, `test-end`, `test-assert`, `test-equal`, `test-approximate`, `test-error` の syntax-rules を `stdlib_macros.scm` に提供し、モジュラーコンパイル環境（`build/ulisp_stdlib.o` とリンクするテスト）で SRFI 64 マクロを即座に利用可能にする。
2. **`ulisp/tests/test_numeric_tower.scm` の移行**:
   - 独自定義の `assert-approx` を SRFI 64 `test-approximate`（または `assert-approx` から `test-approximate` へのエイリアス）に置換。
3. **`ulisp/tests/test_exceptions.scm` の移行**:
   - ファイル冒頭の独自 `(define (equal? ...))` および `(define (test name expected actual) ...)` を削除し、SRFI 64 の `test-begin`, `test-equal`, `test-error`, `test-end` へ置換。

### フェーズ 5: 仕様準拠ドキュメントとトレーサビリティ検証の更新
1. **`ulisp/docs/ref_r7rs_compliance.md` の更新**:
   - Section 4.1 の完了 Issue 一覧に Issue #820 (SRFI 78), #821 (SRFI 252), #822 (SRFI 64 統合) を追記。
   - すべてのリンクが相対パスであることを確認。
2. **`ulisp/docs/guide_testing.md` の更新**:
   - ULisp テスト階層に以下の標準指針とコードスニペットを明記:
     - **SRFI 64 (`(srfi 64)`)**: CI 統合、大規模ユニットテストスイート、階層的レポーティング、XFAIL / SKIP、カスタムテストランナー。
     - **SRFI 78 (`(srfi 78)`)**: モジュール内軽量アサーション、対話的評価・Nanopass 単体クイック検証、アロー記法 `(=>)`。
     - **SRFI 252 (`(srfi 252)`)**: プロパティベーステスト、決定論的 PRNG による反例再現、AST ファジング。
3. **`scripts/verify_r7rs_traceability.py` の同期**:
   - `verify_compliance_doc` が最新の記述と整合していることを検証。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp/tests/passes/common.scm` に共通ハーネスが構築され、全 39 パスのテストファイルから重複する `assert-*` 定義が完全排除されていること。
- [ ] `make -C ulisp test_all_passes` がエラー 0 件で全件 PASS し、階層的グループサマリーが出力されること。
- [ ] Pattern B (`name actual expected`) および Pattern C (`actual expected msg`) を採用していたテストファイルの引数順序が SRFI 64 標準（`msg expected actual`）へ是正されていること。
- [ ] `ulisp/tests/test_numeric_tower.scm` の `assert-approx` が `test-approximate` に、`ulisp/tests/test_exceptions.scm` が `test-equal` / `test-error` に置換され、ネイティブ実行で PASS すること。
- [ ] `ulisp/lib/stdlib_macros.scm` を経由してコンパイルされるテストターゲット群（`test_numeric_tower`, `test_arena` 等）が 100% 正常にビルド・PASS すること。
- [ ] `make -C ulisp test` (全テストスイート) および `make -C ulisp lint_sexpr` が 100% PASS すること。
- [ ] `python3 scripts/verify_r7rs_traceability.py` が 100% PASS すること。
- [ ] 3 大品質ゲート (`make format`, `make static_analysis`, `make test`) が 100% PASS すること。
- [ ] `ulisp/docs/ref_r7rs_compliance.md` および `ulisp/docs/guide_testing.md` に SRFI 64 / 78 / 252 の仕様準拠状況および利用ガイドが反映されていること。
- [ ] ドキュメント内のすべての内部リンクが厳密に相対パス（`file:///` や絶対パスを含まない）で記述されていること。
