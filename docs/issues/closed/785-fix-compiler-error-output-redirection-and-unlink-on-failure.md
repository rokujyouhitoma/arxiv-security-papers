---
ID: 785
種別: Bug
優先度: High
ステータス: Closed (Completed)
完了日: 2026-11-08
---

# [BUG/SEC] コンパイルエラー時の -o 出力先へのログ混入防止および失敗時の中途成果物即時削除 (ID: 785)

## 1. 概要 / Summary

ULisp コンパイラ（`ulisp/bin/ulisp-boot` 等）において `-o <file>` オプションを指定した際、コンパイルエラー（未束縛変数や構文エラー）が発生すると、エラーメッセージが端末画面（stderr）ではなく `-o` で指定した出力ファイルの中に書き込まれてしまう不具合が確認された。

さらに、コンパイラがエラー終了したにもかかわらず、その中途成果物ファイルが削除（unlink）されずに残存する。その結果、以下の重大な問題が発生する：
1. **成果物誤認**: 初期ファイル作成時に `0755`（実行可能権限）が付与されているため、ユーザーやビルドツールが「コンパイルに成功して ELF バイナリが生成された」と誤認する。
2. **多重故障（Cascading Confusion）**: 生成されたファイル（中身はエラーテキスト）をシェルから `./tmp.bin` として実行すると、シェル（bash）がテキストをシェルスクリプトと誤認して1行ずつ解釈し、意味不明な `command not found` や `syntax error near unexpected token '('` 等のシェルエラーを連発させ、真のエラー原因（Scheme のコンパイルエラー）を完全に隠蔽してしまう。

### 再現手順 / Steps to Reproduce
1. 未定義の変数（例: `print`）を含む式を `-o tmp.bin` かつ `--target-elf` でコンパイルする：
   ```bash
   ulisp/bin/ulisp-boot -e "(print 1 2)" --target-elf -o tmp.bin
   ```
2. コンパイル結果の `./tmp.bin` を直接実行する：
   ```bash
   ./tmp.bin
   ```
3. 端末に以下のようなシェルの文法エラーが出力され、コンパイラのエラーログが `tmp.bin` の中に閉じ込められている：
   ```text
   ./tmp.bin: line 2: ======================================================================: command not found
   ./tmp.bin: line 3: [LIR: command not found
   ./tmp.bin: line 4: ======================================================================: command not found
   ./tmp.bin: line 5: Unbound: command not found
   ./tmp.bin: line 6: Current: command not found
   ./tmp.bin: line 7: syntax error near unexpected token `('
   ./tmp.bin: line 7: `  Current Expr     : (print 1 2)'
   ```

### 再現環境 / Environment
- OS / Env: Linux x86-64 / bash
- Component: `ulisp/compiler/driver.scm`, `ulisp/compiler/helpers.scm`, `ulisp/backend/142_backend_x86_freestanding.scm`, `ulisp/bin/ulisp-boot`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler/driver.scm](../../../ulisp/compiler/driver.scm) (`sys-dup2` stdout リダイレクト管理、遅延オープン `open-and-redirect-output-file!`、コンパイル失敗時の `(compiler-abort-and-cleanup! 1)` 自動 `sys-unlink`、`sys-chmod` パーミッション遅延確定 `0755`)
- [x] [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm) (`*compiler-stderr-port*`, `get-compiler-error-port`, `display-stderr`, `newline-stderr`, `write-stderr`、`compiler-abort-and-cleanup!`、および `unbound-variable-error` を含む全エラー診断出力の stderr 完全統一)
- [x] [ulisp/backend/142_backend_x86_freestanding.scm](../../../ulisp/backend/142_backend_x86_freestanding.scm) (ネイティブランタイムの未処理例外ハンドラ `.L_ue_generic` / `.L_ue_exit` による `ulisp_flush_stderr` (fd 2) 出力の保証)
- [x] [ulisp/lib/posix.scm](../../../ulisp/lib/posix.scm) (`sys-chmod` ラッパー実装: Linux x86-64 syscall 90, AArch64 syscall 268)
- [x] [ulisp/tests/test_cli_diagnostics.sh](../../../ulisp/tests/test_cli_diagnostics.sh) (コンパイル失敗時に `-o` ファイルが残存しないこと、および stderr 出力を検証する回帰テスト 12 項目)
- [x] [docs/issues/README.md](../README.md) (Issue 台帳)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

