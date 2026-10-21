---
ID: 587
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/REFACTOR] Nanopass DSL展開パスの先行分離 (Pass 015) によるマクロ展開器決め打ちの完全排除 (ID: 587)

## 1. 概要 / Summary

現在、`ulisp/passes/020_macro_expander.scm` において、Nanopass DSL フォーム（`define-language`, `define-pass`, `define-parser`, `define-unparser`）およびホスト専用の `define-macro` を特定シンボルとしてハードコードし、マクロ展開走査からスキップ（決め打ち除外）していた。

この理由は、Pass 020 が純粋な `syntax-rules`（パターン置換）展開器であり手続き型マクロを展開できないため、後続の Pass 025（`rewrite-top-level`）で展開するまでの間、文法パターン規則（`...`, `.` ドットペア, `,x` 等）を通常の「Scheme 式」と誤認して破壊しないための防衛的バイパス措置であった。同様に、Pass 025 でも `define-language`, `define-pass`, `define-parser`, `define-unparser` および `define-macro` のハンドリングが混在し、トップレベル定義巻き上げ（`define` の抽出と `%program` 構造化）の単一責務が損なわれていた。

しかし、汎用マクロ展開器が特定コンパイラDSLの構文名をハードコードして抱え込むことは、関心の分離（Separation of Concerns）および直交性に反する。また、Pass 020 が Nanopass DSL 展開よりも前に動作しているため、DSL 展開によって生成されたコード内で `syntax-rules` マクロを活用することができないという制約もあった。

本 Issue では、パイプライン構成を再編し、**「DSL 展開処理（Pass 015: `expand-dsl-forms`）をマクロ展開（Pass 020）の直前に実行する」** アーキテクチャへ移行した。これにより：
1. Pass 020（衛生的マクロ展開器）から DSL 固有シンボルのハードコード決め打ち判定およびホスト専用マクロ除外処理を完全に撤廃した。
2. Pass 025（トップレベル巻き上げ）から DSL 展開責務を切り離し、トップレベル定義の標準化と `%program` AST 構築へ純化させた。
3. DSL が展開した標準 Scheme コード（`define`, `lambda`, `syntax-rules` 等）を後続の Pass 020 で自然にマクロ展開可能とした。

---

## 2. トレーサビリティ / Traceability

- **アーキテクチャ仕様**:
  - DSN-33 コンパイラアーキテクチャ仕様書 (Pass 010〜Pass 160)
  - Keep & Dybvig (2013) *A Nanopass Framework for Compiler Education*
- **関連 Issue**:
  - [581-implement-nanopass-framework-dsl-and-migrate-compiler-passes.md](581-implement-nanopass-framework-dsl-and-migrate-compiler-passes.md) (Nanopass DSL Phase 1)
  - [584-nanopass-framework-phase2-ellipsis-subforms-and-normalization.md](584-nanopass-framework-phase2-ellipsis-subforms-and-normalization.md) (Nanopass DSL Phase 2)
  - [../585-nanopass-framework-phase3-catamorphism-extra-values-and-analysis-passes.md](../585-nanopass-framework-phase3-catamorphism-extra-values-and-analysis-passes.md) (Nanopass DSL Phase 3)
  - [588-fix-and-syntax-desugaring-unbound-variable-in-lir.md](588-fix-and-syntax-desugaring-unbound-variable-in-lir.md) (Reader Quasiquote / And Desugar Fix)
  - [570-refactor-canonical-intermediate-representation-and-pipeline-decoupling.md](570-refactor-canonical-intermediate-representation-and-pipeline-decoupling.md) (Pass 025 Top-Level Lifting)
- **対象ソースコード & テスト**:
  - [ulisp/passes/015_dsl_expander.scm](../../../ulisp/passes/015_dsl_expander.scm) (新規)
  - [ulisp/passes/020_macro_expander.scm](../../../ulisp/passes/020_macro_expander.scm) (修正)
  - [ulisp/passes/025_top_level.scm](../../../ulisp/passes/025_top_level.scm) (修正)
  - [ulisp/compiler/driver.scm](../../../ulisp/compiler/driver.scm) (修正)
  - [ulisp/Makefile](../../../ulisp/Makefile) (修正)
  - [ulisp/tests/passes/test_015_dsl_expander.scm](../../../ulisp/tests/passes/test_015_dsl_expander.scm) (新規)
  - [ulisp/docs/pipeline_architecture.md](../../../ulisp/docs/pipeline_architecture.md) (ドキュメント更新)

