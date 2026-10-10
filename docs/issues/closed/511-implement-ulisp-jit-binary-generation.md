---
ID: 511
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] 任意の Scheme コードを動的 JIT 実行するスタンドアロンバイナリ (ulisp-jit) の生成コマンド実装 (ID: 511)

## 1. 概要 / Summary
標準入力から任意の Scheme ソースコードを読み込み、MLisp の自動ループ計装（Auto-Instrumentation）によって `jit-merge-point` を透過的に挿入し、内因的メタトレーシング JIT エンジンによってホットループを動的に x86-64 機械語へ JIT コンパイルして高速実行するスタンドアロンネイティブバイナリ `ulisp-jit`（およびビルドコマンド `make ulisp-jit`）を実装する。
これにより、ユーザーは手動アノテーションを一切記述することなく、純粋な Scheme コードをワンバイナリの JIT 実行環境で即座に高速実行可能となる。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-34: MLisp 内因的メタトレーシング JIT アーキテクチャ仕様書](../designs/DSN-34-mlisp_endogenous_meta_tracing_jit_architecture_specification.md)
- 関連 Issue: [Issue 510: MLisp によるループ構文の自動検知と jit-merge-point 自動計装機能の実装](closed/510-implement-mlisp-auto-instrumentation-for-jit-merge-points.md)
- 関連 Issue: [Issue 509: MLisp JIT 実行基盤による ULisp コンパイラ (compiler.scm) のコンパイルと自己ホスティングバイナリ出力](closed/509-compile-ulisp-compiler-via-mlisp-jit.md)
- 関連 Issue: [Issue 508: MLisp の AOT 統合および JIT 内蔵型ワンバイナリ (scheme-jit) の生成](closed/508-integrate-mlisp-with-ulisp-aot-compiler.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [mlisp/driver/ulisp_jit.scm](../../mlisp/driver/ulisp_jit.scm) (新規作成: S式リーダー + 自動計装 + JIT エンジン統合ドライバ)
- [x] [mlisp/Makefile](../../mlisp/Makefile) (`ulisp-jit`, `run_ulisp_jit` ターゲット追加)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`ulisp-jit` 転送ターゲット追加)
- [x] [mlisp/README.md](../../mlisp/README.md) (`ulisp-jit` のビルド・実行手順および動作例の記載)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/511-ulisp-jit-binary-generation`

1. **JIT 搭載型スタンドアロン Scheme ドライバ (`mlisp/driver/ulisp_jit.scm`) の作成**:
   - AOT 向け Scheme 基本ヘルパーおよびボックス化可変セル (`make-cell`, `cell-get`, `cell-set!`)。
   - 限定継続（shift/reset）、メタトレーサ（`tracer.scm`）、自動計装（`auto_instrument.scm`）、トレース最適化（`pe.scm`, `virtuals.scm`）、LIR ブリッジ（`to_lir.scm`）、JIT メモリバッファ（`jit_buffer.scm`）を統合。
   - ULisp の S 式リーダー（`read-char`, `read`）を組み込み、標準入力から任意の Scheme フォームを動的読み込み。
   - 読み込まれたフォームを `auto-instrument-forms` に通し、Named `let` や自己末尾再帰ループに透過的に `jit-merge-point` を注入。
   - Scheme 評価器（`eval-expr`）で逐次実行し、ホットループに到達すると JIT トレーサがトレース生成・PE 最適化・LIR 変換・機械語バッファインストールを経てネイティブディスパッチを実行。
   - 最終評価結果を標準出力に表示。

2. **Makefile ビルドターゲットの整備**:
   - `mlisp/Makefile` に `ulisp-jit: bin/ulisp-jit` および `run_ulisp_jit` ターゲットを追加。
   - ULisp AOT コンパイラ（`ULISP_STAGE2` または `ULISP_STAGE1`）と GCC で `ulisp/runtime.c` とリンクし、単一 ELF バイナリ `bin/ulisp-jit` を生成。
   - `ulisp/Makefile` に `ulisp-jit` ターゲットを追加（`mlisp/Makefile` への透過委任）。

3. **動作検証 & 品質ゲート**:
   - 標準入力から未注釈の Scheme ループ `(let loop ((i 0) (sum 0)) (if (< i 10) (loop (+ i 1) (+ sum i)) sum))` を渡し、`bin/ulisp-jit` が正常に `45` を出力し、JIT トレースが実行されることを実証。
   - `make -C mlisp test` および全品質ゲート（`make check_format`, `make static_analysis`）が 100% PASS することを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `make -C mlisp ulisp-jit`（または `make -C ulisp ulisp-jit`）コマンドにより、スタンドアロン実行可能ファイル `mlisp/bin/ulisp-jit` が生成されること
- [x] 標準入力から与えられた未注釈の Scheme コードが正しく読み込まれ、自動計装を経て JIT 実行されること
- [x] 計算結果が標準出力に正しく出力されること
- [x] `make -C mlisp test` および全品質ゲートが 100% PASS すること


