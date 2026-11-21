---
ID: 905
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] Implement Freestanding Demand-Paged BSS Bump Allocator and GC (ID: 905)

## 1. 概要 / Summary

[[DSN-33-07]](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md) 第 4 章に基づき、外部 `malloc` や libc を介さず、Linux カーネルが自動提供するデマンドページング BSS セクション（16MB）を初期ヒープとして利用するベアメタル自立型バンプアロケータ、および Raw Syscall `sys-mmap` と連動する Zero-libc Cheney's 2-Space コピー GC を実装・確立する。

本機能により、ULisp は起動時に動的システムコール（`mmap`）を発行することなく即座に BSS 領域からメモリ割り当てを開始でき、OS 起動直後や極小組み込み・セキュアコンテナ環境における起動レイテンシを最小化（物理メモリ消費ゼロからオンデマンドで物理ページ割り当て）するとともに、ヒープ枯渇時には完全自立型 Cheney 2-Space GC によりメモリの再利用・圧縮・回収を達成する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-07] ULisp Zero-libc / Freestanding Pure Scheme ベアメタルランタイム包括設計書 (第4章 メモリ管理と GC)](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md)
  - [[DSN-33] ULISP 包括設計仕様書 (第2.3節 黄金比 Cheney's 2-Space GC)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [[DSN-33-02] ULisp 多言語フロントエンド ＆ 型付き機械語 LIR 設計書](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md)
- 先行 Issue:
  - [Issue #904: 外部 C ランタイム完全排除と Pure Scheme _start エントリポイント・Raw Syscall 直結](closed/904-eliminate-external-c-runtime-and-establish-pure-scheme-start-entry.md)
  - [Issue #903: 統計的性能退行（Regression Detector）自動検知器および日本語ベンチマークレポート自動生成](closed/903-implement-performance-regression-detector-and-automated-markdown-reporting.md)
- 後続 Issue:
  - [Issue #906: 完全自立型静的 ELF (-nostdlib -static) の E2E 実行可能性および動的依存ゼロの検証](906-verify-freestanding-static-nostdlib-elf-e2e-execution.md)

---

## 3. STRIDE 脅威分析とセキュリティ対策 / STRIDE Threat Modeling

| 脅威分類 (STRIDE) | 脅威シナリオ | 影響度 | 対策・緩和策 (Mitigation) |
|---|---|---|---|
| **Spoofing (なりすまし)** | ヒープ領域外のアドレスを正規オブジェクトポインタと誤認する | High | GC ルート走査およびオブジェクトコピー時、`from <= ptr < from + size` かつ 8 バイト境界整列を厳格に検査し、範囲外ポインタは即座にスキップ。 |
| **Tampering (改ざん)** | コピー中における転送ポインタ（Forwarding Pointer）の二重書き込みや破壊 | Critical | オブジェクト先頭ヘッダの最下位 2 ビットタグ検査（`not (= (%ptr-tag hdr) 0)`）により転送済み状態を一意に識別し、同一オブジェクトの多重コピーを完全防止。 |
| **Repudiation (否認)** | メモリ枯渇時（OOM）のサイレント終了・原因不明停止 | Medium | ヒープ枯渇時、Raw Syscall `sys_write` (stderr) により `Fatal Error: ULisp Heap Limit Exhausted (OOM)\n` を直接出力し、終了コード 1 で即時プロセス停止。 |
| **Information Disclosure (情報漏洩)** | 解放済みメモリや未初期化ヒープ領域の残留データ読み出し | High | 初期ヒープに Linux カーネル提供のゼロ初期化 BSS ページ（Demand-Paged Zero Page）を採用し、過去プロセスのメモリ残留を物理的に排除。 |
| **Denial of Service (サービス妨害)** | 循環参照オブジェクトのコピーによる GC 無限ループ | High | Cheney's 2-Space コピーアルゴリズムにおいて、複製直後に旧オブジェクトヘッダへ新アドレスを記録する Forwarding 機構により、有向閉路を O(N) で確実に終端。 |
| **Elevation of Privilege (権限昇格)** | 不正スタックマップによる任意メモリ書き換え | Critical | Pass 131 スタックマップテーブル（`__ulisp_stackmap_table`）を `.rodata` セクションに配置し、実行時改変を不可能にするとともに、bitmap でマークされたスロットのみを追跡。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- `ulisp/backend/140_backend_x86_64.scm`:
  - `.bss` セクションに `ulisp_initial_heap`（16MB、16バイトアライン）の定義を追加。
  - `_start` エントリポイントにおいて、BSS 初期ヒープをベースとするバンプポインタ初期化ロジックの統合。
- `ulisp/backend/141_backend_x86_gc.scm`:
  - Freestanding 環境における Cheney 2-Space GC のルート走査・コピー・空間反転（Space Flip）ルーチンの整合性検証・強化。
- `ulisp/runtime/gc.scm` & `ulisp/lib/gc.scm`:
  - Pure Scheme レベルのヒープ初期化および GC 状態管理の整備。
- `ulisp/tests/test_freestanding_gc.scm`:
  - ベアメタル環境（libc なし）で大量のペア生成を行い、GC が自動トリガーされて回収・再利用されることを検証する単体テスト。
- `tests/test_bare_metal_ulisp.py`:
  - `test_bare_metal_freestanding_gc_suite` を追加し、`-nostdlib -static` リンクされたバイナリが動的ライブラリ依存ゼロで GC ストレス下で正常完遂することを E2E 検証。
- `ulisp/Makefile`:
  - `test_freestanding_gc` ターゲットの追加。

---

## 5. 実装方針と詳細手順 / Implementation Plan

Target Branch: `feat/905-implement-freestanding-demand-paged-bss-bump-allocator-and-gc`

### 5.1 BSS デマンドページング初期ヒープの配置 (`ulisp/backend/140_backend_x86_64.scm`)
1. x86-64 バックエンドの `.bss` セクション出力部に `ulisp_initial_heap` を定義：
   ```asm
       .bss
       .align 16
       .globl ulisp_initial_heap
       .weak ulisp_initial_heap
   ulisp_initial_heap:
       .space 16777216     # 16 MB デマンドページング領域
   ```
2. `_start` において、`rdi` に `ulisp_initial_heap` のアドレスを設定し、`ulisp_heap_limit` を `ulisp_initial_heap + 16777216` に設定する BSS 初期化パスを整備。

### 5.2 Cheney's 2-Space コピー GC の Zero-libc 動作確認 (`ulisp/backend/141_backend_x86_gc.scm`)
1. `ulisp_gc_collect` 内の dual-space モードにおいて、外部 libc の関数呼び出しが一切存在しないことを保証。
2. 時計取得（`sys_clock_gettime`）および OOM 出力（`sys_write`）が Raw Syscall で直接実行されていることを確認。
3. `From-Space` と `To-Space` の空間反転（Space Flip）後、バンプポインタ `%r12` が新しい空間の先頭に更新され、アロケーションがシームレスに継続することを確認。

### 5.3 テストコード作成 (`ulisp/tests/test_freestanding_gc.scm`)
1. 再帰的リスト生成ループ（10,000〜50,000 ペアのアロケーション）を実行。
2. GC が複数回トリガーされた後、最終的な計算結果（リストの長さや合計値）が正確に保持されていることを検証。
3. 外部 libc なしで標準出力に `=== [TEST] Zero-libc Freestanding GC Suite ===` および `[SUCCESS] GC Verification Complete` を出力。

### 5.4 E2E テストハーネス統合 (`tests/test_bare_metal_ulisp.py`)
1. `test_bare_metal_freestanding_gc_suite` を追加。
2. `as` + `ld -static -nostdlib`（または `gcc -nostdlib -static`）でバイナリをビルド。
3. `readelf -d` で動的ライブラリ依存が 0 件であることを確認し、実行してリターンコード 0 を検証。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `.bss` セクションに `ulisp_initial_heap`（16MB）が定義され、外部 `malloc` なしで初期バンプアロケーションが機能すること。
- [x] Cheney's 2-Space GC がベアメタル環境で正常に起動し、生存オブジェクトの退避・転送ポインタ追跡・空間反転を完遂すること。
- [x] `ulisp/tests/test_freestanding_gc.scm` が作成され、大量オブジェクト生成下でのメモリ回収が実証されること。
- [x] `make -C ulisp test_freestanding_gc` が PASS すること。
- [x] `pytest tests/test_bare_metal_ulisp.py` において GC テストを含む全項目が 100% PASS すること。
- [x] 生成された実行可能ファイルにおいて動的ライブラリ依存が 0 件（`readelf -d` 検証）であること。
- [x] `make py_compile && make static_analysis` がエラー 0 件で合格すること。

---

## 7. 検証手順 / Verification Steps

```bash
# 1. 単体テスト実行 (Zero-libc Freestanding GC テスト)
make -C ulisp test_freestanding_gc

# 2. Python 側ベアメタル E2E テスト実行
pytest -v tests/test_bare_metal_ulisp.py

# 3. 動的依存ゼロの検証
readelf -d /tmp/test_freestanding_gc_bin | grep NEEDED || echo "Zero dynamic dependencies verified!"

# 4. 静的解析とコンパイル検証
make py_compile && make static_analysis
```

