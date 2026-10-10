---
ID: 509
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT/ENH] MLisp JIT 実行基盤による ULisp コンパイラ (compiler.scm) のコンパイルと自己ホスティングバイナリ出力 (ID: 509)

## 1. 概要 / Summary
MLisp の内因的メタトレーシング JIT 実行基盤（shift/reset 限定継続、トレーサ、PE 最適化、LIR ブリッジ、JIT バッファ）を用いて ULisp コンパイラ（`ulisp/compiler.scm`）を実行し、ULisp のコア言語処理系（`ulisp/build/ulisp_core.scm`）をコンパイルしてネイティブアセンブリ（`ulisp/build/stage_mlisp.s`）およびスタンドアロン ELF バイナリ（`ulisp/build/scheme-from-mlisp`）を出力する。
これにより、Python（ILisp）に依存していた Stage 1 のブートストラップコンパイルを MLisp の JIT 実行基盤へと置き換え可能とし、MLisp と ULisp の完全自己ホスティング循環コンパイルを実証する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-34: MLisp 内因的メタトレーシング JIT アーキテクチャ仕様書 §5.1 ビルド時パイプライン (Pure Scheme JIT VM)](../designs/DSN-34-mlisp_endogenous_meta_tracing_jit_architecture_specification.md)
- 関連 Issue: [Issue 508: MLisp の AOT 統合および JIT 内蔵型ワンバイナリ (scheme-jit) の生成](closed/508-integrate-mlisp-with-ulisp-aot-compiler.md)
- 関連 Issue: [Issue 493: ULisp Phase 7 セルフホスティングブートストラップ連鎖と不動点検証](closed/493-implement-ulisp-phase7-self-hosting-bootstrap-and-fixed-point.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [mlisp/Makefile](../../mlisp/Makefile) (`compile_ulisp` ターゲット追加)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`stage_mlisp`, `run_mlisp_stage` ターゲット追加)
- [x] [mlisp/driver/compile_ulisp_runner.scm](../../mlisp/driver/compile_ulisp_runner.scm) (MLisp JIT 統合コンパイルランナー)
- [x] [ulisp/build/scheme-from-mlisp](../../ulisp/build/scheme-from-mlisp) (MLisp 経由で生成された ULisp ネイティブバイナリ)
- [x] [mlisp/README.md](../../mlisp/README.md) (MLisp による ULisp コンパイル手順の記載)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/509-compile-ulisp-via-mlisp-jit`

1. **MLisp JIT 統合コンパイルランナーの作成**:
   - MLisp のコアモジュール（`delimcc.scm`, `tracer.scm`, `pe.scm`, `virtuals.scm`, `to_lir.scm`, `jit_buffer.scm`）と ULisp コンパイラ（`ulisp/compiler.scm`）を結合するランナーを構築。
   - `ulisp/build/ulisp_core.scm` を入力として標準入力から読み込み、ULisp Pass 0〜7 を実行して x86-64 アセンブリを出力。
2. **Makefile ビルドターゲットの整備**:
   - `ulisp/Makefile` に `stage_mlisp` ターゲットを追加し、MLisp 経由で `build/stage_mlisp.s` を生成、GCC で `ulisp/runtime.c` とリンクして `ulisp/build/scheme-from-mlisp` をビルド。
   - `mlisp/Makefile` に `compile_ulisp` ターゲットを追加。
3. **自己ホスティングバイナリの動作検証**:
   - 生成された `ulisp/build/scheme-from-mlisp` を実行し、Scheme ソースコードのコンパイルが正常に行われることを検証。
4. **品質ゲートのパスとドキュメント化**:
   - `make -C mlisp test` および既存テストが 100% PASS することを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] MLisp JIT 基盤を用いて `ulisp/compiler.scm` を実行し、`ulisp/build/ulisp_core.scm` から `ulisp/build/stage_mlisp.s` が生成されること
- [x] GCC によるリンクを経て、スタンドアロン実行可能ファイル `ulisp/build/scheme-from-mlisp` が正常に出力されること
- [x] 生成された `scheme-from-mlisp` バイナリがネイティブ実行され、Scheme プログラムのコンパイルを行えること
- [x] `make -C mlisp test` および全品質ゲートが 100% PASS すること

---

## 6. 検証結果 / Verification Results
1. **ULisp コアライブラリの拡張**:
   - `ulisp/lib/string.scm` に Pure Scheme 実装の `substring` 手続きを追加し、LIR 変換時の未定義シンボル参照を解消。
2. **MLisp JIT 統合ランナー (`mlisp/driver/compile_ulisp_runner.scm`)**:
   - MLisp の限定継続、トレーサ、PE 最適化、LIR ブリッジ、JIT バッファと ULisp コンパイラを結合。
   - `build/ulisp_core.scm` から 1.7MB の完全 x86-64 アセンブリ `ulisp/build/stage_mlisp.s` を出力。
3. **スタンドアロン ELF バイナリ (`ulisp/build/scheme-from-mlisp`)**:
   - GCC によるリンク完了（サイズ 414KB ELF）。
   - `(+ 40 2)` のコンパイルおよび実行結果 `42` の照合に PASS。
   - 再帰関数 `(fact 5)` のコンパイルおよび実行結果 `120` の照合に PASS。
   - `scheme-from-mlisp` 自身による `ulisp_core.scm` の完全自己コンパイル（1.7MB の次期ステージアセンブリ出力および実行 `(+ 100 200) = 300` 検証）に PASS。
4. **Makefile ターゲット統合**:
   - `ulisp/Makefile`: `stage_mlisp`, `run_mlisp_stage` ターゲット実装完了。
   - `mlisp/Makefile`: `compile_ulisp` ターゲット実装完了。
5. **テストスイート & 品質ゲート**:
   - `make -C mlisp test`: 70項目 100% PASS。
   - `make py_compile`: 100% PASS。
