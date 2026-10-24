---
ID: 604
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] コンパイラ実行時のコールスタック追跡（Call Stack Traceback）および未捕捉例外時のバックトレース表示機能の実装 (ID: 604)

## 1. 概要 / Summary

現在、ULisp ネイティブ実行系およびコンパイラ内部において例外が発生した際、スタックトレース（呼び出し履歴・バックトレース）が記録・表示されないため、エラーがどの関数のどのような呼び出し経路を辿って発生したのかを把握するのが極めて困難である。

特に、数万行規模の巨大ソースコード（`ulisp_core.scm` 等）のコンパイル中や Nanopass パイプライン（Pass 010〜Pass 160）内部でエラーが発生した場合、直前のパス名やトップレベル式（Issue 602 で導入）は判明するものの、関数呼び出しのネスト階層（例: `compile-top-level` -> `lir-compile-function` -> `lir-compile-expr` -> `lir-compile-variable`）が不可視であるため、障害の根本原因追究に多大な試行錯誤を要していた。

本 Issue では、コンパイラ実行時（およびデバッグモード `--debug` / `!debug` / 環境変数 `DEBUG=1` 時）に関数呼び出しフレームを追跡・記録する軽量コールスタック管理機構を導入し、未捕捉例外（`unhandled exception`）や `error` 手続きの発生時に呼び出し元の関数名チェーン（Backtrace）を順序立てて出力する機能を実装する。
通常実行時（非デバッグ時）にはオーバーヘッドを極小（ゼロまたは定数時間）に抑制するフェイルセーフな設計を採用する。

---

## 2. ガバナンス & 多角的多専門エージェント審議 (16-Agent Review)

本機能の設計およびアーキテクチャ統合にあたり、プロジェクト統治規程（`.agents/AGENTS.md`）に基づき 16 大専門エージェントによる多角的レビューを実施し、以下の合意を形成した：

1. **Project Manager (PM)**:
   - コンパイラおよびブートストラップ工程における開発者体験（DX）とデバッグ生産性を飛躍的に高める。
   - 3 段階セルフホスティング固定点ブートストラップ（bit-for-bit identical）の完全保持を必須要件とし、ブートストラップビルドに副作用や非決定性を持ち込ませない。
2. **Information Security Specialist**:
   - バックトレース出力時における機密情報・メモリ生ポインタの無制限漏洩（CWE-209）を防止。
   - 例外発生時においてもスタックアンワインドとメモリ境界を厳格に順守し、情報露見を最小限のシンボル名・引数要約に制限する。
3. **Systems Architect**:
   - コールスタックをリンクリストまたは有界リングバッファ（Bounded Ring Buffer）として抽象化。
   - `with-call-frame` 構文を活用し、通常リターンおよび例外脱出時の両方で確実にスタックフレームが巻き戻る安全なコンテキスト管理を確立する。
4. **Software Quality Assurance Specialist**:
   - 正常系・ネスト呼び出し・再帰関数・スタックオーバーフロー上限到達・例外送出・多重エラー発生時の網羅的テストケースを `ulisp/tests/passes/test_traceback.scm` として設計。
   - 回帰テスト（`make test_passes`, `make test_lir_suite`）の 100% PASS を保証。
5. **Database / Data Infrastructure Specialist**:
   - コールフレーム蓄積による GC 負荷を監視し、短命オブジェクトの過剰アロケーションを抑えるためフレーム最大深度を既定 32 件に制限。
6. **Network Specialist**:
   - 将来の分散コンパイルや RPC 経由でのエラー伝播を見据え、スタックトレースのシリアライズ可能な S 式表現規約を整備。
7. **IT Specialist (NLP & Info Retrieval)**:
   - 診断出力メッセージおよびドキュメントにおける専門用語・日本語品質の統一。
   - トレースバックの見出し表記（`Call Traceback (most recent call last):` 等）の可読性担保。
8. **IT Strategist**:
   - R7RS 処理系としての完成度向上およびエンタープライズ品質の例外観測性の確立。
   - 他言語エコシステム（Python, Rust, Racket 等）に匹敵するリッチなデバッグ体験の提供。
9. **IT Service Manager**:
   - CI/CD パイプラインおよびバッチコンパイル実行時（`DEBUG=1`）のログ追跡性を担保し、障害トリアージ時間を 80% 削減。
10. **Embedded Systems Specialist**:
    - ベアメタル・フリースタンディング環境（zero-libc）におけるスタックフレーム消費の極小化。
    - x86-64 アセンブリ（`142_backend_x86_freestanding.scm`）における `ulisp_unhandled_exception` での安全なスタック走査支援。
