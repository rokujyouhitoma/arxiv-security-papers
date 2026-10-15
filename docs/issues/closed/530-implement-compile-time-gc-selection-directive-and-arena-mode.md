---
ID: 530
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] コンパイル時 GC 切り替え機構 (!gc ディレクティブ / --gc オプション) および Arena (GC-None) モードの実装 (ID: 530)

## 1. 概要 / Summary
ULisp コンパイラ（`ulisp/passes/08_driver.scm`）およびビルドシステムを拡張し、ターゲット環境やフットプリント要件に応じてコンパイル時に GC アルゴリズムを選択可能にする。

### GC モードのサポート
1. **デフォルト・指定なし (`all` / デフォルト)**:
   - 両方の GC（Cheney 型 2 空間コピー GC および ナーサリ世代別コピー GC の双方）を完全サポート。どちらの初期化・回収関数もランタイムで自由に利用可能（BSS 128B＋ライトバリア）。
2. **`(!gc generational)` (世代別コピー GC 特化)**:
   - 第 0 世代ナーサリ＋第 1 世代成熟空間を備えた世代別コピー GC（Issue #525）。高スループット・低一時停止時間を実現。
3. **`(!gc dual-space)` (組み込み・極小メモリ向け)**:
   - 最小限の Cheney 型 2 空間コピー GC 単体。IoT / 組み込み・極小メモリ環境向けに、ライトバリアおよび記憶集合（Remembered Set）のフットプリントを完全排除（BSS 64B）。
4. **`(!gc none)` (Arena / ゼロオーバーヘッド)**:
   - GC コードを一切リンクしない Arena バンプアロケータのみのゼロオーバーヘッドモード。一時実行 CLI / マイクロバイナリや OS カーネル起動初期向け（BSS 0B）。

### コンパイル時ディレクティブ & CLI オプション
- **ソースコード内ディレクティブ**:
  - ソースコード内先頭の `(!gc <mode>)` ディレクティブの構文解析（`ulisp/passes/08_driver.scm`）。
- **CLI オプション**:
  - コマンドライン引数 `--gc=all|generational|dual-space|none` のサポート。

### 条件付きコード生成 & E2E 差分テスト
- **アセンブリ・BSS 最適化**:
  - 選択された GC モードに応じた `ulisp_gc_state`（0B / 64B / 128B）およびアセンブリシンボルの条件付き生成と最適化。
- **E2E 差分テスト**:
  - `tests/test_bare_metal_ulisp.py` における各モードの実行・バイナリサイズ削減効果の検証。

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
- [x] [ulisp/passes/08_driver.scm](../../ulisp/passes/08_driver.scm) (`!gc` ディレクティブおよび `--gc` オプションの構文解析と GC モード伝播)
- [x] [ulisp/passes/07_backend_x86_64.scm](../../ulisp/passes/07_backend_x86_64.scm) (選択された GC モードに応じた `ulisp_gc_state`（0B / 64B / 128B）およびアセンブリシンボルの最適化)
- [x] [ulisp/lib/gc.scm](../../ulisp/lib/gc.scm) (モジュール単位での独立利用およびリンク互換性)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (ビルドターゲットおよびテスト連携)
- [x] [tests/test_bare_metal_ulisp.py](../../tests/test_bare_metal_ulisp.py) (各 GC モードの E2E コンパイル・バイナリサイズ削減効果・動作検証テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/530-ulisp-compile-time-gc-selection-directive`

1. **`!gc` ディレクティブおよび `--gc` CLI オプションの実装**:
   - `08_driver.scm` の `extract-target-and-forms` を拡張し、フォーム先頭の `(!gc <mode>)`（`generational`, `dual-space`, `none`）およびコマンドライン引数 `--gc=generational|dual-space|none` を抽出・統合。
2. **条件付きコード生成 & BSS サイズ最適化**:
   - `none` モード時: GC 関連シンボルや `ulisp_gc_state`（0B）を完全除去し、極小 Arena バンプアロケーションバイナリを出力。
   - `dual-space` モード時: `ulisp_gc_state` を 64 バイトとし、ライトバリアフックを完全除外。
   - `generational` モード時: 128 バイト状態配列＋ライトバリアフックをフル配備。
3. **E2E 差分検証テストの配備**:
   - `tests/test_bare_metal_ulisp.py` にて、各モード（`none`, `dual-space`, `generational`）でのコンパイル・実行・バイナリサイズ削減効果の検証テストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] デフォルト・指定なし時（`all`）に両方の GC（2空間 GC および 世代別 GC）が完全サポートされ、128B バッファとライトバリアが有効であること。
- [x] `(!gc none)` または `--gc=none` 指定時に GC コードを含まない極小静的バイナリが生成され、正常に実行完了すること。
- [x] `(!gc dual-space)` または `--gc=dual-space` 指定時に従来の Cheney 2 空間 GC のみで動作し、ナーサリ/ライトバリア関連フットプリント（BSS 64B）が保証されること。
- [x] `(!gc generational)` または `--gc=generational` 指定時に第 0 世代ナーサリ＋第 1 世代成熟空間の世代別コピー GC（BSS 128B）が有効になること。
- [x] `tests/test_bare_metal_ulisp.py` において各モードの実行およびバイナリサイズ削減効果が自動検証され、100% PASS すること。
