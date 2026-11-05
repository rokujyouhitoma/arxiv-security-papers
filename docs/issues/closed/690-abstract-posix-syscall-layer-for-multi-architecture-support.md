---
ID: 690
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] ULisp POSIX システムコール層のマルチアーキテクチャ抽象化と AArch64 Linux 対応 (ID: 690)

## 1. 概要 / Summary
現在 `ulisp/lib/posix.scm` において、Linux x86-64 固有のシステムコール番号（`sys_read`=0, `sys_write`=1, `sys_open`=2, `sys_close`=3, `sys_mmap`=9, `sys_exit`=60 等）が直接ハードコードされている。
また、AArch64 (ARM64) Linux カーネルではレガシーシステムコール（`open`, `access`, `unlink`, `dup2`）が ABI レベルで完全に廃止され、新世代の `*at` 系システムコール（`openat`=56, `faccessat`=48, `unlinkat`=35, `dup3`=24）に統一されている。

本 Issue では、以下の 3 点を包括的に解決し、ULisp のマルチターゲット POSIX システムコール抽象化基盤を確立する：
1. **システムコール定数およびディスパッチの抽象化**:
   - `x86_64` と `aarch64` の各システムコール番号を体系的に分離・定義し、コンパイル時条件展開（`cond-expand`）またはターゲット指定に応じて適切な定数・ラッパーを選択する機構の導入。
2. **AArch64 新世代 POSIX API の実装と透過的フォールバック**:
   - `sys-open`, `sys-access`, `sys-unlink`, `sys-dup2` 等の基本プリミティブにおいて、AArch64 環境下では `AT_FDCWD` (-100) を自動バインドした `openat`, `faccessat`, `unlinkat`, `dup3` を発行し、上位層（`file-exists?`, `delete-file`, `open-input-file` 等）に対して 100% 透過的な互換性を提供する。
3. **LIR および AArch64 バックエンドにおける `%raw-syscall` コード生成の是正**:
   - `ulisp/lir/129_lir_primitives.scm` の `%raw-syscall` 生成ルーチンおよび `ulisp/backend/150_backend_aarch64.scm` の命令エミッタを改修し、AArch64 システムコール規約（システムコール番号: `x8`、引数: `x0`〜`x5`、戻り値: `x0`、命令: `svc #0`）に厳密に準拠したアセンブリを生成可能とする。

---

## 2. トレーサビリティ / Traceability
- **DSN-33 (ULisp Bare-Metal Architecture & Nanopass Pipeline)**:
  - §2.2: ハードウェアおよび ABI 整合性（AArch64 AAPCS64 呼び出し規約、スタック 16 バイト整列、Linux AArch64 syscall ABI）
  - §3: 低レイヤコード生成仕様（`%raw-syscall` のターゲット依存レジスタ割り当て）
  - §4.3: Pass 150 AArch64 バックエンドコードジェネレータ
- **R7RS 規格準拠**:
  - §4.2.1: `cond-expand` によるプラットフォーム機能判定（`x86-64`, `aarch64`）
  - §6.13: 入出力ポートプリミティブ（`open-input-file`, `open-output-file`）
  - §6.14: システムインターフェース（`file-exists?`, `delete-file`, `exit`, `current-second`, `current-jiffy`）