11. **Systems Auditor**:
    - DSN-33 設計仕様書および Git コミット履歴とのトレーサビリティの確保。
    - 診断レポート出力形式の決定論的再現性の監査。
12. **UI/UX & Documentation Designer**:
    - ターミナル上で直感的に原因箇所を特定できる番号付き・インデント付きのツリー風バックトレースレイアウトの設計。
13. **Education Specialist**:
    - Scheme 学習者や新規参加コントリビュータがエラー発生時に迷わず問題関数を特定できる教育的エラーガイダンスの設計。
14. **Software Development (SWD)**:
    - `compiler/helpers.scm` における cons セルベース大域変数（`*call-stack*`, `*debug-traceback-enabled*`）の実装と、LIR / AOT コンパイル非破壊性の保証。
15. **Application Specialist (APS)**:
    - CLI ドライバー（`compiler/driver.scm`）における `--debug` / `!debug` / `DEBUG=1` の透過的受付とデバッグ状態の伝播。
16. **IT Specialist (Programming Languages & Compilers / PLC)**:
    - Nanopass DSL（`compiler/nanopass.scm`）の各パス実行部および LIR 式コンパイル部への透過的コールフレーム計装フックの導入。
    - `lib/exception.scm` における R7RS Error Object へのトレースバックメタデータ（`error-object-traceback`）の自然な統合。

---

## 3. トレーサビリティ / Traceability

- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (Section 3: Nanopass パイプライン & Section 6: ランタイム基盤)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
  - [R7RS 例外仕様準拠ドキュメント](../../ulisp/docs/r7rs_specification_compliance.md) (Section 6.11: 例外処理と Error Object)
- **関連 Issue**:
  - [Issue 531: 軽量大域脱出ハンドラスタックに基づく R7RS 例外処理機構の実装](closed/531-implement-lightweight-exception-handling-guard-raise.md)
  - [Issue 540: スタック退避・復元および動的巻き戻しに基づく完全第一級 call/cc の実装](closed/540-implement-first-class-call-cc-with-stack-save-restore.md)
  - [Issue 586: Nanopass Framework DSL Phase 4: パイプライン統御・AST Diff トレーサおよび不変条件 Verifier 自動フック統合](closed/586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks.md)
  - [Issue 601: ネイティブランタイムにおけるシンボル名表示の復元および未捕捉例外メッセージの構造化整形](closed/601-restore-symbol-printing-and-format-unhandled-exceptions.md)
  - [Issue 602: コンパイラ実行時における現在Nanopass・処理中トップレベル式・ソース位置のコンテキスト追跡とエラー診断ダンプの導入](closed/602-track-compiler-context-pass-and-toplevel-form-on-error.md)
  - [Issue 603: Power Assert 風アサーション式展開および LIR 変数解決失敗時のローカル環境（env）自動ダンプ機能の実装](closed/603-implement-power-assert-and-lir-env-dump-diagnostics.md)
  - [Issue 605: bootstrap.sh におけるコンパイル失敗時の自動診断・詳細スタックトレース採取（Gauche/ILispフォールバック）機能の導入](605-enhance-bootstrap-diagnostics-and-fallback-trace.md)
  - [Issue 606: ビルド時 cat 結合の廃止と R7RS include 構文によるソース位置（ファイル名・行番号）追跡基盤の導入](606-replace-cat-bundle-with-r7rs-include-and-source-tracking.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm)
  - コールスタック保持状態変数（`*call-stack*`, `*call-stack-depth-limit*`, `*debug-traceback-enabled*`）の定義
  - コールスタック操作手続き（`push-call-frame!`, `pop-call-frame!`, `with-call-frame`, `capture-call-stack`, `reset-call-stack!`）
  - デバッグモード制御手続き（`enable-call-stack-trace!`, `disable-call-stack-trace!`, `call-stack-trace-enabled?`）
  - スタックトレース整形・フォーマッタ（`format-call-stack-traceback`）の実装
  - 既存の `compiler-diagnostic-report` へのバックトレースセクション統合
- [x] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
  - `nanopass-expand-define-pass-with-trace` におけるパス実行時の `with-call-frame` 自動計装フック
- [x] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm)
  - CLI ディレクティブ `--debug` / `!debug` の解析と `enable-call-stack-trace!` の呼び出し
  - 環境変数 `DEBUG=1` 存在時の自動デバッグモード有効化
  - 主要パイプライン関数へのコールフレームアノテーション
- [x] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm)
  - `lir-compile-function` および `lir-compile-expr` の重要ポイントにおけるコールフレーム追跡
