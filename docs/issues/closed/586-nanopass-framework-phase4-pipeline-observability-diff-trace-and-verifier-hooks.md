---
ID: 586
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ARCH] Nanopass Framework DSL Phase 4: パイプライン統御・AST Diff トレーサおよび不変条件 Verifier 自動フック統合 (ID: 586)

## 1. 概要 / Summary
Nanopass Framework DSL Phase 1〜3 (Issue #581, #584, #585) により、構文脱糖（Transform Pass）、エリップシス・サブフォーム正規化（Normalization）、および属性文法的解析パス（Analysis Pass with Extra Values）の基盤が確立された。
コンパイラが 30 段以上の極小パス群（Nanopasses）で構成される大規模パイプラインに発展した際、最大の運用課題となるのは **「コンパイラの可観測性（Pipeline Observability）」** と **「デバッグ容易性（どのパスで意図しない S 式の変形が発生したかの即時特定）」** である。

本 Issue（Phase 4）では、Nanopass Framework の集大成として以下の **コンパイラ検証・パイプライン統御プリミティブ** を完全実装する：

1. **言語メタ情報インスペクタ＆仕様書・Mermaid自動生成器 (`language->s-expression` / `tools/generate_nanopass_docs.scm`)**:
   - 定義された各言語（`L_src`, `L_core`, 等）の生成規則・終端記号・拡張差分（`+`, `-`）をリフレクション取得するメタ API。
   - リポジトリ内の言語仕様ドキュメントおよびパイプライン全体の Mermaid 構文遷移図・系統図を完全自動生成する CLI ツール。
2. **AST Diff ステップトレーサ (`trace-define-pass` / `*nanopass-trace*`)**:
   - パス実行時の入力 AST と出力 AST を自動比較し、変更点（追加 `+`、削除 `-`、変更箇所）を ANSI カラーまたはマークダウン形式で端末にステップ表示するデバッグ専用ラッパー構文およびグローバルトレース機構。
3. **差分アサーション・不変条件自動検証フック (Invariant Verifier Hook)**:
   - `define-pass` の入口と出口に構文スキーマ検査（`nanopass-ast-valid?`）および軽量 IR Verifier (`compiler/verifier.scm`) への連携フックを自動挿入。
   - デバッグモード時（`ULISP_VERIFY_PASS=1` または `!verify` ディレクティブ）にパス境界での不変条件違反（未脱糖キーワードの残留、非アトミック式の混入等）を即座に検知し、フェイルファストに異常停止する品質保護機構。

---

## 2. トレーサビリティ / Traceability
- **先行研究系譜**:
  - Keep & Dybvig, "A Nanopass Framework for Commercial Compiler Development" (ICFP 2013 / Chez Scheme)
    - Section 2.4: "Debugging and Tracing Compiler Passes"
    - Section 4: "Language Invariants and Verifiers"
- **DSN-33 コンパイラアーキテクチャ仕様書** (第8章 パイプライン統御と検証機構)
- **関連 Issue**:
  - [581-implement-nanopass-framework-dsl-and-migrate-compiler-passes.md](581-implement-nanopass-framework-dsl-and-migrate-compiler-passes.md) (Phase 1: コア DSL 基盤)
  - [584-nanopass-framework-phase2-ellipsis-subforms-and-normalization.md](584-nanopass-framework-phase2-ellipsis-subforms-and-normalization.md) (Phase 2: エリップシス・サブフォーム)
  - [585-nanopass-framework-phase3-catamorphism-extra-values-and-analysis-passes.md](585-nanopass-framework-phase3-catamorphism-extra-values-and-analysis-passes.md) (Phase 3: Catamorphism Extra Values)
  - [closed/576-implement-lightweight-ir-verifier-framework.md](closed/576-implement-lightweight-ir-verifier-framework.md) (軽量 IR Verifier 基盤)
  - [587-extract-dsl-expansion-pass-before-macro-expander.md](closed/587-extract-dsl-expansion-pass-before-macro-expander.md) (Pass 015 DSL 先行展開)
  - [589-establish-canonical-lir-specification-and-boundary-validator.md](589-establish-canonical-lir-specification-and-boundary-validator.md) (Canonical LIR 境界検証)
- **関連ファイル**:
  - [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm) (構文マクロ展開器)
  - [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm) (メタ情報・差分・リフレクションエンジン)
  - [ulisp/compiler/verifier.scm](../../ulisp/compiler/verifier.scm) (IR Verifier 実体)
  - [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (コンパイラドライバ・CLI)
  - [ulisp/tools/generate_nanopass_docs.scm](../../ulisp/tools/generate_nanopass_docs.scm) (ドキュメント・Mermaid生成スクリプト)
  - [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm) (フレームワーク単体テスト)
  - [ulisp/tests/test_nanopass_tracer.scm](../../ulisp/tests/test_nanopass_tracer.scm) (トレーサ・Verifier Hook 単体テスト)

---

## 3. セキュリティ / 脅威モデル分析 (Threat Model)
- **AST 破壊・型不変条件違反によるメモリ破壊の防止 (Integrity & Memory Safety)**:
  - コンパイラの中間パスで AST の一部が破損、未脱糖マクロが残留、または期待される型表現から逸脱した場合、バックエンドのネイティブアセンブリ生成器（x86-64 / AArch64 / C）が誤った命令列や境界チェック漏れのコードを出力し、生成バイナリにバッファオーバーフローや型混乱（Type Confusion）等の致命的脆弱性をもたらす恐れがある。
  - **対策**: パス境界での自動 Verifier Hook により、入力および出力 AST が宣言された言語仕様（`L_in`, `L_out`）および IR 不変条件に 100% 合致していることを機械的に強制し、不正な構文を後続パスへ一切伝播させない。
- **トレース出力における DoS（リソース枯渇）防止 (Availability)**:
  - 巨大な AST や再帰構造を含むプログラムのコンパイル時に、全 AST を無制限にインメモリ差分比較・標準出力すると、極端なメモリ消費やコンパイル時間の指数関数的増大（ReDoS 類似現象）を招くリスクがある。
  - **対策**: AST Diff 計算器に深さ制限（Depth Clipping）および最大表示ノード数のリミッターを実装し、安定した O(N) 計算量を保証。
- **ゼロオーバーヘッド原則 (Zero-Cost Abstraction in Production)**:
  - リリースビルドや本番コンパイル時にトレースや検証フックのオーバーヘッドが残留するとコンパイル性能が低下する。
  - **対策**: `*nanopass-trace*` および `*nanopass-verifier-enabled*` の判定を高速な述語フラグで短絡評価し、非デバッグ時の実行コストをゼロ化。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm):
  - `trace-define-pass` マクロ構文の定義
  - `define-pass` 展開コードへの Verifier Hook 自動挿入機構（`nanopass-wrap-verifier`）の実装
- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm):
  - AST 木構造差分比較関数 `nanopass-ast-diff` の実装
  - 差分の ANSI カラー表示フォーマッタ `nanopass-display-ast-diff` の実装
  - 言語メタ情報問い合わせ API `language-declaration` / `language-all-productions` の拡張
