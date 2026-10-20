---
ID: 581
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ARCH] Nanopass Framework DSL Phase 1: コア DSL マクロ基盤 (define-language / define-pass) の自律実装と構文脱糖パス刷新 (ID: 581)

## 1. 概要 / Summary
現在 uLisp は 27 個の分割パス（010〜160）によって Nanopass 思想を実践しているが、すべて生の S 式木に対する手書きの再帰走査（Catamorphism）関数によって実装されている。
そのため、各パスにおいて「そのパスで変換したい構文（例: `cond`）」以外の変化しない無数の構文（`lambda`, `if`, `set!`, 関数呼び出し等）を全木走査・再構築する定型ボイラープレートコードが大量に重複し、パスのメンテナンス性を阻害していた。さらに、中間言語（IR）の境界で「何が除去され何が追加されたか」という言語不変条件（Invariants）が機械的に検査されず、暗黙知となっていた。

本 Issue（Phase 1）では、Andrew W. Keep & R. Kent Dybvig (2013) の **Nanopass Framework DSL 仕様** の中核基盤を uLisp にネイティブ自律実装する。
自律的なマクロ基盤として `define-language`（終端記号 `terminals`、エントリ記号 `entry`、非生成的UID `nongenerative-id`、メタ変数エイリアス規則、差分継承 `extends` による構文の追加 `+` / 削除 `-`）および `define-pass`（パターンマッチング、ガード節 `guard`、未変更構文の Catamorphism 自動再帰走査コードの完全合成）を構築し、パーサ/アンパーサ（`define-parser`, `define-unparser`）を提供する。
その上で、手書きボイラープレートが最も多い脱糖パス群（Pass 026_desugar_constructors.scm 〜 Pass 030_desugar.scm）を Nanopass DSL 記述へと刷新・スリム化する。

