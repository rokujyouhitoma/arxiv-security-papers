---
ID: 564
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] バックエンド %alloc からの世代別コピーGC自動トリガーおよびスタックマップ回収ルーチンの直接結線 (ID: 564)

## 1. 概要 / Summary
Issue #563 において、ヒープ上限チェック（`ulisp_heap_limit`）および上限超過時の安全停止ハンドラ（`ulisp_oom_panic`）が配備された。
本 Issue では、すでに [ulisp/lib/gc.scm](../../ulisp/lib/gc.scm) に実装されている Cheney 型 2 空間コピー GC および世代別コピー GC、ならびに [ulisp/passes/131_lir_safepoint.scm](../../ulisp/passes/131_lir_safepoint.scm) の Exact GC スタックマップテーブル（`__ulisp_stackmap_table`）を活用し、`%alloc` の上限判定から自動的に GC コレクタ（スローパス）を起動して不要オブジェクトを回収・ヒープを巻き戻して処理を継続する完全な自動ガベージコレクション機構をバックエンドに結線する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第8.5節 TBAA・エスケープ解析 & 世代別GC)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-36: Zero-libc / Freestanding Pure Scheme Bare-Metal Runtime](../designs/DSN-36-zero_libc_pure_scheme_bare_metal_runtime.md)
- **関連先行 Issue**:
  - Issue #519: アンボクシング混在環境向け Exact GC スタックマップ (Stackmap) 自動生成機構の実装
  - Issue #525: TBAA・エスケープ解析に基づくスタック割当昇格とナーサリ世代別コピーGCの実装
  - Issue #530: コンパイル時 GC 切り替え機構 (!gc ディレクティブ / --gc オプション) および Arena (GC-None) モードの実装
  - Issue #563: コンパイラの大規模AST変換時における12GBヒープ枯渇とOOMセーフガード欠如によるSEGVクラッシュの解消

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/140_backend_x86_64.scm](../../ulisp/passes/140_backend_x86_64.scm) (`%alloc` スローパスでの GC トリガー生成、`gc_collect` 呼出アセンブリコードの出力)
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (`passes/140_backend_x86_64.scm` との同期)
- [x] [ulisp/lib/gc.scm](../../ulisp/lib/gc.scm) (ランタイム起動時の自動 `gc-init!` 連携)
- [x] [tests/test_bare_metal_ulisp.py](../../tests/test_bare_metal_ulisp.py) (小規模ヒープでの自動 GC 回収・継続実行テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/564-wire-automatic-copying-gc-trigger-in-backend`

1. **`%alloc` スローパスの分岐化**:
   - `cmp r12, [rip + ulisp_heap_limit]`
   - `ja .L_gc_slowpath_xxxx`
   - `.L_gc_slowpath_xxxx` において、生レジスタを退避し、`gc-collect!`（またはナーサリの `gc-minor-collect!`）を自動起動。
2. **スタックマップ照合と生存オブジェクト回収**:
   - `__ulisp_stackmap_table` を用いて、コールスタック上のポインタを To 空間へコピー・更新。
   - コレクション完了後、`r12` を To 空間のフリーポインタへ更新してアロケーションをリトライ。
3. **ランタイム初期化**:
   - `_start` において、`gc-mode != none` 時は広大な固定領域ではなく、適正サイズ（例: 4MB ナーサリ＋64MB 成熟空間）を mmap して `gc-init-generational!` を自動実行。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `%alloc` においてヒープ上限到達時に自動的に GC が起動し、不要オブジェクトが回収されること。
- [x] 回収後、プロセスが停止せずにアロケーションを継続し、正常終了すること。
- [x] 小規模ヒープ（例: 64KB）を設定した環境で大量の cons を生成するプログラムが、OOM せずに GC を複数回実行しながら完遂すること。
- [x] 既存のテストスイートが 100% PASS すること。