- [ ] [ulisp/compiler/verifier.scm](../../ulisp/compiler/verifier.scm):
  - Nanopass スキーマ検証（`nanopass-ast-valid?`）と既存の pass-specific verifier を統合した `nanopass-verify-pass-data` の実装
  - フェイルファストな詳細エラーレポート出力ルーチンの整備
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm):
  - `--trace-passes` / `!trace` ディレクティブの解析と `*nanopass-trace*` への配線
  - `!verify` ディレクティブと Nanopass 自動検証フックの連動
- [ ] [ulisp/tools/generate_nanopass_docs.scm](../../ulisp/tools/generate_nanopass_docs.scm):
  - 全登録言語のメタ情報を走査し、仕様書 Markdown および Mermaid 構文遷移図を出力するツールの新規作成
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm):
  - `language->s-expression` および言語メタ情報取得の回帰テスト追加
- [ ] [ulisp/tests/test_nanopass_tracer.scm](../../ulisp/tests/test_nanopass_tracer.scm):
  - AST Diff 計算、カラー表示、および Verifier Hook による不正構文検知の網羅的テスト追加

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks`

### Step 1: 言語メタ情報リフレクション＆ドキュメント生成器の実装
1. **リフレクション API の拡充 (`ulisp/compiler/nanopass_meta.scm`)**:
   - `(nanopass-get-all-languages)`: 登録済みの全言語レコードのリストを返却。
   - `(language-declaration 'L_name)`: 親言語、追加・削除されたプロダクション、終端記号リストを構造化 S 式で返却。
   - `(language-parent-chain 'L_name)`: 継承ツリーのルートから当該言語までの階層リストを算出。
2. **自動ドキュメント生成ツール (`ulisp/tools/generate_nanopass_docs.scm`)**:
   - コマンドライン実行により `docs/nanopass_spec.md` を生成。
   - 各中間言語の構文定義一覧表および言語間の派生関係（`extends`）を表す Mermaid `graph TD` 構文遷移図を出力。

### Step 2: AST Diff 比較器とカラートレーサの実装
1. **構造的 AST Diff エンジン (`ulisp/compiler/nanopass_meta.scm`)**:
   - `(nanopass-ast-diff old-ir new-ir)`:
     - 2 つの S 式ツリーを再帰的に比較。
     - 等価ノードはスキップし、変更ノードを `(diff:modified old new)`、追加ノードを `(diff:added new)`、削除ノードを `(diff:removed old)` として差分ツリーを構築。
2. **差分フォーマッタ & ステップトレーサ**:
   - `(nanopass-display-ast-diff pass-name old-ir new-ir)`:
     - ANSI エスケープシーケンス（緑: 追加, 赤: 削除, シアン: パス境界）を用いて端末の標準エラー出力（stderr）に出力。
     - 出力例:
       ```
       --- [PASS: desugar-cond] ------------------------
       - (cond ((= x 1) 10) (else 20))
       + (if (= x 1) (begin 10) (begin 20))
       ------------------------------------------------
       ```
3. **`trace-define-pass` マクロ構文 (`ulisp/compiler/nanopass.scm`)**:
   - `(trace-define-pass pass-name ...)` を `define-pass` と同等の構文として提供し、実行時に入力・出力および AST Diff を自動表示するラッパーを合成。

### Step 3: 不変条件 Verifier 自動フック機構の実装
1. **透過的 Verifier ラッパー合成 (`ulisp/compiler/nanopass.scm`)**:
   - `nanopass-expand-define-pass` を改修し、展開されるエントリポイントプロシージャの前後を `nanopass-verify-guard` でラップ：
     ```scheme
     (define (pass-name ir . extra)
       (when (nanopass-verifier-enabled?)
         (nanopass-verify-entry 'pass-name 'L_in ir))
       (let ((res (actual-pass-body ir . extra)))
         (when (nanopass-verifier-enabled?)
           (nanopass-verify-exit 'pass-name 'L_out res))
         res))
     ```
2. **IR Verifier との相互連携 (`ulisp/compiler/verifier.scm`)**:
   - 言語スキーマ適合性（`nanopass-ast-valid?`）に加えて、Pass 030 (Desugar), Pass 070 (ANF), Pass 110 (Closure), Pass 130 (LIR) の特定不変条件チェッカーを自動呼び出し。
   - 不適合検知時は `(verifier-error 'pass-name "Schema/Invariant violation" ir)` を呼び出し、即座にコンパイルを安全にアボート。

### Step 4: コンパイラドライバおよび CLI オプション統合
1. **ドライバ改修 (`ulisp/compiler/driver.scm`)**:
   - 入力ディレクティブ `!trace` または CLI オプション `--trace-passes` により `(enable-nanopass-trace!)` を設定。
   - `!verify` ディレクティブと `(enable-nanopass-verifier!)` を連動。
   - トレースモード時は全パスの AST Diff がステップ実行順に標準エラー出力へストリーム表示されるよう統合。

### Step 5: テストスイート拡充 & 検証
1. **新設テスト (`ulisp/tests/test_nanopass_tracer.scm`)**:
   - `nanopass-ast-diff` による原子値・リスト・ネスト木構造の差分検出精度テスト。
   - `trace-define-pass` の実行と出力フォーマット検証。
   - 不正構文を意図的に出力するパスを定義し、Verifier Hook が例外を捕捉してフェイルファストに停止することの検証。
2. **既存テストへの回帰確認**:
   - `make -C ulisp test_nanopass`
   - `make -C ulisp test_all_passes`
   - `make -C ulisp bootstrap_verify` (3-Stage 固定点検証)

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `language->s-expression` および `language-declaration` により、登録言語のメタ情報（終端記号・非終端規則・キーワード・削除規則）が S 式で完全に取得できること
- [x] `tools/generate_nanopass_docs.scm` により、登録言語仕様の Markdown および Mermaid 構文遷移図が完全自動生成できること
- [x] `nanopass-ast-diff` が正しく変更箇所を検出し、`trace-define-pass` または `!trace` 有効時に ANSI カラーで差分が表示されること
- [x] `define-pass` に Verifier Hook が透過的に埋め込まれ、`ULISP_VERIFY_PASS=1` または `!verify` 時に不正構文（仕様外の S 式）を即座に検知して停止すること
- [x] 新設テスト `ulisp/tests/test_nanopass_tracer.scm` を含む全テスト（`make -C ulisp test_nanopass`）が 100% PASS すること
- [x] 全パス単体テスト（`make -C ulisp test_all_passes` または `test_passes`）が 100% PASS すること
- [x] 3-Stage Bootstrap 固定点検証（`make -C ulisp bootstrap_verify`）が完全一致（bit-for-bit identical）で PASS すること
- [x] すべてのファイル参照およびドキュメント内リンクにおいて、相対パスのみが使用され絶対パスが含まれないこと
