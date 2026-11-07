---
ID: 778
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] モジュール分割増分コンパイルと make -j 並列実行によるサブセカンド・ブートストラップ基盤の実装 (ID: 778)

## 1. 概要 / Summary

[Issue #608](closed/608-implement-modular-separate-compilation-and-incremental-build.md) において、ULisp コンパイラは各 Nanopass 群および基盤を独立したモジュール（`compiler_base`, `frontend_passes`, `lir_passes`, `backend_passes`, `compiler_driver`）に分割し、`build/ulisp-modular` として静的リンクする機構が確立された。
しかし、ブートストラッププロセス（[ulisp/bootstrap.sh](../../ulisp/bootstrap.sh)）においては、依然として全パスを 1 つにまとめた単一翻訳単位の逐次コンパイルが行われており、マルチコア CPU の並列計算リソースを全く活用できていない。

本 Issue では、モジュール分割コンパイル基盤をブートストラップパイプラインへ本格適用し、以下の機能を実現する：
1. **モジュール単位の並列コンパイル（`make -j$(nproc)`）**:
   - `compiler_base`、`frontend_passes`、`lir_passes`、`backend_passes` の各モジュールを並列バックグラウンドで同時コンパイルし、マルチコア CPU の全コアを活用してビルド時間を極小化する。
2. **増分ブートストラップ（Incremental Bootstrap）**:
   - 変更のあったモジュール（例: フロントエンドの 1 パスのみ修正時）のみを再コンパイルし、既存の未変更 `.o` と再リンクして瞬時に開発用バイナリを更新する。
3. **モジュラー不動点検証プロトコル**:
   - Stage 1 モジュラーバイナリで各モジュールを再コンパイルし、生成される各モジュールのアセンブリ（`*.s`）の一致を並列検証する。

これにより、日常開発時における再ビルド時間を **数秒〜十数秒（最大 100 倍高速化）** へ短縮する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 5 章
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
- 依存・関連 Issue:
  - [Issue #608](closed/608-implement-modular-separate-compilation-and-incremental-build.md): Nanopass・モジュール単位の完全分割コンパイルおよび増分ビルド基盤の実装
  - [Issue #772](closed/772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md): ULisp 標準ライブラリの事前コンパイル済みオブジェクト化と分割静的リンクへの統一
  - [Issue #777](777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md): 事前コンパイル済み標準ライブラリ静的リンクによるコンパイラ単体ブートストラップ

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh)
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
- [ ] [ulisp/tests/test_incremental_build.sh](../../ulisp/tests/test_incremental_build.sh)
- [ ] [docs/issues/README.md](README.md)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/778-implement-modular-parallel-incremental-bootstrap`

1. **Makefile のモジュラーターゲットのブートストラップ統合**:
   - `make -j bootstrap_modular` を新設し、各モジュールオブジェクト（`build/frontend_passes.o`, `build/lir_passes.o`, etc.）の並列ビルドルールを整理。
2. **`bootstrap.sh` への `--modular` オプション追加**:
   - `./bootstrap.sh --modular` 指定時に `build/ulisp-modular` を活用した並列増分パイプラインを駆動。
3. **並列不動点検証（Parallel Fixed-Point Check）**:
   - Stage 1 モジュラーバイナリで Stage 2 の各モジュール `.s` を並列生成し、Stage 3 との差分をモジュール単位で検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 1 つの Nanopass ファイルを変更した際、変更されたモジュールのみが再コンパイルされ、10 秒以内で新しいコンパイラバイナリが生成されること。
- [ ] `make -j` による並列ビルドが CPU コア数に応じてスケールし、クリーンビルド時でも並列化による大幅な時間短縮が達成されること。
- [ ] モジュラービルドされたバイナリがスモークテストおよび既存テストスイートを 100% PASS すること。
- [ ] `make check` / `make verify_quality` がエラー 0 件で通過すること。

