---
ID: 569
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] x86-64 バックエンドからの GC コレクタおよびフリースタンディングランタイムの物理的パス分離 (ID: 569)

## 1. 概要 / Summary
`ulisp/passes/140_backend_x86_64.scm` (84KB / 2,252行) に巨大な一枚岩として同居しているインライン GC コレクタ生成ルーチン (`emit-gc-collector`) および libc なしベアメタル用ランタイム生成ルーチン (`emit-freestanding-runtime`) を、Nanopass 設計方針および単一責務の原則 (Single Responsibility Principle) に基づき、それぞれ `ulisp/passes/141_backend_x86_gc.scm` および `ulisp/passes/142_backend_x86_freestanding.scm` に物理的に分離・独立化する。
これにより、AST 走査回数およびコンパイル・自己ホスト性能のペナルティを一切生じることなく、バックエンドコード生成部の可読性・保守性および並行開発性を劇的に向上させる。

---

## 2. トレーサビリティ / Traceability
- 関連仕様書:
  - [DSN-33 (ULisp アーキテクチャ包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 仕様書](../ulisp/docs/pipeline_architecture.md)
  - Issue #553 (ULisp コンパイラアーキテクチャのモジュール分離)
  - Issue #568 (Pass 131 スタックマップと保守的スタック走査のフォールバック・ハイブリッド化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/140_backend_x86_64.scm](../../ulisp/passes/140_backend_x86_64.scm)
- [x] [ulisp/passes/141_backend_x86_gc.scm](../../ulisp/passes/141_backend_x86_gc.scm)
- [x] [ulisp/passes/142_backend_x86_freestanding.scm](../../ulisp/passes/142_backend_x86_freestanding.scm)
- [x] [ulisp/Makefile](../../ulisp/Makefile)
- [x] [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/569-separate-x86-gc-collector-and-freestanding-runtime-passes`

1. `emit-gc-collector` および関連ヘルパーを `ulisp/passes/141_backend_x86_gc.scm` に抽出・定義。
2. `emit-freestanding-runtime` および関連文字列定数・出力関数群を `ulisp/passes/142_backend_x86_freestanding.scm` に抽出・定義。
3. `140_backend_x86_64.scm` を純粋な LIR 命令選択およびアセンブリコード生成ルーチンに専念させる。
4. `ulisp/Makefile` の `PASSES_LIB` に `passes/141_backend_x86_gc.scm` と `passes/142_backend_x86_freestanding.scm` を追加し、`compiler.scm` 連結パイプラインを整合化。
5. 全既存テスト (`make test`, `make test_aot`, `make test_freestanding`, `make test_gc_hybrid`) が完全一致でパスすることを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `emit-gc-collector` が `141_backend_x86_gc.scm` に独立して存在すること。
- [x] `emit-freestanding-runtime` が `142_backend_x86_freestanding.scm` に独立して存在すること。
- [x] `ulisp/Makefile` のビルドターゲットおよび `compiler.scm` 生成ルールが更新されていること。
- [x] `make test_aot`, `make test_freestanding`, `make test_gc_hybrid` を含む全品質ゲートが PASS すること。

