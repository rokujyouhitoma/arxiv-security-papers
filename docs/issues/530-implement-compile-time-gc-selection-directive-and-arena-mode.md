---
ID: 530
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] コンパイル時 GC 切り替え機構 (!gc ディレクティブ / --gc オプション) および Arena (GC-None) モードの実装 (ID: 530)

## 1. 概要 / Summary
ULisp コンパイラ（`ulisp/passes/08_driver.scm`）およびビルドシステムを拡張し、ターゲット環境やフットプリント要件に応じてコンパイル時に GC アルゴリズムを選択可能にする。
1. **`generational` モード（デフォルト）**:
   - ナーサリ空間（第0世代）と成熟空間（第1世代）を備えた世代別コピーGC（Issue #525）。高スループット・低一時停止時間を実現。
2. **`dual-space` モード（組み込み・小メモリ向け）**:
   - 最小限の Cheney 型 2 空間コピーGC。ナーサリ、ライトバリア、記憶集合（Remembered Set）のメタデータを一切含まず、バイナリサイズと BSS 領域を極小化。
3. **`none` モード（Arena / Bump-only）**:
   - 一時実行 CLI ツールや OS カーネル起動初期・マイクロコントローラ向け。GC コードを一切含まず、`R12` バンプアロケータのみで動作する極小バイナリを出力。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第8.5節 TBAA・エスケープ解析 & 世代別GC)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-36: Zero-libc / Freestanding Pure Scheme Bare-Metal Runtime](../designs/DSN-36-zero_libc_pure_scheme_bare_metal_runtime.md)
- **関連先行 Issue**:
  - Issue #501: ULisp ターゲットランタイム向けガベージコレクタの実装
  - Issue #516: libc/C依存完全排除と 100% Pure Scheme ベアメタル Linux ランタイムの実装
  - Issue #525: TBAA・エスケープ解析に基づくスタック割当昇格とナーサリ世代別コピーGCの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/08_driver.scm](../../ulisp/passes/08_driver.scm) (`!gc` ディレクティブの構文解析および GC モード伝播)
- [ ] [ulisp/passes/07_backend_x86_64.scm](../../ulisp/passes/07_backend_x86_64.scm) (選択された GC モードに応じた `ulisp_gc_state` サイズおよび初期化の最適化)
- [ ] [ulisp/lib/gc.scm](../../ulisp/lib/gc.scm) (モジュール単位での独立利用およびリンク互換性)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (ビルドターゲットおよびテスト連携)
- [ ] [tests/test_bare_metal_ulisp.py](../../tests/test_bare_metal_ulisp.py) (各 GC モードの E2E コンパイル・バイナリサイズ比較・動作検証テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/530-ulisp-compile-time-gc-selection-directive`

1. **`!gc` ソースコード内ディレクティブの構文解析**:
   - `08_driver.scm` の `extract-target-and-forms` を拡張し、フォーム先頭の `(!gc <mode>)`（`generational`, `dual-space`, `none`）を抽出。
2. **バックエンドおよびランタイムの条件付きコード生成**:
   - `none` モード時は GC 関連シンボルや `ulisp_gc_state` を極小化し、完全な Arena 割り当てバイナリを出力。
   - `dual-space` モード時は `ulisp_gc_state` を 64 バイトとし、ライトバリアフックを完全除外。
   - `generational` モード時はフル機能（128 バイト状態配列＋ライトバリア）を維持。
3. **E2E 差分検証テストの配備**:
   - `tests/test_bare_metal_ulisp.py` にて、各モード（`none`, `dual-space`, `generational`）でのコンパイル・実行・バイナリサイズ削減効果を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(!gc none)` 指定時に GC コードを含まない極小静的バイナリが生成され、正常に実行完了すること。
- [ ] `(!gc dual-space)` 指定時に従来の Cheney 2 空間 GC のみで動作し、ナーサリ/ライトバリア関連フットプリントが排除されること。
- [ ] `(!gc generational)` 指定時に第 0 世代ナーサリ＋第 1 世代成熟空間の世代別コピー GC が有効になること。
- [ ] `tests/test_bare_metal_ulisp.py` および既存の AOT テストスイートがすべて 100% PASS すること。
