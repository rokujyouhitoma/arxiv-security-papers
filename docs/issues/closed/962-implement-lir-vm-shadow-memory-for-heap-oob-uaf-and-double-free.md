---
ID: 962
種別: Feature
優先度: High
ステータス: Closed
担当エージェント:
  - Information Security Specialist [Lead]
  - Software Development (SWD)
  - IT Specialist (Programming Languages & Compilers / PLC)
  - Software Quality Assurance Specialist
  - Systems Architect (SA)
ターゲットブランチ: feat/962-lir-vm-shadow-memory-object-checks
完了日: 2026-11-25
---

# [FEAT/ENH] LIR 参照 VM へのシャドウメモリ導入によるヒープ範囲外アクセス・UAF・二重解放・不正解放のオブジェクト単位検査 (ID: 962)

## 1. 概要・背景 / Summary & Background

`#930`（`--sanitize-bounds`）と `#943`（LIR 参照 VM の検査付き C99 インタプリタ化）の導入により、メモリ安全性の検査がコンパイル時サニタイザと VM 解釈時の2箇所に存在するが、現状の [lir_interpreter.scm](../../../ulisp/vm/lir_interpreter.scm) は線形メモリ全体（16MB）の上下限と NULL ページ（`0..4095`）のみを検査しており、オブジェクト単位のヒープ検査を持たない。

現状の実装調査で判明した具体的なギャップは以下の通りである：
1. `vm-mem-read-u8` / `vm-mem-write-u8!`（L586–L600）は `(< addr *lir-vm-null-page-limit*)` と `(>= addr (bytevector-length mem))` しか検査しておらず、隣接ヒープ領域・パディング・解放済み領域へのアクセスをそのまま通してしまう。
2. `malloc` / `calloc` / `realloc`（L3557–L3616）は `8` バイト境界に切り上げて隙間なくバンプ割り当てし、`vm-libc-record-alloc!`（L3162）で `__vm_alloc_sizes`（`assv` 線形探索 alist）に記録するのみで、ロード・ストア時の境界検査に使われていない。また `malloc(10)` に対する `p[10]` 等のアライメント端数（1〜7バイト）越境が検出できない。
3. `free`（L3618–L3624）および `realloc`（コピー後の旧ブロック）で解放状態が記録されないため、解放後の使用（UAF: CWE-416）、二重解放（Double Free: CWE-415）、非ヒープ/チャンク途中ポインタの解放（Invalid Free: CWE-590）を検出できない。

本 Issue では ASan / Miri と同等の **1 バイト/バイトのシャドウメモリ（16MB `bytevector`）とオブジェクト間 Redzone（前後 16 バイト）** を `<lir-vm>` に導入し、LIR 参照 VM をオブジェクト単位でメモリ破壊を捕捉する厳密なオラクルへ格上げする。あわせて前段 Redzone `[ptr - 8]` へ要求サイズを格納することで `__vm_alloc_sizes`（`assv` 探索）を廃止し、サイズ参照を $O(1)$ 化する。

---

## 2. トレーサビリティと影響範囲 / Traceability & Scope

