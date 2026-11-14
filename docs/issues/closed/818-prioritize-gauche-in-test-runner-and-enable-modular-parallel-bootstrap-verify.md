---
ID: 818
種別: Feature
優先度: Medium
ステータス: Closed
完了日: 2026-11-14
Target Branch: feat/818-prioritize-gauche-in-test-runner-and-enable-modular-parallel-bootstrap-verify
---

# [FEAT/ENH] Makefile テストランナー RUN_SCHEME の Gauche (gosh) 優先化とモジュラー並列ブートストラップ検証の統合 (ID: 818)

## 1. 概要 / Summary
開発・CI サイクルにおけるテストスイート実行および 3-Stage セルフホスティング検証の総所要時間を大幅に短縮し、ビルド障害時の不整合を防止するため、ビルド・テスト基盤（[ulisp/Makefile](../../../ulisp/Makefile) および [ulisp/bootstrap.sh](../../../ulisp/bootstrap.sh)）および LIR・テスト群の以下 3 点を実装・完了した：

1. **テスト実行エンジン `RUN_SCHEME` の Gauche (`gosh`) 優先化とホスト処理系間の互換性統一**:
   - `USE_ILISP=1` が明示されていない限り、`GOSH_BIN` が存在する環境では `RUN_SCHEME` を `$(GOSH_BIN) -ugauche.uvector -uscheme.file -I $(CURDIR) -I $(ROOT_DIR)` に優先設定し、`USE_ILISP=1` または `gosh` 不在時のみ Python インタプリタ (`ilisp`) へフォールバックするよう統合した（`test_all_passes`, `test_nanopass`, `test_passes`, `test_pass_manager`, `test_jit`, `test_144a`, `test_elf64`, `test_144` 等の高速一括実行を実現）。
   - 併せて、`gosh` と `ilisp` の双方で 100% PASS させるため以下を是正した：
     - `-ugauche.uvector -uscheme.file` 指定により、`pass_check_affine.scm` の `bytevector?` および `test_144a` / `test_elf64` / `test_144` の `open-binary-output-file` を解決。
     - [ulisp/tests/test_nanopass_framework.scm](../../../ulisp/tests/test_nanopass_framework.scm#L2063-L2070) Section 27.2（`Hash-bucketed *femto-analysis-cache*`）で、右から左へ `let` 束縛を評価する Gauche でもキャッシュ登録 `v1` が `v1-hit` より先に評価されるよう `let*` へ変更。
     - [ulisp/tests/passes/test_120_alias_escape.scm](../../../ulisp/tests/passes/test_120_alias_escape.scm#L154-L166) で、リーダ構文 `#:stack-alloc` ではなく `*stack-alloc-attr*` への準クォート参照（`,*stack-alloc-attr*`）へ統一。
     - [ulisp/lir/123_lir_closures.scm](../../../ulisp/lir/123_lir_closures.scm#L45-L52) および [ulisp/lir/130_lir.scm](../../../ulisp/lir/130_lir.scm#L24-L31) の `stack-alloc-attr?` に `(string=? s "stack-alloc")` を追加し、Gauche が未インターンシンボルとして読み取る `#:stack-alloc` を正しく認識できるよう修正。
2. **5 モジュール並列ブートストラップ検証 (`bootstrap_verify_modular`) の標準化**:
   - 5 分割モジュール（`MODULAR_MODULES = compiler_base frontend_passes lir_passes backend_passes compiler_driver`）の `build/stage2-modular` と `build/stage3-modular` を並列ビルドし、全 5 モジュールの `build/stage2_<mod>.s` と `build/stage3_<mod>.s` のビット完全一致（`cmp -s`）を検証して `bin/ulisp-boot` / `bin/ulisp-modular` を更新する `bootstrap_verify_modular` ターゲットを追加した。
   - `MONOLITHIC_BOOTSTRAP=1` が指定されていない場合のデフォルト `bootstrap_verify` として `bootstrap_verify_modular` を統合し、従来の単一ファイル検証は `bootstrap_verify_monolithic` として保持した。
3. **ステージ失敗・中断時の 0 バイト `.s` 残留および `stderr` 混入防止**:
   - [ulisp/Makefile](../../../ulisp/Makefile) 先頭に `.DELETE_ON_ERROR:` を追加し、`> $@` リダイレクト等で非ゼロ終了した不完全ターゲットを GNU Make が自動削除するよう設定した。
   - [ulisp/bootstrap.sh](../../../ulisp/bootstrap.sh#L279-L405) の `check_asm_output()`、`run_stage()`、`compile_asm()`、`run_stage_try()` にて失敗時 `rm -f "$asm_file"` / `"$obj_file"` クリーンアップを実装し、さらに `run_stage()` / `run_stage_try()` で `stderr`（`[WARN]` 等）を `$err_file` へ分離することでアセンブリファイルへの警告混入を防止した。

---

## 2. トレーサビリティ / Traceability
- [DSN-33 ULisp ネイティブ AOT コンパイラ アーキテクチャ仕様書](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- 関連完了 Issue: [Issue #815](815-optimize-nanopass-catamorphism-shallow-dispatch-and-term-memo-buckets.md), [Issue #816](816-optimize-rtyper-escape-pruning-and-lir-peephole-window-allocation.md), [Issue #817](817-hash-table-compiler-registries-and-inline-higher-order-list-ops-in-cp0.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/Makefile](../../../ulisp/Makefile)
  - `.PHONY` への `bootstrap_verify_modular` / `bootstrap_verify_monolithic` 追加および `.DELETE_ON_ERROR:` 宣言
  - `USE_ILISP` 分岐による `RUN_SCHEME` の `$(GOSH_BIN) -ugauche.uvector -uscheme.file -I $(CURDIR) -I $(ROOT_DIR)` 優先化
  - `BOOTSTRAP_JOBS` / `BOOTSTRAP_JFLAG` 導入、`bootstrap_verify_modular`・`bootstrap_verify_monolithic` 定義および `MONOLITHIC_BOOTSTRAP=1` 切替統合
- [x] [ulisp/bootstrap.sh](../../../ulisp/bootstrap.sh)
  - `check_asm_output()`, `run_stage()`, `compile_asm()`, `run_stage_try()` における失敗時 `$asm_file` / `$obj_file` 削除と `err_file` による `stderr` 分離
- [x] [ulisp/lir/123_lir_closures.scm](../../../ulisp/lir/123_lir_closures.scm)
  - `stack-alloc-attr?` に `(string=? s "stack-alloc")` を追加（Gauche 未インターンシンボル `#:stack-alloc` 互換対応）
- [x] [ulisp/lir/130_lir.scm](../../../ulisp/lir/130_lir.scm)
  - `stack-alloc-attr?` に `(string=? s "stack-alloc")` を追加
- [x] [ulisp/tests/test_nanopass_framework.scm](../../../ulisp/tests/test_nanopass_framework.scm)
  - L2063: Section 27.2 のキャッシュ検証束縛を `let` から `let*` に変更
- [x] [ulisp/tests/passes/test_120_alias_escape.scm](../../../ulisp/tests/passes/test_120_alias_escape.scm)
  - L154, L165: `#:stack-alloc` リテラルを `,*stack-alloc-attr*` の準クォート参照へ変更
- [x] [ulisp/compiler.scm](../../../ulisp/compiler.scm) ・ [ulisp/bin/ulisp-boot](../../../ulisp/bin/ulisp-boot)
  - 変更反映済み `compiler.scm` 再生成および 3-Stage 不動点検証済みシードバイナリ更新

---

## 4. 実装内容 / Implementation Summary
Target Branch: `feat/818-prioritize-gauche-in-test-runner-and-enable-modular-parallel-bootstrap-verify`

1. **失敗時ターゲット自動削除と `stderr` 分離クリーンアップ ([ulisp/Makefile](../../../ulisp/Makefile), [ulisp/bootstrap.sh](../../../ulisp/bootstrap.sh))**:
   - `.DELETE_ON_ERROR:` を [ulisp/Makefile](../../../ulisp/Makefile) に宣言し、シェルの `> $@` リダイレクト生成中にコマンドが失敗した場合に 0 バイト `.s` が残存しないようにした。
   - [ulisp/bootstrap.sh](../../../ulisp/bootstrap.sh) 側でも各ステージ失敗時の `rm -f "$asm_file"` / `"$obj_file"` と `$err_file` 分離を適用し、`./bootstrap.sh --modular` および `./bootstrap.sh --pure`（`test_pure_bootstrap`）がクリーンに通過することを確認した。
2. **`RUN_SCHEME` の Gauche (`gosh`) 優先化とテスト・LIR 互換性修正**:
   - [ulisp/Makefile](../../../ulisp/Makefile#L30-L43) に `USE_ILISP=1` オーバーライド付きの `$(GOSH_BIN) -ugauche.uvector -uscheme.file -I $(CURDIR) -I $(ROOT_DIR)` 構成を実装した。
   - `test_nanopass_framework.scm`（`let`→`let*`）、`test_120_alias_escape.scm`（`,*stack-alloc-attr*`）、および `123_lir_closures.scm` / `130_lir.scm`（`stack-alloc-attr?`）の修正により、`gosh`・`ilisp` 双方での全テスト PASS を達成した。
3. **モジュラー並列ブートストラップ検証ターゲットの統合 ([ulisp/Makefile](../../../ulisp/Makefile))**:
   - `bootstrap_verify_modular` により 5 モジュール並列での Stage 2 ⇔ Stage 3 ビット完全一致検証とシード更新を標準化し、`make -C ulisp -j4 bootstrap_verify` および `cd ulisp && ./bootstrap.sh --modular` の双方で全 5 モジュールの不動点収束を確認した。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] デフォルトの `make -C ulisp compiler test_all_passes test_144a test_elf64 test_144 test_nanopass test_passes test_pass_manager test_verifier test_lir_verifier test_jit test_bootstrap_diagnostics` が `gosh` 上で高速実行され、全テストが 100% PASS すること。
- [x] `make -C ulisp USE_ILISP=1 test_nanopass test_passes test_pass_manager` により Python `ilisp` フォールバック実行も引き続き 100% PASS すること。
- [x] `ulisp/Makefile` に `.DELETE_ON_ERROR:` が設定され、また `ulisp/bootstrap.sh` でもステージ失敗時に 0 バイトや不完全な `.s` ファイルが残存しないこと（`ulisp/build` 内 0 バイト `.s`/`.o` 件数 0、`test_pure_bootstrap` 10/10 PASS）。
- [x] `make -C ulisp -j4 bootstrap_verify`（モジュラー並列 3-Stage 検証）および `cd ulisp && ./bootstrap.sh --modular` による不動点検証が正常に PASS すること。
- [x] `make -C ulisp lint_sexpr`（173 ファイル PASS）およびリポジトリルートの `make format && make static_analysis && make test`（2766 passed, 1 skipped, 8 deselected, coverage 83.14%）がすべて PASS すること。
- [x] ドキュメント内のすべてのリンクが相対パスで記述されていること（絶対パス 0 件）。
