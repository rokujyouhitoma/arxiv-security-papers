---
ID: 822
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 既存テストスイート (267箇所の重複 assert-*) の SRFI 64 統一・引数順序是正および仕様準拠ドキュメント更新 (ID: 822)

## 1. 概要 / Summary
現在 `ulisp/tests/` および `tests/concurrency/` 内の各テストファイルに個別定義されている **267 箇所の `(define (assert-...))` 重複ボイラープレート** を整理し、3 パターンに分裂している `assert-equal` の引数順序（① `(label expected actual)`、② `(name actual expected)`、③ `(actual expected msg)`）を [Issue #819](819-implement-srfi-64-test-suites-library-and-custom-test-runners.md) の **SRFI 64 (`test-equal`, `test-assert`, `test-approximate`, `test-error`)** へ段階的に統一する。
あわせて、[ulisp/Makefile](../../ulisp/Makefile) のバッチ結合テスト（`test_all_passes`）におけるトップレベル再定義衝突の解消、[ulisp/tests/test_numeric_tower.scm](../../ulisp/tests/test_numeric_tower.scm) の独自 `assert-approx` の `test-approximate` 置換、および [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) / [guide_testing.md](../../ulisp/docs/guide_testing.md) の更新を行う。

---

## 2. トレーサビリティ / Traceability
- [Issue #818 Makefile テストランナー RUN_SCHEME の Gauche (gosh) 優先化とモジュラー並列ブートストラップ検証の統合](818-prioritize-gauche-in-test-runner-and-enable-modular-parallel-bootstrap-verify.md)
- [Issue #819 R7RS-large / SRFI 64 テストスイート標準ライブラリ (srfi 64) の実装](819-implement-srfi-64-test-suites-library-and-custom-test-runners.md)
- [Issue #820 SRFI 78 軽量テストライブラリ (srfi 78) の実装](820-implement-srfi-78-lightweight-testing-library.md)
- [Issue #821 SRFI 252 プロパティベーステストライブラリ (srfi 252) の実装](821-implement-srfi-252-property-based-testing-library.md)
- [ULisp R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md)
- [ULisp テストおよび検証ガイド](../../ulisp/docs/guide_testing.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/tests/passes/common.scm](../../ulisp/tests/passes/common.scm) (SRFI 64 ベースの共通テストハーネス化)
- [ ] [ulisp/tests/passes/](../../ulisp/tests/passes/) (全 39 パス単体テストの重複 `assert-*` 定義削除と `test-begin` / `test-end` グループ化)
- [ ] [ulisp/tests/test_numeric_tower.scm](../../ulisp/tests/test_numeric_tower.scm) (`assert-approx` から `test-approximate` への移行)
- [ ] [ulisp/tests/test_exceptions.scm](../../ulisp/tests/test_exceptions.scm) (`test-error` / `test-equal` への移行)
- [ ] [ulisp/tests/](../../ulisp/tests/) (Pattern B `(name actual expected)` / Pattern C `(actual expected msg)` の引数順序是正・SRFI 64 統一)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_all_passes` バッチランナーと標準テストターゲットの整理)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (SRFI 64 / SRFI 78 / SRFI 252 のステータスを `◎` へ更新)
- [ ] [ulisp/docs/guide_testing.md](../../ulisp/docs/guide_testing.md) (SRFI 64 / 78 / 252 の使い分けガイド追記)
- [ ] [scripts/verify_r7rs_traceability.py](../../scripts/verify_r7rs_traceability.py) (新規 SRFI ライブラリ・Issue 参照の監査ルール更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/822-unify-existing-test-suites-to-srfi-64-and-update-compliance-docs`

1. **Nanopass 単体テスト群 (`ulisp/tests/passes/test_*.scm`) のバッチ統合改善**:
   - `Makefile` の `test_all_passes` で `tests/passes/common.scm`（または `ulisp/lib/test.scm`）を先頭に 1 回だけ読み込み、各パス単体テストから重複する `(define (assert-equal ...))` 等を除去して `(test-begin "pass-XXX")` ... `(test-end "pass-XXX")` でスコープ化する。
2. **引数順序が逆転しているテストファイルの是正**:
   - `test_srfi1.scm`, `test_char.scm`, `test_file_port.scm`, `test_string_to_number.scm` 等の `(assert-equal name actual expected)`、および `test_record.scm`, `test_case_lambda.scm`, `tests/concurrency/test_*.scm` 等の `(assert-equal actual expected msg)` を SRFI 64 標準順序へ統一し、エラー時の Expected / Actual 逆転表示を解消する。
3. **特殊アサーションの標準 API 置換**:
   - `test_numeric_tower.scm` の `assert-approx` を `test-approximate` に、手動 `(guard ...)` による例外テストを `test-error` に置き換える。
4. **ドキュメントとトレーサビリティ検証の更新**:
   - `ulisp/docs/ref_r7rs_compliance.md` の SRFI 64 を `△` から `◎` に昇格し、SRFI 78 および SRFI 252 を `◎` として追加する。
   - `ulisp/docs/guide_testing.md` に SRFI 64（本格ユニットテスト・CI 連携）、SRFI 78（単一ファイル・Nanopass 手軽確認）、SRFI 252（プロパティベーステスト）の標準記述例と使い分け指針を明記する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp/tests/passes/` 等の重複 `assert-*` 定義が解消され、SRFI 64 の階層集計で全件 PASS すること。
- [ ] `make -C ulisp test` および `make -C ulisp test_r7rs_traceability lint_sexpr` が 100% PASS すること。
- [ ] `ulisp/docs/ref_r7rs_compliance.md` および `ulisp/docs/guide_testing.md` に SRFI 64 / 78 / 252 の仕様準拠状況と利用ガイドが反映されていること。
- [ ] ドキュメント内のすべてのリンクが相対パスで記述されていること。