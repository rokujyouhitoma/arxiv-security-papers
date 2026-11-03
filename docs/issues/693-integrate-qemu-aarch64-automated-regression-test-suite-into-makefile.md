---
ID: 693
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] ULisp Makefile への QEMU AArch64 全自動回帰テストスイートの統合 (ID: 693)

## 1. 概要 / Summary
AArch64 向けのコンパイル、静的バイナリリンク、および `qemu-aarch64` を用いたテスト実行パイプラインを `ulisp/Makefile` に統合する。
開発者が `make test-aarch64-qemu` を実行するだけで、全単体テスト・並行性テスト・R7RS 基本手続きテスト群が QEMU エミュレーション環境上で自動実行され、アーキテクチャ中立性と回帰なきことが保証される体制を整備する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §6 (検証およびテストアーキテクチャ)
- **関連 Issue**: #503 (AArch64 Backend), #591 (Compiler Test Driver), #689 (QEMU Toolchain), #691 (AArch64 AOT Verification), #692 (AArch64 Context Switch)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/Makefile](../../ulisp/Makefile): `test-aarch64-qemu`, `check-qemu` ターゲットの追加
- [ ] [ulisp/test_aarch64_runner.sh](../../ulisp/test_aarch64_runner.sh): QEMU テストランナー統合スクリプト
- [ ] [docs/issues/README.md](../../docs/issues/README.md): Issue 台帳の同期

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/693-integrate-qemu-aarch64-test-suite`

1. `ulisp/Makefile` に AArch64 用ツール定義を追加：
   ```makefile
   QEMU_AARCH64 ?= qemu-aarch64
   CROSS_AS_AARCH64 ?= aarch64-linux-gnu-as
   CROSS_LD_AARCH64 ?= aarch64-linux-gnu-ld
   ```
2. `test-aarch64-qemu` ターゲットの追加：
   - 単体テスト群（`test_char.scm`, `test_values.scm`, `test_ports.scm`, `test_case_lambda.scm` 等）のバッチコンパイル・リンク。
   - `$(QEMU_AARCH64)` による連続実行と集計レポート出力。
3. エラー発生時の速やかなフェイルファスト機構と要約ログ出力の整備。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `make test-aarch64-qemu` コマンド 1 回で AArch64 向け全自動テストが完走すること。
- [ ] QEMU 上で実行されたテストスイートの合否結果が CI/開発者に明確にレポートされること。
- [ ] 既存の x86-64 向け `make test` の挙動に影響を与えないこと。
