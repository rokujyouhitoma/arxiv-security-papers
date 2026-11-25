---
ID: 964
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-11-25
担当エージェント:
  - IT Specialist (Programming Languages & Compilers / PLC) [Lead]
  - Information Security Specialist
  - Systems Architect (SA)
  - Software Development (SWD)
  - Software Quality Assurance Specialist
ターゲットブランチ: feat/964-unify-memory-checks-via-define-mem-check
---

# [FEAT/ENH] `define-mem-check` によるメモリ安全性検査仕様の単一情報源化と LIR VM・`--sanitize-bounds` 双方への統一射影 (ID: 964)

## 1. 概要・背景 / Summary & Background

`#963` で構築した差分カバレッジ計測により、現在の C99 メモリ安全性検査には以下の 2 つの構造的課題が明らかとなった：
1. **検査意味論の二重管理**: [lir_interpreter.scm](../../../ulisp/vm/lir_interpreter.scm)（シャドウメモリ＋`vm-mem-read-u8` / `vm-mem-write-u8!` / `vm-heap-validate-and-free!`）と [lower_to_lir.scm](../../../ulisp/frontend_c/lower_to_lir.scm)（`%c99-san-emit-null-check!` / `%c99-san-emit-bounds-check!`）が、CWE 分類・エラーメッセージ・検査条件を別々の手書きコードで重複定義していた。
2. **第 1 射影ギャップ 10/16 件 (62.5%) の存在**: `#963` のベンチマーク 16 件のうち、サニタイザが先制捕捉していたのは 6 件（`CWE-121` スタック/静的配列 3 件、`CWE-476` 直接 NULL 参照 3 件）であり、残り **10 件**（`CWE-122` ヒープ境界 4 件、`CWE-416` UAF 2 件、`CWE-415` 二重解放 1 件、`CWE-590` 不正解放 2 件、`CWE-476` `strlen(NULL)` 1 件）が VM オラクルのみの捕捉（`gap-vm-only`）となっていた。

`#944` で値表現を `define-value-repr` に一本化したのと同様に、本 Issue ではメモリ安全性検査の仕様（CWE ID、診断コード `C99-SAN-001`〜`006`、VM トラップ種別 `'out-of-bounds` / `'heap-out-of-bounds` / `'use-after-free` / `'double-free` / `'invalid-free`、境界比較ルール、診断メッセージ書式）を **`define-mem-check`** 単一情報源（SSOT）に集約し、**VM 実行時検査** と **`--sanitize-bounds` 静的/残余 LIR ガード生成** の 2 方向へ統一射影した。

---

## 2. トレーサビリティと影響範囲 / Traceability & Scope

