---
ID: 777
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 事前コンパイル済み標準ライブラリ (ulisp_stdlib.o) 静的リンクによるコンパイラ単体ブートストラップの導入 (ID: 777)

## 1. 概要 / Summary

現在、[ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) は `entry_core.scm` 経由で標準ライブラリ（`lib/*.scm` 全28モジュール）とランタイム（`runtime/*.scm` 全4モジュール）をコンパイラ本体と一緒に全結合した巨大ファイル `ulisp_core.scm`（約25,000行）を、Stage 1 / Stage 2 / Stage 3 で毎回フルコンパイルしている。
しかし、標準ライブラリおよびランタイムはコンパイラのメタサーキュラーな自己変換ロジックを含んでおらず、本来セルフホスティングの不動点（Fixed Point）証明の対象とする必要はない。

先行する [Issue #772](closed/772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md) では、標準ライブラリを1回だけ事前コンパイルしたオブジェクト（`build/ulisp_stdlib.o`）を静的リンクする方式により、テストスイートのコンパイル時間を 50〜100 倍（0.1s）に短縮した実績がある。

本 Issue では、この分割静的リンク基盤をブートストラップパイプラインへ適用する：
1. **ブートストラップ対象の極小化**:
   - `ulisp_core.scm` の全結合コンパイルを廃止し、ブートストラップ対象を **`compiler_entry.scm`（コンパイラ本体）のみ** に絞る。
2. **事前コンパイル済み標準ライブラリとの静的結合**:
   - 事前ビルドされた `build/ulisp_stdlib.o` と生成された `stage_compiler.o` を `ld` で静的リンクして各ステージの実行可能バイナリ（`scheme-stage1`, `scheme-stage2`, `scheme-stage3`）を生成する。
3. **コンパイラ単体での不動点検証（Fixed Point Protocol）**:
   - 不動点検証を `stage2_compiler.s` と `stage3_compiler.s` の完全ビット一致（`cmp -s`）判定へ移行する。

これにより、各ステージの入力 S 式規模および出力アセンブリ（15MB $\to$ 4〜5MB）が半減し、各ステージのコンパイル時間が **6 分 $\to$ 約 1 分前後**、3-Stage 全体でも **約 3 分（従来比 6 倍高速化）** へ劇的に短縮される。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 5 章「3段階セルフホスティングブートストラップ連鎖と不動点検証」
- 依存・関連 Issue:
  - [Issue #607](closed/607-support-extern-symbols-and-split-stdlib-compiler-linking.md): 外部シンボル（extern）参照解決と標準ライブラリ・コンパイラの2分割 .o 静的リンク基盤の導入
  - [Issue #772](closed/772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md): ULisp 標準ライブラリの事前コンパイル済みオブジェクト化と分割静的リンクへの統一
  - [Issue #776](776-introduce-quick-bootstrap-mode-and-opt-in-post-tests.md): Quick Bootstrap モード導入

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh)
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
- [ ] [ulisp/compiler_entry.scm](../../ulisp/compiler_entry.scm)
- [ ] [docs/issues/README.md](README.md)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking`

1. **ブートストラップ入力のコンパイラ単体化**:
   - `build/ulisp_stdlib.o` が未生成または依存変更時に自動ビルドされるよう Makefile 依存を接続。
   - `bootstrap.sh` のコンパイル入力を `build/compiler_input.scm`（`(!gc none) (!allow-extern #t)` + `compiler_entry.scm`）に変更。
2. **ステージバイナリ生成パイプラインの分割リンク化**:
   - `compile_asm` 関数を拡張し、`ld -m elf_x86_64 -static "$obj_file" "$BUILD_DIR/ulisp_stdlib.o" -o "$bin_file"` でリンクするように改修。
3. **不動点検証対象の切り替え**:
   - `stage2_compiler.s` と `stage3_compiler.s` を比較対象とし、決定論的アセンブリ出力の一致を検証。
4. **互換性モードの保持**:
   - レガシーな全結合モノリシックブートストラップを必要とする場合のため、`MONOLITHIC_BOOTSTRAP=1` オプションを残す。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `build/ulisp_stdlib.o` と静的リンクしたコンパイラバイナリが正常に動作し、スモークテスト（42）および Nanopass 単体テストを 100% PASS すること。
- [ ] 3-Stage ブートストラップが約 3 分前後（従来比 5〜8 倍高速化）で完走し、`stage2_compiler.s` と `stage3_compiler.s` の不動点（Bit-for-bit identical）が PASS すること。
- [ ] Issue #776 の Quick モードと組み合わせた場合、約 1 分前後で Stage 1 開発ビルドが完了すること。
- [ ] `make check` / `make verify_quality` がエラー 0 件で通過すること。

