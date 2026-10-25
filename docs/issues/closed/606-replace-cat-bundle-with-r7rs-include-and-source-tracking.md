---
ID: 606
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ビルド時 cat 結合の廃止と R7RS include 構文によるソース位置（ファイル名・行番号）追跡基盤の導入 (ID: 606)

## 1. 概要 / Summary

現在、ULisp のブートストラップスクリプト（`ulisp/bootstrap.sh`）およびビルドシステム（`ulisp/Makefile`）では、多数の Scheme ソースファイル（`lib/*.scm`、`runtime/*.scm`、`compiler/*.scm`、`frontend/*.scm`、`lir/*.scm`、`backend/*.scm`）をシェルの `cat` コマンドで物理的に結合し、15,000〜25,000 行超の単一巨大ファイル（`build/ulisp_core.scm` や `compiler.scm`）を一時生成してコンパイラに入力している。

### 現行アーキテクチャの課題と障害要因:
1. **ソース位置（ファイル名・行番号）の完全な喪失**:
   - コンパイラ内部で構文エラー（`nanopass-parse: invalid expression`）や LIR 生成エラー（`Unbound variable in LIR`）、型アノテーション例外が発生した際、エラーの報告行が結合後の一時ファイルの行番号（例: `line 18450`）となってしまい、元のどのソースファイル（例: `lib/list.scm` なのか `compiler/scope.scm` なのか `lir/130_lir.scm` なのか）の何行目に起因するのかが完全に不可視となっている。
2. **ビルドスクリプト間の重複・乖離と脆弱性**:
   - `ulisp/Makefile` の `COMPILER_BASE` / `PASSES` リストと `ulisp/bootstrap.sh` の `cat` 結合対象ファイルリストが二重管理されており、新規パスやライブラリを追加した際に一方への追記漏れによる未定義変数バグが頻発している。
3. **ファイル I/O と R7RS 標準インクルード機構の未充足**:
   - `ulisp/frontend/010_library.scm` 内の `slurp-single-file` が「ベアメタルセルフホスティングにおける POSIX open システムコール未対応」を理由に空リスト `'()` を返すスタブとなっており、R7RS Section 4.1.7 および 5.6.1 で規定される `(include "path/to/file.scm")` 構文が機能していない。
4. **テストランナー生成の非効率とディスク I/O 負荷**:
   - 単体テストの実行ごとに `cat build/compiler_passes.scm tests/... > build/runner_temp.scm` が数十回実行され、一時ファイルの生成・消去が繰り返されている。

### 本 Issue における解決策:
本 Issue では、シェルの `cat` 結合を全面的に廃止し、**R7RS 準拠の `(include "path/to/file.scm")` 構文に基づく単一エントリーポイント構成**へ移行する。
具体的には：
1. **ゼロ libc POSIX ファイル入出力基盤の実装**:
   `lib/posix.scm` に Linux x86-64 システムコール `sys-open`（Syscall 2）および `sys-close`（Syscall 3）を追加し、`lib/port.scm` にファイル入力ポート（`open-input-file`, `close-port`）を実装する。
2. **ソース位置注釈付きリーダー（`read-with-source-info`）の導入**:
   `lib/reader.scm` のポート構造に行番号（line）および列番号（column）のカウンタを統合し、S 式を読み込む際に `(%source-loc "path/file.scm" line col form)` などのソース位置注釈属性を透過的に保持する。
3. **R7RS `(include ...)` 静的インクルード展開エンジンの完成**:
   `frontend/010_library.scm` を拡張し、ライブラリ宣言内のみならずトップレベル式の `(include ...)` を再帰的・相対パス解決して安全に展開する。
4. **Issue 602 診断機構との統合**:
   コンパイラ実行時エラー発生時に、`compiler-diagnostic-report` が AST のソース位置注釈から `[Source Location: lib/list.scm:45:2]` を自動抽出・整形表示できるようにする。
