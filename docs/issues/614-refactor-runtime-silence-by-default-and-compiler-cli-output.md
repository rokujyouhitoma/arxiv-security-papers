---
ID: 614
種別: Refactor
優先度: High
ステータス: Open (New)
---

# [REFACTOR/ARCH] ランタイムのデフォルト沈黙化（Quiet-by-Default）とコンパイラ成果物出力（明示的終了値 0 / -o オプション）の根本是正 (ID: 614)

## 1. 概要 / Summary

現在、ULisp のネイティブランタイム（`ulisp/runtime/entry.scm`）および x86-64 バックエンド（`ulisp/backend/140_backend_x86_64.scm`）では、プログラムのトップレベル式の最終評価値（戻り値）を標準出力に自動印字する挙動（Verbose by Default）がデフォルトとなっており、これを抑制するために環境変数 `ULISP_QUIET=1` を外部から注入する設計となっている。

### 現行アーキテクチャの課題と構造的歪み:
1. **初期ミニ評価器（REPL）時代の名残と AOT コンパイラの不整合**:
   - `echo "(+ 1 2)" | ./ulisp` のように対話的に計算結果を返すミニ評価器だった頃の設計がそのままネイティブランタイムに残っており、AOT コンパイラ自身を実行した際にもプログラム終了時に戻り値（AST の S 式データ）を勝手に標準出力へダンプしてしまう。
2. **コンパイル成果物（アセンブリ）の汚染とビルド破綻**:
   - コンパイラ（`ulisp/compiler/driver.scm`）の最終式がコード生成結果の AST（`(%asm-program ...)`）を返却するため、`ULISP_QUIET=1` が欠落した瞬間にアセンブリ末尾に S 式が追記され、アセンブラ（`as` / `gcc`）が `invalid character '(' in mnemonic` でクラッシュする。
3. **Unix 哲学（Rule of Silence）への背反**:
   - C、Go、Rust、あるいは R7RS のスタンドアロン実行バイナリにおいて、プログラマが明示的に `(display ...)` や `printf` を呼ばない限り、プログラム終了時に戻り値を勝手に標準出力に垂れ流すことはなく、現状の挙動は Unix の「沈黙のルール（エラーがない限り沈黙せよ）」に反している。

### 本 Issue における解決策:
本 Issue では、このアーキテクチャの歪みを根本的に是正し、**「デフォルト沈黙（Quiet-by-Default）」** かつ **「クリーンな成果物出力」** の体系を確立する。

1. **ネイティブランタイムのデフォルト沈黙化（Quiet-by-Default）**:
   - スタンドアロン実行バイナリは、デフォルトでは戻り値を印字せず静かにプロセスを終了（ステータスコード 0）させる。
   - 戻り値の印字が必要なケース（REPL モード、ワンライナー評価、または環境変数 `ULISP_PRINT_RESULT=1`）のみ明示的に印字を有効化する。
2. **コンパイラエントリーポイントの明示的終了値（Exit Code 0）**:
   - `ulisp/compiler/driver.scm` の末尾において、巨大な AST をプログラムの戻り値として垂れ流すのを廃止し、C言語の `return 0;` と同様に明示的に整数 `0` を返却して終了する。
3. **コンパイラの直接ファイル出力（`-o <output>`）基盤の設計・導入**:
   - 標準出力への垂れ流しとシェルのリダイレクト（`> out.s`）依存から脱却し、Issue #606 で導入されたファイル入出力（`sys-open`）を活用して、コンパイラ自身が直接指定ファイルにアセンブリや C コードを書き出せる `-o` CLI オプションをサポートする。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、リポジトリ規約（`.agents/AGENTS.md`）に従い、専門エージェントによる設計レビューを統合して策定された。

- **Project Manager (PM) (Chair / Governance)**:
  - `ULISP_QUIET=1` の付け忘れによるビルド破綻は、パイプラインの保守性と再現性を著しく損なう脆弱要因である。根本からデフォルト沈黙（Quiet-by-Default）に反転させることで、テスト・ブートストラップ・Makefile の記述を大幅に簡素化・堅牢化する。
- **Systems Architect**:
  - Unix 哲学（Rule of Silence）および POSIX / C ABI 標準に完全合致させる。スタンドアロンバイナリは明示的な I/O 以外で stdout/stderr を汚してはならない。REPL 実行系としての振る舞いと、AOT コンパイルされたバッチツールの振る舞いを明確に分離する。
- **Software Quality Assurance Specialist (SQA)**:
  - `make test`, `test.sh`, `test_c.sh`, `bootstrap.sh` の全テストスイートにおいて、`ULISP_QUIET=1` を指定しない場合でもアセンブラ構文エラーが 100% 発生しないことを保証する。
