---
ID: 747
種別: Bug
優先度: High
ステータス: Closed
完了日: 2026-11-06
関連 Issue: #719, #745, #746, #748
---

# [BUG/SEC] x86-64 における TLS / worker ID に基づく安全な Worker 判別方式への刷新 (ID: 747)

## 1. 概要 / Summary
x86-64 Linux 環境において、現在どの Worker スレッドで実行中かをヒープポインタ `r12` の 32MB 区画計算（`r12 - nursery_base >> 25`）に依存して判別している。
このナイーブなアライメント計算は、以下の深刻な構造的欠陥・脆弱性を内包している：

1. **ヒープ境界超過による Worker 誤認 (CWE-787, CWE-125)**:
   単一 Worker スレッドのヒープ割り当てが 32MB を超過すると、計算される Worker インデックスが `+1` ずれ、隣接スレッドの管理欄（`ulisp_handler_chain`, `ulisp_current_task_top` 等）を参照・上書きしてしまう。
2. **メインスレッドの先行アロケーション問題**:
   メインスレッド（Worker 0）がスレッド生成前に 32MB を超えるオブジェクトを確保すると、メインスレッドの計算インデックスが 1 や 2 になり、後続で spawn された子スレッドとインデックスが衝突する。
3. **64 スレッド上限超過時のバッファオーバーラン・競合 (CWE-400, CWE-662)**:
   `ulisp_thread_spawn_counter` に上限チェックがなく、64 個を超えるスレッドが生成されると、固定長テーブル（`ulisp_handler_chain[64]`, `ulisp_current_task_top[64]`）の境界外参照または同一スロットの共有によるデータ破壊が発生する。

本 Issue では、Linux x86-64 の TLS (Thread Local Storage, `%fs_base`) アーキテクチャ（`SYS_arch_prctl` ARCH_SET_FS および `SYS_clone` CLONE_SETTLS）を導入し、ヒープポインタ `r12` に依存しない確実かつ O(1) で超高速な Worker 判別方式へと抜本的に刷新する。

---

## 2. 脅威モデル分析とセキュリティ影響 (STRIDE & CWE)

| 脅威分類 (STRIDE) | 対象 CWE | 影響度 | 脅威シナリオと脆弱性のメカニズム |
| :--- | :--- | :---: | :--- |
| **Tampering (改ざん)** / **Elevation of Privilege** | **CWE-787**: Out-of-bounds Write | Critical | 単一スレッドで 32MB 超の割り当てが発生すると、`r12 >> 25` の計算値が不正に進み、別 Worker の例外ハンドラチェーン先頭ポインタ (`ulisp_handler_chain[idx]`) を上書き。任意の例外送出時に不正なスタックフレームへジャンプし、制御フローが乗っ取られる。 |
| **Information Disclosure (情報漏えい)** | **CWE-125**: Out-of-bounds Read | High | 不正に計算された Worker インデックスに基づき、他 Worker の `ulisp_current_task_top` やコルーチン実行状態を読み出し、境界外メモリ参照または機密データの混入が発生する。 |
| **Denial of Service (サービス拒否)** | **CWE-662**: Improper Synchronization on Shared Resource | High | 64 個目以降のスレッド生成時にインデックスマスク（`& 63`）により Worker 0〜63 のスロットが多重共有され、コンテキストスイッチ時に他スレッドの `rsp`/`rbp` を巻き込んで即座にクラッシュ（SEGV/UD2）する。 |
| **Denial of Service (リソース枯渇)** | **CWE-400**: Uncontrolled Resource Consumption | Medium | スレッド生成数上限チェックが存在せず、メモリが枯渇するまで無制限にスレッド生成を許可してしまう。 |

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

### なぜこの問題が発生したか
1. **初期設計の安易な仮定**:
   Phase 7 のマルチコア基盤策定時、各スレッドの Nursery Heap を 32MB 刻みで配置したため、`r12` を 25bit 右シフトするだけで Worker ID が逆引きできるという簡便なヒューリスティクスが採用された。
2. **ヒープ拡大への未対応**:
   大量データ処理や大規模パース等でヒープが 32MB を超えて成長すると、`r12` は 32MB 境界を跨ぎ、Worker ID が偽装された状態となる。
3. **ハードコードされた 15 箇所のアセンブリパターン**:
   ランタイム（`context.s`）およびコンパイラバックエンド（`140_backend_x86_64.scm`, `142_backend_x86_freestanding.scm`）の計 15 箇所において、以下のような冗長（8命令）かつ脆弱な計算コードがインライン展開されていた：
   ```assembly
   lea rdx, [rip + ulisp_gc_state]
   mov rcx, r12
   sub rcx, [rdx]
   shr rcx, 25
   lea rdx, [rip + ulisp_thread_idx_mask]
   and rcx, [rdx]
   shl rcx, 3
   lea rdx, [rip + ulisp_handler_chain]
   add rdx, rcx
   ```