### 関連ドキュメント（すべて相対リンク）
- [Issue #943](943-verify-and-extend-lir-vm-as-checked-c99-interpreter.md)（LIR 参照 VM の検査付き C99 インタプリタ化）
- [Issue #930](930-implement-c99-bounds-checking-sanitizer-mode.md)（C99 `--sanitize-bounds` サニタイザ）

### 影響範囲・変更対象ファイル
- [x] [lir_interpreter.scm](../../../ulisp/vm/lir_interpreter.scm)（`<lir-vm>` への `shadow-memory` フィールド追加、シャドウ状態操作・検査ヘルパ実装、`vm-mem-read-u8` / `vm-mem-write-u8!` / `ulisp_alloc` / `malloc` / `calloc` / `realloc` / `free` 更新、`__vm_alloc_sizes` 廃止）
- [x] [c_driver_module_header.scm](../../../ulisp/compiler/c_driver_module_header.scm)（`<lir-vm>` アクセサおよび新規シャドウメモリ関連シンボル登録）
- [x] [test_c99_lir_vm_checked.scm](../../../ulisp/tests/test_c99_lir_vm_checked.scm)（CWE-122 1 バイト越境含む・CWE-415・CWE-416・CWE-590・`realloc` 後旧ポインタ UAF・0 バイト割り当ておよび正常系のテスト追加）

---

## 3. セキュリティ設計仕様 / Shadow Memory Design & Threat Mitigations

### 3.1 シャドウメモリエンコーディング（1 バイト/バイト、`bytevector`）
`<lir-vm>` に `mem-size`（既定 16MB = `*lir-vm-default-mem-size*`）と同サイズの `shadow-memory` (`bytevector`, 初期値 `0`) を保持する。各バイト `addr` に対応する状態値 `shadow[addr]` は以下の通り：

| 状態コード | 定数名 | 意味 | アクセス時の挙動 | `free`/`realloc` 引数時の挙動 |
| :---: | --- | --- | --- | --- |
| `0` (`#x00`) | `*lir-vm-shadow-ok*` | 通常使用可（データ・スタック・未初期化グローバル領域） | 許可 | `invalid-free` トラップ（CWE-590） |
| `1` (`#x01`) | `*lir-vm-shadow-heap-head*` | ヒープ有効オブジェクトの先頭バイト (`ptr`, `req_bytes > 0`) | 許可 | 正常解放対象（`[ptr - 8]` から実サイズ取得） |
| `2` (`#x02`) | `*lir-vm-shadow-heap-live*` | ヒープ有効オブジェクトの 2 バイト目以降 (`ptr + 1 .. ptr + req_bytes - 1`) | 許可 | `invalid-free` トラップ（CWE-590：途中ポインタ） |
| `129` (`#x81`) | `*lir-vm-shadow-heap-zero*` | `malloc(0)` / `calloc(0, ...)` の先頭マーカーバイト (`[ptr]` はアクセス不可) | `heap-out-of-bounds` トラップ | 正常解放対象（サイズ 0） |
| `250` (`#xFA`) | `*lir-vm-shadow-redzone*` | ヒープ Redzone・アライメント端数・未割当ヒープ隙間のガード | `heap-out-of-bounds` トラップ（CWE-122） | `invalid-free` トラップ（CWE-590） |
| `253` (`#xFD`) | `*lir-vm-shadow-freed*` | `free` / `realloc` により解放済みのヒープ領域 | `use-after-free` トラップ（CWE-416） | `double-free` トラップ（CWE-415） |

### 3.2 ヒープチャンク＆Redzone レイアウト（$O(1)$ サイズ管理）
- 割り当て単位（`malloc(bytes)` / `calloc(nmemb, sz)` / `realloc(ptr, new_bytes)`）：
  - `effective-bytes = (max 1 bytes)` を 8 バイト切り上げ：`aligned = (bitwise-and (+ effective-bytes 7) -8)`
  - `[base .. base + 15]`: 前段 16 バイト Redzone（シャドウ値 `#xFA`、`base + 8` の 8 バイトに要求サイズ `bytes` をリトルエンディアン 64-bit 整数で記録）
  - `ptr = base + 16`: 返却ポインタ
  - `[ptr .. ptr + bytes - 1]`: 有効領域（`bytes > 0` のとき先頭 `ptr` を `#x01`、残りを `#x02`。`bytes == 0` のときは `ptr` 1 バイトを `#x81`）
  - `[ptr + bytes .. ptr + aligned + 15]`: 末尾アライメント端数 + 後段 16 バイト Redzone（すべてシャドウ値 `#xFA`）

---

## 4. 実装方針・手順 / Step-by-Step Implementation Plan

Target Branch: `feat/962-lir-vm-shadow-memory-object-checks`

1. `<lir-vm>` への `shadow-memory` 追加・シャドウ塗り/メタデータ 64-bit 読み書きヘルパ実装。
2. `vm-mem-read-u8` / `vm-mem-write-u8!` へのシャドウ状態検査（`heap-out-of-bounds` / `use-after-free`）組み込み。
3. `malloc` / `calloc` / `realloc` / `free` のオブジェクト単位 Redzone＋$O(1)$ ヘッダサイズ管理化（`__vm_alloc_sizes` 線形探索廃止）。
4. [c_driver_module_header.scm](../../../ulisp/compiler/c_driver_module_header.scm) 更新および [test_c99_lir_vm_checked.scm](../../../ulisp/tests/test_c99_lir_vm_checked.scm) Group 5 追加・検証・`bin/ulisp-cc` 再ビルド。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `malloc(N)` に対する `p[N]`（アライメント 8 バイト境界未満の 1 バイト越境含む）・`p[-1]` 負オフセット・`memcpy`/`strcpy` 越境が `'heap-out-of-bounds` (CWE-122) でトラップすること
- [x] `free(p)` 後および `realloc(p, ...)` 後の旧ポインタ参照が `'use-after-free` (CWE-416) でトラップすること
- [x] 二重 `free` が `'double-free` (CWE-415)、スタック・静的・途中ポインタ `free` が `'invalid-free` (CWE-590) でトラップすること
- [x] `__vm_alloc_sizes`（`assv` 線形探索）が廃止され、前段 Redzone `[ptr - 8]` による $O(1)$ サイズ参照に置き換わっていること
- [x] `make -C ulisp test_c99_lir_vm_checked test_lir_interpreter test_lint_sexpr bin/ulisp-cc`（および `test_c99_bounds_sanitizer` / `test_c99_setjmp_longjmp` の Scheme・VM・Native ELF 経路、`bin/ulisp-cc --target=vm` 実機スモークテスト）が PASS すること
- [x] `make check_format`・`make static_analysis`・`make py_compile` および Issue ドキュメント相対リンク検証（絶対パス 0 件）が PASS すること

---

## 6. 完了サマリー / Completion Summary

- [lir_interpreter.scm](../../../ulisp/vm/lir_interpreter.scm) に 1 バイト/バイトの `shadow-memory`（`#x00`, `#x01`, `#x02`, `#x81`, `#xFA`, `#xFD`）と前後 16 バイト Redzone レイアウトを導入し、`vm-mem-read-u8` / `vm-mem-write-u8!` での CWE-122（1 バイト端数・負オフセット・`malloc(0)` 参照含む）および CWE-416（UAF）検出を実装。
- `malloc`/`calloc`/`realloc`/`free` を `vm-heap-alloc-chunk!` / `vm-heap-validate-and-free!` に統合し、前段 Redzone `[ptr - 8]` による $O(1)$ サイズ管理へ移行して `__vm_alloc_sizes`（`assv` 探索）を廃止、CWE-415 (`double-free`) および CWE-590 (`invalid-free`) を捕捉可能にした。
- [c_driver_module_header.scm](../../../ulisp/compiler/c_driver_module_header.scm) を同期し、`bin/ulisp-cc` を再ビルド。[test_c99_lir_vm_checked.scm](../../../ulisp/tests/test_c99_lir_vm_checked.scm) Group 5 を含む全 43 件 PASS、`test_lir_interpreter` 65/65 PASS、`test_lint_sexpr` PASS、`bin/ulisp-cc --target=vm` 実機検証 PASS、`make check_format && make static_analysis && make py_compile` PASS を確認。