- **Software Development (SWD)**:
  - `runtime/entry.scm` の `runtime-main` における条件分岐フラグを反転。また `driver.scm` の末尾に `0` を配置し、アセンブリ生成パスの戻り値リークを物理的に遮断する。

---

## 3. トレーサビリティ / Traceability

- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (Section 2: ランタイムシステム & CLI 仕様)
  - [R7RS Small Specification (Revised^7 Report on Scheme)](../../ulisp/docs/r7rs_specification_compliance.md)
- **関連 Issue**:
  - [Issue 580: runtime.c の完全廃止と低水準 Scheme による完全自己完結ランタイムの実現](../closed/580-deprecate-runtime-c-and-implement-pure-scheme-runtime.md)
  - [Issue 606: ビルド時 cat 結合の廃止と R7RS include 構文によるソース位置追跡基盤の導入](../closed/606-replace-cat-bundle-with-r7rs-include-and-source-tracking.md)
  - [Issue 613: ILisp における R7RS include / include-ci 構文およびライブラリ宣言 include の実装](613-implement-ilisp-r7rs-include-and-include-ci-support.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/runtime/entry.scm](../../ulisp/runtime/entry.scm)
  - `runtime-main` における印字制御ロジックの反転（デフォルトで非印字、`print-result` フラグ時のみ印字）
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)
  - `_start` エントリールーチンにおける環境変数パース処理の刷新（`ULISP_PRINT_RESULT` / `--repl` の検出）
- [ ] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm)
  - C バックエンドにおける `main()` 関数の結果印字ロジックの同期
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm)
  - コンパイラトップレベル式の戻り値を明示的に `0` に設定
  - CLI 引数パースにおける `-o <output-file>` オプションおよび直接ファイル出力の実装
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
  - `ULISP_COMPILER` 定義からの冗長な `ULISP_QUIET=1` ハックの撤廃とクリーン化
- [ ] [ulisp/test.sh](../../ulisp/test.sh) & [ulisp/test_c.sh](../../ulisp/test_c.sh) & [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh)
  - スクリプト内の冗長な `ULISP_QUIET=1` 指定の整理
- [ ] [docs/issues/614-refactor-runtime-silence-by-default-and-compiler-cli-output.md](614-refactor-runtime-silence-by-default-and-compiler-cli-output.md) (本 Issue ドキュメント)
- [ ] [docs/issues/README.md](README.md) (Issue 管理台帳の更新)

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/614-refactor-runtime-silence-by-default-and-compiler-cli-output`

1. **コンパイラ終了値の即時是正 (`driver.scm`)**:
   - `driver.scm` の末尾 `(compile-backend ...)` を評価した直後に `0` を返却するように修正。これだけで AST の標準出力漏洩が原理的に完全に防止される。
2. **ランタイムの Quiet-by-Default 化 (`runtime/entry.scm`, `backend/140_backend_x86_64.scm`)**:
   - `runtime-main` の第 4 引数を `quiet-mode` から `print-result?` に変更。
   - `(if print-result? (runtime-print-value result))` に変更し、明示的に結果印字が要求されない限り完全沈黙とする。
   - `_start` での環境変数スキャンを `ULISP_PRINT_RESULT`（またはワンライナー/REPLオプション）に反転。
3. **`-o` オプションによるファイル直接出力のサポート (`driver.scm`)**:
   - コマンドライン引数（`argv`）から `-o <file>` をパース。
   - 指定がある場合は `(sys-open file O_WRONLY|O_CREAT|O_TRUNC 0644)` で直接ファイルを開き、標準出力へのリダイレクトなしでコードを書き出す。
4. **Makefile およびテストスクリプトのクリーンアップ**:
   - 各種スクリプトに散在していた `ULISP_QUIET=1` の個別指定を排除。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp/compiler/driver.scm` の終了値が明示的に `0` となり、AST（`%asm-program`）が戻り値として漏洩しないこと
- [ ] ネイティブランタイムがデフォルト沈黙（Quiet-by-Default）となり、`ULISP_QUIET=1` を指定しなくてもアセンブリ出力が破損しないこと
- [ ] コンパイラが `-o <file>` オプションを解釈し、直接ファイルへ出力可能となること
- [ ] `make test_gc_growth` を含むすべてのテストターゲットが、環境変数ハックなしで正常にコンパイル・リンク・実行できること
- [ ] `3-Stage Bootstrap`（`bash ulisp/bootstrap.sh`）が 100% 成功し、固定点が一致すること
- [ ] `make py_compile` および `make static_analysis` がエラー 0 件で合格すること
- [ ] `docs/issues/README.md` のステータスが適切に管理されていること
