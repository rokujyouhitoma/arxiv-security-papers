---
ID: 844
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] ビルド中間生成物クリーンアップとゼロ Gauche 依存の自動回帰検証 (ID: 844)

## 1. 概要 / Summary
Issue 841〜843 の対応完了後、リポジトリ内の `ulisp/build/` ディレクトリに残存している過去のビルド成果物（`test_*_runner.scm`, `compiler_passes.scm`, `compiler_base_in.scm` 等）には、旧ソースコードからコピーされた `(gauche ...)` 節が多数残存している。
本 Issue では、これら中間生成物を完全にクリーンアップ（`make clean`）して再構築を行い、リポジトリ全体でコンパイラおよびテストランナーから Gauche への依存表記が根絶された状態を実現する。

さらに、今後の開発で不用意に `(gauche ...)` や `gosh` 直接呼び出しが再混入しないよう、Makefile の静的検証ターゲット（`make check` / `make verify_quality`）に「ゼロ Gauche 依存検証（Zero Gauche Dependency Gate）」を導入する。

---

## 2. トレーサビリティ / Traceability
- **関連仕様・ドキュメント**:
  - `ulisp/docs/spec_pipeline.md` (自己完結型ツールチェイン・ゼロ外部依存仕様)
  - Issue 841 (コンパイラ本体ソースコードからの Gauche 固有 cond-expand 分岐の撤去)
  - Issue 842 (テストおよび回帰検証スクリプトにおける gosh 直書き呼出のネイティブ置換)
  - Issue 843 (Makefile および bootstrap.sh からの Gauche フォールバック機構の疎結合化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/build/](../../ulisp/build/) (中間 Scheme 生成物群の完全消去・再生成)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (静的解析・品質ゲートターゲットへの grep 検証ルール追加)
- [x] [ulisp/tests/test_pure_bootstrap.sh](../../ulisp/tests/test_pure_bootstrap.sh) (CI 検証ゲート)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/844-clean-build-artifacts-and-verify-zero-gauche`

1. **ビルド中間生成物の一掃と再生成**:
   - `make -C ulisp clean` を実行し、`ulisp/build/` 配下の中間ファイル（特に `test_*_runner.scm`, `compiler_passes.scm`）を完全に削除。
   - `make -C ulisp compiler.scm` および必要なテストランナー群を新規ソースから再生成。
2. **ゼロ Gauche 依存検証ルールの導入**:
   - `ulisp/Makefile` の `verify_quality`（または `check`）ターゲットに以下の回帰防止検査を追加：
     ```makefile
     verify_zero_gauche:
     	@echo "Checking for unexpected (gauche) references in compiler and runner sources..."
     	@! git grep -n "(gauche" -- ulisp/compiler/ ulisp/backend/ ulisp/runtime/ ulisp/build/*.scm || \
     	  (echo "Error: Unexpected (gauche) branch found in compiler/runner sources!" && exit 1)
     	@echo "Zero Gauche dependency check PASSED."
     ```
3. **CI / 回帰テスト実行**:
   - `make -C ulisp verify_quality`
   - `./ulisp/tests/test_pure_bootstrap.sh`
   - 上記テストを実行し、完全自立環境でビルド・テストが成立することを実証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `git grep "(gauche" -- ulisp/compiler/ ulisp/backend/ ulisp/runtime/ ulisp/build/*.scm` の検出件数が **0 件** であること。
- [x] `make -C ulisp verify_zero_gauche`（または `make -C ulisp check`）が正常終了（exit code 0）すること。
- [x] 全テストランナーの再生成後、`make -C ulisp test_all` が正常に PASS すること。
- [x] 外部ツール完全マスキングテスト（`test_pure_bootstrap.sh`）が PASS すること。
