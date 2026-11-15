---
ID: 833
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT] コンパイラ・マクロ展開・インタプリタ共通の統合エラー診断エンジン (Diagnostic Reporter) の導入 (ID: 833)

## 1. 概要 / Summary
コンパイラの全フェーズ（字句解析・構文解析・Nanopass 中間パス・型検査）、衛生的マクロ展開器、および将来の Scheme インタプリタ REPL で共通利用可能な「統合エラー診断エンジン（Pretty Diagnostic Reporter: `ulisp/compiler/diagnostic.scm`）」を設計・実装する。

Issue #824 で導入された第一級ソース位置情報（`<source-span>`）および来歴情報と連携し、対象ソースコードの行スニペット遅延抽出、行番号・境界パイプ（`|`）描画、キャレット（`^`）および下線ハイライト、マクロ展開スタックトレース（`macro-origin`）、類似シンボル推薦（Wagner-Fischer DP レーベンシュタイン距離）による Fix-it 修正提案を、Clang / Rustc スタイルの美しい開発者体験（DX）として標準出力/エラー出力へ出力する。

### 背景とアーキテクチャ上の動機
1. **多言語フロントエンドの診断統一 (DSN-33-02 §3.4, S1マイルストーン)**:
   - ULisp は現在 Scheme フロントエンドに加えて、C99 プリプロセッサおよびフロントエンド（Issue #826, #837）の整備を進めている。フロントエンドごとにエラー出力形式が乖離することを防ぎ、構文エラー・型不一致・未定義識別子に対して統一されたフォーマット（Rustc/Clang 準拠の `error[E0001]: ...`）を提供する必要がある。
