---
ID: 692
種別: Feature
優先度: High
ステータス: Closed (Resolved)
完了日: 2026-11-10
---

# [FEAT] Synapse 並行性ランタイム向け AArch64 ネイティブコンテキストスイッチ (context_aarch64.s) の実装 (ID: 692)

## 1. 概要 / Summary

Synapse 並行性ランタイム（uLisp Concurrency Runtime）において、現在 x86-64 System V AMD64 ABI に特化している `ulisp/runtime/concurrency/context.s`（`swap_context` およびコルーチントランポリン群）を、ARM64 AAPCS64（ARM 64-bit Architecture Procedure Call Standard）に完全準拠した **`ulisp/runtime/concurrency/context_aarch64.s`** として新設・実装する。

AArch64 における Callee-saved レジスタ群（`x19`〜`x28`、`x29/fp`、`x30/lr`）の 16 バイト境界整列による退避・復元、ヒープフロントポインタ（`x19`）の引き継ぎ、およびタスク起動・終了トランポリン（`ulisp_task_entry_trampoline` / `ulisp_task_exit_trampoline`）を整備し、`qemu-aarch64` 上でコルーチンの `resume`/`yield`、P2P `switch`、および例外ハンドラ連鎖の隔離が正常に機能することを実証する。

---

## 2. 脅威モデル分析とセキュリティ要件 (STRIDE & CWE)

| 脅威分類 (STRIDE) | 対象 CWE | 影響度 | 脅威シナリオと対策方針 |
| :--- | :--- | :---: | :--- |
| **Tampering (改ざん)** | **CWE-787**: Out-of-bounds Write / Memory Corruption | High | **スタック境界破壊・アライメント不正**: AArch64 は SP が 16 バイト整列されていないメモリアクセスをハードウェア例外（SP Alignment Fault / SIGBUS）として遮断する。96 バイト（12 レジスタ分）の厳格な `stp`/`ldp` ペア操作により常に SP % 16 == 0 を維持し、境界カナリア（`*context-stack-canary*`）によるスタックオーバーフロー監視を徹底する。 |
| **Elevation of Privilege** | **CWE-662**: Improper Synchronization on Shared Resource | High | **レジスタ破壊による制御フロー逸脱**: Callee-saved レジスタ（特に `x19` ヒープポインタおよび `x29/fp`, `x30/lr`）がコンテキストスイッチ間で 1 ビットでも破壊されると、呼び出し側フレームのメモリ破壊や任意コード実行へ繋がる。100% 決定論的な Callee-saved レジスタ退避と往復検証ルーチン（`%asm-verify-swap-context-regs!`）を実装する。 |
| **Information Disclosure** | **CWE-125**: Out-of-bounds Read / Cross-Task Leakage | Medium | **他タスクの例外ハンドラ・コンテキスト漏洩**: タスク切り替え時に例外ハンドラ連鎖が適切にプルーニング・復元されないと、別タスクのハンドラが実行されデータ漏洩が発生する。AArch64 `tpidr_el0` TLS に基づくワーカー別ハンドラチェーンテーブル管理を連動させる。 |

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/runtime/concurrency/context_aarch64.s](../../ulisp/runtime/concurrency/context_aarch64.s) - AAPCS64 準拠ネイティブコンテキストスイッチルーチンおよび Scheme プリミティブ群の新規実装
- [x] [ulisp/runtime/concurrency/context.scm](../../ulisp/runtime/concurrency/context.scm) - アーキテクチャに応じたフレームサイズ（x86-64: 64B, AArch64: 96B）および初期スタックレイアウト（`setup-task-stack`）の適応
- [x] [ulisp/lib/ulisp/concurrency/context.sld](../../ulisp/lib/ulisp/concurrency/context.sld) - ライブラリ定義およびエクスポートシンボルの整合性維持
- [x] [ulisp/Makefile](../../ulisp/Makefile) - `build/context_aarch64.o` アセンブルターゲットおよび QEMU AArch64 コンテキストスイッチ結合テストの追加
- [x] [tests/concurrency/test_context_switch_aarch64.scm](../../tests/concurrency/test_context_switch_aarch64.scm) - AArch64 QEMU 上で実行するネイティブコンテキストスイッチ単体・結合テストスイート
- [x] [docs/designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) - Section 7.3 における AArch64 AAPCS64 レジスタレイアウトの仕様追記
- [x] [docs/issues/README.md](README.md) - Issue 台帳のステータス更新 (`Closed`)

---

