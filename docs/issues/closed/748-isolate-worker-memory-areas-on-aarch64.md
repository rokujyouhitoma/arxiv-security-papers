---
ID: 748
種別: Feature
優先度: High
ステータス: Closed
関連 Issue: #719, #747, #689, #690, #691
---

# [FEAT/SEC] AArch64 における TPIDR_EL0 TLS に基づく Worker メモリ領域の個別分離とマルチスレッド基盤整備 (ID: 748)

## 1. 概要 / Summary
Issue #719 において、ULisp ランタイムにマルチスレッド Worker 対応の例外ハンドラ連鎖テーブル（`ulisp_handler_chain[64]`）が導入され、x86-64 では Issue #747 により `%fs_base` TLS を用いた O(1) の安全な Worker 識別が確立された。
しかし、AArch64 バックエンド（`ulisp/backend/150_backend_aarch64.scm`）においては、`ulisp_handler_chain` テーブルが 64 スレッド分（512 バイト）確保されているにもかかわらず、コード生成ルーチンが依然として常にオフセット 0（Worker 0 スロット）のみを直接参照している。

この結果、AArch64 上でマルチスレッド並行処理が稼働した際、全 Worker スレッドが Worker 0 の単一ハンドラチェーンスロットを共有・競合上書きしてしまい、深刻なデータ破壊や例外取り違え（CWE-662, CWE-787）が発生する。

本 Issue では、ARMv8-A アーキテクチャの EL0 専用スレッドポインタレジスタ **`TPIDR_EL0`** を導入し、x86-64 と同等の O(1) かつシステムコール不要で安全な Worker メモリ領域分離機構を AArch64 バックエンドに整備する。

---

## 2. 脅威モデル分析とセキュリティ影響 (STRIDE & CWE)

| 脅威分類 (STRIDE) | 対象 CWE | 影響度 | 脅威シナリオと脆弱性のメカニズム |
| :--- | :--- | :---: | :--- |
| **Tampering (改ざん)** / **Elevation of Privilege** | **CWE-662**: Improper Synchronization on Shared Resource | High | AArch64 上で Worker 1..63 が例外ハンドラ（`%push-handler`）を登録した際、全スレッドが同一の `ulisp_handler_chain[0]` に書き込むため、他スレッドのハンドラ連鎖が破壊される。例外送出時に無関係なスレッドのスタックフレームへ分岐し、未定義動作やメモリ改ざんが発生する。 |
| **Denial of Service (サービス拒否)** | **CWE-787**: Out-of-bounds Write | High | 複数スレッドが同時に `ulisp_handler_chain[0]` を更新するとデータレースが発生し、チェーンのループ（循環参照）や不正ポインタへの書き込みによってプロセス全体がクラッシュする。 |
| **Information Disclosure (情報漏えい)** | **CWE-125**: Out-of-bounds Read | Medium | 他スレッドの終了済みスタックフレームアドレスをハンドラチェーンから読み出し、解放済みスタックメモリへのアクセス（CWE-416）が発生する。 |

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

### なぜこの問題が存在しているか
1. **初期 AArch64 バックエンドの単一スレッド前提**:
   `150_backend_aarch64.scm` の初期実装（Issue #503）時、シングルスレッド実行のみが想定されていたため、固定シンボル `ulisp_handler_chain` の先頭（スロット 0）に直接 `ldr`/`str` を行うコードが生成されていた。
2. **ハードコードされた 5 箇所のハンドラ参照コード**:
   - `%push-handler` (Line 560-561)
   - `%pop-handler` (Line 574-575)
   - `%raise` (Line 580-581)
   - `%call/cc` (Line 731-732)
   - continuation restore (Line 903-904)
   これら全 5 箇所において、Worker オフセット計算が一切行われず `ulisp_handler_chain` の先頭に直接アクセスしている。

---

## 4. 恒久対策アーキテクチャ設計 (AArch64 TLS / `TPIDR_EL0`)

### 4.1 AArch64 ARMv8-A `TPIDR_EL0` アーキテクチャの優位性
- ARMv8-A では、ユーザー空間（EL0）から直接アクセス可能な 64-bit スレッド ID レジスタ **`TPIDR_EL0`** が定義されている。
- 特権（EL1）へのコンテキストスイッチを伴うシステムコールを介さず、ユーザー空間命令 `msr tpidr_el0, <Xt>` で書き込み、`mrs <Xt>, tpidr_el0` で 1 サイクル O(1) 読み出しが可能。
- x86-64 の `SYS_arch_prctl` よりも軽量・高速に動作する。

### 4.2 Worker TLS テーブルの設計 (`ulisp_worker_tls_table`)
BSS 領域に 64 ワーカー × 64 バイト（キャッシュライン整列）のテーブルを配置：
```assembly
    .bss
    .align 6
    .globl ulisp_worker_tls_table
    .weak ulisp_worker_tls_table
ulisp_worker_tls_table:
    .zero 4096    // 64 workers * 64 bytes
```
各スレッドの TLS ブロック（オフセット 0）:
- `+0` (8 bytes): `worker_id` (0, 1, 2, ..., 63)
- `+8` (56 bytes): 予約領域 / キャッシュラインパディング

