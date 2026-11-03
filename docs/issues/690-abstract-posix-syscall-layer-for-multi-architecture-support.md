---
ID: 690
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] ULisp POSIX システムコール層のマルチアーキテクチャ抽象化と AArch64 Linux 対応 (ID: 690)

## 1. 概要 / Summary
`ulisp/lib/posix.scm` に現在ハードコードされている Linux x86-64 固有のシステムコール番号（`read`=0, `write`=1, `open`=2, `close`=3, `mmap`=9, `exit`=60 等）をターゲットアーキテクチャに応じて切り替え可能とする抽象化レイヤーを導入する。
また、AArch64 Linux においてレガシー syscall（`open`, `access`, `unlink` 等）が廃止され、新世代 API（`openat`, `faccessat`, `unlinkat`）に統一されている仕様差異を吸収・実装する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §2.2 (ハードウェア・ABI 整合), §3 (低レイヤコード生成仕様)
- **R7RS 準拠**: §6.13 (Ports), §6.14 (System Interface)
- **関連 Issue**: #516 (Zero-libc Linux Runtime), #503 (AArch64 Backend), #689 (QEMU Toolchain)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm): システムコール番号および新世代 syscall ラッパーのマルチアーキテクチャ化
- [ ] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm): `%raw-syscall` のターゲット別引数マッピング検証
- [ ] [ulisp/backend/150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm): `%syscall` 命令の `svc #0` コード生成整合性

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/690-abstract-posix-syscall-layer`

1. AArch64 Linux のシステムコール番号辞書の策定：
   - `sys_read`: 63, `sys_write`: 64, `sys_close`: 57, `sys_exit`: 93
   - `sys_mmap`: 222, `sys_mremap`: 216, `sys_clock_gettime`: 113
   - `sys_openat`: 56 (`AT_FDCWD` = -100), `sys_unlinkat`: 35, `sys_faccessat`: 48
2. `posix.scm` においてコンパイル時または実行時にターゲットアーキテクチャに応じた定数群を選択・展開する構造へのリファクタリング。
3. `openat` / `faccessat` / `unlinkat` を利用した汎用 `file-exists?`, `delete-file`, `open-input-file` プリミティブの適合。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] x86-64 と AArch64 のシステムコール番号が明確に分離・抽象化されていること。
- [ ] AArch64 モードで `sys-write`, `sys-read`, `sys-mmap`, `sys-exit` が正しい syscall 番号で発行されること。
- [ ] 既存の x86-64 ターゲットの動作に一切の後退（デグレ）が発生しないこと。
