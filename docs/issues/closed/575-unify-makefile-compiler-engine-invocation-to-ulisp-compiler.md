---
ID: 575
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] Makefile 内コンパイラ実行コマンドの ULISP_COMPILER 統一および ILISP 直接呼び出しの排除 (ID: 575)

## 1. 概要 / Summary
現在 `ulisp/Makefile` において、AOT コンパイルやテストランナー実行時に、ネイティブ AOT 実行エンジンである `ULISP_COMPILER` (`bin/ulisp-boot` / `build/scheme-stage1`) を使用しているターゲットと、低速な Python インタプリタ `ILISP` を直接呼び出しているターゲットが混在・分散している。
ネイティブコンパイラ `ULISP_COMPILER` は実行速度が Python 比で数十倍〜数百倍（サブセカンド / 即時）高速であり、開発サイクルおよびテスト実行の UX（ユーザー体験）を大幅に向上させる。
本 Issue では、`ulisp/Makefile` 内でコンパイルおよびテスト実行を行う全ルールにおいて `ULISP_COMPILER` 経由の統一呼び出しに集約し、`ULISP_BOOT` が存在する場合はすべてネイティブ高速パスで完結させ、存在しない場合のみ透過的に `ILISP` へフォールバックする一貫したアーキテクチャを確立する。

---

## 2. トレーサビリティ / Traceability
- DSN-33 コンパイラアーキテクチャ仕様
- Issue #541 (高速ブートストラップシード bin/ulisp-boot 導入)
- Issue #572 (1:1 パステスト網羅およびエンジン一元化)
- 関連資料: [ulisp/Makefile](../../ulisp/Makefile)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/Makefile](../../ulisp/Makefile) (コンパイラ呼び出しマクロおよび全テストターゲットの統一)
- [x] [ulisp/test.sh](../../ulisp/test.sh) (Makefile ターゲット呼び出し整合性の確認)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/575-unify-makefile-compiler-engine-invocation-to-ulisp-compiler`

1. **実行コマンドマクロ `RUN_SCHEME` / `ULISP_COMPILER` の統一設計**:
   - Scheme スクリプトを直接実行するルール（パステストや JIT テスト等）は `RUN_SCHEME = PYTHONPATH=$(ROOT_DIR) $(ILISP)` で Scheme インタプリタとして実行。
   - コンパイルターゲットは `ULISP_BOOT` が利用可能な場合 `./$(ULISP_BOOT)` を最優先使用し、存在しない場合は `$(RUN_SCHEME) compiler.scm <` へフォールバック。
   - `build/scheme-stage1` の長時間（2時間）自動ビルド依存を完全に排除。
2. **個別のターゲットの置換**:
   - `test_exceptions`, `test_values`, `test_call_cc`, `test_eqv`, `test_syntax_rules`, `test_ports`, `test_record`, `test_promise`, `test_stdlib`, `test_gc_*` で `$(ULISP_COMPILER)` を一貫して呼び出すよう統一。
   - `test_passes`, `test_all_passes`, JIT テスト群で `$(RUN_SCHEME)` を一貫して使用。
3. **ベンチマークと回帰検証**:
   - AOT テスト、パステスト群の実行が安定して行えることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/Makefile` 内で処理系エンジン決定が `ULISP_BOOT` 優先、なければ `ILISP` の安全なフォールバックに統一されていること（長時間かかる stage1 自動ビルドの排除）
- [x] `bin/ulisp-boot` が存在する場合、すべてのコンパイルステップがネイティブ実行され、ビルド・テスト速度が最大化されること
- [x] テストスクリプト実行 (`$(RUN_SCHEME)`) と AOT コンパイル (`$(ULISP_COMPILER)`) の責務が明確に分離統一されていること
- [x] `make test_record test_promise` および AOT テスト群の動作が確認されていること
