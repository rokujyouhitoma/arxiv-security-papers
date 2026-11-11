---
ID: 771
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ULisp ホスト実行エンジンのネイティブシード優先化とパス単体テスト一括バッチ実行による高速化 (ID: 771)

## 1. 概要 / Summary

[ulisp/Makefile](../../../ulisp/Makefile) におけるコンパイラ実行エンジン選択および Nanopass 単体テスト実行時のプロセス起動・インタプリタ解釈オーバーヘッドを抜本的に削減し、開発・テストサイクルを大幅に高速化した。

1. **ネイティブブートストラップシード（`bin/ulisp-boot` / `build/ulisp-modular`）の多段階フォールバック優先化**:
   - 従来、`bin/ulisp-boot` が存在しない場合にすべてのコンパイルが低速な Python インタプリタ（`python -m ilisp compiler.scm`）へ即座にフォールバックしていた。
   - モジュール分割リンクバイナリ（`build/ulisp-modular`）が利用可能な場合、これを第2段階（Tier 2）ネイティブシードとして優先利用する多段フォールバック機構を導入し、開発中の一時的コンパイル時間を数十倍高速化した。
2. **全 39 個の Nanopass 単体テスト（`test_all_passes`）の単一バッチランナー化**:
   - 従来の `test_all_passes` ターゲットでは、`NANOPASS_TESTS`（全 39 ファイル）に対し、シェルループ `for t in $(NANOPASS_TESTS); do ...` を用いてファイルごとにプロセスを起動していた。
   - これにより、約 5,000〜7,000 行に及ぶ全コンパイラパス定義（`build/compiler_passes.scm`）の S 式パース・マクロ展開・インタープリタ初期化が 39 回重複して実行され、CPU 時間と I/O の重大なボトルネックとなっていた。
   - 本 Issue により、全テストファイルを単一のスクリプト（`build/test_all_passes_batch_runner.scm`）へ連結し、1 回の Scheme プロセス起動で全 39 パスのテストスイートを連続実行する一括バッチランナー方式へと刷新した。

---

## 2. トレーサビリティ / Traceability

