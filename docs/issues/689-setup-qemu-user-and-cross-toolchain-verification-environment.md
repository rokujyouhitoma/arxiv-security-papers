---
ID: 689
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] QEMU ユーザーエミュレーションおよび AArch64 クロスツールチェーン検証環境の構築 (ID: 689)

## 1. 概要 / Summary
ULisp のマルチ CPU サポート（特に AArch64 / ARM64）をホスト環境（x86-64 Linux）上で実機レスかつ高速に検証可能とするため、QEMU ユーザー空間エミュレータ（`qemu-user`, `qemu-user-static`）およびクロスビルド用ツールチェーン（`binutils-aarch64-linux-gnu`, `gcc-aarch64-linux-gnu`）を導入し、テスト自動化の基盤環境を確立する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §3 (言語機能と低レイヤコード生成仕様), §4 (フェーズ別コンパイラ設計)
- **関連 Issue**: #503 (Implement AArch64 Backend via LIR), #616 (ELF64 Generator), #690 (Abstract POSIX Syscall Layer)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/Makefile](../../ulisp/Makefile): QEMU 実行ラッパーおよびクロスツールチェーン変数の定義
- [ ] [ulisp/test_aarch64_qemu_env.sh](../../ulisp/test_aarch64_qemu_env.sh): ツールチェーン疎通確認用テストスクリプト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/689-setup-qemu-user-and-cross-toolchain`

1. ホスト環境への `qemu-user` / `qemu-user-static`、`binutils-aarch64-linux-gnu`、`gcc-aarch64-linux-gnu` の導入確認。
2. 最小の AArch64 アセンブリ（`svc #0` による exit(42) 等）を作成し、`aarch64-linux-gnu-as` / `ld` でアセンブル・リンク。
3. `qemu-aarch64` 経由で直接実行し、終了コードが正しく取得できることを疎通テストとして確認。
4. `Makefile` に `CROSS_AS_AARCH64`, `CROSS_LD_AARCH64`, `QEMU_AARCH64` 等の環境変数を定義。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `qemu-aarch64 --version` および `aarch64-linux-gnu-as --version` が正常に実行できること。
- [ ] 最小 AArch64 静的バイナリが `qemu-aarch64` 上で期待通りの動作・終了コードを返すこと。