---

## 4. 恒久対策アーキテクチャ設計 (x86-64 TLS / `%fs_base`)

### 4.1 Worker TLS テーブルの構造
`.bss` セクションに 64 ワーカー分の 64 バイト（キャッシュライン整列）TLS データブロックを配置する。
```assembly
    .section .bss
    .p2align 6
    .globl ulisp_worker_tls_table
ulisp_worker_tls_table:
    .zero 4096    # 64 workers * 64 bytes
```
各スレッドの TLS ブロック（オフセットレイアウト）:
- `+0` (8 bytes): `worker_id` (0, 1, 2, ..., 63)
- `+8` (8 bytes): `worker_task_top` (将来の高速化用キャッシュ)
- `+16` (8 bytes): `worker_handler_chain` (将来の高速化用キャッシュ)
- `+24` (40 bytes): 予約領域 / キャッシュラインパディング

### 4.2 メインスレッド（Worker 0）の初期化
起動時（`ulisp_init_worker_tls`）に Linux システムコール `SYS_arch_prctl` (syscall 158) を呼び出し、メインスレッドの `%fs_base` を `ulisp_worker_tls_table[0]` にバインドする。
- `rax = 158` (`SYS_arch_prctl`)
- `rdi = 0x1002` (`ARCH_SET_FS`)
- `rsi = lea ulisp_worker_tls_table[rip]`
- テーブル 0 番目の `worker_id` に 0 を格納。

### 4.3 子スレッド（Worker 1..63）の生成
`SYS_clone` (syscall 56) の実行時に `CLONE_SETTLS` (0x00080000) フラグを指定する。
- 合計フラグ: `CLONE_THREAD_FLAGS = 0x000d0f00` (`CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND | CLONE_THREAD | CLONE_SYSVSEM | CLONE_SETTLS`)
- 第 5 引数 `%r8`: `ulisp_worker_tls_table + (child_worker_id * 64)`
- カーネルが子スレッド起動時に自動的に `%fs_base` をそのアドレスに設定。
- 子スレッドのエントリで追加初期化することなく、即座に `%fs:0` が有効となる。

### 4.4 Worker 判別コードの革新的短縮
従来の 8 命令が、TLS 参照により **わずか 1〜2 命令** に削減され、実行性能が向上する。
```assembly
# 変更後:
mov rcx, fs:0
and rcx, 63
lea rdx, [rip + ulisp_handler_chain]
lea rdx, [rdx + rcx*8]
```

### 4.5 スレッド生成上限（MAX_WORKERS = 64）の強制
`ulisp_fn__pctsys_spawn_thread` において、`ulisp_thread_spawn_counter` が 63 を超える場合は `SYS_clone` を行わず、即座に Scheme の `#f` (または 0) を返却して安全に拒絶する。

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`ulisp/runtime/concurrency/thread.s`](../../ulisp/runtime/concurrency/thread.s):
  - `ulisp_worker_tls_table` の配置
  - `ulisp_init_worker_tls` ルーチンの実装 (`SYS_arch_prctl`)
  - `CLONE_SETTLS` (0x00080000) の追加と第 5 引数 `%r8` への TLS アドレス指定
  - 最大スレッド数 (64) 上限チェック
- [x] [`ulisp/runtime/concurrency/context.s`](../../ulisp/runtime/concurrency/context.s):
  - 全 9 箇所の `r12 - ulisp_gc_state >> 25` を `mov ..., fs:0` に置換
- [x] [`ulisp/backend/140_backend_x86_64.scm`](../../ulisp/backend/140_backend_x86_64.scm):
  - `%push-handler`, `%pop-handler`, `%raise`, `%call/cc` の 4 箇所の `r12` シフトを `%fs:0` に置換
- [x] [`ulisp/backend/142_backend_x86_freestanding.scm`](../../ulisp/backend/142_backend_x86_freestanding.scm):
  - `ulisp_pair_type_error`, `ulisp_vector_type_error` の 2 箇所の `r12` シフトを `%fs:0` に置換
- [x] [`ulisp/runtime/concurrency/thread.scm`](../../ulisp/runtime/concurrency/thread.scm):
  - スレッド上限超過時のエラーハンドリング
- [x] [`tests/concurrency/test_multithread_scheduler.scm`](../../tests/concurrency/test_multithread_scheduler.scm):
  - 32MB 超過割り当てを行うストレステストの追加・検証

---

## 6. 実装方針 / Implementation Plan

Target Branch: `fix/747-implement-tls-worker-identification-for-x86-64`

