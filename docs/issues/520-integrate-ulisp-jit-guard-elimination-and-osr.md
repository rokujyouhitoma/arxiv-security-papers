---
ID: 520
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 静的型知識に基づく JIT ガード命令事前消去 (Guard Elimination) と OSR 復元コード合成の実装 (ID: 520)

## 1. 概要 / Summary
現在 `ulisp/jit/` で動作している内因的メタトレーシング JIT（旧 MLisp）は、ループ実行時に動的な型ガード命令（`guard_fixnum` 等）を挿入しているが、S-Annotator（Issue #517）の静的型知識と連携していないため、冗長なガードが大量に残存している。
本 Issue では、S-Annotator の型情報を JIT 最適化パス（`ulisp/jit/optimizer/pe.scm`）に統合し、静的に型が確定している箇所のガード命令を事前消去（A-priori Guard Elimination）するとともに、万一投機が外れた場合の On-Stack Replacement (OSR) 脱出アダプタを自動合成することで、JIT ホットループの実行オーバーヘッドを最小化する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (AOT & JIT 統合アーキテクチャ 第7章)](file:///workspace/arxiv-security-papers/docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-35: Continuous Benchmarking Framework](file:///workspace/arxiv-security-papers/docs/designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md)
- **関連先行 Issue**:
  - Issue #507: 限定継続と ULisp LIR に基づく内因的メタトレーシング JIT ツールチェーンの実装
  - Issue #510: MLisp によるループ構文の自動検知と jit-merge-point 自動計装機能の実装
  - Issue #517: ULisp コンパイラへの抽象解釈型推論器 (S-Annotator) と型格子 (Lattice) の実装
  - Issue #518: ULisp 低水準IR具象化器 (S-RTyper) とアンボクシングによるタグ検査完全消去

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/jit/optimizer/pe.scm](file:///workspace/arxiv-security-papers/ulisp/jit/optimizer/pe.scm) (静的型アノテーションに基づく Guard 消去パス)
- [ ] [ulisp/jit/tracer/tracer.scm](file:///workspace/arxiv-security-papers/ulisp/jit/tracer/tracer.scm) (型付きトレース記録と Guard 生成条件の精緻化)
- [ ] [ulisp/jit/bridge/to_lir.scm](file:///workspace/arxiv-security-papers/ulisp/jit/bridge/to_lir.scm) (OSR 脱出ハンドラおよび Typed LIR 変換)
- [ ] [ulisp/tests/jit/test_guard_elimination.scm](file:///workspace/arxiv-security-papers/ulisp/tests/jit/test_guard_elimination.scm) (新規作成: ガード消去単体テスト)
- [ ] [ulisp/benchmarks/run_benchmarks.sh](file:///workspace/arxiv-security-papers/ulisp/benchmarks/run_benchmarks.sh) (JIT ベンチマーク測定)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/520-ulisp-jit-guard-elimination-and-osr`

1. **静的型環境の JIT エンジンへの注入**:
   - `jit-merge-point` が呼ばれる際、S-Annotator が付与した引数・環境の静的型マップをメタトレーサへ伝達。
2. **Guard 事前消去パスの実装 (`pe.scm`)**:
   - 引数・中間演算結果の型が `SomeFixnum` と保証されている場合、トレースリストから対応する `guard-fixnum` 命令を完全に刈り込む。
   - ループ不変量となる境界チェック・述語ガードの巻き上げ（Loop Invariant Guard Motion）。
3. **OSR（On-Stack Replacement）脱出アダプタの合成**:
   - 残存したガードが失敗した場合、アンボックスされた仮想レジスタを生整数から Tagged Pointer 形式へボクシングして復元し、安全にインタプリタのフレームへ合流させる。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 算術演算ループ（`sum_loop`, `poly_loop`）の JIT トレースにおいて、自明なガード命令が 0 件に削減されること。
- [ ] JIT 実行時の命令数およびガード判定オーバーヘッドが半減し、JIT ベンチマークのスループットが向上すること。
- [ ] `make -C ulisp test_jit` 全 94 件（+新規テスト）が 100% PASS すること。