- **関連 Issue**:
  - [Issue #503: Implement AArch64 Backend via LIR](503-implement-ulisp-aarch64-backend-via-lir.md)
  - [Issue #516: Bare-Metal Linux Runtime without libc](516-implement-zero-libc-pure-scheme-bare-metal-runtime.md)
  - [Issue #689: Setup QEMU User and Cross Toolchain Verification Environment](689-setup-qemu-user-and-cross-toolchain-verification-environment.md)
  - [Issue #691: Verify ULisp AArch64 AOT Codegen and QEMU Execution](../691-verify-ulisp-aarch64-aot-codegen-and-qemu-execution.md)
  - [Issue #692: Implement AArch64 Native Context Switch for Concurrency Runtime](../692-implement-aarch64-native-context-switch-for-concurrency-runtime.md)
  - [Issue #693: Integrate QEMU AArch64 Automated Regression Test Suite into Makefile](../693-integrate-qemu-aarch64-automated-regression-test-suite-into-makefile.md)

---

## 3. セキュリティ考慮事項・脅威分析 / Security & Threat Analysis
- **CWE-693 (Protection Mechanism Failure / Syscall Mismatch & ABI Corruption)**:
  - AArch64 上で x86-64 のシステムコール番号を直接発行した場合、番号の不一致により意図しないシステムコール（例: x86-64 の `sys_exit`=60 は AArch64 では `sys_uname`、`sys_read`=0 は `sys_io_setup`、`sys_write`=1 は `sys_io_destroy`）が誤実行され、不正メモリアクセスやサイレントなハングアップ、特権昇格脆弱性を誘発する。
  - **対策**: ターゲットアーキテクチャに応じた厳密なシステムコール番号ディクショナリを構築し、未定義・不整合なシステムコール番号の発行を静的・動的に遮断する。
- **CWE-704 (Incorrect Type Conversion or Cast / Raw Argument Truncation)**:
  - `AT_FDCWD` (-100) や 64-bit ファイル記述子、ポインタを `%raw-syscall` の引数として渡す際、タグ付け処理（Fixnum tag bit）や 32-bit/64-bit 符号拡張の誤りによりポインタ破壊（Memory Corruption）を招く恐れがある。
  - **対策**: `%to-raw` および `%ptr-untag` の引数正規化を徹底し、64-bit 符号付き整数の表現がレジスタ `x0`〜`x5` に正確に展開されることを検証する。
- **CWE-426 (Untrusted Search Path / File Descriptor Confusion)**:
  - `openat`, `faccessat`, `unlinkat` において、誤ったディレクトリファイル記述子（dfd）が渡されると、意図しない基底ディレクトリからの相対パス探索が発生するリスクがある。
  - **対策**: `AT_FDCWD` (-100) を明確な定数として管理し、カレントワーキングディレクトリ基準での相対パス解決を強制する。
- **CWE-833 (Deadlock / Indefinite Wait Due to System Call Failure)**:
  - `sys_clock_gettime` の番号差異（x86-64: 228 vs AArch64: 113）により時間取得が失敗すると、並行性スケジューラや Futex タイムアウトが無限待機に陥る。
  - **対策**: 時刻取得プリミティブの戻り値を検証し、AArch64 環境下で正しいナノ秒単位の単調増加・リアルタイム取得を保証する。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/posix.scm](../../../ulisp/lib/posix.scm):
  - x86-64 と AArch64 のシステムコール番号定数分離（`cond-expand` 対応）
  - `AT_FDCWD` (-100) 定数定義
  - AArch64 向け `openat`, `faccessat`, `unlinkat`, `dup3` を利用した `sys-open`, `sys-access`, `sys-unlink`, `sys-dup2` の統合実装
  - `sys-mmap`, `sys-mremap`, `sys-munmap`, `sys-clock-gettime` のマルチターゲット番号対応
- [x] [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm):
  - `ulisp-supported-feature?` における現在ターゲット（`*current-target-arch*`）に基づく `x86-64` / `aarch64` / `arm64` 機能識別子の動的判定対応
- [x] [ulisp/compiler/driver.scm](../../../ulisp/compiler/driver.scm):
  - コンパイルターゲット設定時に `*current-target-arch*` を同期更新するフックの配線
- [x] [ulisp/lir/129_lir_primitives.scm](../../../ulisp/lir/129_lir_primitives.scm):
  - `lir-compile-raw-syscall` の改修（スタックフレームへの引数退避および `%syscall` 命令への `si` 渡し）
- [x] [ulisp/backend/140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm):
  - `%syscall` のスタックフレーム参照（`si` 指定時）および既存 `syscall` 命令との後方互換性担保
- [x] [ulisp/backend/150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm):
  - `emit-arm-lir-instruction` への `(%syscall ...)` 実装追加：
    - `si` から `x8`（システムコール番号）および `x0`〜`x5`（引数 1〜6）へのレジスタロード
    - `svc #0` 命令発行（戻り値 `x0`）
- [x] [ulisp/tests/test_backend_aarch64.scm](../../../ulisp/tests/test_backend_aarch64.scm):
  - `%raw-syscall` の LIR 生成および AArch64 コード生成（`svc #0`, `x8` 等）のユニットテスト追加
- [x] [docs/issues/README.md](../README.md):
  - Issue 台帳ステータス管理

---

## 5. Linux x86-64 vs AArch64 システムコール対照表 / ABI Specification Reference

| システムコール論理名 | 引数シグネチャ | x86-64 番号 | AArch64 番号 | AArch64 システムコール名 & 差異 |
| :--- | :--- | :---: | :---: | :--- |
| `read` | `(fd, buf, count)` | 0 | 63 | `sys_read` |
| `write` | `(fd, buf, count)` | 1 | 64 | `sys_write` |
| `open` | `(path, flags, mode)` | 2 | 56 | `sys_openat(AT_FDCWD, path, flags, mode)` ※AArch64 は `open` 廃止 |
| `close` | `(fd)` | 3 | 57 | `sys_close` |
| `access` | `(path, mode)` | 21 | 48 | `sys_faccessat(AT_FDCWD, path, mode, 0)` ※AArch64 は `access` 廃止 |
| `dup2` | `(oldfd, newfd)` | 33 | 24 | `sys_dup3(oldfd, newfd, 0)` ※AArch64 は `dup2` 廃止 |
| `exit` | `(status)` | 60 | 93 | `sys_exit` |
| `unlink` | `(path)` | 87 | 35 | `sys_unlinkat(AT_FDCWD, path, 0)` ※AArch64 は `unlink` 廃止 |
| `mmap` | `(addr, len, prot, flags, fd, off)` | 9 | 222 | `sys_mmap` |
| `munmap` | `(addr, len)` | 11 | 215 | `sys_munmap` |
| `mremap` | `(old_addr, old_size, new_size, flags)` | 25 | 216 | `sys_mremap` |
| `clock_gettime` | `(clock_id, timespec_ptr)` | 228 | 113 | `sys_clock_gettime` |

- **共通定数**:
  - `AT_FDCWD` = -100 (Linux 全アーキテクチャ共通)

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/690-abstract-posix-syscall-layer`

### Step 1: `ulisp/compiler/helpers.scm` & `driver.scm` のターゲット機能判定強化
1. グローバルパラメータまたはボックス `*current-target-arch*`（初期値: `'x86_64`）を定義。
2. `ulisp/compiler/driver.scm` の CLI パースおよびディレクティブ抽出処理において、ターゲットが決定した時点で `(set! *current-target-arch* target)` を設定する。
3. `ulisp/compiler/helpers.scm` の `ulisp-supported-feature?` を改修：
   - `feat` が `'x86-64` または `'x86_64` の場合: `(eq? *current-target-arch* 'x86_64)`
   - `feat` が `'aarch64` または `'arm64` の場合: `(eq? *current-target-arch* 'aarch64)`
   - その他 R7RS 標準機能識別子は従来通り維持。

### Step 2: `ulisp/lib/posix.scm` におけるシステムコール番号抽象化と新世代 API 実装
1. `cond-expand` を利用してアーキテクチャ別のシステムコール番号定数およびフラグを定義：
   - AArch64 節:
     - `*sys-read*`: 63, `*sys-write*`: 64, `*sys-close*`: 57, `*sys-exit*`: 93
     - `*sys-mmap*`: 222, `*sys-mremap*`: 216, `*sys-munmap*`: 215, `*sys-clock-gettime*`: 113
     - `*sys-openat*`: 56, `*sys-faccessat*`: 48, `*sys-unlinkat*`: 35, `*sys-dup3*`: 24
     - `*sys-at-fdcwd*`: -100
   - x86-64 / else 節:
     - `*sys-read*`: 0, `*sys-write*`: 1, `*sys-open*`: 2, `*sys-close*`: 3
     - `*sys-access*`: 21, `*sys-dup2*`: 33, `*sys-exit*`: 60, `*sys-unlink*`: 87
     - `*sys-mmap*`: 9, `*sys-munmap*`: 11, `*sys-mremap*`: 25, `*sys-clock-gettime*`: 228
     - `*sys-openat*`: 257, `*sys-at-fdcwd*`: -100
2. 抽象化された各 API ラッパーの実装：
   - `sys-exit`: `*sys-exit*` を使用。
   - `sys-write`: `*sys-write*` を使用。
   - `sys-read`: `*sys-read*` を使用。
   - `sys-close`: `*sys-close*` を使用。
   - `sys-open`:
     - `cond-expand` 内で AArch64 の場合は `(%raw-syscall (%to-raw *sys-openat*) (%to-raw *sys-at-fdcwd*) path-ptr (%to-raw flags) (%to-raw mode) 0 0)` を発行。
     - x86-64 の場合は従来の `*sys-open*` (2) を発行。
   - `sys-access`:
     - AArch64 の場合は `(%raw-syscall (%to-raw *sys-faccessat*) (%to-raw *sys-at-fdcwd*) path-ptr (%to-raw mode) 0 0 0)` を発行。
     - x86-64 の場合は従来の `*sys-access*` (21) を発行。
   - `sys-unlink`:
     - AArch64 の場合は `(%raw-syscall (%to-raw *sys-unlinkat*) (%to-raw *sys-at-fdcwd*) path-ptr 0 0 0 0)` を発行。
     - x86-64 の場合は従来の `*sys-unlink*` (87) を発行。
   - `sys-dup2`:
     - AArch64 の場合は `(%raw-syscall (%to-raw *sys-dup3*) (%to-raw oldfd) (%to-raw newfd) 0 0 0 0)` を発行。
     - x86-64 の場合は従来の `*sys-dup2*` (33) を発行。
   - `sys-mmap`, `sys-mremap`, `sys-clock-gettime-monotonic`, `sys-clock-gettime-realtime`: 対応する抽象定数を使用。
3. `ulisp/runtime/concurrency/context.scm` における `sys_munmap` (11 -> 215 on aarch64) の抽象定数化。

### Step 3: LIR および バックエンドにおける `%syscall` 命令の発行是正
1. `ulisp/lir/129_lir_primitives.scm`:
   - `lir-compile-raw-syscall` において、7 つの引数をスタック（`si` 〜 `si - 48`）にストア後、`(emit-lir! (list '%syscall si))` を発行する構造へと改良。
2. `ulisp/backend/140_backend_x86_64.scm`:
   - `((%syscall) ...)` において、引数 `si` が指定されている場合はスタックからのロード命令（`%rax`, `%rdi`, `%rsi`, `%rdx`, `%r10`, `%r8`, `%r9`）と `syscall` 命令を展開。引数なしの場合は互換性のため単一 `syscall` を維持。
3. `ulisp/backend/150_backend_aarch64.scm`:
   - `emit-arm-lir-instruction` に `((%syscall) ...)` 節を追加：
     - `si` からスタック上の値をロード：
       - `ldr x8, [sp, #si]` (システムコール番号)
       - `ldr x0, [sp, #(si - 8)]` (引数 1)
       - `ldr x1, [sp, #(si - 16)]` (引数 2)
       - `ldr x2, [sp, #(si - 24)]` (引数 3)
       - `ldr x3, [sp, #(si - 32)]` (引数 4)
       - `ldr x4, [sp, #(si - 40)]` (引数 5)
       - `ldr x5, [sp, #(si - 48)]` (引数 6)
     - `emit "    svc #0"` を発行（戻り値は `x0` に自動格納）。

### Step 4: 回帰テスト・品質検証の実施
1. `tests/test_backend_aarch64.scm` に `%raw-syscall` 命令の LIR およびアセンブリ生成検証テスト（Step 8）を追加。
2. `make -C ulisp test_aarch64` を実行し、全テスト PASS を確認。
3. `make -C ulisp test_aarch64_env` を実行し、クロスツールチェーン環境での正常動作を確認。
4. `make check_format` および `make static_analysis` を実行し、品質ゲート 100% 準拠を確認。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] x86-64 と AArch64 の Linux システムコール番号定数が分離・抽象化され、`posix.scm` が両アーキテクチャで正しく展開されること。
- [x] AArch64 において、廃止されたレガシー API（`open`, `access`, `unlink`, `dup2`）の代替として `openat`, `faccessat`, `unlinkat`, `dup3` が `AT_FDCWD` 経由で正しく発行されること。
- [x] `ulisp/lir/129_lir_primitives.scm` および `ulisp/backend/150_backend_aarch64.scm` において、`%raw-syscall` から AArch64 ABI 規約通りの `x8` / `x0`〜`x5` ロードおよび `svc #0` が出力されること。
- [x] `make -C ulisp test_aarch64` が 100% PASS すること。
- [x] 既存の x86-64 ターゲットの全テストスイート（`make -C ulisp test` / `make check_format` / `make static_analysis`）に一切の後退（デグレ）が発生しないこと。
- [x] `docs/issues/README.md` のステータスが `Closed` に更新されていること。
