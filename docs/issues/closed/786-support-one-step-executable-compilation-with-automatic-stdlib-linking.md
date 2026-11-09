---
ID: 786
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] ULisp ドライバにおける 1 ステップ実行バイナリ生成と標準ライブラリ (ulisp_stdlib.o) 自動リンクパイプラインの実装 (ID: 786)

## 1. 概要 / Summary

現在、ULisp において標準ライブラリ（`display` / `newline` / `write` / `read` / ポート I/O 等）を使用する Scheme コードを実行可能なスタンドアロン ELF64 バイナリ（`ET_EXEC`）へコンパイルするには、以下の 2 ステップを手動で実行する必要がある：

```bash
# 手動ステップ 1: 再配置可能オブジェクト (.o) の生成
ulisp -c -e '(include "ulisp/lib/stdlib_macros.scm") (display "hello") (newline)' --allow-extern -o tmp.o

# 手動ステップ 2: 内蔵静的リンカ (--ld) で標準ライブラリと結合
ulisp --ld tmp.o ulisp/build/ulisp_stdlib.o -o tmp.bin
```

`-c`（オブジェクト生成のみ）や `--target-elf` 単体では、`*stdout-port*` などの外部大域変数や関数が未束縛エラー（`Unbound Variable Resolution Failed`）となるか、あるいは手動で `ulisp_stdlib.o` を渡す必要がある。
また、GCC や Clang において `gcc main.c -o main` と 1 コマンド叩くだけで自動的に C ランタイム（`crt1.o`）や libc が結合されて実行バイナリが生成されるのと比較して、Scheme 開発者にとって大きな認知的摩擦となっていた。

本 Issue では、ULisp コンパイラドライバ（[ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm)）を拡張し：

```bash
# 1 コマンドでの実行可能 ELF64 出力
ulisp -e '(display "hello") (newline)' -o tmp.bin
./tmp.bin  # => hello
```