### 関連ドキュメント（すべて相対リンク）
- [Issue #963](963-measure-sanitizer-detection-coverage-against-lir-vm-shadow-oracle.md)（VM オラクル比較による検出ギャップ計測：`6/16` → `16/16`）
- [Issue #962](962-implement-lir-vm-shadow-memory-for-heap-oob-uaf-and-double-free.md)（LIR VM シャドウメモリ・オブジェクト単位検査）
- [Issue #944](944-unify-host-and-guest-value-representation-via-define-value-repr.md)（`define-value-repr` による SSOT 設計パターン）
- [Issue #930](930-implement-c99-bounds-checking-sanitizer-mode.md)（C99 `--sanitize-bounds`）

### 影響範囲・変更対象ファイル
- [x] [lir_interpreter.scm](../../../ulisp/vm/lir_interpreter.scm)（`§1b` `<mem-check-spec>`, `define-mem-check` マクロ＆6 種検査仕様定義、`vm-trigger-mem-check!`, `mem-check-format-san-msg`, `mem-check-emit-*-lir` 実装と VM シャドウ検査の統一）
- [x] [c_driver_module_header.scm](../../../ulisp/compiler/c_driver_module_header.scm)（`define-mem-check` / `mem-check-*` / `san-ptr-meta` 公開シンボル登録、`c99_vm` → `c99_frontend` 間のモジュラーリンク保証）
- [x] [lower_to_lir.scm](../../../ulisp/frontend_c/lower_to_lir.scm)（`define-mem-check` サニタイザ LIR 射影への全面移行＋`--sanitize-bounds` 時ポインタ来歴追跡 `san-ptr-meta` / 関数入口ゼロ初期化 / `CWE-122`/`415`/`416`/`590`/`476(libc)` ギャップ解消）
- [x] [sema.scm](../../../ulisp/frontend_c/sema.scm)（`c-call` ノードへの `<source-span>` 伝播追加により `strlen(NULL)` 等の libc 呼び出し診断で実ソース位置を出力）
- [x] [lint_sexpr.py](../../../ulisp/scripts/lint_sexpr.py)（`define-mem-check` 特殊形式ホワイトリスト登録）
- [x] [test_c99_bounds_sanitizer.scm](../../../ulisp/tests/test_c99_bounds_sanitizer.scm)（Group 5 カバレッジ基準更新 `16/16`・`gap-vm-only = 0` および Group 6 `define-mem-check` SSOT 整合テスト追加、計 106/106 PASS）
- [x] [test_c99_stdarg.sh](../../../ulisp/tests/test_c99_stdarg.sh)（`#955` Pass 143 `rule-x86-and-cmp-zero-branch-fuse` 適用後の `and rax, 255` 直下 `je .L_c99_va_skip_xmm` 検証に更新）

---

## 3. 単一情報源（`define-mem-check`）アーキテクチャ設計 / Architecture Design

### 3.1 `define-mem-check` 検査仕様テーブル（6 種別 SSOT）

| Check ID | CWE | サニタイザコード | VM トラップ型 | VM シャドウ条件 / ガード条件 |
| :--- | :---: | :---: | :--- | :--- |
| `mem-check:static-array-bounds` | `CWE-121` | `C99-SAN-001` | `'out-of-bounds` | 添字符号なし比較 `idx >= len`（`&arr[N]` は `>`） |
| `mem-check:null-pointer` | `CWE-476` | `C99-SAN-002` | `'out-of-bounds` | `ptr == 0`（または `addr < 4096`） |
| `mem-check:heap-bounds` | `CWE-122` | `C99-SAN-003` | `'heap-out-of-bounds` | VM: `REDZONE`/`HEAP_ZERO`; Sanitizer: `off < 0` または `off + access_bytes > heap_sz`（`strcpy`/`memcpy` 長含む） |
| `mem-check:use-after-free` | `CWE-416` | `C99-SAN-004` | `'use-after-free` | VM: `SHADOW_FREED`; Sanitizer: 関数内解放状態フラグ `freed != 0` |
| `mem-check:double-free` | `CWE-415` | `C99-SAN-005` | `'double-free` | VM: `free`/`realloc` 時に `SHADOW_FREED`; Sanitizer: `free(p)` 前に `freed != 0` 検証 |
| `mem-check:invalid-free` | `CWE-590` | `C99-SAN-006` | `'invalid-free` | VM: 非 `HEAP_HEAD`; Sanitizer: スタック変数由来・`'interior` 派生ポインタへの `free` |

### 3.2 検証結果サマリー

- **`test_c99_bounds_sanitizer.scm` (106 passed, 0 failed)**:
  - Group 1〜4（Zero-Overhead 不変条件、`0-diff` LIR、`trailing [1]` FAM 免除）全 PASS。
  - Group 5 CWE カバレッジ行列: **Unsafe 16/16 (100%) 捕捉**（`caught-both = 13`, `sanitizer-only = 3`, `gap-vm-only = 0`, `Negative Controls = 3`, `False Positives = 0`）。
  - Group 6 `define-mem-check` SSOT 整合・`malloc(0)`・自己再代入 `realloc` エッジケース全 PASS。
- **E2E・ネイティブ実機検証**:
  - Lua 5.4.7 全 33 TU `--sanitize-bounds` 静的 musl ビルド＆公式 `all.lua` 完走（`final OK !!!`, 偽陽性 `0` 件）。
  - `bin/ulisp-cc --sanitize-bounds` ネイティブ ELF 実行で CWE-122 (`C99-SAN-003`), CWE-416 (`C99-SAN-004`), CWE-415 (`C99-SAN-005`), CWE-590 (`C99-SAN-006`) が終了コード `134` でトラップ。
  - `make -C ulisp test`（全フェーズ＆3段自己ホスト不動点ブートストラップ含む）および `make check_format && make static_analysis && make py_compile` 全 PASS。

---

## 4. 完了条件 / Success Criteria (DoD)

- [x] `define-mem-check` から VM 側トラップ仕様（`lir_interpreter.scm`）と `lower_to_lir.scm` サニタイザ LIR ガード生成の双方が単一情報源として導出されていること
- [x] `#963` の CWE カバレッジベンチマークにおいて `--sanitize-bounds` による Unsafe 捕捉率が `6/16 (37.5%)` → **`16/16 (100.0%)`**（`gap-vm-only = 0`）へ向上し、Negative Control（Lua trailing `[1]` FAM 含む）の False Positive が `0` 件であること
- [x] ネイティブ ELF コンパイル（`bin/ulisp-cc --sanitize-bounds`）においてもヒープ範囲外・UAF・二重解放・不正解放が終了コード `134` と `C99-SAN-003`〜`006` 診断でトラップすること
- [x] `--sanitize-bounds` 無効時のゼロオーバーヘッド不変条件（`.o` SHA-256 一致・LIR 0-diff・`__ulisp_san_trap` 0 件）が維持されていること
- [x] `make -C ulisp test`・`make -C ulisp test_c99_bounds_sanitizer test_c99_lir_vm_checked test_lir_interpreter test_c99_setjmp_longjmp test_lint_sexpr bin/ulisp-cc` および `make check_format && make static_analysis && make py_compile` が全 PASS すること
- [x] Issue ドキュメントの相対リンク検証（絶対パス 0 件）が PASS すること