## 4. アーキテクチャ設計 (AAPCS64 Context Switch & Trampoline)

### 4.1 Callee-saved レジスタセットとスタックフレーム
ARM64 AAPCS64 における Callee-saved レジスタは以下の 12 本（計 96 バイト = $12 \times 8$ バイト、16 バイト整列）：
- `x19`〜`x28` (10 本): 汎用保存レジスタ（`x19` は uLisp の生ヒープフロントポインタ）
- `x29` (FP / Frame Pointer): フレームポインタ
- `x30` (LR / Link Register): 戻り先アドレス（`swap_context` の復帰 PC）

```assembly
# Canonical 17-instruction AAPCS64 Context Switch
# x0 = old_sp_ptr (uint64_t*)
# x1 = new_sp     (uint64_t)
swap_context:
    sub sp, sp, #96
    stp x19, x20, [sp, #0]
    stp x21, x22, [sp, #16]
    stp x23, x24, [sp, #32]
    stp x25, x26, [sp, #48]
    stp x27, x28, [sp, #64]
    stp x29, x30, [sp, #80]
    mov x2, sp
    str x2, [x0]
    mov sp, x1
    ldp x19, x20, [sp, #0]
    ldp x21, x22, [sp, #16]
    ldp x23, x24, [sp, #32]
    ldp x25, x26, [sp, #48]
    ldp x27, x28, [sp, #64]
    ldp x29, x30, [sp, #80]
    add sp, sp, #96
    ret
```

### 4.2 初期スタックフレーム構造 (`setup-task-stack`)
スタック最上位 `top` から 64 バイトの TCB ヘッダ直下に、96 バイトの `swap_context` 初期復元フレームを配置：
- `[frame_top - 16 .. frame_top -  0]`: `x29` = `frame_top`, `x30` = `ulisp_task_entry_trampoline`
- `[frame_top - 32 .. frame_top - 16]`: `x27` = 0, `x28` = 0
- `[frame_top - 48 .. frame_top - 32]`: `x25` = 0, `x26` = 0
- `[frame_top - 64 .. frame_top - 48]`: `x23` = 0, `x24` = 0
- `[frame_top - 80 .. frame_top - 64]`: `x21` = `entry-fn`, `x22` = 0
- `[frame_top - 96 .. frame_top - 80]`: `x19` = `heap_base`, `x20` = `top` (TCB Base)
- `init_sp` = `frame_top - 96`（16 バイト整列）

### 4.3 タスク起動および終了トランポリン
- **`ulisp_task_entry_trampoline`**:
  - `x19`: 呼び出し側のヒープポインタを保持。
  - `x20`: TCB ベースアドレス。
  - `x21`: 実行対象（Scheme クロージャまたは生関数ポインタ）。
  - クロージャ判定 (`and x0, x21, #3; cmp x0, #1`):
    - クロージャの場合: `mov x10, x21`, `mov x7, #0`, `ldr x1, [x10, #-1]`, `blr x1`。
    - 生関数の場合: `mov x0, x20`, `blr x21`。
  - 戻り値 `x0` を TCB の結果スロット `[x20, #-40]` に退避。
  - `b ulisp_task_exit_trampoline` へジャンプ。
- **`ulisp_task_exit_trampoline`**:
  - タスク状態を `3` (`'terminated`) に更新 (`str #3, [x20, #-24]`)。
  - ハンドラチェーンスロット `[x20, #-32]` を 0 クリア。
  - `tpidr_el0` よりワーカー ID を取得し、親タスクの `top` を `ulisp_current_task_top` に復帰。
  - コンテキストスイッチ総数カウンタをアトミック加算。
  - `x0 = x20 - 16` (`old_sp_ptr`), `x1 = [x20 - 8]` (`parent_sp`) をセットして `bl swap_context`。