5. **エントリーファイルの確立と `bootstrap.sh` / `Makefile` の簡素化**:
   `ulisp/entry_core.scm` および `ulisp/compiler_entry.scm` を作成し、シェル結合スクリプトを排除する。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、リポジトリ規約（`.agents/AGENTS.md`）に従い、16 専門エージェントによる設計レビューを統合して策定された。

- **Project Manager (PM) (Chair / Governance)**:
  - ビルド時 `cat` 結合の排除は、後続の Issue #607（extern シンボル解決と 2 分割リンク）および Issue #608（モジュール別分割コンパイル・インクリメンタルビルド）の絶対的な前提基盤である。最優先で品質ゲートを担保しつつ完了させる。
- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - R7RS 4.1.7（`include`）および 5.6.1（ライブラリ宣言 `include`）の仕様適合性を厳密に遵守。
  - ソース位置注釈（Source Location Annotation）は AST のセマンティクスを破壊しないよう、Nanopass DSL 内部で透過的に伝播するか、またはトップレベル式ラッパー `(%source-loc "file" line col form)` として Pass 025 / 030 / 035 / 130 で追跡する設計とする。
- **Systems Architect**:
  - ホスト処理系（Gauche `gosh`、Python `ilisp`）およびセルフホスティングネイティブ実行系（`ulisp-boot` / `ulisp-stage1`）の双対環境で同一の `(include ...)` 意味論が破綻なく成立するポータブルなパス解決規約（カレントディレクトリ基準および親ファイル相対パス基準）を定義。
- **Information Security Specialist**:
  - `(include ...)` によるパストラバーサル脆弱性（CWE-22 / CWE-23）、循環インクルードによるコンパイラスタック枯渇（CWE-400 / CWE-674）、および非信頼ファイル読み込みに伴うクラッシュ（CWE-703）を STRIDE / CWE 観点で分析し、防護境界を設計。
- **Software Quality Assurance Specialist (SQA)**:
  - 3-Stage Bootstrap（Stage 1 → Stage 2 → Stage 3 固定点検証）が 100% 決定論的に成功すること。
  - ソース位置追跡が正確にファイル名・行番号を指し示していることを検証する単体・結合テスト（`test_include_source_loc.scm`）を策定。
- **Software Development (SWD)**:
  - ベアメタル Linux x86-64 環境における `sys-open`（Syscall 2）および `sys-close`（Syscall 3）を `lib/posix.scm` にゼロ libc で実装。Scheme 文字列（タグ 3）の生ポインタ変換を安全に行う。
- **Application Specialist (APS)**:
  - ビルドログおよび診断ダンプの可読性を最大化し、エラー発生時に開発者が対象ソースファイルの該当下行へダイレクトにジャンプできる GNU / Clang 互換の `file:line:col: error: ...` 形式出力を支援。

---

## 3. トレーサビリティ / Traceability

- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (Section 2: ランタイムシステム & Section 3: パイプライン設計)
  - [R7RS Small Specification (Revised^7 Report on Scheme)](../../ulisp/docs/r7rs_specification_compliance.md) (Section 4.1.7: `include`, Section 5.6.1: Library declarations)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
  - [LIR 命令セット仕様書](../../ulisp/docs/spec_lir.md)