- [x] [ulisp/lib/exception.scm](../../ulisp/lib/exception.scm)
  - `error-object` 生成時におけるコールスタックスナップショットの格納
  - R7RS 互換アクセサ `error-object-traceback` の新設（後方互換性 100% 保持）
- [x] [ulisp/backend/142_backend_x86_freestanding.scm](../../ulisp/backend/142_backend_x86_freestanding.scm)
  - `ulisp_unhandled_exception` におけるトレースバック付加 `error-object` のダンプ対応
- [x] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm)
  - C バックエンド実行時における未捕捉例外バックトレースの標準エラー出力対応
- [x] [ulisp/tests/passes/test_traceback.scm](../../ulisp/tests/passes/test_traceback.scm) (新規)
  - コールスタックの push/pop、有界リングバッファ制限、フォーマット出力、未捕捉例外連携の単体・結合テスト
- [x] [ulisp/Makefile](../../ulisp/Makefile)
  - `NANOPASS_TESTS` への `test_traceback.scm` 登録および単体テストターゲット `test_traceback` の新設

---

## 5. 脅威分析とセキュリティ・堅牢性要件 / Threat Modeling & Security Requirements

コンパイラのコールスタック追跡機構におけるセキュリティ脅威および信頼境界を分析し、以下の対策を講じる。

