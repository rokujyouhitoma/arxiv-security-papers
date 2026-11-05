---
ID: 689
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] QEMU ユーザーエミュレーションおよび AArch64 クロスツールチェーン検証環境の構築 (ID: 689)

## 1. 概要 / Summary
ULisp のマルチ CPU アーキテクチャサポート（特に AArch64 / ARM64）をホスト環境（x86-64 Linux）上で実機レスかつ高速に検証可能とするため、QEMU ユーザー空間エミュレータ（`qemu-user`, `qemu-user-static`）およびクロスビルド用 GNU ツールチェーン（`binutils-aarch64-linux-gnu`, `gcc-aarch64-linux-gnu`）を導入・標準化し、クロスビルド＆エミュレーション実行の自動検証基盤を確立する。

本 Issue は、後続のシステムコール層抽象化 (#690)、AOT コンパイラ出力の結合検証 (#691)、並行性コンテキストスイッチ実装 (#692)、および Makefile 自動回帰テスト統合 (#693) を支える前提インフラストラクチャとなる。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**:
  - §2.2: ハードウェア・ABI 整合性（AArch64 AAPCS64 呼び出し規約、スタック 16 バイト整列要件）
  - §3: 言語機能と低レイヤコード生成仕様（AArch64 レジスタ割り当て・命令体系）
  - §4.3: Pass 150 AArch64 バックエンドコードジェネレータ
- **関連 Issue**:
  - [Issue #503: Implement AArch64 Backend via LIR](503-implement-aarch64-backend-via-lir.md)
  - [Issue #616: ELF64 Static Binary Generator](616-implement-zero-libc-elf64-generator.md)
  - [Issue #690: Abstract POSIX Syscall Layer for Multi-Architecture Support](690-abstract-posix-syscall-layer-for-multi-architecture-support.md)
  - [Issue #691: Verify ULisp AArch64 AOT Codegen and QEMU Execution](691-verify-ulisp-aarch64-aot-codegen-and-qemu-execution.md)
  - [Issue #692: Implement AArch64 Native Context Switch for Concurrency Runtime](692-implement-aarch64-native-context-switch-for-concurrency-runtime.md)
  - [Issue #693: Integrate QEMU AArch64 Automated Regression Test Suite into Makefile](693-integrate-qemu-aarch64-automated-regression-test-suite-into-makefile.md)

---

## 3. セキュリティ考慮事項・脅威分析 / Security & Threat Analysis
- **CWE-426 (Untrusted Search Path / Dynamic Linker Hijacking)**:
  - 外部アーキテクチャのバイナリをエミュレーション実行する際、ホスト側の動的リンカ (`/lib64/ld-linux-x86-64.so.2`) や共有ライブラリが誤認・探索されると予期しないコード実行リスクが生じる。
  - **対策**: 検証バイナリは `-static` オプションによる完全静的リンク（Zero-libc / 自前 syscall）を徹底し、ホストおよびターゲットの動的共有ライブラリへの依存を一切排除する。
- **CWE-693 (Protection Mechanism Failure / Syscall Emulation Fidelity)**:
  - QEMU ユーザー空間エミュレータが Linux システムコール（特に `mmap`, `clone`, `futex`, `write`, `exit`）をホストカーネルに仲介する際、アーキテクチャ間の構造体アライメントや errno 変換が不完全であるとエミュレーション異常を招く。
  - **対策**: 最小検証コードにおいて、直接 `svc #0` 命令を発行し、終了コード・標準出力・システムコール戻り値が Linux AArch64 ABI 規約通りに透過されることを厳密にアサートする。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/Makefile](../../ulisp/Makefile): AArch64 クロスツールチェーン変数 (`CROSS_AS_AARCH64`, `CROSS_LD_AARCH64`, `QEMU_AARCH64`) および `test_aarch64_env` ターゲットの定義
- [x] [ulisp/scripts/test_aarch64_env.sh](../../ulisp/scripts/test_aarch64_env.sh): クロスツールチェーン疎通・最小アセンブリ生成・リンク・QEMU 実行・終了コード検証を行う自動チェックスクリプト
- [x] [docs/issues/README.md](README.md): Issue 台帳のステータス管理

---

## 5. 前提条件と技術仕様 / Prerequisites & Technical Specifications
1. **Ubuntu 24.04 (Noble) パッケージ**:
   - `qemu-user-static` (または `qemu-user`): `qemu-aarch64-static` / `qemu-aarch64`
   - `binutils-aarch64-linux-gnu`: `aarch64-linux-gnu-as`, `aarch64-linux-gnu-ld`
   - `gcc-aarch64-linux-gnu`: `aarch64-linux-gnu-gcc` (C ランタイムおよびリンカ補助)
2. **Linux AArch64 ABI 基本仕様**:
   - システムコール発行: `svc #0`
   - システムコール番号レジスタ: `x8`
   - 引数レジスタ: `x0`〜`x5`
   - 戻り値レジスタ: `x0`
   - システムコール番号:
     - `sys_exit` = 93 (`x8 = 93`, `x0 = exit_code`)
     - `sys_write` = 64 (`x8 = 64`, `x0 = fd`, `x1 = buf_ptr`, `x2 = len`)

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/689-setup-qemu-user-and-cross-toolchain`

1. **ホスト環境へのパッケージ導入確認・自動化**:
   - `apt-get install -y --no-install-recommends qemu-user-static binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu` により必要なバイナリがパス上に存在することを保証する。
2. **`ulisp/Makefile` へのクロス環境変数と検証ターゲット定義**:
   - `CROSS_AS_AARCH64 ?= aarch64-linux-gnu-as`
   - `CROSS_LD_AARCH64 ?= aarch64-linux-gnu-ld`
   - `CROSS_CC_AARCH64 ?= aarch64-linux-gnu-gcc`
   - `QEMU_AARCH64 ?= $(shell command -v qemu-aarch64-static 2>/dev/null || command -v qemu-aarch64 2>/dev/null)`
   - 新規ターゲット `test_aarch64_env`:
     - ツールチェーンの存在確認
     - スクリプト `scripts/test_aarch64_env.sh` の起動
3. **疎通検証スクリプト `ulisp/scripts/test_aarch64_env.sh` の実装**:
   - ステップ 1: `aarch64-linux-gnu-as --version` および `qemu-aarch64 --version` の確認
   - ステップ 2: 最小 exit(42) AArch64 アセンブリの生成、アセンブル、完全静的リンク (`-static`)
   - ステップ 3: `qemu-aarch64` 実行、終了ステータスが 42 であることの検証
   - ステップ 4: 文字列出力 (`write(1, "AArch64 QEMU OK\n", 16)`) + exit(0) の AArch64 アセンブリ生成、アセンブル、リンク、実行
   - ステップ 5: 標準出力内容と終了ステータス 0 の検証
4. **Makefile 回帰・品質ゲートの確認**:
   - `make -C ulisp test_aarch64_env` の正常終了
   - 既存の x86-64 ビルドおよび全テストに影響を与えないことの確認

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `aarch64-linux-gnu-as`、`aarch64-linux-gnu-ld`、および `qemu-aarch64-static` (または `qemu-aarch64`) がホスト環境で実行可能であること。
- [x] `make -C ulisp test_aarch64_env` が実行され、最小 AArch64 静的バイナリのビルドと QEMU エミュレーション実行（exit(42) および write 出力）が 100% PASS すること。
- [x] 既存の `make check_format`, `make static_analysis`, `make -C ulisp test` の挙動にデグレが発生しないこと。