### 4.3 メインスレッド（Worker 0）の起動時初期化
`150_backend_aarch64.scm` の `_start:` エントリ直後において、メインスレッドの `TPIDR_EL0` を `ulisp_worker_tls_table[0]` にバインド：
```assembly
    adrp x0, ulisp_worker_tls_table
    add x0, x0, :lo12:ulisp_worker_tls_table
    msr tpidr_el0, x0
```

### 4.4 Worker ごとのスロットアドレス動的解決パターン
ハンドラチェーンを参照する全箇所において、以下の耐障害セーフガード付き動的解決コードを展開：
```assembly
    mrs x1, tpidr_el0
    cbz x1, 1f
    ldr x1, [x1]                // x1 = worker_id (0..63)
    and x1, x1, #63             // Bound mask
1:
    adrp x2, ulisp_handler_chain
    add x2, x2, :lo12:ulisp_handler_chain
    add x1, x2, x1, lsl #3       // x1 = &ulisp_handler_chain[worker_id]
```
`cbz x1, 1f` により、万が一 `tpidr_el0` が 0（未初期化）の状態で実行された場合でも安全にスロット 0（メインスレッド領域）にフォールバックし、クラッシュ（SIGSEGV）を 100% 防止する。

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`ulisp/backend/150_backend_aarch64.scm`](../../ulisp/backend/150_backend_aarch64.scm):
  - `_start:` での `TPIDR_EL0` 初期化
  - `%push-handler`, `%pop-handler`, `%raise`, `%call/cc`, continuation restore の全 5 箇所のスロット参照刷新
  - BSS 領域への `ulisp_worker_tls_table` (4096 bytes) の追加
- [ ] [`ulisp/tests/test_backend_aarch64.scm`](../../ulisp/tests/test_backend_aarch64.scm):
  - AArch64 LIR コード生成テストに TLS / `TPIDR_EL0` 命令検証を追加
- [ ] [`ulisp/tests/test_aarch64_qemu_smoke.scm`](../../ulisp/tests/test_aarch64_qemu_smoke.scm):
  - AArch64 ネイティブ実行における例外ハンドラ（`guard`/`raise`）および `call/cc` の QEMU 動作検証テストケースを追加
- [ ] [`scripts/test_aarch64_qemu_smoke.sh`](../../scripts/test_aarch64_qemu_smoke.sh):
  - 例外処理・TLS スモークテストの実行連携

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/748-isolate-worker-memory-areas-on-aarch64`

### Step 1: `150_backend_aarch64.scm` への TLS テーブル定義とメインスレッド初期化
1. BSS セクションに `ulisp_worker_tls_table`（4096 バイト、64 バイト整列）を追加。
2. `_start:` ルーチンの先頭で `adrp`/`add` により `ulisp_worker_tls_table` のアドレスを `TPIDR_EL0` に格納。

### Step 2: `150_backend_aarch64.scm` のハンドラチェーン参照箇所の刷新
以下の 5 箇所を動的スロット解決コードに置換：
1. Line 560-561 (`%push-handler`)
2. Line 574-575 (`%pop-handler`)
3. Line 580-581 (`%raise`)
4. Line 731-732 (`%call/cc` handler chain save)
5. Line 903-904 (`ulisp_restore_continuation` handler chain restore)

### Step 3: AArch64 バックエンド LIR テストの拡充
`ulisp/tests/test_backend_aarch64.scm` に、`%push-handler` や `%raise` が生成するアセンブリ出力に `tpidr_el0` およびスロットオフセット計算が含まれることを検証するアサーションを追加。

### Step 4: QEMU AArch64 ネイティブエミュレーションテストの拡充
`ulisp/tests/test_aarch64_qemu_smoke.scm` に以下のテストケースを追加：
- Case 7: AArch64 上での `guard` / `raise` 例外捕捉とハンドラチェーンの巻き戻し
- Case 8: AArch64 上での `call/cc` による非ローカル脱出とハンドラチェーン復帰
`make -C ulisp test_aarch64_qemu` により、QEMU エミュレータ上で正常終了（Exit code 0）することを実機検証。

### Step 5: 全体回帰テストの実行
- `make -C ulisp test_aarch64` PASS
- `make -C ulisp test_aarch64_qemu` PASS
- `make -C ulisp test` PASS（全 38 nanopass パス、セルフホスティング bit-for-bit 一致）

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] **AArch64 TLS 基盤の確立**: `ulisp_worker_tls_table` が定義され、`_start:` において `TPIDR_EL0` が正常に初期化されること
- [x] **スロット 0 固定依存の完全撤廃**: `150_backend_aarch64.scm` の全 5 箇所（`%push-handler`, `%pop-handler`, `%raise`, `%call/cc`, continuation restore）において、`TPIDR_EL0` に基づく Worker ごとの個別スロット参照に置換されていること
- [x] **未初期化セーフガードの配備**: `tpidr_el0` が 0 の場合でも安全にスロット 0 にフォールバックし、クラッシュしない耐障害性が確保されていること
- [x] **QEMU AArch64 ネイティブ実行テストの合格**:
  - `make -C ulisp test_aarch64` が全 28 テスト PASS すること
  - `make -C ulisp test_aarch64_qemu` において、例外処理・call/cc を含む全 9 スモークテストが PASS すること
- [x] **全 Nanopass パス・ブートストラップテストの完全合格**:
  - `make -C ulisp test` が全 38 nanopass パスを PASS すること
  - Stage 2 と Stage 3 のコンパイラバイナリが bit-for-bit identical であること
