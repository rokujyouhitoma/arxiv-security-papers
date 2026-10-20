---
ID: 584
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ARCH] Nanopass Framework DSL Phase 2: エリップシス反復展開 (Ellipsis) とサブフォーム局所ハンドラ (in-context) の実装および正規化パス移行 (ID: 584)

## 1. 概要 / Summary
Nanopass Framework DSL Phase 1 (Issue #581) では、中核マクロ基盤（`define-language`, `define-pass`, `terminals`, `entry`, `nongenerative-id`, `extends`, `guard`, `define-parser`, `define-unparser`）と Pass 026〜030 の脱糖パス移行を実現する。

本 Issue（Phase 2）では、より高度で複雑な構文木を扱うために不可欠となる以下の 2 大マクロ変換エンジンを実装する：
1. **サブフォーム局所ハンドラ (`in-context`)**:
   - トップレベル式（`Program`）、大域定義（`Def`）、式（`Expr`）、文（`Stmt`）、左辺値（`LValue`）など、1 つのパス内で異なる非終端記号の再帰処理を同一パス内に局所化して多段ハンドリングする機構。
2. **エリップシス反復展開プリミティブ (`...`)**:
   - `([,x* ,e*] ...)` のような複数リストの並行アンパック、可変長スプライス再構築、および多重ネストした反復構文（`... ...`）の展開深度を正確に追跡・分配するマクロパターンエンジン。

これらを基盤として、トップレベル展開および式正規化パス群（Pass 010_library, Pass 025_top_level, Pass 070_anf）を Nanopass DSL へ刷新・移行する。

---

## 2. トレーサビリティ / Traceability
- 先行研究系譜: Keep & Dybvig, "A Nanopass Framework for Commercial Compiler Development" (ICFP 2013 / Chez Scheme)
- DSN-33 コンパイラアーキテクチャ仕様
- 関連 Issue:
  - [581-implement-nanopass-framework-dsl-and-migrate-compiler-passes.md](581-implement-nanopass-framework-dsl-and-migrate-compiler-passes.md) (Phase 1)
  - [585-nanopass-framework-phase3-catamorphism-extra-values-and-analysis-passes.md](585-nanopass-framework-phase3-catamorphism-extra-values-and-analysis-passes.md) (Phase 3)
  - [586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks.md](586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks.md) (Phase 4)
- 関連ファイル:
  - [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
  - [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
  - [ulisp/passes/010_library.scm](../../ulisp/passes/010_library.scm)
  - [ulisp/passes/025_top_level.scm](../../ulisp/passes/025_top_level.scm)
  - [ulisp/passes/070_anf.scm](../../ulisp/passes/070_anf.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm) (`in-context` 構文定義およびエリップシス `...` パターンマッチャー拡張)
- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm) (複数非終端記号ハンドラ間の相互再帰 Catamorphism コード自動合成)
- [ ] [ulisp/passes/010_library.scm](../../ulisp/passes/010_library.scm) (Nanopass DSL 化: `define-library` / `import` 展開)
- [ ] [ulisp/passes/025_top_level.scm](../../ulisp/passes/025_top_level.scm) (Nanopass DSL 化: トップレベル定義と式本体の分離)
- [ ] [ulisp/passes/070_anf.scm](../../ulisp/passes/070_anf.scm) (Nanopass DSL 化: 複合式の A-Normal Form 正規化)
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm) (エリップシスおよび `in-context` の単体テスト拡充)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/584-nanopass-framework-phase2-ellipsis-subforms-and-normalization`

1. **エリップシス (`...`) パターンマッチングエンジンの実装**:
   - パターン内の `...` の直前要素を反復要素として識別。
   - `([,x* ,e*] ...)` からリスト `x*` と `e*` への並行抽出を行うマクロヘルパー `nanopass-match-ellipsis` を実装。
   - テンプレート出力側でのスプライス展開 `(list ,(map ... x*) ...)` を自動コード生成。
2. **局所サブフォームハンドラ (`in-context`) の実装**:
   - `(define-pass pass-name : L_src (ir) -> L_dst () (NonTerminal1 ...) (NonTerminal2 ...))` の形式をサポート。
   - 各非終端記号ごとに独立した走査関数を生成し、相互参照可能な局所束縛（`letrec`）を展開。
3. **パスの載せ替え**:
   - `010_library.scm`, `025_top_level.scm`, `070_anf.scm` を手書き S 式走査から Nanopass DSL へ移行。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `...`（エリップシス）による並行アンパックおよびリスト再構築が DSL 内で正しく動作すること
- [ ] `in-context` / 複数非終端記号ハンドラが 1 つの `define-pass` 内で相互再帰的に機能すること
- [ ] Pass 010, 025, 070 が Nanopass DSL で書き直され、手書き再帰ボイラープレートが大幅に削減されること
- [ ] 全パス単体テスト（`make -C ulisp test_all_passes`）および 3-Stage Bootstrap 固定点検証（`make -C ulisp bootstrap_verify`）が 100% PASS すること
- [ ] 相対パスのみを使用し、絶対パスが含まれないこと