2. **第一級 `<source-span>` とマクロ展開来歴の完全活用 (Issue #824)**:
   - 単なるファイル名と行番号の平文表示（`file:line:col`）にとどまらず、正確な列範囲（`start-col` 〜 `end-col`）に基づく波線・キャレット下線強調を行い、マクロ展開によって生成されたノードでは展開元（Call-site）と定義元（Def-site）の 2 重位置注記（`= note: expanded from macro ...`）を可視化する。
3. **ANSI カラー表示と CLI 環境適合性 (`--color=auto|always|never`)**:
   - ターミナル出力時は赤・黄・シアン・緑のカラー強調で可読性を極限まで高めつつ、CI ログやパイプライン、`NO_COLOR` 環境変数、`--color=never` 指定時には完全な ASCII プレーンテキストへ動的フォールバックし、文字化けやログ汚染を 100% 排除する。
4. **堅牢性と DoS 耐性**:
   - 不正なスパン値、巨大なソースファイル、悪意あるエスケープシーケンス混入に対して例外クラッシュや OOM を起こさず、安全に切り詰め・サニタイズされた診断情報を出力する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33-02 設計書**:
  - §3.4: 統合 Pretty Diagnostic Reporter (Issue #833)
  - §3.1: 第一級ソース位置情報 (Source Span) と来歴追跡 (Issue #824)
  - §8.1: ロードマップ S1 (基盤整備 ＆ Reference VM)
- **DSN-38 仕様書**:
  - §1: フロントエンド診断基盤とコンパイラ内部基盤
  - §2 B3: 構文解析・エラーリカバリ
  - §2 B4: 意味解析・型診断
- **関連 Issue**:
  - #603: Power Assert & LIR 類似シンボル推薦エンジン (Wagner-Fischer DP)
  - #785: CLI 出力リダイレクトおよびエラー時ファイルロールバック
  - #823: SRFI 64 統一テストランナー
  - #824: Nanopass AST ノードにおける第一級ソース位置情報 (Source Span)
  - #834: 純粋 Scheme 製 LIR 参照仮想マシン (Reference VM)
  - #837: 構文解析後の一意束縛解決 (Binding ID) とスコープ環境管理

---

## 3. 脅威モデルとセキュリティ要件 (Threat Model & Security Mitigation)

診断レポータは外部入力（ソースコードおよびコンパイル対象ファイル）を直接読み込んでターミナルに出力するため、入力起因の DoS、端末エスケープ注入、パストラバーサル等の脆弱性を排除する厳格なセキュリティ不変条件を確立する。

| 脅威 ID | 脅威分類 (CWE) | 脅威シナリオ | 緩和策・設計上の防御不変条件 |
| :--- | :--- | :--- | :--- |
| **THREAT-833-1** | **CWE-400 / CWE-770**<br>制御不能なリソース消費による DoS | 悪意ある巨大ソースファイル（例: 1 行が数十万文字、あるいは数百メガバイトの単一ファイル）を解析中にエラーが発生し、スニペット抽出時にヒープが枯渇（OOM）または行走査ループでフリーズする。 | スニペット表示対象行の最大文字数を 256 文字に制限（超過時は `...` で安全に切り詰め）。ファイル行走査時は対象行番号近傍のみを読み込み、ファイルキャッシュの上限行数を 4,096 行に制限する。 |
| **THREAT-833-2** | **CWE-119 / CWE-125**<br>境界外読込によるクラッシュ | 不正な `<source-span>`（負の列番号、行長を超える開始列、`end-col < start-col`、行数超過）が与えられた場合に、文字列参照（`substring`）で境界外アクセスが発生しコンパイラが異常終了する。 | 列番号のクランプガード（`1 <= start-col <= line-len + 1`）および下線長計算の飽和演算（下限 1 文字、上限行末）を強制し、不正なスパンでも安全にデフォルト描画する。 |
| **THREAT-833-3** | **CWE-116 / CWE-150**<br>不適切な出力エンコードと ANSI エスケープ注入 | ソースコード内に端末エスケープコード（`\033]0;...` や端末制御文字）が含まれていた場合、エラーメッセージ出力時に開発者のターミナルが乗っ取られたり、画面描画が改ざんされる。 | ソース行出力前に非印字文字（ASCII 0x00〜0x1F、0x7F、ESC `\x1b`）をサニタイズ（制御文字は空白または可視化文字へ置換）してからレンダリングする。 |
| **THREAT-833-4** | **CWE-22 / CWE-200**<br>パストラバーサルと情報漏洩 | 不正なファイルパス（`/etc/passwd` やシステム絶対パス）を持つ Span が渡された際、コンパイラが任意システムファイルを読み込んでエラーログに内容を露出させてしまう。 | `sanitize-source-path` を適用し、登録済みソースファイル一覧（`registered-source-files`）または相対パス検証済みファイルのみを読み込み対象とする。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/diagnostic.scm](../../ulisp/compiler/diagnostic.scm):
  - 新設：`<diagnostic>` レコード定義（`level`, `code`, `span`, `message`, `labels`, `notes`, `help`）。
  - 新設：ソースファイル行キャッシュ（`*source-file-line-cache*`）および遅延行スニペット抽出機構。
  - 新設：ANSI カラー制御モジュール（`--color=auto|always|never` および `NO_COLOR` 判定）。
  - 新設：Rustc / Clang スタイルのマルチライン整形・キャレット・下線ハイライト描画エンジン。
  - 新設：マクロ展開来歴スタックトレース可視化エンジン。
- [x] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm):
  - `compiler-diagnostic-report` を新診断エンジンへ委譲・統一。
  - `report-diagnostic`、`emit-diagnostic-error`、`emit-diagnostic-warning`、`emit-diagnostic-note` API の新設。
  - 既存の `recommend-similar-symbols`（レーベンシュタイン距離）と `help: did you mean ...` 連携。
- [x] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm):
  - CLI 引数 `--color`, `--color=auto|always|never`, `--no-color` のパースと診断カラーモード設定。
  - 累積エラー数（`*diagnostic-error-count*`）・警告数（`*diagnostic-warning-count*`）の集計と、終了時サマリー出力。
- [x] [ulisp/compiler_entry.scm](../../ulisp/compiler_entry.scm):
  - `(include "compiler/diagnostic.scm")` の追加。
