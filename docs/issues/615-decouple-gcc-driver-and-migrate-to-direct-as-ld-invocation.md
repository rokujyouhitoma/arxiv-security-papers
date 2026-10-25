---
ID: 615
種別: Refactor
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ビルドパイプラインからの GCC 呼出し排除と GNU as / ld 直接駆動（脱 GCC ドライバ）への移行 (ID: 615)

## 1. 概要 / Summary
現在 ULisp のネイティブ x86-64 AOT コンパイルでは、出力されたアセンブリファイル（`.s`）のアセンブルおよび ELF 実行バイナリのリンクに `gcc -nostdlib -static` を利用している。ULisp は既に Linux システムコールを直接発行する Freestanding ランタイム（Pass 142）を備えており、C 標準ライブラリ（libc）には一切依存していないにもかかわらず、アセンブラ（`as`）とリンカ（`ld`）の起動ラッパーとして GCC に依存している状態である。

本 Issue では、将来の「完全自前 ELF 出力（Direct-to-ELF）」に向けた第一段階として、`Makefile`、`bootstrap.sh`、`test.sh`、および各種テストスクリプトにおける `gcc` 依存を排除し、GNU binutils の `as` および `ld` を直接起動するパイプラインへ刷新する。これにより、C コンパイラとしての GCC への暗黙の依存を完全に断ち切る。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp ポータブルビルドガイド](../../ulisp/docs/guide_portable_build.md)
- **関連 Issue**:
  - Issue 541: ブートストラップシード導入による高速ビルドパイプラインの構築
  - Issue 607: 外部シンボル（extern）参照解決と標準ライブラリ・コンパイラの2分割 .o 静的リンク基盤の導入
  - Issue 608: Nanopass・モジュール単位の完全分割コンパイル（.o）および増分ビルド基盤の実装
  - Issue 616: Scheme ネイティブ x86-64 マシン語エンコーダおよび ELF64 実行可能バイナリ直接出力バックエンドの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`AS = as`, `LD = ld` の導入、`$(CC) -nostdlib -static` から `$(AS)` / `$(LD)` 直接呼出しへの分離)
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (GCC 実行部分のエラーハンドリングを `as` / `ld` 呼出しへ刷新)
- [ ] [ulisp/test.sh](../../ulisp/test.sh) (ネイティブテストのコンパイル・リンクコマンド刷新)
- [ ] [ulisp/test_backend.sh](../../ulisp/test_backend.sh) (バックエンド検証における as/ld 直接制御)
- [ ] [ulisp/docs/guide_portable_build.md](../../ulisp/docs/guide_portable_build.md) (ビルド要件および依存ツールチェーンドキュメントの更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/615-decouple-gcc-driver-and-migrate-to-direct-as-ld-invocation`

1. **Makefile のツールチェーン変数再定義**:
   - `AS ?= as`、`LD ?= ld`、`ASFLAGS ?= --64`、`LDFLAGS ?= -m elf_x86_64 -static` を定義。
   - ネイティブ x86-64 のパターンルールを `%.s -> %.o` (`$(AS) $(ASFLAGS) -o $@ $<`) および `%.o -> %` (`$(LD) $(LDFLAGS) -o $@ $^`) に明確に分離。
2. **`bootstrap.sh` のアセンブル・リンク分離**:
   - `run_stage_try` 内のアセンブル・リンク処理で `gcc` を使わず、`as "$asm_file" -o "$obj_file"` および `ld -static "$obj_file" -o "$bin_file"` を実行。
3. **ベンチマーク・テストスクリプトの整理**:
   - ポータブル C バックエンド（`!target c`）用コンパイル（C 言語の検証）のみ `CC` を残し、Native x86-64 パイプラインからは `CC` / `gcc` を完全に分離。
4. **回帰テスト**:
   - `make test` および `make bootstrap`（Stage 1〜3）が GCC を経由せずに完全に通過することを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] ネイティブ x86-64 AOT ビルドおよびブートストラップにおいて `gcc` コマンドが一切呼び出されないこと。
- [ ] `as` および `ld` の直接呼出しにより、Stage 1〜3 のブートストラップ（Fixed Point 一致）が 100% 成功すること。
- [ ] `make test` および全 Nanopass 単体テストが回帰なく正常終了すること。
- [ ] ドキュメント上の依存ツールチェーン要件から「C コンパイラ」がネイティブ実行パスから除外されていること。
