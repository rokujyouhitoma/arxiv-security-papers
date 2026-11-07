---
ID: 771
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ULisp ホスト実行エンジンのネイティブシード優先化とパス単体テスト一括バッチ実行による高速化 (ID: 771)

## 1. 概要 / Summary

[ulisp/Makefile](../../ulisp/Makefile) におけるコンパイルおよびパス単体テスト実行時のプロセス起動・インタプリタ解釈オーバーヘッドを抜本的に削減し、ビルド・テストサイクルを高速化する。

1. **ネイティブブートストラップシード（`bin/ulisp-boot` / `build/ulisp-fast`）の自動維持・優先利用**:
   - `bin/ulisp-boot` が未生成の場合にすべてのコンパイルが Python インタプリタ上の `python -m ilisp compiler.scm` にフォールバックし、1回のコンパイルに数十倍の時間を要する問題を解消するため、ネイティブコンパイラバイナリのビルド依存とシード配置を整備する。
2. **38個の Nanopass 単体テスト（`test_all_passes`）の一括バッチ実行化**:
   - 現行の `test_all_passes` ターゲットでは、`NANOPASS_TESTS`（38ファイル）に対してシェルループで毎回 `cat build/compiler_passes.scm $$t > build/runner_temp.scm` と `$(RUN_SCHEME)` を個別起動しており、`build/compiler_passes.scm` のパース・ロードが38回重複している。これを1回のプロセス起動（または並列ジョブ）で全テストスイートを実行するバッチランナー方式へ改善する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
- 依存関係:
  - 関連 Issue: [Issue #770](770-verify-stage3-self-hosting-fixed-point-and-benchmark-pass-fusion.md), [Issue #772](772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/Makefile](../../ulisp/Makefile)
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/771-optimize-ulisp-host-compiler-seed-and-batch-pass-test-runner`

1. **`ulisp/Makefile` におけるネイティブコンパイラ選択と依存関係の最適化**:
   - `ULISP_BOOT`（`bin/ulisp-boot`）または分割リンクバイナリ（`build/ulisp-fast` / `build/scheme-stage2`）を自動検出し、AOT コンパイルターゲットでネイティブバイナリが優先利用されるように構成する。
2. **`test_all_passes` ターゲットのバッチ実行化**:
   - `build/compiler_passes.scm` を1度だけロードして各パステストを連続評価する統合ランナー（または `make -j` 対応の個別ターゲット構造）を導入し、38回の重複パース・プロセス生成コストを削減する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `make -C ulisp test_all_passes` の実行時間が従来比で大幅に短縮され、全38パスの単体テストが 100% PASS すること。
- [ ] ネイティブシード有効時に Python `ilisp` フォールバックが発生せず高速に `.scm` $\to$ `.s` コンパイルが完了すること。
- [ ] `make check` / `make verify_quality` がエラー 0 件で PASS すること。