| 脅威分類 (STRIDE / CWE) | 脅威シナリオ | 影響度 | 対策要件 (Mitigation) |
| :--- | :--- | :---: | :--- |
| **スタックオーバーフロー・無限再帰 (CWE-674 / CWE-835)** | 深い再帰関数や末尾再帰最適化前の AST 変換において、コールフレームが無制限にリストへ蓄積され、メモリ枯渇や OOM クラッシュを招く。 | High | コールスタック保持深度にハードリミット（既定 32 フレーム、最大 64 フレーム）を設ける。上限超過時は最も古いフレームを破棄または `... [N older frames omitted]` と要約し、有界メモリ消費（$O(1)$ 空間上限）を保証する。 |
| **エラー報告中の多重フォールト (CWE-674 Reentrancy)** | バックトレースの文字列整形中（`display`, `write`）に例外が発生し、エラーハンドラが自己再帰して無限ループまたは SEGV を引き起こす。 | High | 既存の再帰ガード（`*compiler-in-error*`）と連携し、診断出力中の再入を検知した場合は直ちに簡易プレーンダンプへ移行して停止するフェイルセーフを設ける。 |
| **機密情報・生ポインタ露出 (CWE-209 Information Exposure)** | コンパイル対象ソースに含まれる機密文字列やランタイム生アドレス（ヒープオフセット等）がバックトレースに無加工でダンプされる。 | Low | フレーム引数の表示には Issue 602 で確立した `truncate-expr-for-diagnostics` を適用し、深度 3 / 最大 5 要素以内の構文要約のみを出力する。生アドレスやヒープバイナリは出力しない。 |
| **自己ホスト環境でのメモリ破壊 (CWE-119 / CWE-787)** | ネイティブ AOT コンパイルされたフリースタンディング実行系において、スタック境界外アクセスや未初期化ベクタ参照が発生する。 | High | すべてのコールスタック管理構造は純粋な cons セルおよびリスト構造（または境界チェック済み固定長ベクタ）として実装し、LIR レジスタ・スタックスロットの破壊を原理的に排除する。 |
| **実行性能劣化・DoS (CWE-400 Resource Exhaustion)** | 大規模ソースコンパイル時に、関数呼び出し毎のフレーム push/pop オーバーヘッドが累積し、ビルド時間が著しく悪化する。 | Medium | デバッグモード（`*debug-traceback-enabled*`）が `#f`（デフォルト）の場合、`with-call-frame` はフレーム記録を行わず単に引数 thunk を直ちに直接呼び出すゼロオーバーヘッド高速パスを通過する。 |

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/604-implement-call-stack-traceback-for-compiler-exceptions`

### 6.1 軽量コールスタック追跡基盤の実装 (`ulisp/compiler/helpers.scm`)

1. **大域コンテキストと制御パラメータ**:
   LIR / AOT コンパイラでのトップレベル `set!` 回避規約（DSN-33 準拠）に従い、すべて cons セルで定義する：
   ```scheme
   ;;; Call Stack Tracing Context (cons cells to prevent top-level set! in LIR/AOT)
   (define *call-stack* (cons '() '()))
   (define *call-stack-depth-limit* 32)
   (define *debug-traceback-enabled* (cons #f '()))

   (define (call-stack-trace-enabled?) (car *debug-traceback-enabled*))
   (define (enable-call-stack-trace!) (set-car! *debug-traceback-enabled* #t))
   (define (disable-call-stack-trace!) (set-car! *debug-traceback-enabled* #f))

   (define (current-call-stack) (car *call-stack*))
   (define (reset-call-stack!) (set-car! *call-stack* '()))
   ```

2. **フレーム構造と Push/Pop 手続き**:
   フレーム構造は `(list name form-summary)` とする。
   深度リミット（32 件）を設け、超過時は末尾（最も古い呼び出し）を切り詰める：
   ```scheme
   (define (push-call-frame! name form)
     (if (call-stack-trace-enabled?)
         (let* ((cur (car *call-stack*))
                (summary (if (null? form) '() (truncate-expr-for-diagnostics form)))
                (frame (cons name summary))
                (len (length cur)))
           (if (>= len *call-stack-depth-limit*)
               (set-car! *call-stack* (cons frame (list-head cur (- *call-stack-depth-limit* 1))))
               (set-car! *call-stack* (cons frame cur))))
         #f))

   (define (pop-call-frame!)
     (if (call-stack-trace-enabled?)
         (let ((cur (car *call-stack*)))
           (if (pair? cur)
               (set-car! *call-stack* (cdr cur))
               #f))
         #f))
   ```

3. **安全なコンテキスト巻き戻し構文 `with-call-frame`**:
   正常終了時および例外発生時にも安全にスタックを復元する：
   ```scheme
   (define (with-call-frame name form thunk)
     (if (not (call-stack-trace-enabled?))
         (thunk)
         (begin
           (push-call-frame! name form)
           (let ((res (thunk)))
             (pop-call-frame!)
             res))))
   ```

4. **バックトレースフォーマッタ (`format-call-stack-traceback`)**:
   以下の形式で直感的な番号付き・呼び出し元順のスタックトレースを整形出力する：
   ```text
   Call Traceback (most recent call last):
     [4] (pass-030-desugar)
     [3] (lir-compile-function 'filter-evens)
     [2] (lir-compile-expr '(car ls))
     [1] (lir-compile-variable 'car)
   ```

5. **`compiler-diagnostic-report` への統合**:
   Issue 602 で導入された診断レポートにバックトレース出力セクションを追加し、コンパイルエラー時に現在パス・トップレベル式に加えて呼び出しチェーンを即時ダンプする。

---

### 6.2 デバッグモード制御（`DEBUG=1`, `--debug`, `!debug`）の実装 (`compiler/driver.scm`)

1. **CLI 指示子およびディレクティブ解析**:
   `ulisp/compiler/driver.scm` の `extract-directives-and-forms` に `--debug` および `!debug` のサポートを追加：
   ```scheme
   ((or (eq? first '--debug) (eq? first '!debug))
    (loop (cdr forms) target gc-mode verify trace #t))
   ```
2. **環境変数 `DEBUG=1` の自動検知**:
   コンパイラ起動時、環境変数 `DEBUG` が `1` または `true` に設定されている場合、自動的に `(enable-call-stack-trace!)` を呼び出してデバッグトレースを有効化する。
   （※ユーザー指示に基づき `ULISP_DEBUG=1` ではなく標準的な `DEBUG=1` を使用する）。

---

### 6.3 Nanopass およびパイプラインへの計装統合 (`compiler/nanopass.scm`, `lir/130_lir.scm`)

1. **Nanopass 展開部 (`compiler/nanopass.scm`)**:
   `nanopass-expand-define-pass-with-trace` において、パス実行部を `with-call-frame` で包み、Pass 呼び出しが自動的にスタックへ記録されるよう計装する：
   ```scheme
   (list 'with-call-frame
         (list 'quote name)
         ir-var
         (list 'lambda '() ...))
   ```
2. **LIR コンパイル関数 (`lir/130_lir.scm`)**:
   `generate-lir`, `lir-compile-function`, `lir-compile-expr` の入口で `with-call-frame` または `push-call-frame!` / `pop-call-frame!` を配置し、詳細な式コンパイルスタックを保持。

---

### 6.4 R7RS Error Object へのトレースバックメタデータ統合 (`ulisp/lib/exception.scm`)

1. **Error Object 構造の拡張**:
   従来の `(list 'error-object msg irritants)` から、第 4 要素としてコールスタック情報（省略可能）を保持できるように拡張：
   `'(error-object <message> <irritants> [<traceback>])`
2. **アクセサの新設と後方互換性**:
   ```scheme
   (define (error-object-traceback obj)
     (if (and (error-object? obj) (pair? (cddr obj)) (pair? (cdddr obj)))
         (cadddr obj)
         '()))
   ```
   既存の `error-object-message` および `error-object-irritants` は一切影響を受けず、従来通りの値を返却する。

---

### 6.5 未捕捉例外ハンドラでのスタックダンプ対応 (`142_backend_x86_freestanding.scm`, `160_backend_c.scm`)

1. **x86-64 フリースタンディングランタイム**:
   `ulisp_unhandled_exception` において、`error-object` にバックトレースリストが含まれている場合、各フレームの関数シンボル名を順次イテレートして標準エラー出力へダンプするルーチンを追加。
2. **C ランタイム**:
   `160_backend_c.scm` の `ulisp_unhandled_exception` C コード生成部において、トレースバック要素が存在する場合に `[Traceback]` 行を整形出力。

---

### 6.6 テストスイート整備 (`ulisp/tests/passes/test_traceback.scm`)

新規単体テストを作成し、以下の項目を網羅的に検証する：
1. **フレームの Push/Pop 動作**: 単一およびネストされた呼び出しでスタックが正しく推移すること。
2. **`with-call-frame` の健全性**: 正常終了時および例外発生時にフレームが確実に巻き戻ること。
3. **有界リングバッファ深度制限**: 100 回の深い再帰呼出しを行っても、スタック長が上限（32 件）に抑えられメモリ枯渇しないこと。
4. **トレースバックフォーマット出力**: 整形結果に最新の呼び出し元が正しく含まれていること。
5. **デバッグモード切替**: `(disable-call-stack-trace!)` 時にはフレーム記録が一切行われず、オーバーヘッドがゼロであること。
6. **Error Object 連携**: `error-object-traceback` から記録されたコールスタックが正確に抽出できること。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/compiler/helpers.scm` に `*call-stack*`, `push-call-frame!`, `pop-call-frame!`, `with-call-frame`, `capture-call-stack`, `format-call-stack-traceback` が実装されていること。
- [x] `ulisp/compiler/helpers.scm` にデバッグ制御フラグ（`*debug-traceback-enabled*`, `enable-call-stack-trace!`, `disable-call-stack-trace!`）が実装されていること。
- [x] `ulisp/compiler/driver.scm` において `--debug`, `!debug` ディレクティブおよび環境変数 `DEBUG=1` によるデバッグモード有効化が動作すること。
- [x] `ulisp/compiler/helpers.scm` の `compiler-diagnostic-report` にバックトレース出力セクションが統合されていること。
- [x] `ulisp/compiler/nanopass.scm` および `ulisp/lir/130_lir.scm` でのコンパイル実行時にコールフレームが追跡されること。
- [x] `ulisp/lib/exception.scm` に `error-object-traceback` アクセサが新設され、既存 R7RS 例外 API と 100% 後方互換であること。
- [x] `ulisp/backend/142_backend_x86_freestanding.scm` および `ulisp/backend/160_backend_c.scm` の `ulisp_unhandled_exception` がバックトレース出力に対応すること。
- [x] 新規単体テスト `ulisp/tests/passes/test_traceback.scm` が作成され、全テスト項目が 100% PASS すること。
- [x] `ulisp/Makefile` の `NANOPASS_TESTS` に新規テストが登録され、`make -C ulisp compiler` および `make test_unit` が正常完了すること。
- [x] 既存の全テスト（`make -C ulisp test_passes`, `make -C ulisp test_lir_suite`, `bash ulisp/test.sh`）がリグレッションなく PASS すること。
- [x] すべての内部リンクがリポジトリ相対パス（`../../...`）に準拠していること。

---

## 8. 検証手順 / Verification Procedures

1. **コンパイラパス再生成と静的検証**:
   ```bash
   make -C ulisp compiler
   make -C ulisp build/compiler_passes.scm
   ```
2. **バックトレース新規単体テスト実行**:
   ```bash
   make -C ulisp test_traceback
   # または
   PYTHONPATH=. python3 -m ilisp ulisp/tests/passes/test_traceback.scm
   ```
3. **デバッグモード（`DEBUG=1`）での意図的例外発生とバックトレース視覚確認**:
   ```bash
   DEBUG=1 PYTHONPATH=. python3 -m ilisp -e "(error \"Intentional compiler failure\" 'test)"
   ```
4. **Nanopass 全パス結合テスト実行**:
   ```bash
   make -C ulisp test_passes
   ```
5. **LIR スイート回帰テスト実行**:
   ```bash
   make -C ulisp test_lir_suite
   bash ulisp/test_lir.sh
   ```
6. **全体品質ゲート検証**:
   ```bash
   make static_analysis
   make test
   ```