- [x] [ulisp/Makefile](../../ulisp/Makefile):
  - `COMPILER_BASE` 変数への `compiler/diagnostic.scm` 追加。
  - `test_diagnostic_reporter` ターゲット新設および `make test` 統合。
- [x] [ulisp/tests/test_diagnostic_reporter.scm](../../ulisp/tests/test_diagnostic_reporter.scm):
  - 新設：診断オブジェクト生成、スニペット抽出、キャレット位置、マルチライン描画、カラー切替、制御文字サニタイズ、マクロ追跡の網羅的テストスイート。
- [x] [docs/issues/README.md](README.md): Issue 台帳のステータス更新。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/833-unified-pretty-diagnostic-reporter`

### ステップ 1: 診断データ構造 (`<diagnostic>`) とアクセサの設計 (`ulisp/compiler/diagnostic.scm`)
1. **診断レコード型 `<diagnostic>`**:
   ```scheme
   (define-record-type <diagnostic>
     (%make-diagnostic-raw level code span message labels notes help)
     diagnostic?
     (level   diagnostic-level)   ; 'error | 'warning | 'note | 'help
     (code    diagnostic-code)    ; symbol or string (例: 'S0001, 'C0042) または #f
     (span    diagnostic-span)    ; <source-span> または #f
     (message diagnostic-message) ; 人間可読なエラー概要文字列
     (labels  diagnostic-labels)  ; list of (span . label-text)
     (notes   diagnostic-notes)   ; list of string または (span . note-text)
     (help    diagnostic-help))   ; list of string (Fix-it 提案)
   ```
2. **ファクトリ手続きとビルダー**:
   - `make-diagnostic`: レベル、コード、スパン、メッセージを受け取り、安全に正規化して生成。
   - `diagnostic-add-label!`, `diagnostic-add-note!`, `diagnostic-add-help!`: 注釈や提案を追加。

### ステップ 2: ソースコード行キャッシュと遅延スニペット抽出
1. **ソース行キャッシュ (`*source-file-line-cache*`)**:
   - `((file . #("line1" "line2" ...)) ...)` の連想リスト。
   - 同一コンパイル単位内で同じファイルの再オープンを防止。
   - インライン式（`-e` オプション）用の仮想ファイル名 `<expression>` または `*stdin*` のバッファ行にも透過的に対応。
2. **行取得手続き (`diagnostic-get-source-line file line-no`)**:
   - ファイルが存在し、かつ安全に読み込める場合に指定行の文字列を返す。
   - 存在しない場合は `#f` を返し、スニペットなしのフォールバック表示へ遷移。
   - THREAT-833-1 に基づき、最大文字数を 256 文字にクランプ。
   - THREAT-833-3 に基づき、制御文字（`\t` 以外の制御文字および ESC）を安全な空白文字または置換文字へサニタイズ。

### ステップ 3: ANSI カラー強調・フォーマッタと端末互換性制御
1. **カラーモード設定**:
   - `*diagnostic-color-mode*`: `'auto` | `'always` | `'never'`（デフォルトは `'auto`）。
   - `NO_COLOR` 環境変数がセットされている場合は自動的に `'never` へ移行。
   - `diagnostic-color-enabled?`: 現在のモードと出力先（TTY）に基づきカラー有効性を判定。
2. **ANSI カラーエスケープ**:
   - Error: 太字赤 (`\033[1;31m`)
   - Warning: 太字黄 (`\033[1;33m`)
   - Note: 太字シアン (`\033[1;36m`)
   - Help: 太字緑 (`\033[1;32m`)
   - Gutter / Line numbers: シアン (`\033[36m`)
   - Bold: 太字 (`\033[1m`)
   - Reset: (`\033[0m`)
   - カラー無効時は空文字列を返すエスケープヘルパー。

### ステップ 4: Rustc / Clang スタイルのレンダリングエンジン
1. **ヘッダー描画**:
   ```text
   error[S0001]: unbound variable 'calculate-pi'
     --> src/main.scm:12:5
   ```
2. **スニペットとガター（Gutter）描画**:
   - 行番号の桁数に応じた動的パディング幅（Line number width）の計算。
   - ガター区切り ` | ` の描画。
   ```text
      |
   12 |     (calculate-pi 10)
      |      ^^^^^^^^^^^^ unbound variable
   ```
3. **キャレット（`^`）と下線配置**:
   - `span-start-col` から `span-end-col` までの文字数分、キャレット `^` または下線 `~` を描画。
   - 単一文字または `start-col = end-col` の場合は最低 1 個の `^` を出力。
4. **マクロ展開来歴トレース**:
   - `span-macro-origin` を再帰的に辿り、マクロ展開元がある場合は注記を出力：
   ```text
     = note: expanded from macro 'with-constants' at src/macros.scm:4:3
   ```
5. **Fix-it / 類似シンボル提案**:
   - `help` フィールドに含まれる修正提案を出力：
   ```text
     = help: did you mean 'calculate-pi-approx'?
   ```

### ステップ 5: コンパイラエラーハンドラおよび CLI ドライバ統合
1. **`compiler/helpers.scm` の更新**:
   - `compiler-diagnostic-report` を `format-diagnostic` / `render-diagnostic` 経由に更新。
   - 既存の `recommend-similar-symbols` の結果を自動的に `diagnostic-add-help!` へ接続。
2. **`compiler/driver.scm` の更新**:
   - CLI 引数 `--color`, `--color=auto`, `--color=always`, `--color=never`, `--no-color` をパース。
   - エラー発生時の累積カウントとサマリー出力（`error: aborting due to previous error`）。
3. **`compiler_entry.scm` および `Makefile` の構成更新**:
   - `COMPILER_BASE` に `compiler/diagnostic.scm` を配置し、3-Stage ブートストラップおよび全テストスイートの通過を確認。

### ステップ 6: 包括的テストスイート (`test_diagnostic_reporter.scm`)
1. `<diagnostic>` レコードの不変条件、アクセサ、ファクトリの検証。
2. スニペット抽出エンジン（単一行、複数行、境界値）のテスト。
3. カラーモード切替テスト（`--color=always` で ANSI エスケープが含まれ、`--color=never` で完全プレーンテキストになること）。
4. 不正なスパン（負数、超過列）に対する防御的フォールバックの検証。
5. 制御文字サニタイズ（エスケープコード除去）の検証。
6. マクロ展開トレースおよび Fix-it 提案のフォーマット突合テスト。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/compiler/diagnostic.scm` が純粋 Scheme で実装され、`<diagnostic>` レコード、ソース行キャッシュ、ANSI カラー制御、スニペット・キャレット・下線描画エンジンが提供されること。
- [x] Rustc / Clang スタイルの診断出力（`error[code]: msg`, `--> file:line:col`, ガター ` | `, キャレット `^^^^`）が決定論的にレンダリングされること。
- [x] `--color=never`、`--no-color`、および `NO_COLOR` 環境変数設定時に、一切の ANSI エスケープシーケンスを含まない純粋なプレーンテキストが出力されること。
- [x] 不正な列番号、負の座標、行末超過スパンが与えられた場合でも、境界外参照例外を起こさず安全にフォールバックすること（THREAT-833-2 緩和）。
- [x] 入力ソース内の制御文字および端末エスケープコードが安全にサニタイズされて出力されること（THREAT-833-3 緩和）。
- [x] マクロ展開元（`span-macro-origin`）が存在する場合、`= note: expanded from macro ...` として展開階層が明示されること。
- [x] `ulisp/tests/test_diagnostic_reporter.scm` が作成され、全テスト項目が 100% PASS すること。
- [x] `make -C ulisp test` に上記テストが統合され、既存の全テストスイートおよび 3-Stage セルフホスティングブートストラップ検証を通過すること。
- [x] リポジトリ内の全ドキュメントにおいて、内部リンクが相対パスのみで構成されていること。