のように、`-c`（オブジェクト出力のみ）や `-S`（アセンブリ出力のみ）、`--as`、`--ld` が明示されていない場合に、ドライバが自動的に：
1. 標準ライブラリマクロ（`ulisp/lib/stdlib_macros.scm`）を暗黙プレリュードとして読み込み
2. 外部シンボル参照（`--allow-extern`）を有効化して中間オブジェクトを生成
3. 内蔵静的リンカ（`link-elf64-objects-to-file`）により事前コンパイル済み標準ライブラリ（`ulisp/build/ulisp_stdlib.o`）と自動結合
4. 実行権限（`0755`）を付与したスタンドアロン ELF64 実行バイナリを直接出力する
ワンステップ・コンパイルパイプラインを確立する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 4 章「バックエンド・コード生成およびゼロ libc ELF ビルダー」
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 5 章「3段階セルフホスティングブートストラップ連鎖と不動点検証」
- 依存・関連 Issue:
  - [Issue #772](closed/772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md): ULisp 標準ライブラリの事前コンパイル済みオブジェクト化と分割静的リンクへの統一
  - [Issue #777](closed/777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md): 事前コンパイル済み標準ライブラリ静的リンクによるコンパイラ単体ブートストラップ
  - [Issue #783](closed/783-support-builtin-as-assembler-cli-option-and-elf64-relocatable-object-emission.md): 内蔵アセンブラ (--as / -c) と ELF64 再配置可能オブジェクト (.o) 出力
  - [Issue #784](closed/784-support-builtin-ld-static-linker-cli-option-for-elf64-objects.md): 内蔵静的リンカ (--ld) と複数 ELF64 オブジェクト静的リンク
  - [Issue #785](closed/785-fix-compiler-error-output-redirection-and-unlink-on-failure.md): コンパイルエラー時の -o 出力先へのログ混入防止および失敗時の中途成果物即時削除

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (コンパイラドライバ：`-c` / `-S` 非指定時の自動中間オブジェクト生成・自動リンクディスパッチ、プレリュード注入、`--nostdlib` フラグ解釈)
- [x] [ulisp/lib/stdlib_macros.scm](../../ulisp/lib/stdlib_macros.scm) (標準ライブラリマクロの暗黙プレリュード展開・再帰 include 耐性検証)
- [x] [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm) (インメモリ再配置オブジェクトの直接リンクまたは安全な一時オブジェクト経由リンク)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`test_onestep_compile` 検証ターゲット、`build/ulisp_stdlib.o` の依存関係整備)
- [x] [ulisp/tests/test_onestep_compile.sh](../../ulisp/tests/test_onestep_compile.sh) (1 ステップコンパイル・自動リンク検証テストスイート)
- [x] [docs/issues/README.md](README.md) (Issue 台帳)

---

## 4. セキュリティ・信頼性脅威分析 / Threat Model & Boundary Analysis

| 脅威 / リスク | 分類 | 影響度 | 発生要因 | 緩和策 / 防御メカニズム |
| :--- | :---: | :---: | :--- | :--- |
| **一時オブジェクトファイルの競合・不完全残留** | CWE-377 / CWE-459 | 中 | 自動リンク用の中間オブジェクトを固定パス（例: `/tmp/tmp.o`）に書き出すと、並行実行時の競合やコンパイル失敗時の残留が発生する | 出力先バイナリ名に基づく一意なサフィックス（例: `<out-file>.tmp.<pid>.o` またはインメモリ bytevector 渡し）を採用し、コンパイル完了後および異常終了シグナルハンドラにて `sys-unlink` で即時削除する（Issue #785 規約準拠） |
| **標準ライブラリ探索パスの偽装（DLL Injection / Untrusted Path）** | CWE-426 | 高 | カレントディレクトリや `/tmp` に悪意ある `ulisp_stdlib.o` が配置されていた場合、意図せずリンクされて不正コードが実行される | `ulisp_stdlib.o` の探索順序を厳格化：① 明示的な環境変数 `ULISP_STDLIB`、② コンパイラ実行バイナリ起点・リポジトリ固定パス（`ulisp/build/ulisp_stdlib.o` / `build/ulisp_stdlib.o`）のみを信頼し、任意の相対ディレクトリを盲信しない |
| **未定義シンボル（Undefined Reference）の検知漏れ** | CWE-476 | 高 | 自動的に `--allow-extern` を有効化した結果、標準ライブラリにも存在しないタイポ変数（例: `dispaly`）がコンパイル時に無視され、実行時にクラッシュする | フロントエンドの `--allow-extern` を通過したシンボルは、続く内蔵リンカ（`link-elf64-objects-to-file`）のシンボル解決フェーズで厳格に照合され、標準ライブラリに未定義の強シンボルが存在する場合は詳細な未解決診断を出力して `exit 1` で中断する |
| **非実行可能スタック（W^X 違反）の混入** | CWE-250 / CWE-732 | 中 | 自動リンクパイプラインにおいて `PT_GNU_STACK` が欠落した場合、OS によりスタックが実行可能化される | 内蔵リンカの `PT_GNU_STACK`（flags 6 = RW）属性をそのまま継承・検証し、完全な W^X 規約を強制する |

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/786-support-one-step-executable-compilation-with-automatic-stdlib-linking`

```
  +-----------------------------------------------------------------------------------+
  |                             ulisp CLI 入力                                        |
  |  ulisp [-e '(display "hi")'] [main.scm] -o app.bin [--nostdlib]                   |
  +-----------------------------------------------------------------------------------+
                                           |
                                           v
  +-----------------------------------------------------------------------------------+
  | Step 1: ターゲット種別判定 (driver.scm)                                            |
  |  - `-c`: オブジェクト出力モード ('obj) -> 従来通り .o を出力                      |
  |  - `-S`: アセンブリ出力モード ('x86_64) -> 従来通り .s を出力                     |
  |  - `--as` / `--ld`: アセンブラ / リンカ直接モード -> 従来通り                     |
  |  - その他（デフォルト / `--target-elf` / `-o <file>` 指定時）:                      |
  |    -> 1 ステップ実行バイナリ生成モード ('exec-mode) を選択                        |
  +-----------------------------------------------------------------------------------+
                                           |
                                           v
  +-----------------------------------------------------------------------------------+
  | Step 2: プレリュード注入 & コンパイル ('exec-mode)                                 |
  |  - `--nostdlib` が指定されていない場合:                                            |
  |    - `ulisp/lib/stdlib_macros.scm` を暗黙インクルード / プレリュード展開          |
  |    - `set-allow-extern-symbols! #t` を自動有効化                                  |
  |  - フロントエンド -> LIR -> ELF オブジェクトバックエンド ('pass-144-backend-x86-elf-obj)|
  |  - 一時オブジェクト `<app.bin>.tmp.<pid>.o`（またはインメモリ bytevector）を生成  |
  +-----------------------------------------------------------------------------------+
                                           |
                                           v
  +-----------------------------------------------------------------------------------+
  | Step 3: 事前コンパイル済み標準ライブラリ探索 & 内蔵リンク                           |
  |  - `find-ulisp-stdlib-object`:                                                    |
  |    1. `(get-environment-variable "ULISP_STDLIB")`                                 |
  |    2. `"ulisp/build/ulisp_stdlib.o"`                                              |
  |    3. `"build/ulisp_stdlib.o"`                                                    |
  |  - `link-elf64-objects-to-file` にて `[tmp.o, stdlib.o]` を結合して `<app.bin>` 出力|
  |  - 一時オブジェクト `tmp.o` を `sys-unlink` で削除                               |
  |  - `sys-chmod` により `<app.bin>` に実行権限 `0755` を付与                        |
  +-----------------------------------------------------------------------------------+
```

### Step 1: CLI 引数パーサの拡張 (`ulisp/compiler/driver.scm`)
1. `parse-cli-arguments` において：
   - `--nostdlib`: 標準ライブラリの自動プレリュード注入および自動リンクを無効化するフラグを追加。
   - ターゲット種別の導出規則：
     - `-c`, `--target-obj`, `-obj`: `'obj`（変更なし）
     - `-S`: `'x86_64`（変更なし）
     - `--target-lir`: `'lir`（変更なし）
     - `--as`: `'as-mode`（変更なし）
     - `--ld`: `'ld-mode`（変更なし）
     - `--target-elf`, `-elf`: `'exec-mode`（自動リンク有効）
     - ターゲット未指定かつ `-o` 指定時（または通常実行時）：デフォルトで `'exec-mode` として扱い、実行可能バイナリを出力。

### Step 2: 標準ライブラリ探索ルーチンの実装 (`ulisp/compiler/driver.scm`)
1. `(find-ulisp-stdlib-object)` 関数を実装：
   - 環境変数 `ULISP_STDLIB` が設定されていればそのパスを検証。
   - 相対パス `ulisp/build/ulisp_stdlib.o`、`build/ulisp_stdlib.o` を順に検査。
   - 見つからない場合は「`ulisp: error: cannot locate standard library object (ulisp_stdlib.o). Run 'make -C ulisp build/ulisp_stdlib.o' or set ULISP_STDLIB`」を `display-stderr` に出力して即時安全に `exit 1`。

### Step 3: 自動プレリュード注入と中間オブジェクトコンパイル (`ulisp/compiler/driver.scm`)
1. 実行形式ターゲット（`'exec-mode`）において、`--nostdlib` が無指定の場合：
   - `stdlib_macros.scm` を自動読み込みして `forms` の先頭に結合。
   - `(set-allow-extern-symbols! #t)` を自動セット。
2. 一時ファイル名（例: `(string-append cli-out-file ".tmp." (number->string (sys-getpid)) ".o")`）を決定。
3. 一時ファイルに対して `'obj`（ELF64 `ET_REL`）をバックエンド出力。

### Step 4: 内蔵リンカ起動とクリーンアップ (`ulisp/compiler/driver.scm`)
1. 一時オブジェクトファイルと `ulisp_stdlib.o` のリストを作成。
2. `(link-elf64-objects-to-file (list tmp-obj stdlib-obj) cli-out-file cli-entry-sym)` を呼び出し、最終バイナリへ出力。
3. `(sys-unlink tmp-obj)` で一時オブジェクトを即時削除。
4. `(sys-chmod cli-out-file 493)`（`0755`）で実行権限を付与。
5. エラーハンドラ `*compiler-in-error*` に `tmp-obj` のクリーンアップも登録し、異常終了時にも中間ファイルを残さない。

### Step 5: テストスイート整備 (`ulisp/tests/test_onestep_compile.sh`, `ulisp/Makefile`)
1. `ulisp/tests/test_onestep_compile.sh` を新規作成：
   - `ulisp -e '(display "hello") (newline)' -o test1.bin && ./test1.bin` の 1 コマンド実行検証。
   - `ulisp -e '(let loop ((n 10)) (if (> n 0) (begin (write n) (display " ") (loop (- n 1))) (newline)))' -o test2.bin && ./test2.bin` の検証。
   - ソースファイル指定（`ulisp test_src.scm -o test3.bin`）の 1 コマンド実行検証。
   - `--nostdlib` フラグによる純粋単独実行形式のコンパイル検証。
   - タイポによる未定義シンボル時の正確なエラー診断およびゴミファイルが残らないことの確認。
2. `ulisp/Makefile` に `test_onestep_compile` を追加し、単体検証を可能にする。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `ulisp -e '(display "hello\n")' -o hello.bin && ./hello.bin` が手動の include や 2 段階の `-c` / `--ld` なしに 1 コマンドでビルド＆実行成功すること。
- [x] `ulisp input.scm -o bin && ./bin` により、外部の `as` や `ld` を一切呼び出さずに ELF64 実行バイナリが生成され、正常に動作すること。
- [x] `-c` オプションが指定された場合は従来通り単一の `.o`（オブジェクトファイル）が出力され、自動リンクが走らないこと。
- [x] `-S` オプションが指定された場合は従来通りアセンブリテキスト（`.s`）が出力されること。
- [x] `--nostdlib` オプションが指定された場合は標準ライブラリの自動プレリュードおよび自動リンクが無効化されること。
- [x] コンパイルまたはリンク失敗時に、中間 `.o` や不完全な出力バイナリが残留しないこと（Issue #785 規約準拠）。
- [x] テストスクリプト `ulisp/tests/test_onestep_compile.sh`（`make -C ulisp test_onestep_compile`）が 100% PASS すること。
- [x] 3段階セルフホスティングブートストラップ（`./bootstrap.sh --split-link`）が不動点を維持して通過すること。
- [x] リポジトリ品質ゲート（`make check_format static_analysis py_compile`）がエラー 0 件で通過すること。
- [x] 全ドキュメント内の内部リンクが相対パス規則に 100% 準拠していること。

---

## 7. 検証結果サマリー / Verification Summary

### 7.1 1 ステップコンパイル・テストスイート実行結果
```bash
$ make -C ulisp test_onestep_compile
========================================================================
 Starting 1-Step Executable Compilation Verification Suite (#786)
 Compiler: build/scheme-stage1
========================================================================
Test 1: Inline expression 1-step compilation and execution ... PASS
Test 2: BIN1 is ELF64 ET_EXEC with PT_GNU_STACK ... PASS
Test 3: Loop and arithmetic 1-step compilation ... PASS
Test 4: Scheme source file 1-step compilation ... PASS
Test 5: -c option outputs ET_REL relocatable object ... PASS
Test 6: Built-in ld links object created by -c with stdlib ... PASS
Test 7: -S option outputs assembly text ... PASS
Test 8: --nostdlib rejects stdlib display as unbound ... PASS
Test 9: --nostdlib allows freestanding arithmetic ... PASS
Test 10: Unbound variable error leaves no output binary behind ... PASS
Test 11: Syntax error leaves no output binary behind ... PASS
========================================================================
 1-Step Compilation Test Suite Complete: 11 / 11 PASS
========================================================================
```

### 7.2 3 段階セルフホスティングブートストラップ結果
```bash
$ cd ulisp && ./bootstrap.sh --split-link
[1/3] Stage 1: Fast compiling compiler_entry.scm using native seed...
  -> Stage 1 successfully compiled with native seed.
[2/3] Stage 2: Compiling compiler_entry.scm with Stage 1 compiler...
[3/3] Stage 3: Compiling compiler_entry.scm with Stage 2 compiler...
=== Verifying Fixed Point (diff stage2_compiler.s stage3_compiler.s) ===
SUCCESS: Stage 2 and Stage 3 outputs are bit-for-bit IDENTICAL!
Fixed-point bootstrap verified successfully with Thin Debug Runtime & Scheme stdlib.
=== Running Smoke Test on Stage 3 Binary ===
PASS: Stage 3 binary produced functional executable (output: 42).
Updated local bootstrap seed cache (bin/ulisp-boot) with verified Stage 3 compiler.
```

### 7.3 リポジトリ全体品質ゲート結果
```bash
$ make check_format static_analysis py_compile
Success: no issues found in 617 source files
0 errors, 100% PASS
```