---

## 3. 脅威分析とセキュリティ・堅牢性要件 / Threat Modeling & Security

1. **入力境界 (Input Boundary)**:
   - 外部ソースから入力された不正または悪意のある S 式（極端に深いネスト、循環リスト、不正な DSL キーワード使用）。
   - **対策**: `expand-dsl-forms` は入力の検証を行い、DSL フォームの引数構文不正時に明確なエラーメッセージを出力する。循環構造は `read` 時点および走査フェーズで適切に検出・拒絶される。
2. **名前空間衝突・シンボル漏洩 (Namespace Collision & Symbol Capture)**:
   - Pass 015 の Nanopass DSL 展開時に生成される構文解析・逆パース補助関数や引数シンボルが、ユーザーコードのトップレベルシンボルと衝突するリスク。
   - **対策**: DSL 展開器（`compiler/nanopass.scm`, `compiler/nanopass_meta.scm`）が生成する内部識別子はプレフィックス付きユニークシンボル（`unique-symbol`）を使用し、後続の Pass 020 衛生性カウンタ（`__hyg_`）とも直交性を維持する。
3. **ホスト専用マクロ (`define-macro`) のリーク防止**:
   - ホスト Scheme (Gauche / ilisp) 向けに定義された `define-macro` が AOT コンパイル対象パイプラインへ混入し、未定義プリミティブ例外を引き起こすリスク。
   - **対策**: Pass 015 で `define-macro` を完全に検出し破棄（フィルタリング）することで、下流パスへ一切流出させない。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/passes/015_dsl_expander.scm](../../../ulisp/passes/015_dsl_expander.scm) (新規: Nanopass DSL 手続き型先行展開パス)
- [x] [ulisp/passes/020_macro_expander.scm](../../../ulisp/passes/020_macro_expander.scm) (DSL 固有シンボル判定および `define-macro` 判定の完全撤廃)
- [x] [ulisp/passes/025_top_level.scm](../../../ulisp/passes/025_top_level.scm) (DSL 展開および `define-macro` 判定の削除に伴う `%program` 構造化の純化)
- [x] [ulisp/compiler/driver.scm](../../../ulisp/compiler/driver.scm) (コンパイラ直列ドライバへの Pass 015 結線: `ast015 (expand-dsl-forms ast010)`)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (`PASSES_LIB` への追加、`NANOPASS_TESTS` への `test_015_dsl_expander.scm` 登録、33 パスへの更新)
- [x] [ulisp/tests/passes/test_015_dsl_expander.scm](../../../ulisp/tests/passes/test_015_dsl_expander.scm) (新規: Pass 015 単体テストスイート)
- [x] [ulisp/docs/pipeline_architecture.md](../../../ulisp/docs/pipeline_architecture.md) (パイプライン図およびパス解説の更新)
- [x] [ulisp/compiler.scm](../../../ulisp/compiler.scm) (統合コンパイラの再生成)

---

## 5. 実装方針 / Implementation Plan

Target Branch: `refactor/587-extract-dsl-expansion-pass-before-macro-expander`

### Step 1: Pass 015 (`ulisp/passes/015_dsl_expander.scm`) の新設
- トップレベル手続き `(define (expand-dsl-forms forms) ...)` を定義。
- 入力 `forms` のトップレベル式群を反復走査：
  1. `(begin . rest)`: フラットに展開し再帰的に走査。
  2. `(define-macro . _)`: ホスト専用マクロ定義として破棄（無視）。
  3. `(define-language . _)`: `(nanopass-expand-define-language f)` を呼び出し、結果（`begin` 等）をフォーム列へスプライス。
  4. `(define-pass . _)`: `(nanopass-expand-define-pass f)` を呼び出し、結果をスプライス。
  5. `(define-parser . _)`: `(nanopass-expand-define-parser f)` を呼び出し、結果をスプライス。
  6. `(define-unparser . _)`: `(nanopass-expand-define-unparser f)` を呼び出し、結果をスプライス。
  7. その他すべての式: そのまま保持して後続へ渡す。