なお、後続フェーズは以下の通り分割して順次展開する：
- Phase 2 (Issue #584): エリップシス反復展開（`...`）とサブフォーム局所ハンドラ（`in-context`）および正規化パス移行
- Phase 3 (Issue #585): Catamorphism アナライザ支援（上流集約 `synthesized` / 下流伝播 `inherited` 多値連携）と解析・最適化パス刷新
- Phase 4 (Issue #586): パイプライン統御・AST Diff ステップトレーサ（`trace-define-pass`）および不変条件 Verifier 自動フック統合

---

## 2. トレーサビリティ / Traceability
- 先行研究系譜: Keep & Dybvig, "A Nanopass Framework for Compiler Education" (EDX 2012)
- 先行研究系譜: Keep & Dybvig, "A Nanopass Framework for Commercial Compiler Development" (ICFP 2013 / Chez Scheme)
- DSN-33 コンパイラアーキテクチャ仕様
- 関連 Issue:
  - [closed/570-split-desugar-pass-into-toplevel-lifting-and-core-desugaring.md](closed/570-split-desugar-pass-into-toplevel-lifting-and-core-desugaring.md)
  - [closed/574-nanopass-decomposition-of-desugar-pass-030.md](closed/574-nanopass-decomposition-of-desugar-pass-030.md)
  - [576-implement-lightweight-ir-verifier-framework.md](576-implement-lightweight-ir-verifier-framework.md)
  - [578-coordinate-closure-escape-and-lir-stack-allocation-pipeline.md](578-coordinate-closure-escape-and-lir-stack-allocation-pipeline.md)
- 関連ファイル:
  - [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm) (新規)
  - [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm) (新規)
  - [ulisp/passes/026_desugar_constructors.scm](../../ulisp/passes/026_desugar_constructors.scm)
  - [ulisp/passes/027_desugar_conditionals.scm](../../ulisp/passes/027_desugar_conditionals.scm)
  - [ulisp/passes/028_desugar_bindings.scm](../../ulisp/passes/028_desugar_bindings.scm)
  - [ulisp/passes/029_desugar_dynamic.scm](../../ulisp/passes/029_desugar_dynamic.scm)
  - [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm)
  - [ulisp/Makefile](../../ulisp/Makefile)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm) (新規: `define-language` および `define-pass` のコア DSL マクロ構文基盤)
- [x] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm) (新規: 言語環境テーブル、非終端記号・構文差分計算エンジン、Catamorphism 再帰コード自動合成ロジック)
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (`nanopass.scm` の組み込みと初期ロード)
- [x] [ulisp/passes/026_desugar_constructors.scm](../../ulisp/passes/026_desugar_constructors.scm) 〜 [030_desugar.scm](../../ulisp/passes/030_desugar.scm) (Nanopass DSL による脱糖パスのリファクタリング・ボイラープレート削減)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`COMPILER_BASE` への `nanopass.scm` 追加、`test_nanopass` ターゲット新設)
- [x] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm) (新規: DSL マクロ単体機能、言語継承差分、自動走査合成、違反検出の検証テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/581-implement-nanopass-framework-dsl-and-migrate-compiler-passes`

1. **Nanopass DSL メタエンジン設計 (`ulisp/compiler/nanopass_meta.scm`)**:
   - 言語メタデータ構造: 各非終端記号（Non-terminals: `Expr`, `Body`, etc.）に属する構文プロダクション集合を管理。
   - 差分マージアルゴリズム: `(extends Parent)` に対する追加（`+`）および削除（`-`）の集合演算を行い、子言語の構文規則を決定論的に導出。
   - 自動走査合成器（Catamorphism Synthesizer）: ユーザーが明示的にオーバーライドしなかったプロダクションについて、子要素を自動帰納する再帰式 `(map/recurse ...)` をコード生成。
2. **DSL マクロ構文インターフェース (`ulisp/compiler/nanopass.scm`)**:
   - `define-language` マクロの実装:
     ```scheme
     (define-language L_src
       (terminals (symbol (x)) (constant (c)))
       (Expr (e) x c (if e1 e2 e3) (cond [e1 e2] ... [else e_else]) ...))
     (define-language L_core
       (extends L_src)
       (Expr (e) (- (cond [e1 e2] ... [else e_else]))))
     ```
   - 言語パーサ／バリデータの自動出力: `(parse-L_core s-expr)` を合成し、文法に合致しないノードを即座に拒絶。
   - `define-pass` マクロの実装:
     ```scheme
     (define-pass desugar-cond : L_src (ir) -> L_core ()
       (Expr : Expr (ir) -> Expr ()
         [(cond [else ,[e_else]]) e_else]
         [(cond [,e1 ,e2] . ,[rest]) `(if ,e1 ,e2 ,rest)]))
     ```
3. **Pass 026〜030 の段階的載せ替え**:
   - 現在手書きされている `desugar-cond`, `desugar-let*`, `desugar-list` 等の再帰走査関数を、`define-pass` によるパターン節のみの簡潔な記述へ順次置換。
   - `030_desugar.scm` のコード行数を 500行超から数十行規模へ劇的にスリム化。
4. **自己ホスト整合性の検証**:
   - 生成されるマクロ展開形が uLisp の既存の低水準プリミティブのみで動作し、ブートストラップ（Stage 1〜3）が問題なく完走することを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `define-language` および `define-pass` が uLisp 内でマクロ展開・実行できること
- [ ] 言語の差分継承（`extends`）による構文の追加・削除が正常に動作し、バリデータが未脱糖構文の残存を自動検知できること
- [ ] 構文脱糖パス（Pass 026〜030）が Nanopass DSL で書き直され、手書き再帰ボイラープレートが 70% 以上削減されること
- [ ] `test_nanopass_framework.scm` が新設され、マクロおよび生成されたパスの動作が単体テストで検証されていること
- [ ] 全パス単体テスト（`make -C ulisp test_all_passes`）および AOT テストスイートが 100% PASS すること
- [ ] 相対パスのみを使用し、絶対パスが含まれないこと
