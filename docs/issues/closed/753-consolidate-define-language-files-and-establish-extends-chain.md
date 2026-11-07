---
ID: 753
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] 言語定義ファイルの統廃合と L_cst から L_lir_canonical への連続 extends 継承連鎖の確立 (DSN-33-01 T1.1) (ID: 753)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合（Pipeline / Pass / Nanopass / Picopass）＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 6.2 節・第 8.3 節およびロードマップタスク **T1.1** に基づき、現在 ULisp コードベース内で分散・断絶している `define-language` 定義群を統廃合し、フロントエンド（`L_cst -> L_src -> L_core -> L_anf -> L_lifted`）および LIR（`L_lir_raw -> L_lir_canonical`）・バックエンド（`L_asm_x86`, `L_asm_aarch64`）に至る連続した `extends` 継承チェーンを確立する。

### 現状の構造的課題（コードベース調査結果）
1. **汎用フレームワークへの具体言語の混入**:
   - `ulisp/compiler/nanopass.scm` の末尾（L265-324）に Scheme フロントエンド固有の `L_src` と `L_core` がハードコードされており、Nanopass 汎用エンジン層（`compiler/`）と具体言語定義層（`frontend/`）の責務分離が破れている。
   - ちなみに `ulisp/Makefile`（L55, L61）では `COMPILER_BASE` の末尾付近に `compiler/nanopass.scm` があり、`FRONTEND_PASSES` の先頭に `frontend/frontend_lang.scm` が配置されているため、`L_src` / `L_core` を `frontend/frontend_lang.scm` の先頭へ移管しても単一結合ビルド（`compiler.scm`, `build/compiler_passes.scm`）および分割ビルド（`build/ulisp-modular`）のロード順序と完全に整合する。
2. **`extends` 継承チェーンの断絶とオーバーロード除去時の `removed-prods` 汚染**:
   - `ulisp/frontend/frontend_lang.scm` の `L_anf`（L18-59）が `L_core` を `(extends L_core)` しておらずゼロから再定義されているため、`(language-parent-chain 'L_lifted)` が `'(L_anf L_lifted)` で途切れ、`L_core -> L_anf` 間の `language-diff` が機能しない。
   - さらに、`ulisp/compiler/nanopass_meta.scm` の `nanopass-derive-nonterminals-and-removed`（L177-182）および `nanopass-parse-language-spec`（L265-266）では、`(- (let x ((x1 e1) ...) e ...))` や `(- (if e1 e2 e3))` のように「同一キーワードの別構文（`(let ((x e1) ...) e ...)` や `(if a e1 e2)`）が残る、あるいは `+` で狭義構文に置き換えられるケース」や「`(- (e0 e1 ...))` のようなメタ変数先頭構文」であっても無条件に先頭シンボル（`let`, `define`, `if`, `e0`）を `removed-prods` に追加している。その結果、`generate_nanopass_docs.scm` 等で `let` や `define` が削除済み構文として誤表示される問題がある。
3. **未定義の幽霊言語シンボル (`L_lir_raw`)**:
   - `ulisp/compiler/pass_manager.scm`（L543-549）において `pass-130-lir` の出力言語および `pass-128-lir-branch-fusion` / `pass-133-lir-peephole` の入力言語として `'L_lir_raw` が指定されているにもかかわらず、`ulisp/lir/lir_lang.scm` には `L_lir_canonical` しか定義されておらず、`(assq 'L_lir_raw (nanopass-get-languages))` が `#f` となって `L_lir_raw` 段階の `nanopass-verify-ast` が暗黙にスキップされている。