- **関連 Issue**:
  - [Issue 516: 100% Pure Scheme ベアメタルランタイム基盤の実装 (ゼロ libc / 直接システムコール)](516-implement-zero-libc-pure-scheme-bare-metal-runtime.md)
  - [Issue 548: R7RS ライブラリ構文 (define-library / import) の静的脱糖・フラット名前空間インクルード機構の実装](548-implement-r7rs-define-library-and-import-syntax.md)
  - [Issue 562: R7RS 標準 16 ライブラリ定義 (*.sld) の物理配置および export/include/import 機構の統合](562-implement-r7rs-standard-library-definitions-sld.md)
  - [Issue 598: 統一 Pass Manager の導入によるパイプライン制御・最適化レベルスケジューリング・観測性の一元化](../598-implement-unified-compiler-pass-manager.md)
  - [Issue 600: 統合シンボル・スコープ解決基盤および α 変換エンジンの導入](600-implement-unified-lexical-scope-and-alpha-conversion-engine.md)
  - [Issue 602: コンパイラ実行時における現在Nanopass・処理中トップレベル式・ソース位置のコンテキスト追跡とエラー診断ダンプの導入](602-track-compiler-context-pass-and-toplevel-form-on-error.md)
  - [Issue 603: Power Assert 風アサーション式展開および LIR 変数解決失敗時のローカル環境自動ダンプ機能の実装](603-implement-power-assert-and-lir-env-dump-diagnostics.md)
  - [Issue 604: コンパイラ実行時のコールスタック追跡および未捕捉例外時のバックトレース表示機能の実装](604-implement-call-stack-traceback-for-compiler-exceptions.md)
  - [Issue 607: 外部シンボル（extern）参照解決と標準ライブラリ・コンパイラの2分割 .o 静的リンク基盤の導入](../607-support-extern-symbols-and-split-stdlib-compiler-linking.md)
  - [Issue 608: モジュール別分割コンパイル・依存グラフ解析およびインクリメンタルビルド基盤の実装](../608-implement-modular-separate-compilation-and-incremental-build.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm)
  - `sys-open`（Syscall 2: `open(path, flags, mode)`）および `sys-close`（Syscall 3: `close(fd)`）のゼロ libc 純 Scheme 実装
  - Scheme 文字列ポインタから null 終端 C 文字列への安全なキャスト・変換処理
- [x] [ulisp/lib/port.scm](../../ulisp/lib/port.scm)
  - ファイル入力ポート型 `'%file-input-port` の定義（fd, バッファ, 行番号カウンタ, 列番号カウンタ）
  - `open-input-file`（R7RS Section 6.13.1 準拠）および `close-input-port` / `close-port` の実装
  - `port-read-char` / `port-peek-char` における改行文字検知と行・列番号インクリメント機構
- [x] [ulisp/lib/reader.scm](../../ulisp/lib/reader.scm)
  - ソース位置注釈付きリーダー `port-read-with-source-info` の実装
  - 読み込まれた各トップレベル式への `(%source-loc "<filename>" <line> <col> <datum>)` ラッピング
- [x] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm)
  - ソース位置コンテキスト大域変数（`*current-source-file*`, `*current-source-line*`, `*current-source-col*`）の cons セルベース定義
  - `compiler-diagnostic-report` への `[Source Location: file:line:col]` 出力行の統合
  - ソース位置ラッパー剥ぎ取り・参照ユーティリティ（`strip-source-loc`, `source-loc-file`, `source-loc-line`, `source-loc-col`）
- [x] [ulisp/frontend/010_library.scm](../../ulisp/frontend/010_library.scm)
  - スタブとなっていた `slurp-single-file` および `slurp-included-files` の完全実装
  - トップレベル式における `(include "path" ...)` 構文の再帰的展開・スプライシング
  - インクルードパス相対解決（カレントファイル基準）および循環インクルード検出機構
- [x] [ulisp/entry_core.scm](../../ulisp/entry_core.scm) (新規)
  - `bootstrap.sh` の巨大 `cat` を代替する単一エントリー Scheme ファイル
- [x] [ulisp/compiler_entry.scm](../../ulisp/compiler_entry.scm) (新規)
  - コンパイラ本体の単一エントリー Scheme ファイル（全パス・基盤の `include` 列）
- [x] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh)
  - `cat` コマンドによる一時ファイル結合コードの完全排除
  - `entry_core.scm` を直接各ブートストラップステージに入力するクリーンなフローへの刷新
- [x] [ulisp/Makefile](../../ulisp/Makefile)
  - `compiler.scm` および `build/compiler_passes.scm` の `cat` 生成ルールの排除または `include` 委譲
  - テストランナーにおける一時 `cat` スクリプトの廃止と `include` テンプレート化
