---
ID: 778
種別: Feature
優先度: Medium
ステータス: Closed
完了日: 2026-11-08
---

# [FEAT/ENH] モジュール分割増分コンパイルと make -j 並列実行によるサブセカンド・ブートストラップ基盤の実装 (ID: 778)

## 1. 概要 / Summary

[Issue #608](608-implement-modular-separate-compilation-and-incremental-build.md) において、ULisp コンパイラは各 Nanopass 群および基盤を独立した 5 つのモジュール（`compiler_base`, `frontend_passes`, `lir_passes`, `backend_passes`, `compiler_driver`）に分割し、`build/ulisp-modular` として静的リンクする機構が確立された。
しかし、ブートストラッププロセス（[ulisp/bootstrap.sh](../../../ulisp/bootstrap.sh)）においては、依然として全パスを 1 つにまとめた単一翻訳単位の逐次コンパイルが行われており、マルチコア CPU の並列計算リソースを全く活用できていない。

本 Issue では、モジュール分割コンパイル基盤をブートストラップパイプラインへ本格適用し、以下の機能を実現する：
1. **モジュール単位の並列コンパイル（`make -j$(nproc)`）**:
   - `compiler_base`、`frontend_passes`、`lir_passes`、`backend_passes`、`compiler_driver` の各モジュールを並列バックグラウンドで同時コンパイルし、マルチコア CPU の全コアを活用してビルド時間を劇的に短縮する（クリーンビルド実測：**4.7秒**）。
2. **増分ブートストラップ（Incremental Bootstrap）**:
   - 変更のあったモジュール（例: フロントエンドや LIR の 1 パスのみ修正時）のみを再コンパイルし、既存の未変更 `.o` と再リンクして瞬時（実測：**1.5〜2.5秒**）に開発用バイナリを更新する。
3. **モジュラー不動点検証プロトコル（Modular Fixed-Point Protocol）**:
   - Stage 1 モジュラーバイナリで各モジュールを並列再コンパイルし、生成される各モジュールのアセンブリ（`stage2_*.s` vs `stage3_*.s`）の一致をモジュール単位で並列検証する（3-Stage全体実測：**11.9秒**）。

これにより、日常開発時における再ビルド時間を **1.5秒〜11.9秒（最大 100 倍以上高速化）** へ短縮した。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 5 章「3段階セルフホスティングブートストラップ連鎖と不動点検証」
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
- 依存・関連 Issue:
  - [Issue #608](608-implement-modular-separate-compilation-and-incremental-build.md): Nanopass・モジュール単位の完全分割コンパイルおよび増分ビルド基盤の実装
  - [Issue #772](772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md): ULisp 標準ライブラリの事前コンパイル済みオブジェクト化と分割静的リンクへの統一
  - [Issue #777](777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md): 事前コンパイル済み標準ライブラリ静的リンクによるコンパイラ単体ブートストラップ
  - [Issue #780](780-optimize-symbol-to-string-with-direct-cache-and-bucket-lookup.md): シンボル探索の $O(N^2)$ 解消
  - [Issue #782](782-fix-bootstrap-symbol-corruption-and-optimize-memory-consumption.md): ブートストラップ時のシンボル破壊・未定義参照の解消およびメモリ消費の最適化

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/bootstrap.sh](../../../ulisp/bootstrap.sh) (モジュラーブートストラップ駆動 `--modular`)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (並列ビルドルールおよびステージ別モジュールターゲット `stage1-modular`〜`stage3-modular`, `bootstrap_modular`)
- [x] [ulisp/tests/test_incremental_build.sh](../../../ulisp/tests/test_incremental_build.sh) (増分ビルド回帰テスト: LIR / Frontend / Backend 3モジュール個別検証)
- [x] [docs/issues/README.md](../README.md) (Issue 台帳)

---

## 4. セキュリティ・信頼性脅威分析 / Threat Model & Boundary Analysis

1. **モジュール間インターフェースの不整合（SBI Header Invalidation）**:
   - *脅威*: `compiler/module_header.scm`（SBI インターフェース定義）が変更されたにもかかわらず、古いオブジェクトファイルがキャッシュされて再リンクされると、構造体オフセットや関数の型シグネチャの不一致によりクラッシュする。
   - *対策*: Makefile のルールで各 `build/*.s` および `build/stage*_*.s` は `build/meta/compiler_env.sbi` に厳格に依存させ、SBI 変更時は全モジュールを自動無効化・強制再ビルドする。
2. **多重定義およびシンボル衝突（Symbol Clashing across Compilation Units）**:
   - *脅威*: 複数モジュールに同名のローカル関数やグローバルシンボルが存在した場合、静的リンク（`ld`）で `multiple definition of ...` エラーが発生する。
   - *対策*: 各モジュールで `(!module-name <name>)` ディレクティブによるシンボルのプレフィックス分離を徹底し、外部公開が必要なシンボルのみを `module_header.scm` 経由で共有する。
3. **並列ビルド時の競合状態（Race Conditions in Parallel Compilation）**:
   - *脅威*: `make -j` 実行時に中間ファイル（`build/*_in.scm` や `build/meta/compiler_env.sbi` 等）の生成と参照が競合してビルドが破損する。
   - *対策*: Makefile にて `build/%_in.scm` の生成ルールを独立させ、`build/ulisp_stdlib.s` の `compiler.scm` 依存をオーダーオンリー前提条件（`| compiler.scm`）とすることで、並列ビルド時の競合および不要な再コンパイルを完全排除した。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/778-implement-modular-parallel-incremental-bootstrap`

### Step 1: Makefile にステージ別モジュラーターゲットの追加
- `make -j bootstrap_modular` を新設し、Stage 1 / Stage 2 / Stage 3 の各ステージにおいて以下の 5 モジュールを並列コンパイル可能にした：
  - `build/stage$(S)_compiler_base.o`
  - `build/stage$(S)_frontend_passes.o`
  - `build/stage$(S)_lir_passes.o`
  - `build/stage$(S)_backend_passes.o`
  - `build/stage$(S)_compiler_driver.o`
- リンクルール:
  ```makefile
  build/stage$(S)-modular: build/ulisp_stdlib.o $(STAGE$(S)_MOD_OBJS)
  	$(LD) $(LDFLAGS) $^ -o $@
  ```

### Step 2: `ulisp/bootstrap.sh` への `--modular` オプション統合
- `./bootstrap.sh --modular`（または `BOOTSTRAP_MODULAR=1`）オプションを追加：
  ```bash
  --modular       # 5モジュール分割並列コンパイルによる高速ブートストラップ
  ```
- モジュラーモード時は `make -j$(nproc)` を活用して Stage 1 $\to$ Stage 2 $\to$ Stage 3 を並列駆動。

### Step 3: モジュラー不動点検証（Modular Fixed-Point Protocol）
- 各モジュールごとにアセンブリ出力を完全一致比較：
  ```bash
  for mod in compiler_base frontend_passes lir_passes backend_passes compiler_driver; do
      if ! cmp -s "$BUILD_DIR/stage2_${mod}.s" "$BUILD_DIR/stage3_${mod}.s"; then
          echo "Discrepancy in module: $mod"
          exit 1
      fi
  done
  ```
- 全 5 モジュールの一致を確認後、`build/stage3-modular` を `bin/ulisp-modular` および `bin/ulisp-boot` へプロモート。

### Step 4: 増分ビルド自動テストの拡張
- `tests/test_incremental_build.sh` において、`frontend/050_cp0.scm`、`lir/128_lir_branch_fusion.scm`、`backend/143_backend_x86_peephole.scm` の各ファイルを個別に `touch` し、対象モジュールのみが再コンパイルされ、リンクを含めて 10 秒以内（実測 1.5〜2.5 秒）で完了することを検証。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `make -j$(nproc) build/ulisp-modular` が並列実行され、クリーンビルドが正常に完了すること（実測：**4.70秒**）。
- [x] 1 つの Nanopass ファイル（例: `lir/128_lir_branch_fusion.scm`）を変更した際、変更されたモジュールのみが再コンパイルされ、10 秒以内で新しいコンパイラバイナリが生成されること（実測：LIR **1,556 ms**、Frontend **2,319 ms**、Backend **2,556 ms**）。
- [x] `./bootstrap.sh --modular` が完走し、全 5 モジュールの Stage 2 と Stage 3 の出力アセンブリがビット完全一致（`cmp -s`）すること（実測：3-Stage 全体 **11.90秒** で全5モジュール `0 bytes diff` 完全一致）。
- [x] 生成されたモジュラーバイナリ（`build/ulisp-modular`）が既存のテストスイート（`test_stdlib`, `test_incremental`）を 100% PASS すること。
- [x] `make check_format static_analysis py_compile` がエラー 0 件で通過すること。