4. **表層言語 (`L_cst`) および AArch64 アセンブリ言語 (`L_asm_aarch64`) の未定義**:
   - `pass-010-library`, `pass-015-dsl-expander`, `pass-020-macro-expander` が入力として受け取る最表層構文木 `L_cst`（`define-library`, `import`, `export`, `define-syntax`, `syntax-rules`, `let-syntax`, `letrec-syntax`, `define-language`, `define-pass`, `define-picopass` 等を含む）が独立言語として定義されておらず、`L_src -> L_src` と表記されている。
   - `ulisp/backend/backend_lang.scm` に `L_asm_x86` は存在するが、`150_backend_aarch64.scm` に対応する `L_asm_aarch64` が定義されていない。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 2.5 節)
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 6.2 節, 第 8.3 節, 第 9.2 節 タスク **T1.1**)
- 依存関係:
  - 先行 Issue: なし（Phase 1 の起点タスク）
  - 後続 Issue:
    - [Issue #754 (T1.2: カタモルフィズムのスキーマ駆動化)](../754-refactor-catamorphism-to-schema-driven-traversal.md)
    - [Issue #760 (T3.2: extends (-) 対 eliminates 自動整合性検査)](../760-implement-local-redispatch-and-extends-eliminates-validation.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm) — `nanopass-parse-language-spec` における `removed-prods` フィルタリング精緻化（残存キーワードおよびメタ変数先頭構文を `removed-prods` から除外）
- [x] [ulisp/compiler/nanopass.scm](../../../ulisp/compiler/nanopass.scm) — L265-324 の `L_src` / `L_core` 定義を除去し、純粋な Nanopass DSL エンジンに純化
- [x] [ulisp/frontend/frontend_lang.scm](../../../ulisp/frontend/frontend_lang.scm) — `L_cst -> L_src -> L_core -> L_anf -> L_lifted` の5段階 `extends` 継承チェーンを集約定義
- [x] [ulisp/lir/lir_lang.scm](../../../ulisp/lir/lir_lang.scm) — `L_lir_raw` の新規定義および `L_lir_canonical` の `(extends L_lir_raw)` 差分定義化
- [x] [ulisp/backend/backend_lang.scm](../../../ulisp/backend/backend_lang.scm) — `L_asm_x86` に加え `L_asm_aarch64` スキーマを追加定義
- [x] [ulisp/compiler/pass_manager.scm](../../../ulisp/compiler/pass_manager.scm) — `pass-010-library`, `pass-015-dsl-expander`, `pass-020-macro-expander` の入出力言語契約を `L_cst -> L_src` に整合化
- [x] [ulisp/compiler/module_header.scm](../../../ulisp/compiler/module_header.scm) — 分割コンパイル用 `%declare-extern-identifiers` に `L_cst`, `L_asm_x86`, `L_asm_aarch64` および各言語述語（`L_cst?`, `L_src?`, `L_core?`, `L_anf?`, `L_lifted?`, `L_lir_raw?`, `L_lir_canonical?`, `L_asm_x86?`, `L_asm_aarch64?`）を追加
- [x] [ulisp/tests/test_nanopass_framework.scm](../../../ulisp/tests/test_nanopass_framework.scm) — `language-parent-chain`, `language-diff`, 全言語スキーマ述語の単体テスト追加
- [x] [ulisp/tests/test_pass_manager.scm](../../../ulisp/tests/test_pass_manager.scm) — パイプライン登録パスの全 `in-lang` / `out-lang` が `*nanopass-languages*` に定義済みであることを検証するテスト追加

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/753-consolidate-define-language-hierarchy`

### Step 1: `ulisp/compiler/nanopass_meta.scm` における `extends` 差分導出の精緻化
- `nanopass-parse-language-spec`（L263-272）において、親言語から引き継いだ `parent-removed` と今回の `(- ...)` で抽出された `new-removed` を統合する際、以下の2条件を満たすシンボルのみを `final-removed` に保持する：
  1. 子言語の有効キーワード集合 `final-kws` に含まれていないこと（例：`L_core` で `(let x ...)` を削除しても `(let ((x e1) ...) ...)` が残るため `'let` は有効キーワードであり、`removed-prods` に含めない。同様に `L_anf` で `(if e1 e2 e3)` を削除し `(if a e1 e2)` を追加した場合も `'if` は有効キーワードとして維持される）。
  2. 終端・非終端のメタ変数プレフィックス（`e0`, `a0`, `x`, `c` 等）にマッチしない純粋なキーワード識別子であること。
- さらに、`(- x c)` のように単一シンボル（非リスト）のプロダクションを除去する際、`nanopass-production-equal?` が正しく一致判定して親非終端記号のプロダクションリストから `x` や `c` を除去できることを確認する（現在の `nanopass-canonicalize-production` はリストでない `rm` に対してそのままシンボルを返し、`equal?` で比較するため動作するが、単体テストで厳密に検証する）。

### Step 2: `ulisp/compiler/nanopass.scm` からの具体言語定義の分離
- `ulisp/compiler/nanopass.scm` L265-324 の `L_src` および `L_core` の `(define-language ...)` ブロックを削除し、`nanopass.scm` を言語非依存の純粋な Nanopass DSL マクロ・展開器ファイルとする。

### Step 3: `ulisp/frontend/frontend_lang.scm` における5段階 `extends` 継承チェーンの構築
`ulisp/frontend/frontend_lang.scm` に以下の5言語を順番に定義する：
1. **`L_cst`（Concrete Syntax Tree — 最表層言語）**:
   - `(entry Program)`
   - `terminals`: `(symbol (x lbl var))`, `(constant (c))`
   - `Def (d)`:
     - `(define-library (x ...) d ...)`
     - `(import d ...)`
     - `(export x ...)`
     - `(include c)`
     - `(include-ci c)`
     - `(cond-expand (d e ...) ...)`
     - `(define-syntax x e)`
     - `(define-language x d ...)`
     - `(define-pass x d ...)`
     - `(define-picopass x d ...)`
     - `(define-femtopass x d ...)`
     - `(define-attopass x d ...)`
     - `(define x e)`
     - `(define (x x1 ...) e ...)`
     - `e`
   - `Expr (e)`:
     - `L_src` の全 `Expr` プロダクションに加え、表層マクロ・構文フォーム `(let-syntax ((x e1) ...) e ...)`, `(letrec-syntax ((x e1) ...) e ...)`, `(syntax-rules (x ...) (e1 e2) ...)` を含む。
   - `Program (p)`:
     - `(%program (d ...) e)`
     - `d`
     - `e`
2. **`L_src`（Source HIR — ライブラリ・マクロ展開後、糖衣構文脱糖前）**:
   - `(extends L_cst)`
   - `Def (d)` から `define-library`, `import`, `export`, `include`, `include-ci`, `cond-expand`, `define-syntax`, `define-language`, `define-pass`, `define-picopass`, `define-femtopass`, `define-attopass` を `(- ...)` で除去。
   - `Expr (e)` から `let-syntax`, `letrec-syntax`, `syntax-rules` を `(- ...)` で除去。
3. **`L_core`（Core HIR — 全18種の糖衣構文脱糖後）**:
   - `(extends L_src)`
   - `Def (d)` から `(- (define (x x1 ...) e ...))` を除去。
   - `Expr (e)` から既存の18種の糖衣構文（`quasiquote`, 名前付き `let`, `let*`, `letrec*`, `let-values`, `let*-values`, `cond`, `case`, `and`, `or`, `when`, `unless`, `do`, `delay`, `delay-force`, `parameterize`, `guard`, `(define (x x1 ...) e ...)`）を `(- ...)` で除去。
4. **`L_anf`（A-Normal Form — 複合式の引数・条件式の原子化後）**:
   - `(extends L_core)`
   - 新規非終端記号 `Atom (a)` を追加：`x`, `lbl`, `var`, `c`, `(quote datum)`, `(%closure-ref a c)`, `(%global-ref x)`。
   - `Expr (e)` から非正規化プロダクション `(- x c (quote datum) (if e1 e2 e3) (if e1 e2) (define x e) (e0 e1 ...))` を除去し、ANF 正規化プロダクション `(+ a (if a e1 e2) (if a e1) (%make-closure a1 a ...) (%make-closure-env a1 a ...) (%closure-ref a c) (%closure-set! a1 c a2) (%cont-fun x (x ...) e1 e2) (%cont-call x a ...) (%with-handler a1 a2) (%raw-call/cc a) (%call-with-values a1 a2) (%values a ...) (%direct-call a1 a ...) (%global-ref x) (%global-set! x e) (a0 a ...))` を追加。
5. **`L_lifted`（Lambda-Lifted Form — クロージャ変換・トップレベル関数平坦化後）**:
   - `(extends L_anf)`（既存の差分定義を維持）。

### Step 4: `ulisp/lir/lir_lang.scm` における `L_lir_raw -> L_lir_canonical` 継承チェーンの定義
- 生成直後の未最適化 LIR を表す `L_lir_raw` を基底言語として定義する（既存の `L_lir_canonical` の全プロダクションに、正規化前の未融合比較・一時命令を含める）。
- `L_lir_canonical` を `(extends L_lir_raw)` として定義し、`(language-parent-chain 'L_lir_canonical)` が `'(L_lir_raw L_lir_canonical)` を返すようにする。

### Step 5: `ulisp/backend/backend_lang.scm` における `L_asm_aarch64` の追加定義
- `150_backend_aarch64.scm` が扱う AArch64 レジスタ（`x0`〜`x30`, `w0`〜`w30`, `sp`, `xzr`）、メモリアドレッシング（`(%mem reg offset)`, `(%stack offset)`）、および AArch64 命令群（`mov`, `add`, `sub`, `mul`, `sdiv`, `and`, `orr`, `eor`, `lsl`, `lsr`, `asr`, `cmp`, `cset`, `b`, `b.cc`, `bl`, `blr`, `ret`, `stp`, `ldp`, `str`, `ldr`, `ldrb`, `strb`, `adr`, `svc`, `dmb` 等）を持つ `L_asm_aarch64` を定義する。

### Step 6: `pass_manager.scm` と `module_header.scm` の更新
- `ulisp/compiler/pass_manager.scm`（L497-503）において：
  - `pass-010-library`: `'L_cst -> 'L_cst`
  - `pass-015-dsl-expander`: `'L_cst -> 'L_cst`
  - `pass-020-macro-expander`: `'L_cst -> 'L_src`
  に更新する。
- `ulisp/compiler/module_header.scm` の `%declare-extern-identifiers` に新規追加された言語名・述語・パーサ・アンパーサ識別子を登録する。

### セキュリティ・安全性考慮事項 (Security & Safety Considerations)
- `L_lir_raw` が正式定義されることで、`pass-130-lir` の出力および `pass-128-lir-branch-fusion` の入出力に対しても `nanopass-verify-ast` による構造検証が有効化される。そのため、`130_lir.scm` や `128_lir_branch_fusion.scm` が実際に生成するすべての LIR 命令形式が漏れなく `L_lir_raw` / `L_lir_canonical` に含まれていることを全38パスの単体テストで確認し、正当な AST の誤拒否（False Positive）を防止する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/compiler/nanopass.scm` に特定言語（`L_src`, `L_core` 等）の定義が一切残っておらず、純粋な DSL 展開器となっていること。
- [x] `(language-parent-chain 'L_lifted)` が `'(L_cst L_src L_core L_anf L_lifted)` を返し、`(language-parent-chain 'L_lir_canonical)` が `'(L_lir_raw L_lir_canonical)` を返すこと。
- [x] `(language-diff 'L_core 'L_anf)` がエラーなく削除構文・追加構文の差分ペアを返すこと。
- [x] `pass_manager.scm` に登録されている全パスの `in-lang` / `out-lang` シンボルが `(nanopass-get-all-languages)` に 100% 登録されており、未定義の幽霊言語シンボルが 0 件であること。
- [x] `make -C ulisp test_nanopass`, `make -C ulisp test_pass_manager`, `make -C ulisp test_all_passes`, `make -C ulisp docs_nanopass` がすべてエラー 0 件で PASS すること。
- [x] リポジトリ全体の品質ゲート（`make format`, `make static_analysis`, `make test`）が PASS すること。


