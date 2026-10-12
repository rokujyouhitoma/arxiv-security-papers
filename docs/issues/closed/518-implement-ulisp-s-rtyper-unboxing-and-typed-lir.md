---
ID: 518
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] ULisp 低水準IR具象化器 (S-RTyper) とアンボクシングによるタグ検査完全消去 (ID: 518)

## 1. 概要 / Summary
RPython の RTyper（Representation Typer）に倣い、S-Annotator（Issue #517）が推論した高水準抽象型を、低水準のハードウェア表現（`%raw-i64` 生 64-bit 整数、生メモリアドレス）へ具象化する `Pass 05b: S-RTyper` を実装した。
型が確定している純粋算術演算ループにおいて、従来の 64-bit Tagged Pointer のアンボックス (`sar 2`)、ボックス (`sal 2`)、およびタグ・オーバーフロー検査命令を完全に消去し、C 言語直接コンパイルと同等のネイティブ機械語（`add`, `sub`, `imul` 直結）を生成して実行時性能を極限まで加速した。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (AOT & JIT 統合アーキテクチャ)](file:///workspace/arxiv-security-papers/docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-35: Continuous Benchmarking Framework](file:///workspace/arxiv-security-papers/docs/designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md)
- **関連先行 Issue**:
  - Issue #502: ULisp コンパイラへの低レベルIR (LIR) の導入とバックエンド分離
  - Issue #517: ULisp コンパイラへの抽象解釈型推論器 (S-Annotator) と型格子 (Lattice) の実装
- **関連後続 Issue**:
  - Issue #519: ULisp 正確なGCスタックマップ生成器 (Exact GC Stackmap Generator) の実装
  - Issue #520: ULisp トレースJITにおけるガード除去 (Guard Elimination) とOSR (On-Stack Replacement) の統合

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/00_helpers.scm](file:///workspace/arxiv-security-papers/ulisp/passes/00_helpers.scm) (`%raw-*`, `%box-fixnum`, `%unbox-fixnum` プリミティブ定義)
- [x] [ulisp/passes/05b_rtyper.scm](file:///workspace/arxiv-security-papers/ulisp/passes/05b_rtyper.scm) (新規作成: S-RTyper 具象化ロジック)
- [x] [ulisp/passes/06_lir.scm](file:///workspace/arxiv-security-papers/ulisp/passes/06_lir.scm) (Typed LIR 命令群生成、即値アンボックス即時ロード、`*` タグ保持と生算術の直結)
- [x] [ulisp/passes/07_backend_x86_64.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_x86_64.scm) (生整数演算命令のエミットおよび境界ボクシング)
- [x] [ulisp/passes/07_backend_aarch64.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_aarch64.scm) (ARM64 向け生整数コード生成)
- [x] [ulisp/passes/07_backend_c.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_c.scm) (`int64_t` 型直接出力)
- [x] [ulisp/passes/08_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/08_driver.scm) (`ast3c (rtyper-all ast3b)` パイプライン統合)
- [x] [ulisp/lib/string.scm](file:///workspace/arxiv-security-papers/ulisp/lib/string.scm) (`string=?` / `string->symbol` のクロージャ生成排除)
- [x] [ulisp/tests/passes/test_rtyper.scm](file:///workspace/arxiv-security-papers/ulisp/tests/passes/test_rtyper.scm) (新規作成: 19件の RTyper 詳細単体テスト)
- [x] [ulisp/tests/test_passes.scm](file:///workspace/arxiv-security-papers/ulisp/tests/test_passes.scm) (Pass 05b / Pass 06 拡張テストスイート追加、117/117 PASS)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/518-ulisp-s-rtyper-unboxing-and-typed-lir`

1. **Typed LIR オペレーションの導入**:
   - 生整数演算プリミティブ: `(%raw-add dst src1 src2)`, `(%raw-sub ...)`, `(%raw-mul ...)`, `(%raw-cmp ...)`
   - 境界ボクシング/アンボクシング命令: `(%box-fixnum dst raw-src)`, `(%unbox-fixnum dst tagged-src)`
2. **RTyper 具象化変換**:
   - `SomeFixnum` と注釈された純粋末尾再帰ループ変数の仮想レジスタ割付を生レジスタ（Untagged Virtual Register）へマッピング。
   - ループ内演算を生整数命令へ置き換え。
   - 動的 Scheme 境界でのみ明示的な `(%box-fixnum)` を挿入。
3. **バックエンド機械語エミッタの最適化**:
   - x86-64 / AArch64 / C: `sar`/`sal` を介さず、ネイティブ演算命令を直接出力。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 型付き算術ループにおいて、生成されるアセンブリから不要な `sar/sal` 命令が完全に除去されていること。
- [x] `fib`, `fact`, `sum_loop` などの算術ベンチマークで実行時間が短縮されること。
- [x] 既存の動的 Scheme 機能との互換性が 100% 維持され、全テスト・ブートストラップが PASS すること (`diff stage2.s stage3.s == 0` ビット完全一致達成)。