### Step 2: Pass 020 (`ulisp/passes/020_macro_expander.scm`) の純化
- `macro-expand-all` 内の以下のハードコード比較を削除：
  ```scheme
  ;; 削除前:
  ((or (eq? (car expanded) (quote quote))
       (eq? (car expanded) 'define-language)
       (eq? (car expanded) 'define-pass)
       (eq? (car expanded) 'define-parser)
       (eq? (car expanded) 'define-unparser))
   expanded)
  ;; 修正後:
  ((eq? (car expanded) (quote quote))
   expanded)
  ```
- `expand-macros-in-forms` 内の `define-macro` スキップ分岐を削除：
  ```scheme
  ;; 削除:
  ((and (pair? f) (eq? (car f) 'define-macro))
   (loop (cdr fs) macro-table res))
  ```

### Step 3: Pass 025 (`ulisp/passes/025_top_level.scm`) の純化
- `rewrite-top-level` から DSL 展開節および `define-macro` 節を削除：
  - `define-macro` 分岐を削除。
  - `define-language`, `define-pass`, `define-parser`, `define-unparser` の展開呼び出し分岐をすべて削除。
- `rewrite-top-level` は `begin`、`define-record-type`、`define`、および通常式群のみを純粋に処理し、`%program` を構築する。

### Step 4: パイプラインドライバの更新 (`ulisp/compiler/driver.scm`)
- `ast010` と `ast020` の間に `ast015` を追加：
  ```scheme
  (let* ((ast010     (desugar-libraries-and-imports forms))
         (ast015     (expand-dsl-forms ast010))
         (ast020     (expand-macros-in-forms ast015))
         (ast025     (rewrite-top-level ast020))
         (ast030     (desugar-all ast025))
         ...)
  ```

### Step 5: ビルドスクリプトおよび単体テストスイートの整備
- `ulisp/Makefile`:
  - `PASSES_LIB` に `passes/015_dsl_expander.scm` を `passes/010_library.scm` の直後に追加。
  - `NANOPASS_TESTS` に `tests/passes/test_015_dsl_expander.scm` を追加。
  - テスト実行メッセージを「33 Passes」に更新。
- `ulisp/tests/passes/test_015_dsl_expander.scm` の作成：
  - `define-language` / `define-pass` / `define-parser` / `define-unparser` の展開検証。
  - `define-macro` のフィルタリング（消去）検証。
  - ネストされた `begin` のスプライス検証。
  - 通常の `define` およびトップレベル式の透過的保持検証。

### Step 6: 統合コンパイラ再生成 & 3-Stage Bootstrap 固定点検証
- `make -C ulisp compiler` で `compiler.scm` を再生成。
- `make -C ulisp test_all_passes`（全 33 単体テスト）を実行。
- `make -C ulisp test_nanopass` を実行。
- `make -C ulisp bootstrap_verify` で Stage 2 と Stage 3 のビット完全一致（Fixed-Point Convergence）を検証。
- `make -C ulisp test` および `make -C ulisp test_c` を実行。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/passes/015_dsl_expander.scm` が新設され、`expand-dsl-forms` が正常に機能すること
- [x] `ulisp/passes/020_macro_expander.scm` から `define-language`, `define-pass`, `define-parser`, `define-unparser`, `define-macro` のハードコードが 0 件になること
- [x] `ulisp/passes/025_top_level.scm` から `define-language`, `define-pass`, `define-parser`, `define-unparser`, `define-macro` の処理が 0 件になること
- [x] `ulisp/tests/passes/test_015_dsl_expander.scm` が新規作成され、単体テストが 100% PASS すること
- [x] `make -C ulisp test_all_passes`（全 33 パス単体テスト）が 100% PASS すること
- [x] `make -C ulisp test_nanopass` が 100% PASS すること
- [x] `make -C ulisp bootstrap_verify` で Stage 2 と Stage 3 の差分が 0 バイト（Fixed-Point OK）であること
- [x] `make -C ulisp test` (x86_64 AOT) および `make -C ulisp test_c` (C Backend) が全件 PASS すること
- [x] `ulisp/docs/pipeline_architecture.md` に Pass 015 が反映されていること
- [x] すべてのファイル内リンクで相対パスのみが使用されていること