### 4.4 Scheme プリミティブ群のエントリポイント
`context.s` と完全一致する以下の 8 エントリポイントを AArch64 アセンブリで実装：
1. `ulisp_fn__pctasm_get_trampoline_addr`（which = 0..7: 各種アドレス、カウンタ、および arch/frame-size = 96 の返却）
2. `ulisp_fn__pctasm_set_handler_chain_excl`
3. `ulisp_fn__pctasm_swap_context_excl`
4. `ulisp_fn__pctasm_resume_task_excl`
5. `ulisp_fn__pctasm_yield_task_excl`
6. `ulisp_fn__pctasm_switch_task_excl`
7. `ulisp_fn__pctasm_verify_swap_context_regs_excl`
8. `ulisp_fn__pctasm_bench_swap_context_excl`

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/692-implement-aarch64-native-context-switch`

### Step 1: ブランチ作成
- Git ブランチ `feat/692-implement-aarch64-native-context-switch` を `main` より分岐作成。

### Step 2: `context_aarch64.s` の実装
- `ulisp/runtime/concurrency/context_aarch64.s` を新規作成：
  - ARM64 構文、ELF アセンブリ擬似命令（`.text`, `.globl`, `.p2align 4` 等）。
  - `swap_context`: 12 レジスタ（96 バイト）の `stp`/`ldp` による退避・復元ルーチン。
  - `ulisp_task_entry_trampoline` および `ulisp_task_exit_trampoline`。
  - `ulisp_init_worker_tls`: `tpidr_el0` を用いたワーカー TLS テーブル初期化。
  - Scheme 呼出用 8 つのプリミティブルーチン（タグ付け値の右シフト、レジスタ退避、`bl swap_context`、戻り値セット）。
  - `.bss` セクションへの `ulisp_handler_chain[512]`, `ulisp_current_task_top[512]`, `ulisp_worker_tls_table[4096]`, `ulisp_total_context_switches` の配置。

### Step 3: `context.scm` のアーキテクチャ適応
- `ulisp/runtime/concurrency/context.scm`:
  - `(%asm-get-trampoline-addr 7)` を導入し、ランタイムからフレームサイズ（64 または 96）を取得。
  - `*context-frame-size*` を動的初期化、または AArch64 用フレーム初期化ルーチン（96 バイト配置、`x29`/`x30` スロット設定）へ分岐。
  - `setup-task-stack` が x86-64 と AArch64 の双方でアライメントを維持し正しく初期スタックを構築できるよう整備。

### Step 4: ビルド基盤 (`Makefile`) と AArch64 単体テストの追加
- `ulisp/Makefile`:
  - `build/context_aarch64.o` のクロスアセンブルルールを追加。
  - `test_context_switch_aarch64`: Scheme コンパイラで AArch64 アセンブリを生成し、`context_aarch64.o` と静的リンクした上で `qemu-aarch64` で実行するテストターゲットを追加。
- `tests/concurrency/test_context_switch_aarch64.scm`:
  - Group 1: 16 バイトアライメントとスタックカナリアの検証。
  - Group 2: `swap_context` の Callee-saved レジスタ整合性検証。
  - Group 3: コルーチン `context-resume!` / `context-yield!` の往復値受け渡し検証。
  - Group 4: P2P `context-switch!` ピンポン切り替え。
  - Group 5: 1,000,000 回のスイッチストレステスト。

### Step 5: 全品質ゲート検証とドキュメント更新
- `aarch64-linux-gnu-as` によるアセンブルおよび `qemu-aarch64` による実行検証 100% PASS。
- 既存 x86-64 環境の `make -C ulisp test_context_switch`（89 passed, 0 failed）が 100% 維持されること（リグレッションなし）。
- `make -C ulisp lint_sexpr` が 100% balanced。
- `make verify_quality` が 100% PASS。
- DSN-37 Section 7.3 を更新。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] **AArch64 アセンブル完全成功**:
  - `context_aarch64.s` が `aarch64-linux-gnu-as` で警告・エラー 0 件でオブジェクトファイル（ELF64 AArch64）へアセンブルできること。
- [x] **16 バイトスタックアライメント厳格保証**:
  - `qemu-aarch64` 上でタスク切り替えおよびネスト呼出しを実行した際、SP Alignment Fault や `SIGBUS` が 0 件であること。
- [x] **Callee-saved レジスタ群の完全維持**:
  - `x19`〜`x28`、`x29` (FP)、`x30` (LR) がコンテキストスイッチ間で 1 ビットも破壊されず保持されること。
- [x] **コルーチン基本動作の実証**:
  - `qemu-aarch64` 上で複数のコルーチン間で `context-resume!`、`context-yield!`、`context-switch!` が正常に値を受け渡し、終了時に `'terminated` へ安全に遷移すること。
- [x] **既存アーキテクチャ (x86-64) への無影響**:
  - `make -C ulisp test_context_switch` を含む全 x86-64 並行性テスト（89 passed）がリグレッションなく 100% 合格すること。
- [x] **品質ゲート検証 100% PASS**:
  - `make -C ulisp lint_sexpr` が全ファイルで括弧一致（100% balanced）すること。
  - `make verify_quality` が 100% PASS すること。
