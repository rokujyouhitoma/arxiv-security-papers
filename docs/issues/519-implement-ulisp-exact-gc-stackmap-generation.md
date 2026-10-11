---
ID: 519
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] アンボクシング混在環境向け Exact GC スタックマップ (Stackmap) 自動生成機構の実装 (ID: 519)

## 1. 概要 / Summary
Issue #518 のアンボクシング（生 64-bit 整数 `%raw-i64` の導入）に伴い、スタックフレームやレジスタ上に「ヒープポインタ」と「生スカラー整数」が混在することになる。
この環境下でガベージコレクタ（GC）が生整数をポインタと誤認してメモリ破壊を引き起こすリスクを完全に排除するため、RPython と同様にコンパイラがセーフポイント（GC 起動可能地点）ごとにスタックフレームの型レイアウト（ビットマスク）を記録する **スタックマップ（Stackmap）メタデータ自動生成機構** を実装し、100% 正確な Exact GC を実現する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (AOT & JIT 統合アーキテクチャ)](file:///workspace/arxiv-security-papers/docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-36: Zero-libc / Freestanding Pure Scheme Bare-Metal Runtime Architecture](file:///workspace/arxiv-security-papers/docs/designs/DSN-36-zero_libc_pure_scheme_bare_metal_runtime.md)
- **関連先行 Issue**:
  - Issue #501: ULisp ターゲットランタイム向けガベージコレクタの実装
  - Issue #516: libc/C依存完全排除と 100% Pure Scheme ベアメタル Linux ランタイムの実装
  - Issue #518: ULisp 低水準IR具象化器 (S-RTyper) とアンボクシングによるタグ検査完全消去

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/06_lir.scm](file:///workspace/arxiv-security-papers/ulisp/passes/06_lir.scm) (SafePoint 検出とスタックフレームレイアウト追跡)
- [ ] [ulisp/passes/07_backend_x86_64.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_x86_64.scm) (`.rodata` セクションへのスタックマップテーブル生成)
- [ ] [ulisp/runtime.c](file:///workspace/arxiv-security-papers/ulisp/runtime.c) (Cheney GC のスタックマップ参照対応)
- [ ] [ulisp/lib/posix.scm](file:///workspace/arxiv-security-papers/ulisp/lib/posix.scm) (Zero-libc 環境における Pure Scheme GC スタック走査)
- [ ] [ulisp/tests/passes/test_stackmap.scm](file:///workspace/arxiv-security-papers/ulisp/tests/passes/test_stackmap.scm) (新規作成: スタックマップ整合性検証テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/519-ulisp-exact-gc-stackmap-generation`

1. **SafePoint の定義と識別**:
   - アロケーションプリミティブ（`%alloc-cons`, `%alloc-closure`, `%alloc-vector`）および関数呼び出し命令の直前にラベル `__safe_point_<N>` を発行。
2. **スタックマップ・ビットマスクの計算**:
   - 当該セーフポイントで生存しているスタックフレームの全スロット（8 バイト単位）について、ポインタ（`1`）か生整数（`0`）かを表すビットマスクを生成。
3. **メタデータテーブル（`.rodata`）のエミット**:
   - `__ulisp_stackmap_table`: リターンアドレス（またはセーフポイント PC）からフレームサイズおよびポインタビットマスクへのマッピング構造体を配置。
4. **GC スタックウォーカーの改修**:
   - GC ルート走査時、スタックフレームのアドレスを順に遡り、スタックマップを参照してビットが `1` のスロットのみを Cheney's 2-Space GC / ベアメタル GC の転送対象とする。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 生整数とポインタが混在する深いスタック状態において、GC がトリガーされても安全に生存オブジェクトのみが回収・コピーされること。
- [ ] 生成される ELF バイナリにスタックマップテーブルが正しく埋め込まれ、サイズオーバーヘッドが最小限であること。
- [ ] `make -C ulisp test_passes` および GC ストレステストが 100% PASS すること。