- [x] [ulisp/tests/test_include_source_loc.scm](../../ulisp/tests/test_include_source_loc.scm) (新規)
  - `include` 展開、相対パス解決、循環インクルード検出、およびエラー時ソース位置レポートの網羅的単体テスト
- [x] [docs/issues/closed/606-replace-cat-bundle-with-r7rs-include-and-source-tracking.md](606-replace-cat-bundle-with-r7rs-include-and-source-tracking.md) (本設計書)
- [x] [docs/issues/README.md](../README.md) (Issue 台帳更新)

---

## 5. 脅威モデルとセキュリティ・堅牢性要件 / Threat Modeling & Security Requirements

コンパイラフロントエンドにおける外部ファイル読み込みおよびインクルード機構の導入は、外部入力や悪意あるスクリプトによる攻撃対象領域（Attack Surface）を拡大する。STRIDE および CWE 観点での脅威分析を実施し、以下の防護要件を策定した。

| 脅威分類 (STRIDE / CWE) | 脅威シナリオ | 影響度 | 対策要件 (Mitigation Requirements) |
| :--- | :--- | :---: | :--- |
| **情報漏洩 / パストラバーサル (CWE-22 / CWE-23 / CWE-36)** | `(include "/etc/passwd")` や `(include "../../../../secret.key")` のように、プロジェクトディレクトリ外の機密ファイルをインクルードし、コンパイルエラーやバイナリ文字列埋め込みを通じて機密情報を漏洩させる。 | High | インクルードパス解決時に、ルート基準パス検証を実施。プロジェクトルートまたは許可されたインクルード検索パス外への遡行（`../` によるエスケープ）を検知した場合、コンパイルエラー（`include error: path traversal outside allowed directory`）を発出して処理を即時拒否する。 |
| **サービス拒否 / 循環インクルード (CWE-400 / CWE-674 DoS)** | `a.scm` が `b.scm` をインクルードし、`b.scm` が `a.scm` を再帰インクルードする循環構造により、コンパイラが無限再帰に陥りスタックオーバーフローまたはヒープ枯渇でクラッシュする。 | High | インクルード走査中に「現在探索中のファイル絶対パススタック（`*include-path-stack*`）」を保持。スタック内に同一ファイルパスが既に存在する場合は循環インクルード（`include error: circular dependency detected`）として即座に決定論的エラーを発出し停止する。最大インクルード深度制限（例: 最大 64 階層）を設ける。 |
| **例外処理不全 / ファイル不存在クラッシュ (CWE-703 / CWE-391)** | 指定されたインクルードファイルが存在しない、あるいはパーミッション不足の場合に、ベアメタルネイティブ実行系で不正な fd を読み込んで SEGV または無言終了する。 | High | `sys-open` の戻り値が負（エラー）の場合は直ちにファイルオープン失敗を判定し、`include` を呼び出した親ファイル名と行番号を明記した構造化コンパイラ診断エラーを出力する。空の AST を無言で返却しない。 |
| **リソース枯渇 / ファイル記述子リーク (CWE-775 / CWE-404)** | 多数のファイルを連続して `include` する際、読み込み終了後や途中で構文エラーが発生した際に fd がクローズされず、`EMFILE`（Too many open files）に達してビルドが中断する。 | Medium | `slurp-single-file` において、ファイルの読み込み完了時、および EOF 到達時に必ず `sys-close` を呼ぶことを保証する `call-with-input-file` パターンを厳格に適用する。 |
| **データ改ざん / 構文注釈によるセマンティクス破壊 (CWE-697)** | ソース位置注釈（`%source-loc`）が式ツリーの構文解析パス（マクロ展開、脱糖、α 変換、LIR 生成）を阻害し、意図しない未束縛変数例外や誤変換を誘発する。 | Critical | ソース位置注釈はトップレベル定義の外枠にのみ付加するか、または各 Nanopass が未知の形式として拒絶しないよう、コンパイラコアの入口（Pass 025/030）でコンテキスト変数（`*current-source-file*`, `*current-source-line*`）に抽出・昇格した上で透過的に剥ぎ取る（Transparent Unwrapping）パイプライン設計とする。 |

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/606-replace-cat-bundle-with-r7rs-include-and-source-tracking`

### 6.1 Linux x86-64 ゼロ libc ファイル I/O システムコール (`ulisp/lib/posix.scm`)
1. **`sys-open` (Syscall 2)**:
   ```scheme
   ;; sys-open: sys_open(filename_ptr, flags, mode) -> fd (fixnum)
   ;; O_RDONLY = 0
   (define (sys-open path flags mode)
     (let ((path-ptr (%ptr-untag path)))
       (%to-fixnum (%raw-syscall (%to-raw 2) path-ptr (%to-raw flags) (%to-raw mode) 0 0 0))))
   ```
2. **`sys-close` (Syscall 3)**:
   ```scheme
   ;; sys-close: sys_close(fd) -> status
   (define (sys-close fd)
     (%to-fixnum (%raw-syscall (%to-raw 3) (%to-raw fd) 0 0 0 0 0)))
   ```

### 6.2 ファイル入力ポートおよび行・列番号追跡の実装 (`ulisp/lib/port.scm`)
1. **ファイル入力ポートデータ構造**:
   ```scheme
   ;; %file-input-port: (list '%file-input-port fd buf-cell pos-cell len-cell line-cell col-cell filename)
   (define (open-input-file filename)
     (let ((fd (sys-open filename 0 0))) ; O_RDONLY = 0
       (if (< fd 0)
           #f
           (let ((buf (make-string 4096)))
             (list '%file-input-port
                   fd
                   (cons buf '())
                   (cons 0 '())        ; read pos
                   (cons 0 '())        ; buffer len
                   (cons 1 '())        ; current line (1-indexed)
                   (cons 1 '())        ; current col (1-indexed)
                   filename)))))
   ```
2. **位置追跡付き `port-read-char`**:
   - 入力文字が `#\newline` の場合：`line-cell` を `+ 1` し、`col-cell` を `1` にリセット。
   - その他の文字の場合：`col-cell` を `+ 1`。
3. **安全なポートクローズ**:
   - `(close-input-port p)` で基底の `fd` に対して `sys-close` を発行し、二重クローズを防止。

### 6.3 ソース位置注釈付きリーダーの実装 (`ulisp/lib/reader.scm`)
1. **`read-with-source-info`**:
   - S 式の先頭トークンを読み込む直前の `(port-line p)` および `(port-col p)` を取得。
   - 読み込まれた datum が pair または symbol の場合、トップレベルにおいて `(list '%source-loc filename line col datum)` を構成。
   - 通常の `(read)` との完全な後方互換性を維持。

### 6.4 R7RS `include` 静的展開エンジンの完成 (`ulisp/frontend/010_library.scm`)
1. **`slurp-single-file` の実装**:
   ```scheme
   (define (slurp-single-file path)
     (let ((p (open-input-file path)))
       (if (not p)
           (error "include: failed to open source file" path)
           (let loop ((acc '()))
             (let ((expr (read-with-source-info p)))
               (if (eof-object? expr)
                   (begin
                     (close-input-port p)
                     (reverse acc))
                   (loop (cons expr acc))))))))
   ```
2. **パス相対解決と循環検知**:
   - 親ファイルのディレクトリパスを取得し、相対インクルードパス（例: `"lib/posix.scm"`）を正規化。
   - `*include-path-stack*` により再帰インクルードチェーンを検査し、循環参照を即時エラーとする。
3. **トップレベル式のスプライシング展開**:
   - パス 010 のメインループにおいて、`(include "path1" "path2" ...)` 形式を検出し、その位置にインクルードされたファイルの全式を順序正しくインライン展開する。

### 6.5 コンパイラ診断機構（Issue 602）との統合 (`ulisp/compiler/helpers.scm`)
1. **ソース位置コンテキスト変数**:
   - `*current-source-file*` (初期値 `'none`)
   - `*current-source-line*` (初期値 `0`)
   - `*current-source-col*` (初期値 `0`)
2. **Pass 025 / Pass 030 での自動抽出と透過的剥ぎ取り**:
   - 式が `(%source-loc file line col inner-expr)` の場合、コンテキスト変数を更新した上で `inner-expr` を後続パスへ引き渡す。
3. **`compiler-diagnostic-report` の出力拡張**:
   - エラーレポートに正確なソース位置行を追加：
     ```text
     ======================================================================
     [COMPILER ERROR] Compilation aborted in Pass: pass-130-lir
       Source Location: lib/list.scm:45:2
       Top-Level Form:  (define (list-ref ls n) ...)
       Current Expr:    (car ls)
       Message:         Unbound variable in LIR: ls
     ======================================================================
     ```

### 6.6 エントリーファイルの作成とビルドパイプラインの刷新
1. **`ulisp/entry_core.scm` の作成**:
   - 従来の `cat` ファイル列を `(include ...)` のみで構成したクリーンなエントリー Scheme ファイルへ移行：
     ```scheme
     (!gc none)
     (include "lib/posix.scm")
     (include "lib/list.scm")
     (include "lib/string.scm")
     (include "lib/port.scm")
     (include "lib/printer.scm")
     (include "lib/reader.scm")
     (include "lib/equality.scm")
     (include "lib/predicates.scm")
     (include "lib/bytevector.scm")
     (include "lib/vector.scm")
     (include "lib/promise.scm")
     (include "lib/exception.scm")
     (include "lib/values.scm")
     (include "lib/continuation.scm")
     (include "lib/parameter.scm")
     (include "lib/gc.scm")
     (include "runtime/gc.scm")
     (include "runtime/io.scm")
     (include "runtime/printer.scm")
     (include "runtime/entry.scm")
     (include "compiler_entry.scm")
     ```
2. **`ulisp/bootstrap.sh` の改修**:
   - `cat $ULISP_DIR/lib/... >> "$BUILD_DIR/ulisp_core.scm"` のブロックを全面削除。
   - コンパイラビルドおよびブートストラップの各ステージ（Stage 1, 2, 3）への入力を `ulisp/entry_core.scm` に直接切り替え。
3. **`ulisp/Makefile` の整理**:
   - `cat` による一時ファイル生成を抑制し、エントリーファイル直接コンパイルを標準化。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/lib/posix.scm` に `sys-open`（Syscall 2）および `sys-close`（Syscall 3）がゼロ libc で実装されていること
- [x] `ulisp/lib/port.scm` に `open-input-file` および行・列カウンタ付きファイルポートが実装されていること
- [x] `ulisp/lib/reader.scm` にソース位置注釈付きリーダー `read-with-source-info` が実装されていること
- [x] `ulisp/frontend/010_library.scm` において、ライブラリ内およびトップレベルの `(include ...)` 構文が正しく再帰展開されること
- [x] 循環インクルードおよびパストラバーサルが決定論的かつ安全に検知され、エラー終了すること
- [x] `compiler-diagnostic-report` において、コンパイルエラー時に結合一時ファイルではなく元のソースファイル名・行番号・列番号が出力されること
- [x] `ulisp/entry_core.scm` および `ulisp/compiler_entry.scm` が作成され、`ulisp/bootstrap.sh` 内の `cat` コマンドが排除されていること
- [x] 単体テストスイート `ulisp/tests/test_include_source_loc.scm` が新規作成され、全テストが PASS すること
- [x] `make test_unit` および 3-Stage Bootstrap（`bash ulisp/bootstrap.sh`）が 100% PASS し、バイナリ固定点が一致すること
- [x] `make py_compile` および `make static_analysis` がエラー 0 件で合格すること
- [x] `docs/issues/README.md` のステータスが `Closed (Completed)` に更新されていること
