---
ID: 758
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] Pass 015 (015_dsl_expander.scm) 先行 DSL 展開器への pico / femto / atto 構文統合 (DSN-33-01 T2.3) (ID: 758)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 8.1 節（領域⑥: DSL ブートストラップ展開）およびタスク **T2.3** に基づき、ULisp コンパイラ自身のセルフホスティング AOT ビルド時に Nanopass DSL 構文を先行展開する Pass 015（`ulisp/frontend/015_dsl_expander.scm`）を拡張し、先行タスクで導入された微細粒度ルール構文（`define-picopass`, `define-femtopass`, `define-attopass`）を正準 Scheme 定義群へと手続き的に展開可能にする。

### 1.1 背景とアーキテクチャ上の位置づけ

ULisp コンパイラ基盤は、2系統の実行パスで Nanopass DSL を解釈する二重構造（Dual-Track DSL Expansion）を持つ：
1. **インタプリタ／対話環境（ILisp / Gauche ホスト）**: `ulisp/compiler/nanopass.scm` 内の `define-macro` 群を通じて展開・実行される。
2. **AOT コンパイラパイプライン ＆ 3-Stage セルフホスティング**: Pass 010（ライブラリ読み込み）直後の **Pass 015 (`expand-dsl-forms`)** において、構文マクロ展開（Pass 020 `syntax-rules`）より前にすべての Nanopass DSL フォームを手続き的（Procedural AST Rewriting）に正準 Scheme 定義（`define` 等）へと脱糖し、ホスト専用の `define-macro` を完全に除去（フィルタリング）する。