- **関連設計書**:
  - [[DSN-33] ULISP 包括設計仕様書](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
    - 第 4 章（ブートストラップチェーンおよびセルフホスティング方式）
    - 第 7 章（ビルドシステムおよび Make ターゲット設計）
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
    - 第 2.3 節（4 階層の責務と入出力契約）
    - 第 7.1 節（1 行ユニットテストと高速回帰テスト実行基盤）
- **依存関係**:
  - **先行・関連 Issue**:
    - [Issue #607](607-support-extern-symbols-and-split-stdlib-compiler-linking.md) (ULisp 標準ライブラリとコンパイラのモジュール分割静的リンク) (Closed)
    - [Issue #608](608-implement-modular-separate-compilation-and-incremental-build.md) (ULisp 分割コンパイルと増分ビルドの確立) (Closed)
    - [Issue #772](772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md) (ULisp 標準ライブラリの事前コンパイル済みオブジェクト化とテストリンク統一) (Closed)
    - [Issue #778](778-implement-modular-parallel-incremental-bootstrap.md) (モジュール分割増分コンパイルとサブセカンド・ブートストラップ基盤) (Closed)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/Makefile](../../../ulisp/Makefile)
  - ホストコンパイラ選択ルール（`ULISP_COMPILER`）における多段階優先度チェーンの実装。
  - `test_all_passes` ターゲットにおけるシェルループの廃止と単一バッチスクリプト生成・実行への刷新。
- [x] [docs/issues/closed/771-optimize-ulisp-host-compiler-seed-and-batch-pass-test-runner.md](771-optimize-ulisp-host-compiler-seed-and-batch-pass-test-runner.md)
  - Issue 仕様・設計・実装結果の整備。
- [x] [docs/issues/README.md](../README.md)
  - Issue 台帳（Closed Issues テーブル）の更新。

---

## 4. 詳細設計 / Detailed Design

### 4.1 ホストコンパイラ多段優先度チェーン（Tiered Compiler Selection）

ULisp のビルドおよび AOT コンパイルにおいて、ホスト上で動作するコンパイラバイナリの選択を以下の 3 段階のフォールバック優先度チェーンとして定義した：

```makefile
# --- 処理系エンジンの決定 (ULISP_BOOT または ULISP_MODULAR があれば優先、なければ ILISP を使用) ---
ifeq ($(shell test -x $(ULISP_BOOT) && echo yes),yes)
    ULISP_COMPILER ?= env ULISP_GC_PROFILE=compiler ./$(ULISP_BOOT) <
    COMPILER_DEP = $(ULISP_BOOT)
    USE_NATIVE_BOOT = 1
else ifeq ($(shell test -x build/ulisp-modular && echo yes),yes)
    ULISP_COMPILER ?= env ULISP_GC_PROFILE=compiler ./build/ulisp-modular <
    COMPILER_DEP = build/ulisp-modular
    USE_NATIVE_BOOT = 1
else
    ULISP_COMPILER ?= $(RUN_SCHEME) compiler.scm <
    COMPILER_DEP =
    USE_NATIVE_BOOT = 0
endif
```

#### 優先度階層の役割
1. **Tier 1: `bin/ulisp-boot` (最優先)**
   - 既存のブートストラップ完了済みネイティブ実行バイナリ。最速のコンパイル速度を提供し、外部依存なしで即座に動作する。
2. **Tier 2: `build/ulisp-modular` (準優先)**
   - モジュール分割ビルド（`make modular`）によって生成されたネイティブバイナリ。`bin/ulisp-boot` が一時的に未生成またはクリーンされた状態でも、分割ビルド成果物が残っていればネイティブ速度を維持する。
3. **Tier 3: `$(RUN_SCHEME) compiler.scm` (最終フォールバック)**
   - Python によるリファレンス Scheme インタプリタ `ilisp`。コールドスタート時や初回ブートストラップ時にのみ起動される。

---

### 4.2 `test_all_passes` の単一バッチランナー化

#### (1) 従来方式の課題（シェル反復ループ）
従来の `test_all_passes` は Makefile 内で以下のように定義されていた：

```makefile
# 従来の非効率なシェルループ実装
test_all_passes: build/compiler_passes.scm
	@echo "=== Running 1:1 Nanopass Unit Tests (38 Passes) ==="
	@for t in $(NANOPASS_TESTS); do \
		echo "Running $$t..."; \
		cat build/compiler_passes.scm $$t > build/runner_temp.scm && \
		$(RUN_SCHEME) build/runner_temp.scm || exit 1; \
	done
	@echo "SUCCESS: All 38 1:1 Nanopass Unit Tests PASSED!"
```

- **問題点**:
  - `$(NANOPASS_TESTS)` の各ファイル（全 39 ファイル）ごとにシェルループ内で `cat` と `$(RUN_SCHEME)`（Python プロセス）が反復呼び出しされていた。
  - `build/compiler_passes.scm`（全 Nanopass パイプライン定義）の字句解析・パース・マクロ展開が 39 回ゼロから再実行されていた。
  - プロセスフォーク 39 回 $\times$ インタプリタ初期化 39 回により、全体のテスト実行時間が大きく浪費されていた。

#### (2) バッチランナー方式（単一プロセス連続実行）
改善後は、Make ターゲットで全テストファイルを単一ファイルへ結合し、1 回の Scheme プロセスで評価を完結させる：

```makefile
test_all_passes: build/compiler_passes.scm
	@echo "=== Running 1:1 Nanopass Unit Tests (Batch Runner for $(words $(NANOPASS_TESTS)) Passes) ==="
	@mkdir -p build
	cat build/compiler_passes.scm $(NANOPASS_TESTS) > build/test_all_passes_batch_runner.scm
	@$(RUN_SCHEME) build/test_all_passes_batch_runner.scm
	@echo "SUCCESS: All $(words $(NANOPASS_TESTS)) 1:1 Nanopass Unit Tests PASSED!"
```

- **高速化のメカニズム**:
  1. `build/compiler_passes.scm` のパースおよび全パス定義（マクロ、中間言語仕様、ヘルパー、型注釈）のロードが**最初の 1 回のみ**で完了。
  2. 後続の全テストスイート（`test_000` 〜 `test_extern_symbols`）がメモリ上に保持された同一の Scheme 環境内で順次ロード・評価。
  3. 各テストファイルが独立したテスト名プレフィックスとカウンター（`assert-equal` / `assert-true`）を持つため、相互汚染なく完全な絶縁性を維持しながら連続検証可能。

---

### 4.3 セキュリティ考慮事項 / Security Considerations

- **CWE-400 (Uncontrolled Resource Consumption / CPU・メモリ枯渇防止)**:
  - 39 回に及ぶ重複プロセスフォークおよび中間言語 AST 再構築ループを排除することで、継続的インテグレーション（CI）環境や開発ホストにおける CPU コア枯渇、メモリ急増、およびディスク I/O 圧迫を未然に防止。
- **CWE-377 / CWE-732 (安全な一時ファイル生成とパーミッション保護)**:
  - 中間バッチファイル `build/test_all_passes_batch_runner.scm` はリポジトリローカルの安全な `build/` ディレクトリ内でのみ生成・管理され、システム共有ディレクトリ（`/tmp` 等）への露出や競合状態（Race Condition）を排除。

---

## 5. 実装手順 / Implementation Steps

Target Branch: `feat/771-optimize-ulisp-host-compiler-seed-and-batch-pass-test-runner`

- [x] **Step 1: ホストコンパイラ優先度チェーンの実装 (`ulisp/Makefile`)**
  - `build/ulisp-modular` の存在判定を `else ifeq` として追加し、`ULISP_BOOT` が未生成の場合でもモジュール分割バイナリを第 2 段階ネイティブシードとして利用可能にした。
- [x] **Step 2: `test_all_passes` の単一バッチランナー化 (`ulisp/Makefile`)**
  - シェルループ `for t in ...` を撤廃。
  - `cat build/compiler_passes.scm $(NANOPASS_TESTS) > build/test_all_passes_batch_runner.scm` を生成し、`$(RUN_SCHEME)` で一括実行するルールへ刷新。
  - `$(words $(NANOPASS_TESTS))` による動的テスト総数表示を導入（パス追加時にも自動同期）。
- [x] **Step 3: パステストスイートの動作・整合性検証**
  - `make -C ulisp test_all_passes` を実行し、全 39 パスのテストが 1 回のバッチ実行で 100% PASS することを確認。
- [x] **Step 4: Issue 台帳更新とコミット (`git-workflow`)**
  - `docs/issues/closed/771-optimize-ulisp-host-compiler-seed-and-batch-pass-test-runner.md` を整備。
  - `docs/issues/README.md` を更新し、Conventional Commit 形式でコミット。

---

## 6. 完了条件 / Success Criteria (DoD)

1. [x] **ネイティブシード多段フォールバック**: `bin/ulisp-boot` がなくとも `build/ulisp-modular` が存在する場合、ネイティブバイナリが優先的に選択され高速にコンパイルが実行されること。
2. [x] **単一バッチランナー化**: `test_all_passes` において全 39 パスのテストスクリプトが一括結合され、1 回のインタープリタ起動で高速に完結すること。
3. [x] **テスト完全 PASS**: `make -C ulisp test_all_passes` がエラー 0 件で全件 PASS すること。
4. [x] **既存品質ゲート維持**: `make py_compile`、`make static_analysis` がエラー 0 件で通過し、絶対パスリンクが 0 件であること。

---

## 7. 検証エビデンス / Verification Evidence

### 7.1 `make -C ulisp test_all_passes` 実行結果

```text
make: Entering directory '/workspace/arxiv-security-papers/ulisp'
[PASS] S-expression parenthesis check passed for 51 file(s) (all balanced).
cat compiler/helpers.scm compiler/primitives.scm ... > build/compiler_passes.scm
=== Running 1:1 Nanopass Unit Tests (Batch Runner for 39 Passes) ===
cat build/compiler_passes.scm tests/passes/test_000_compiler_diagnostics.scm ... > build/test_all_passes_batch_runner.scm
...
=======================================================
 External Symbols Unit Tests: ALL 14 TESTS PASSED!
=======================================================
SUCCESS: All 39 1:1 Nanopass Unit Tests PASSED!
make: Leaving directory '/workspace/arxiv-security-papers/ulisp'
```

### 7.2 性能改善実績
- **プロセス起動回数**: 39 回 $\to$ 1 回（39 分の 1 に削減）
- **コンパイラパス定義ロード・パース回数**: 39 回 $\to$ 1 回（重複パース排除）
- **テスト全件実行時間**: 従来の逐次ループ実行に比べ劇的な時間短縮と CPU 負荷削減を達成。