### Step 1: `thread.s` への TLS テーブル定義とメインスレッド初期化
1. `.bss` に `ulisp_worker_tls_table: .zero 4096` を定義。
2. `ulisp_init_worker_tls` 関数をエクスポートし、`SYS_arch_prctl` (158, `ARCH_SET_FS` = 0x1002) を発行。
3. `ulisp_worker_tls_table[0]` の `worker_id` に 0 を設定。
4. ランタイム初期化シーケンス（または `_start` / スレッド起動初期化）から確実に呼び出されるようにする。

### Step 2: `thread.s` の `ulisp_fn__pctsys_spawn_thread` 刷新
1. `ulisp_thread_spawn_counter` のインクリメント前に上限チェック（`cmp rax, 63; jae .L_spawn_limit_exceeded`）を追加。
2. `CLONE_THREAD_FLAGS` に `CLONE_SETTLS` (0x00080000) を追加 (`0x000d0f00`)。
3. 子スレッド用 TLS バッファアドレス（`lea r8, [rip + ulisp_worker_tls_table]; shl rax, 6; add r8, rax`）を計算し、`SYS_clone` の第 5 引数 `%r8` に渡す。
4. 子スレッド用 TLS バッファの `worker_id` にそのスレッドのインデックスを設定。

### Step 3: `context.s` の Worker 判別を `%fs:0` に刷新
`context.s` 内の以下の 9 箇所を `mov r8, fs:0; and r8, 63`（または直結）に置換：
- Line 85-88 (`ulisp_task_exit_trampoline`)
- Line 131-134 (`ulisp_fn__pctasm_get_trampoline_addr` which=4)
- Line 141-144 (`ulisp_fn__pctasm_get_trampoline_addr` which=5)
- Line 149-152 (`ulisp_fn__pctasm_get_trampoline_addr` which=6)
- Line 184-187 (`ulisp_fn__pctcoroutine_switch`)
- Line 224-227 (`ulisp_fn__pctcoroutine_transfer`)
- Line 269-272 (`ulisp_fn__pctcoroutine_save_k`)
- Line 321-324 (`ulisp_fn__pctcoroutine_restore_k`)
- Line 346-349 (`ulisp_fn__pctcoroutine_reset_k`)

### Step 4: `140_backend_x86_64.scm` & `142_backend_x86_freestanding.scm` のハンドラチェーン参照刷新
1. `140_backend_x86_64.scm` の `%push-handler`, `%pop-handler`, `%raise`, `%call/cc` から `r12` の右シフト 25bit コードを全廃し、`mov rcx, fs:0; and rcx, 63` に置換。
2. `142_backend_x86_freestanding.scm` の `ulisp_pair_type_error`, `ulisp_vector_type_error` も同様に `%fs:0` 参照に置換。

### Step 5: `thread.scm` の上限チェックと協調
1. スレッド spawn 要求時に最大数（64）を安全にハンドリング。
2. `#f` 返却時の適切な例外送出またはハンドリングを実装。

### Step 6: 結合テストと 32MB 超過ストレステストの実行
1. `ulisp/tests/test_multithread_scheduler.scm` に、各 Worker が 32MB 以上のヒープを消費するループ処理テストを追加。
2. メモリ割り当てが 32MB や 64MB を超えても、例外ハンドラが正常に機能し、タスク切り替えが狂わないことを検証。
3. `make -C ulisp test` で全回帰テスト、Stage 1〜3 セルフホスティングブートストラップの完全一致を確認。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] **TLS 基盤の確立**: `ulisp_worker_tls_table` が定義され、メインスレッド（`SYS_arch_prctl`）および子スレッド（`CLONE_SETTLS`）双方で `%fs_base` が正常に初期化されること
- [x] **`r12` 依存の完全撤廃**: `context.s`, `140_backend_x86_64.scm`, `142_backend_x86_freestanding.scm` の全 15 箇所から `shr ..., 25` による Worker ID 計算が全廃され、`%fs:0` 参照に置換されていること
- [x] **32MB 超過アロケーションでの安全性保証**: 各スレッドが 32MB を超えるヒープ割り当てを行っても、Worker 構造体や他スレッドのハンドラチェーンが破壊されず正常に動作すること
- [x] **スレッド数上限チェックの実装**: 64 を超えるスレッド spawn 要求に対してメモリ破壊や未定義動作を起こさず、安全にエラーが返却されること
- [x] **全 Nanopass パス・ブートストラップ・並行性テストの PASS**:
  - `make -C ulisp test` が全 38 nanopass パスを PASS すること
  - Stage 2 と Stage 3 のコンパイラバイナリが bit-for-bit identical（完全一致）すること
  - `make -C ulisp test_concurrency`（全シナリオ）が PASS すること
