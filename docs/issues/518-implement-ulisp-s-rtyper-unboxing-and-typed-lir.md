---
ID: 518
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ULisp 低水準IR具象化器 (S-RTyper) とアンボクシングによるタグ検査完全消去 (ID: 518)

## 1. 概要 / Summary
RPython の RTyper（Representation Typer）に倣い、S-Annotator（Issue #517）が推論した高水準抽象型を、低水準のハードウェア表現（`%raw-i64` 生 64-bit 整数、生メモリアドレス）へ具象化する `Pass 06: S-RTyper` を実装する。
型が確定している純粋算術演算ループにおいて、従来の 64-bit Tagged Pointer のアンボックス (`sar 3`)、ボックス (`sal 3`)、およびタグ・オーバーフロー検査命令を完全に消去し、C 言語直接コンパイルと同等のネイティブ機械語（`add`, `sub`, `imul` 直結）を生成して実行時性能を極限まで加速する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (AOT & JIT 統合アーキテクチャ)](file:///workspace/arxiv-security-papers/docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-35: Continuous Benchmarking Framework](file:///workspace/arxiv-security-papers/docs/designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md)
- **関連先行 Issue**:
  - Issue #502: ULisp コンパイラへの低レベルIR (LIR) の導入とバックエンド分離
  - Issue #517: ULisp コンパイラへの抽象解釈型推論器 (S-Annotator) と型格子 (Lattice) の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/06_lir.scm](file:///workspace/arxiv-security-papers/ulisp/passes/06_lir.scm) (S-RTyper 具象化ロジックおよび Typed LIR 拡張)
- [ ] [ulisp/passes/07_backend_x86_64.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_x86_64.scm) (生整数演算命令のエミットおよび境界ボクシング)
- [ ] [ulisp/passes/07_backend_aarch64.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_aarch64.scm) (ARM64 向け生整数コード生成)
- [ ] [ulisp/passes/07_backend_c.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_c.scm) (`int64_t` 型直接出力)
- [ ] [ulisp/tests/passes/test_rtyper.scm](file:///workspace/arxiv-security-papers/ulisp/tests/passes/test_rtyper.scm) (新規作成: RTyper 単体テスト)
- [ ] [tools/benchmark_ilisp_ulisp.py](file:///workspace/arxiv-security-papers/tools/benchmark_ilisp_ulisp.py) (ベンチマーク性能測定・比較)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/518-ulisp-s-rtyper-unboxing-and-typed-lir`

1. **Typed LIR オペレーションの導入**:
   - 生整数演算プリミティブ: `(%raw-add dst src1 src2)`, `(%raw-sub ...)`, `(%raw-mul ...)`, `(%raw-cmp ...)`
   - 境界ボクシング/アンボクシング命令: `(%box-fixnum dst raw-src)`, `(%unbox-fixnum dst tagged-src)`
2. **RTyper 具象化変換**:
   - `SomeFixnum` と注釈された ANF 変数の仮想レジスタ割付を生レジスタ（Untagged Virtual Register）へマッピング。
   - ループ内演算を生整数命令へ置き換え。
   - 動的 Scheme 境界（多相関数呼び出し、ヒープセル格納、I/O 出力）でのみ明示的な `(%box-fixnum)` を挿入。
3. **バックエンド機械語エミッタの最適化**:
   - x86-64: `sar`/`sal` を介さず、`add %reg, %reg` などを直接出力。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 型付き算術ループにおいて、生成されるアセンブリから不要な `sar/sal` 命令が完全に除去されていること。
- [ ] `fib`, `fact`, `sum_loop` などの算術ベンチマークで実行時間がさらに短縮されること。
- [ ] 既存の動的 Scheme 機能との互換性が 100% 維持され、全テスト・ブートストラップが PASS すること。