調査の結果、以下の 4 点の連鎖によって不具合が発生していることが判明した：

1. **ストリーム分離の破綻 (`helpers.scm` による stdout への診断出力)**:
   - `ulisp/compiler/helpers.scm` の `unbound-variable-error` や `format-power-assert-diagram` において、`[LIR COMPILER ERROR]` 等の診断情報が `display`, `write`, `newline`（標準出力 fd 1）を用いて出力されていた。
   - `display-stderr` や `get-compiler-error-port` が一部でしか適用されていなかったため、リダイレクトされた出力ファイルへ直接書き込まれていた。
2. **ネイティブランタイム例外ハンドラの標準出力固定 (`142_backend_x86_freestanding.scm`)**:
   - `ulisp/backend/142_backend_x86_freestanding.scm` の未処理例外ハンドラ（`.L_ue_generic`）が、標準出力（fd 1）専用の `ulisp_flush` を呼び出していた。
   - そのため、実行時・コンパイル時の例外メッセージ `*** ERROR: ...` が fd 1 にフラッシュされ、成果物ファイルに混入した。
3. **早期の実行可能パーミッション付与 (`driver.scm`)**:
   - `ulisp/compiler/driver.scm` にて、`cli-target == 'elf` の場合、最初から `mode 493` (`0755` = `rwxr-xr-x`) で `sys-open`（`O_CREAT | O_TRUNC | O_WRONLY`）されていた。
   - コンパイルが成功したかどうかに関わらず実行可能属性が付与されるため、中身がエラーテキストであってもシェルからスクリプトとして起動されてしまう。
4. **トランザクション性（アトミシティ）の欠如とロールバック不在**:
   - コンパイルエラー発生時に `cli-out-file` を削除（`sys-unlink`）するクリーンアップ機構が存在せず、異常終了コードを返しながらも破損ファイルがディスク上に残存していた。

---

## 4. 恒久対策 / Permanent Fix

1. **診断ログの stderr 完全分離**:
   - `helpers.scm` の `unbound-variable-error` およびすべてのエラー出力を `display-stderr` / `newline-stderr` / `write-stderr` / `(get-compiler-error-port)` に統一。
   - `142_backend_x86_freestanding.scm` の例外ハンドラにおいて、直接 fd 2（stderr）へ `sys_write` する専用エミッタ `ulisp_flush_stderr` を導入。
2. **遅延オープン（Lazy Open）と失敗時の中途成果物即時削除 (`sys-unlink`)**:
   - `driver.scm` において、フロントエンド・LIR 解析が成功するまで出力ファイルの `sys-open` を遅延。構文エラーや未束縛変数エラーが発生した時点ではファイルそのものが作成されない。
   - バックエンド処理中にエラーが発生した場合は、`compiler-abort-and-cleanup!` により開かれた `cli-out-file` を即座に `sys-unlink` して削除し、異常終了する。
3. **二段階コミット（権限確定の遅延）**:
   - 初期ファイル作成時は `0644`（非実行属性）とし、コード生成および ELF リンカが 100% 成功完了した直後（`exit 0` 直前）にのみ `(sys-chmod cli-out-file 493)`（`0755`）で実行可能属性を付与。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] 存在しない変数（例: `print`）や構文エラーを含む式を `-o <file>` 指定でコンパイルした際、端末の標準エラー出力（stderr）にコンパイルエラー内容が表示されること。
- [x] コンパイル失敗時に、`-o` で指定したファイルがファイルシステム上に残存しないこと（`[ ! -f <file> ]` が真）。
- [x] コンパイル失敗時の中途ファイルがシェルスクリプトとして誤実行される事象が 100% 根絶されること。
- [x] 正常なコンパイル時は、従来どおり実行可能権限（`0755`）が付与された ELF64 バイナリが出力され、正常に実行できること。
- [x] 新規回帰テスト `ulisp/tests/test_cli_diagnostics.sh` が PASS すること（全 12 項目 PASS 確認済み）。
- [x] `make test` およびセルフホスティングブートストラップ（`bootstrap.sh` 不動点検証）が 100% PASS すること。

