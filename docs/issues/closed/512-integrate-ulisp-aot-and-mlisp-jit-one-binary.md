---
ID: 512
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ULisp AOT コンパイラと MLisp JIT エンジンを統合したワンバイナリ (ulisp-jit) の構築と性能比較評価 (ID: 512)

## 1. 概要 / Summary
ULisp（AOT コンパイラ型 Scheme 処理系）の Nanopass コンパイル基盤と、MLisp（内因的メタトレーシング JIT）の実行エンジンを統合し、外部の Python/Scheme 処理系に依存せず、AOT コンパイル（`.s` 出力）と JIT 動的実行の双方を提供するスタンドアロンワンバイナリ `mlisp/bin/ulisp-jit` を構築した。
ULisp は AOT として一定の完成度を有するため、`ulisp/` 配下のソースコード修正は行わず（逆依存ゼロの原則を厳格に順守）、すべて `mlisp/` 配下に集約して実装した。
また、完成した `mlisp/bin/ulisp-jit` と純粋 AOT バイナリ `ulisp/build/scheme-stage2` のコンパイル速度・実行速度・メモリ使用量に関する性能評価・比較レポートを `mlisp/benchmarks/README.md` に作成した。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-34: MLisp 内因的メタトレーシング JIT アーキテクチャ仕様書](../designs/DSN-34-mlisp_endogenous_meta_tracing_jit_architecture_specification.md)
- 関連設計書: [DSN-33: ULisp x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- 関連 Issue: [Issue 511: 任意の Scheme コードを動的 JIT 実行するスタンドアロンバイナリ (ulisp-jit) の生成コマンド実装](closed/511-implement-ulisp-jit-binary-generation.md)
- 関連 Issue: [Issue 509: MLisp JIT 実行基盤による ULisp コンパイラ (compiler.scm) のコンパイルと自己ホスティングバイナリ出力](closed/509-compile-ulisp-compiler-via-mlisp-jit.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [mlisp/driver/ulisp_jit.scm](../../mlisp/driver/ulisp_jit.scm) (ULisp AOT Nanopass と MLisp JIT を結合したハイブリッド処理系ドライバ)
- [x] [mlisp/Makefile](../../mlisp/Makefile) (`ulisp-jit`, `run_ulisp_jit`, `compile_ulisp` ターゲット)
- [x] [mlisp/benchmarks/benchmark_stage2_vs_ulisp_jit.py](../../mlisp/benchmarks/benchmark_stage2_vs_ulisp_jit.py) (ベンチマーク測定ランナー)
- [x] [mlisp/benchmarks/README.md](../../mlisp/benchmarks/README.md) (性能比較レポート: scheme-stage2 vs ulisp-jit)
- [x] [mlisp/README.md](../../mlisp/README.md) (AOT + JIT 統合ワンバイナリ仕様およびベンチマーク結果の追記)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/512-integrate-ulisp-aot-and-mlisp-jit-one-binary`

1. **ULisp 非侵入型の統合コア構築 (`mlisp/driver/ulisp_jit.scm`)**:
   - `ulisp/` 配下のソースコード（`lib/*.scm`, `compiler.scm` 等）は変更せず、そのまま読み込み資産として活用。
   - `mlisp/` 側で以下の全レイヤーを結合：
     1. ULisp 標準ライブラリ・リーダー・プリンター (`ulisp/lib/string.scm`, `reader.scm`, `printer.scm`, `gc.scm`)
     2. MLisp JIT ツールチェーン (`tracer`, `auto_instrument`, `pe`, `virtuals`, `to_lir`, `jit_buffer`)
     3. ULisp AOT コンパイラ全パス (`passes/00_helpers.scm` 〜 `passes/07_backend_x86_64.scm`, `c`, `aarch64`)
     4. 統合ハイブリッド CLI ドライバ:
        - `(!compile)` または `(!target ...)` のあるコードを受け取った場合: AOT パイプラインを実行して標準出力に x86-64 / C / AArch64 アセンブリを出力。
        - それ以外の純粋 Scheme 式を受け取った場合: JIT 自動計装を経て高速に JIT 実行・計算結果を出力。
2. **自己ホスティング AOT コンパイル (`make -C mlisp ulisp-jit`)**:
   - `compiler.scm` を用いて `ulisp_jit_combined.scm` をネイティブアセンブリにコンパイルし、`runtime.c` とリンクして `mlisp/bin/ulisp-jit` を生成。
3. **性能評価・比較ベンチマークの実装**:
   - 以下の2つのバイナリを比較：
     - `ulisp/build/scheme-stage2` (純粋な AOT コンパイラ)
     - `mlisp/bin/ulisp-jit` (AOT コンパイラ + JIT 統合バイナリ)
   - 比較項目：
     - (a) 小規模 Scheme プログラムの AOT コンパイル時間（例: `(+ 40 2)`）: 1.07ms vs 0.93ms (同等)
     - (b) 再帰関数プログラム（階乗 10!）: 3.09ms vs 2.13ms (同等)
     - (c) 分岐再帰（fib 12）: 2.56ms vs 2.58ms (同等)
     - (d) JIT ループ実行によるインプロセス実行: 67ms (GCC 不要) vs AOT 事前ビルド実行 0.51ms
4. **品質ゲートとドキュメント化**:
   - `make -C mlisp test`（全94テスト合格）
   - `make -C mlisp run_ulisp_jit`（JIT 実行・AOT コンパイルの双方パス）

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/` 配下のソースコードを変更することなく、`mlisp/` 側で AOT コンパイルと JIT 実行を両立する `mlisp/bin/ulisp-jit` が生成されること
- [x] `(!compile) (+ 40 2)` または `(!compile) (fact 5)` で AOT アセンブリが出力され、GCC リンク後に `42` / `120` が実行されること
- [x] `echo "(let loop ...)" | ./mlisp/bin/ulisp-jit` で JIT トレースが実行され、結果が正しく出力されること
- [x] `scheme-stage2` と `ulisp-jit` の性能評価・比較レポートが作成され、客観的メトリクスが文書化されること
- [x] 全品質ゲートが 100% PASS すること
