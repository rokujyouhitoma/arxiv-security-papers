---
ID: 691
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] ULisp AArch64 AOT コンパイラ出力の結合検証および QEMU エミュレーション実行の確立 (ID: 691)

## 1. 概要 / Summary
Pass 150（`ulisp/backend/150_backend_aarch64.scm`）による AArch64 GNU アセンブリ出力と、抽象化された `posix.scm` ランタイムを結合し、`aarch64-linux-gnu-as` / `ld` を用いて完全静的実行バイナリをビルドする。
生成された AArch64 バイナリを `qemu-aarch64` 上で実行し、Scheme の基本機能（算術計算、文字・文字列入出力、クロージャ、局所変数、末尾再帰）が期待通り動作することをエンドツーエンドで実証する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §3.5 (末尾呼出最適化 TCO), §4.3 (Pass 150 AArch64)
- **関連 Issue**: #503 (AArch64 Backend via LIR), #689 (QEMU Toolchain), #690 (POSIX Syscall Layer)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm): 命令選択・スタック整列・ラベル解決の調整
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm): `--target=aarch64` オプションおよびクロスアセンブルパイプラインの統合
- [ ] [ulisp/tests/test_aarch64_qemu_smoke.scm](../../ulisp/tests/test_aarch64_qemu_smoke.scm): QEMU 向けスモークテストコード

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/691-verify-ulisp-aarch64-aot-codegen`

1. スモークテスト用 Scheme コード（`42` の返却、`(write-string "Hello AArch64\n")`、フィボナッチ再帰計算）の作成。
2. `ulisp` コンパイラドライバに AArch64 ビルドパスを追加：
   `gosh compiler/driver.scm --target=aarch64 input.scm -o output.s`
3. `aarch64-linux-gnu-as output.s -o output.o` および `aarch64-linux-gnu-ld output.o -o output_bin` によるバイナリ生成。
4. `qemu-aarch64 ./output_bin` の自動実行と標準出力・終了コードの検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] AArch64 向けに出力されたアセンブリが GNU as でエラーなくアセンブルできること。
- [ ] 生成された ELF64 AArch64 静的バイナリが `qemu-aarch64` 上で正常に実行され、正確な計算結果および文字列を出力すること。
- [ ] スタックポインタ整列例外（SP Alignment Fault）が一切発生しないこと。
