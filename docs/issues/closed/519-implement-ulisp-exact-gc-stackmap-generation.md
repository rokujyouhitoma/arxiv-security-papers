---
ID: 519
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] アンボクシング混在環境向け Exact GC スタックマップ (Stackmap) 自動生成機構の実装 (ID: 519)

## 1. 概要 / Summary
Issue #518 のアンボクシング（生 64-bit 整数 `%raw-i64` の導入）に伴い、スタックフレームやレジスタ上に「ヒープポインタ」と「生スカラー整数」が混在することになる。
この環境下でガベージコレクタ（GC）が生整数をポインタと誤認してメモリ破壊を引き起こすリスクを完全に排除するため、RPython と同様にコンパイラがセーフポイント（GC 起動可能地点）ごとにスタックフレームの型レイアウト（ビットマスク）を記録する **スタックマップ（Stackmap）メタデータ自動生成機構** を実装し、100% 正確な Exact GC を実現した。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (AOT & JIT 統合アーキテクチャ)](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-36: Zero-libc / Freestanding Pure Scheme Bare-Metal Runtime Architecture](../../designs/DSN-36-zero_libc_pure_scheme_bare_metal_runtime.md)
- **関連先行 Issue**:
  - Issue #501: ULisp ターゲットランタイム向けガベージコレクタの実装
  - Issue #516: libc/C依存完全排除と 100% Pure Scheme ベアメタル Linux ランタイムの実装
  - Issue #518: ULisp 低水準IR具象化器 (S-RTyper) とアンボクシングによるタグ検査完全消去
- **関連後続 Issue**:
  - Issue #520: ULisp トレースJITにおけるガード除去 (Guard Elimination) とOSR (On-Stack Replacement) の統合

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/00_helpers.scm](../../../ulisp/passes/00_helpers.scm) (`%get-stackmap-table` プリミティブ定義)
- [x] [ulisp/passes/06_lir.scm](../../../ulisp/passes/06_lir.scm) (SafePoint 検出とスタックフレームレイアウト追跡、ビットマップ生成)
- [x] [ulisp/passes/07_backend_x86_64.scm](../../../ulisp/passes/07_backend_x86_64.scm) (`.rodata` セクションへの `__ulisp_stackmap_table` 生成)
- [x] [ulisp/passes/07_backend_aarch64.scm](../../../ulisp/passes/07_backend_aarch64.scm) (AArch64 向けスタックマップテーブル定義)
- [x] [ulisp/passes/07_backend_c.scm](../../../ulisp/passes/07_backend_c.scm) (C バックエンド向けスタックマップエミッタ)
- [x] [ulisp/runtime.c](../../../ulisp/runtime.c) (`__ulisp_stackmap_table` weak シンボル定義)
- [x] [ulisp/lib/gc.scm](../../../ulisp/lib/gc.scm) (スタックマップ参照による Exact GC ルートスキャン `gc-scan-roots!`)
- [x] [ulisp/tests/passes/test_stackmap.scm](../../../ulisp/tests/passes/test_stackmap.scm) (新規作成: スタックマップ単体テスト 6/6 PASS)
- [x] [tests/test_bare_metal_ulisp.py](../../../tests/test_bare_metal_ulisp.py) (`test_bare_metal_exact_gc_stackmap_unboxed` 統合テスト PASS)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/519-ulisp-exact-gc-stackmap-generation`

1. **SafePoint の定義と識別**:
   - アロケーションプリミティブおよび関数呼び出し（`%call-closure`）の直後にセーフポイントラベル `__safepoint_<N>` を発行。
2. **スタックマップ・ビットマスクの計算**:
   - `compute-stackmap-bitmap` により、フレーム内スロット（8バイト単位）を走査。
   - `get-raw-vars` 環境を参照し、生整数スカラー変数スロットには `0`、ヒープポインタおよび `%self` スロットには `1` を割り当てた 64-bit 整数ビットマップを算出。
3. **メタデータテーブル（`.rodata`）のエミット**:
   - `__ulisp_stackmap_table` に `<エントリー数>`, `<セーフポイントラベルアドレス>, <フレームサイズ>, <ビットマップ>` の構造体配列を出力。
4. **GC スタックウォーカーの改修**:
   - `lib/gc.scm` の `gc-find-stackmap` および `gc-scan-roots!` で、RBP チェインを巡回しながらスタックマップのビットマスクに従い、ポインタスロットのみを Cheney's 2-Space GC の転送対象とする Exact GC を実装。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 生整数とポインタが混在する深いスタック状態において、GC がトリガーされても安全に生存オブジェクトのみが回収・コピーされ、生整数が破壊されないこと (`test_bare_metal_exact_gc_stackmap_unboxed` で 100% PASS 検証)。
- [x] 生成される ELF バイナリにスタックマップテーブルが正しく埋め込まれ、サイズオーバーヘッドが最小限であること (`.rodata` にテーブル生成)。
- [x] `make -C ulisp test_passes` (119/119 PASS), `make -C ulisp test_stackmap` (6/6 PASS), `make -C ulisp test_rtyper` (19/19 PASS), `make -C ulisp test_aarch64` (13/13 PASS) が 100% PASS すること。
