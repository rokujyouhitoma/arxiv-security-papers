---
ID: 786
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ULisp ドライバにおける 1 ステップ実行バイナリ生成と標準ライブラリ (ulisp_stdlib.o) 自動リンクパイプラインの実装 (ID: 786)

## 1. 概要 / Summary

現在、ULisp において標準ライブラリ（`display` / `newline` / `write` / `read` 等）を使用する Scheme コードを実行可能なスタンドアロン ELF64 バイナリ（`ET_EXEC`）へコンパイルするには、以下の 2 ステップを手動で実行する必要がある：

```bash
# 手動ステップ 1: 再配置可能オブジェクト (.o) の生成
ulisp -c -e '(include "ulisp/lib/stdlib_macros.scm") (display "hello") (newline)' --allow-extern -o tmp.o

# 手動ステップ 2: 内蔵静的リンカ (--ld) で標準ライブラリと結合
ulisp --ld tmp.o ulisp/build/ulisp_stdlib.o -o tmp.bin
```

`-c`（オブジェクト生成のみ）や `--target-elf` 単体では、`*stdout-port*` などの外部大域変数や関数が未束縛エラー（`Unbound Variable Resolution Failed`）となるか、あるいは手動で `ulisp_stdlib.o` を渡す必要がある。

本 Issue では、GCC において `gcc main.c -o main` で C ランタイムや libc が暗黙的にリンクされるのと同様に、ULisp コンパイラドライバ（`ulisp/compiler/driver.scm`）を拡張し：

```bash
# 1 コマンドでの実行可能 ELF64 出力
ulisp -e '(display "hello") (newline)' -o tmp.bin
./tmp.bin  # => hello
```

のように、`-c`（または `-S`, `--as`, `--ld`）が指定されていない場合に、ドライバが自動的に中間オブジェクトの生成と事前コンパイル済み標準ライブラリ（`build/ulisp_stdlib.o`）の内蔵リンク処理をパイプライン実行し、1 コマンドで実行可能な完全スタンドアロンバイナリを出力する機能を実装する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- 依存・関連 Issue:
  - [Issue #772](closed/772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md): ULisp 標準ライブラリの事前コンパイル済みオブジェクト化と分割静的リンクへの統一
  - [Issue #777](closed/777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md): 事前コンパイル済み標準ライブラリ静的リンクによるコンパイラ単体ブートストラップ
  - [Issue #783](closed/783-support-builtin-as-assembler-cli-option-and-elf64-relocatable-object-emission.md): 内蔵アセンブラ (--as / -c) と ELF64 再配置可能オブジェクト (.o) 出力
  - [Issue #784](closed/784-support-builtin-ld-static-linker-cli-option-for-elf64-objects.md): 内蔵静的リンカ (--ld) と複数 ELF64 オブジェクト静的リンク
  - [Issue #785](closed/785-fix-compiler-error-output-redirection-and-unlink-on-failure.md): コンパイルエラー時の -o 出力先へのログ混入防止および失敗時の中途成果物即時削除

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (コンパイラドライバ：`-c` / `-S` 非指定時の自動中間オブジェクト生成・自動リンクディスパッチ)
- [ ] [ulisp/lib/stdlib_macros.scm](../../ulisp/lib/stdlib_macros.scm) (標準ライブラリマクロの暗黙プレリュード展開 / インクルード機構)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`build/ulisp_stdlib.o` の配置パス規約、検証ターゲット `test_onestep_compile`)
- [ ] [ulisp/tests/test_onestep_compile.sh](../../ulisp/tests/test_onestep_compile.sh) (1 ステップコンパイル・自動リンク検証テストスイート)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/786-support-one-step-executable-compilation-with-automatic-stdlib-linking`

1. **デフォルトターゲットの整理**:
   - CLI 引数において `-c`（`'obj`）や `-S`（`'asm`）、`--as`、`--ld` が明示されていない場合、実行形式の直接生成（`'exec`）をデフォルトとする。
2. **自動プレリュードと `--allow-extern` の暗黙有効化**:
   - 実行形式生成時、標準 I/O マクロ（`display`, `newline` 等）を自動利用可能とするため、自動的に `stdlib_macros.scm` をプレリュードとして読み込み、外部シンボル参照（`--allow-extern`）を許可して中間オブジェクトを生成する。
3. **内蔵静的リンカによる自動結合**:
   - 生成された中間オブジェクトと、標準ライブラリオブジェクト（`build/ulisp_stdlib.o`）を `link-elf64-objects-to-file` で自動的に結合し、最終バイナリへ出力する。
   - コンパイル失敗時は中間ファイルおよび中途出力先を即座に削除（Issue #785 規約準拠）。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp -e '(display "hello\n")' -o hello.bin && ./hello.bin` が 1 コマンドでコンパイル・実行可能であること。
- [ ] `ulisp input.scm -o bin && ./bin` により、外部の `as` や `ld` を一切呼び出さず、かつ 2 段階の手動コマンドなしで完走すること。
- [ ] `-c` オプションが指定された場合は従来通り単一の `.o`（オブジェクトファイル）が出力されること。
- [ ] テストスクリプト `ulisp/tests/test_onestep_compile.sh` が 100% PASS すること。
- [ ] リポジトリ品質ゲート（`make check_format static_analysis py_compile`）がエラー 0 件で通過すること。