先行タスク [Issue #756](closed/756-implement-rule-descriptor-and-picopass-femtopass-attopass-dsl.md) および [Issue #757](closed/757-implement-picopass-strategy-combinators.md) により、`define-picopass` / `define-femtopass` / `define-attopass` の手続き型展開器（`nanopass-expand-define-picopass` 等）および関数合成コンビネータ群が確立された。
しかし現行の Pass 015 は `define-language`, `define-pass`, `trace-define-pass`, `define-parser`, `define-unparser` のみを受け付けており、AOT コンパイル対象コード内に `define-picopass` 等が直接現れると、後続の Pass 020 以降で未定義シンボル／構文エラーとして拒絶される。

本タスクにより Pass 015 が `define-picopass` / `define-femtopass` / `define-attopass` を完全サポートすることで、後続の [Issue #759 (T3.1: fuse-rules)](759-implement-fuse-rules-and-head-tag-o1-dispatch.md) および [Issue #762 (T4.1: 脱糖パス 026〜029 の Picopass 移行)](762-migrate-desugar-passes-026-to-029-to-picopass.md) において、フロントエンドのコアパス群が純粋な微細 DSL で記述され、完全自動でセルフホスティング AOT コンパイルされる基盤を完成させる。

---

## 2. トレーサビリティ / Traceability

- **関連設計書**:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
    - 第 3.1 節（三権分立 DSL: `pico`, `femto`, `atto`）
    - 第 8.1 節（既存 Nanopass 全機能インベントリ 領域⑥: DSL ブートストラップ展開）
    - 第 9.2 節（Phase 2 タスク **T2.3**）
- **依存関係**:
  - **先行 Issue**:
    - [Issue #756 (T2.1: Rule Descriptor と Picopass DSL 実装)](closed/756-implement-rule-descriptor-and-picopass-femtopass-attopass-dsl.md) (Closed)
    - [Issue #757 (T2.2: 関数合成コンビネータ群の実装)](closed/757-implement-picopass-strategy-combinators.md) (Closed)
  - **後続 Issue**:
    - [Issue #759 (T3.1: define-pass 内 fuse-rules 構文と Head-Tag O(1) ディスパッチ)](759-implement-fuse-rules-and-head-tag-o1-dispatch.md)
    - [Issue #762 (T4.1: フロントエンド脱糖パス 026〜029 の Picopass 化)](762-migrate-desugar-passes-026-to-029-to-picopass.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/frontend/015_dsl_expander.scm](../../ulisp/frontend/015_dsl_expander.scm)
  - `expand-dsl-forms` 内の `%source-loc` 検査対象リストに `define-picopass`, `define-femtopass`, `define-attopass` を追加。
  - トップレベルフォーム走査 `cond` 分岐に `define-picopass`, `define-femtopass`, `define-attopass` の展開・フラット化（`begin` 分解）処理を追加。
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
  - `nanopass-expand-rule-dsl` 実行時に、コンパイル時ルールレジストリ（`*nanopass-rules*`）へのコンパイル時登録（`nanopass-register-rule!`）を連動させ、同一コンパイル単位内の後続 `define-pass` が即座にルール記述子を参照可能にする。
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm)
  - `make -C ulisp compiler` による結合ソース再生成と括弧バランス検証。
- [ ] [ulisp/tests/passes/test_015_dsl_expander.scm](../../ulisp/tests/passes/test_015_dsl_expander.scm)
  - Pass 015 単体テストスイートに、`define-picopass`, `define-femtopass`, `define-attopass` の展開検証、`%source-loc` ラッパー付与時の行番号維持検証、および展開時ルールレジストリ登録の検証テストを追加。

---

## 4. 詳細設計 / Detailed Design

### 4.1 `expand-dsl-forms` の分岐拡張と再帰的フラット化

Pass 015 の主走査ループ `expand-dsl-forms` は、入力フォームリスト `fs` を先頭から1つずつ検査し、Nanopass DSL フォームを手続き的展開器で変換した上で、残余のフォーム列の前方に挿入（アンシフト）して再帰処理する。

```scheme
;; 1. ソース位置情報ラッパー (%source-loc file line col inner) の透過
((and (pair? f) (eq? (car f) '%source-loc))
 (let ((file (cadr f))
       (line (caddr f))
       (col (cadddr f))
       (inner (car (cddddr f))))
   (cond
     ((and (pair? inner)
           (memq (car inner)
                 '(define-language define-pass trace-define-pass
                   define-parser define-unparser
                   define-picopass define-femtopass define-attopass)))
      (let ((exp-inner (expand-dsl-forms (list inner))))
        (loop (append (map (lambda (x) (list '%source-loc file line col x)) exp-inner)
                      (cdr fs))
              res)))
     ...)))

;; 2. トップレベル DSL フォームの展開と begin 平坦化
((and (pair? f) (eq? (car f) 'define-picopass))
 (let ((expanded (nanopass-expand-define-picopass f)))
   (loop (append (if (and (pair? expanded) (eq? (car expanded) 'begin))
                     (cdr expanded)
                     (list expanded))
                 (cdr fs))
         res)))
((and (pair? f) (eq? (car f) 'define-femtopass))
 (let ((expanded (nanopass-expand-define-femtopass f)))
   (loop (append (if (and (pair? expanded) (eq? (car expanded) 'begin))
                     (cdr expanded)
                     (list expanded))
                 (cdr fs))
         res)))
((and (pair? f) (eq? (car f) 'define-attopass))
 (let ((expanded (nanopass-expand-define-attopass f)))
   (loop (append (if (and (pair? expanded) (eq? (car expanded) 'begin))
                     (cdr expanded)
                     (list expanded))
                 (cdr fs))
         res)))
```

### 4.2 展開結果の正準 Scheme 定義形式

`define-picopass` は `nanopass-expand-rule-dsl` により以下の正準 Scheme 形式へと展開される：

```scheme
;; 入力 DSL
(define-picopass desugar-quote (Expr)
  ('quote (const c)) -> (make-const-node c))

;; Pass 015 展開後のフラットなトップレベル定義群
(define __desc_desugar-quote
  (nanopass-make-rule-descriptor
    'desugar-quote 'pico 'Expr '(quote) '(quote) '() '() '(((quote (const c)) ...)) #f))
(define (desugar-quote ir)
  (let ((__m_ (nanopass-match-clause '(quote (const c)) ir '(c) 'Expr)))
    (if __m_ (nanopass-bind-matched-vars '(c) __m_ (make-const-node c)) #f)))
(nanopass-rule-set-proc! __desc_desugar-quote desugar-quote)
(nanopass-register-rule! __desc_desugar-quote)
'desugar-quote
```

`expand-dsl-forms` が `begin` を平坦化することにより、上記5個の式が順序を保ったまま後続の Pass 020 / Pass 025 へと供給される。

### 4.3 コンパイル時ルール登録（Compile-Time Rule Registry）の保証

後続タスク T3.1（`fuse-rules`）では、コンパイラが `define-pass` を展開する時点で、参照対象の Picopass が持つメタデータ（`head-tags`, `reads`, `writes`, `eliminates`）を `(nanopass-lookup-rule 'rule-name)` によりインメモリで取得する必要がある。

そのため、`nanopass.scm` の `nanopass-expand-rule-dsl` において、コード生成用 AST を構築するだけでなく、**展開処理自体の副作用としてインメモリの `*nanopass-rules*` レジストリにルール記述子（コンパイル時メタデータ）を即座に登録**する：

```scheme
;; compiler/nanopass.scm: nanopass-expand-rule-dsl 内
(let ((compile-time-desc
       (nanopass-make-rule-descriptor
         name rule-kind nt-name head-tags reads writes eliminates expanded-rules #f)))
  (nanopass-register-rule! compile-time-desc))
```

これにより：
1. **同一コンパイル単位での即時参照**: `define-picopass` の直後に置かれた `define-pass` が AOT 展開時にルール定義を参照可能となる。
2. **自己ホスト完全一致**: インタプリタ実行（Gauche / ILisp）でもセルフホスト AOT ビルドでも、同一のルール記述子が `*nanopass-rules*` に蓄積される。

---

## 5. セキュリティ考慮事項 ＆ 脅威分析 (Security Considerations)

1. **不正・不完全構文に対する堅牢な入力検証 (CWE-20: Improper Input Validation)**:
   - 悪意あるコードや壊れた S 式 `(define-picopass)`、シンボル以外の名前、不正なオプション指定が入力された場合でも、未ハンドルの内部例外でコンパイラがクラッシュせず、`nanopass-parse-rule-spec` により明瞭な構文エラーが報告されること。
2. **マクロ展開の有限収束保証 (CWE-400: Uncontrolled Resource Consumption)**:
   - `expand-dsl-forms` は展開結果の先頭に `begin` が含まれている場合のみ平坦化して残余 `fs` にプッシュする。`nanopass-expand-define-picopass` が生成する `define` や式はいずれも DSL 予約語を含まないため、再帰展開が無限ループに陥るリスクを構造的に排除する。
3. **ソース位置情報の厳密伝播によるトレーサビリティ担保 (CWE-384 対策 / Provenance)**:
   - `%source-loc` 構造を持つフォームが展開される際、展開後の `define` 群に対しても元のファイル名・行番号・列番号が漏れなく再付与されること。これによりコンパイルエラーや実行時診断におけるスタックトレースの偽造・脱落を防止する。
4. **コンパイラ ABI と環境分離の保護 (CWE-704 対策)**:
   - Pass 015 はホスト専用マクロ `define-macro` を完全に遮断（破棄）し、ターゲット言語環境を純粋な Scheme 意味論に保つ。これによりホスト側マクロとターゲット側コードのシンボル汚染を排除する。

---

## 6. 実装手順 / Implementation Steps

Target Branch: `feat/758-integrate-picopass-into-pass-015`

### Step 1: ブランチ作成とベースライン確認
- `git checkout -b feat/758-integrate-picopass-into-pass-015`
- `make -C ulisp test_all_passes` および `make -C ulisp bootstrap` が正常であることを確認。

### Step 2: コンパイル時ルール登録の導入 (`ulisp/compiler/nanopass.scm`)
- `nanopass-expand-rule-dsl` 内で、AST 返却前にコンパイル時記述子を作成し `(nanopass-register-rule! compile-time-desc)` を呼び出すよう修正。

### Step 3: Pass 015 展開器の拡張 (`ulisp/frontend/015_dsl_expander.scm`)
- `%source-loc` 対象構文リストに `define-picopass`, `define-femtopass`, `define-attopass` を追加。
- トップレベル分岐に `define-picopass`, `define-femtopass`, `define-attopass` のハンドラを追加し、展開後の `begin` を平坦化してループ処理する。

### Step 4: コンパイラ結合ソースの更新
- `make -C ulisp compiler` を実行し、`ulisp/compiler.scm` を再生成（52ファイル正常結合・括弧バランス検証）。

### Step 5: 単体テストスイートの拡充 (`ulisp/tests/passes/test_015_dsl_expander.scm`)
- 以下の新規テストケースを配備：
  1. `define-picopass` の正準 Scheme `define` 群への展開検証。
  2. `define-femtopass` の正準 Scheme `define` 群への展開検証（`femto-recurse` を含む `letrec` 構造）。
  3. `define-attopass` の正準 Scheme `define` 群への展開検証（`picopass-fail` を含むガード構造）。
  4. `%source-loc` 付きフォーム展開時における位置情報ラッパーの全要素への正確な付与検証。
  5. 展開直後の `(nanopass-lookup-rule 'rule-name)` によるインメモリ登録の確認。
- `cat ulisp/build/compiler_passes.scm ulisp/tests/passes/test_015_dsl_expander.scm | gosh` にて全件 PASS を確認。

### Step 6: 統合検証とブートストラップ
- `make -C ulisp test_nanopass` (100% PASS)
- `make -C ulisp test_passes` (全 Nanopass 1:1 単体テスト PASS)
- `make -C ulisp bootstrap` (Stage 1 Native Seed $\to$ Stage 2 $\to$ Stage 3 ビット完全一致)
- `make py_compile static_analysis` (0 エラー合格)

---

## 7. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp/frontend/015_dsl_expander.scm` が `define-picopass`, `define-femtopass`, `define-attopass` を認識し、正準 Scheme 定義群へ展開できること。
- [ ] `%source-loc` ラッパーが付与された上記 DSL フォームが、展開後のすべての定義・式に対して位置情報を保持して再包装されること。
- [ ] `nanopass-expand-define-picopass` 等の展開処理中に、コンパイル時ルール記述子がインメモリの `*nanopass-rules*` に自動登録されること。
- [ ] `ulisp/tests/passes/test_015_dsl_expander.scm` に新規テストケースが追加され、全件 PASS すること。
- [ ] `make -C ulisp test_passes` および `make -C ulisp test_nanopass` が 100% PASS すること。
- [ ] `make -C ulisp bootstrap` が Stage 1 から Stage 3 まで成功し、ビット完全一致の固定小数点検証を通過すること。
- [ ] `docs/issues/README.md` および本 Issue ファイルのステータスが `Closed` に更新され、コミットログが Conventional Commit 形式に従っていること。
