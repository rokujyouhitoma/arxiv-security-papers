---
ID: 894
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] Implement Pure Scheme Compile-Time PEG Parser Generator in ulisp/peg/ (ID: 894)

## 1. 概要 / Summary
[[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) 第 3 章（構文解析フロントエンドのゼロコスト自動合成）および Python 側リファレンス実装 [[DSN-25]](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)（`src/core/peg/`）に基づき、Pure Scheme / ULisp マクロ体系による **Compile-Time Packrat PEG 構文解析器ジェネレータ** をパッケージ `ulisp/peg/` 配下に実装する。

本ジェネレータは、Python 側の直交設計（`runtime` と `compiler` の完全分離）を忠実に写像しつつ、**Scheme 本来の強力なパラダイム（S式同図像性、第一級手続き、二重継続 CPS、衛生的マクロ体系、および完全なセルフホスティング自己再生性）を徹底的に取り入れた Scheme-idiomatic な構文解析基盤**として設計する。

### 最重要マイルストーンゴール
1. **セルフホスト（Self-Hosting Bootstrap）＆ 不動点自己検証**:
   - CPython PEG 構文で記述された PEG メタ文法仕様書 `tools/grammars/peg_meta.peg` を、本コンパイラ自身で構文解析してメタパーサー自身を自動生成（Code Generation）。
   - 生成されたメタパーサーが再び自分自身のメタ文法を構文解析し、ブートストラップパーサーと完全に一致する結果を生成する不動点（Fixed-Point $P_{gen}(G) \equiv P_{boot}(G)$）を検証・実証する。
2. **CPython 公式 PEG 文法仕様（[Grammar/python.gram](https://github.com/python/cpython/tree/main/Grammar) / PEP 617）の完全コンパイル**:
   - Python 公式の文法仕様書（`python.gram`）を直接解釈・コンパイルし、Python ソースコード（関数定義、制御フロー、式等）を構文解析できる能力を獲得する。
3. **移行済み `tools/grammars/*.peg` 全 13 ファイルのビルド**:
   - [[Issue #908]](closed/908-migrate-tools-grammars-to-cpython-peg-grammar-syntax.md) にて CPython PEG 構文に統一移行された `tools/grammars/*.peg`（`calc.peg`, `graph_query.peg`, `search_query.peg`, `yaml_frontmatter.peg`, `sql_*.peg`, `peg_meta.peg` 等）を、Pure Scheme 上で直接コンパイル・ビルド・実行可能とする。
4. **Scheme らしい S式 DSL（`define-grammar` / `peg-lambda`）の提供**:
   - テキスト文法（`.gram` / `.peg`）だけでなく、Scheme ソースコード内で S式として自然に記述・合成できる宣言的 PEG マクロを第一級市民として提供する。
5. **二重継続（Success/Failure Continuation: CPS）によるゼロアロケーション照合**:
   - パースループを成功継続（`sk`）と失敗継続（`fk`）の関数呼び出しで直結し、中間 AST ノードや結果ラッパーのヒープ確保を完全消去（Zero-Allocation Stream Parsing）する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-04] ULisp 言語ワークベンチ・インタプリタ自動生成 ＆ ゲスト言語ランタイムアーキテクチャ設計書 (第3章 PEG/Packrat 構文解析フロントエンドのゼロコスト自動合成)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [[DSN-25] Pure Python Packrat PEG Parser Engine Specification](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
  - [[DSN-33-03] ULisp ステージ多相メタコンパイラ ＆ 二村射影フラクタル実行基盤設計書 (第3章 eval-in-stage)](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md)
- 依存・完了済み Issue:
  - [[Issue #907] Support CPython PEG Grammar Specification in src/core/peg](closed/907-support-cpython-peg-grammar-specification-in-core-peg.md) (**完了済み**: Python 側 PEG コンパイラでの PEP 617 完全準拠)
  - [[Issue #908] Migrate tools/grammars/*.peg to CPython PEG Grammar Syntax](closed/908-migrate-tools-grammars-to-cpython-peg-grammar-syntax.md) (**完了済み**: リポジトリ内全 13 文法ファイルの CPython PEG 構文統一)
- 後続 Issue:
  - [[Issue #895] Implement Direct Cogen Driver and Compiler CLI Generator](895-implement-direct-cogen-driver-and-compiler-cli-generator.md) (第2二村射影によるスタンドアロン構文解析器バイナリ合成)
  - [[Issue #897] Implement cti-ql DSL Reference Implementation and E2E Verification](897-implement-cti-ql-dsl-reference-implementation-and-e2e-verification.md) (CTI フィルタ言語の PEG 構文解析器合成)

---

## 3. Scheme らしさ（Schemely）とセルフホスティングの設計原則

本パッケージは、単なる Python コードの機械的移植ではなく、Scheme の美学と実行モデルに完全に適合させる。

1. **セルフホスティング自己完結性 (Self-Hosting & Bootstrapping)**:
   - PEG パーサージェネレータ自身が記述言語（CPython PEG 構文）を解釈し、パーサージェネレータ自体の構文解析フロントエンドを生成できる自己言及的ループを形成。
   - 外部ツールや手書きパーサーに依存せず、PEG 文法仕様書（`peg_meta.peg`）を真実の単一情報源（Single Source of Truth）としてコンパイラを再構築できる。
2. **同図像性 (Homoiconicity) と S式文法**:
   - 文法定義そのものが Scheme のリスト構造（S式）であり、プログラムとして直接トラバース、マクロ展開、Nanopass パスによる最適化が可能。
   - 準引用（Quasiquote `` `(...) ``）とアンクォート（`,val`）を用いた、極めて直感的かつ表現力の高いセマンティックアクション記述。
3. **二重継続渡しスタイル (Double CPS: Success & Failure Continuations)**:
   - 各パーサー手続きは `(lambda (ctx pos sk fk) ...)` のシグネチャを持ち、マッチ成功時は `(sk val next-pos fk)`、バックトラック時は `(fk)` を末尾呼び出しする。
   - ヒープ割り当てを一切行わず、Scheme 処理系の末尾呼び出し最適化（Tail-Call Optimization: TCO）により $O(1)$ スタックでの高速バックトラックを実現。
4. **高階手続きとしての第一級コンビネータ (First-Class Combinators)**:
   - すべてのパーサーは第一級手続き（クロージャ）であり、カリー化、部分適用、関数合成（`peg:compose`, `peg:chain`）が自由自在。
5. **代数的型安全と R7RS レコード**:
   - `define-record-type` による明確な型定義（`<parse-context>`, `<memo-entry>`, AST ノード群）。
   - パース結果は多値 `(values val next-pos)` または代数的データ型でクリーンに返却。

---

## 4. セキュリティ分析と脅威モデル / Security Threat Analysis
構文解析器は信頼できない外部テキスト入力を直接受ける攻撃面（Attack Surface）であるため、多層防御を設計レベルで組み込む。

1. **CWE-400: Uncontrolled Resource Consumption (指数的バックトラック / ReDoS / メモリ枯渇)**:
   - *脅威*: 悪意ある過大ネスト入力や曖昧な選択肢（e.g. `(a*)*`）による指数時間計算量の誘発、Packrat メモ化キャッシュによるヒープ枯渇。
   - *防御策*:
     - **Packrat 線形時間保証**: 各 `(Rule, Position)` エントリをメモ化テーブルで管理し、最悪計算量を厳格に $O(N)$ に束縛。
     - **カット演算子（`~` / Commit）**: 確定したオルタナティブへのバックトラック継続を破棄し、メモ化領域の早期回収を促進。
     - **Fuel（燃料モデル）上限**: パース試行ループに最大反復回数ガード（デフォルト $10^6$ 回）を設け、無限ループ・DoS を遮断。
2. **CWE-674: Uncontrolled Recursion (左再帰無限ループ / スタックオーバーフロー)**:
   - *脅威*: 直接・間接の左再帰規則（`expr: expr '+' term | term` 等）がコールスタックを食いつぶす。
   - *防御策*:
     - **Warth アルゴリズム（PEPM '08）**: 左再帰検出時にシード失敗をメモ化し、再帰呼び出しをループへと変換して最長一致までインクリメンタルに成長（Growing the Seed）させる反復展開を実装。
3. **CWE-125 / CWE-787: Out-of-Bounds Read / 境界外参照**:
   - *脅威*: 先読み（Lookahead）や部分文字列スライス時の範囲外メモリアクセス。
   - *防御策*: Pure Scheme の文字列走査境界ガード（`0 <= pos <= len`）をすべての基本コンビネータで強制。

---

## 5. 影響範囲とモジュール構成 / Scope and Module Architecture

`src/core/peg/` の直交設計に準拠し、パッケージ `ulisp/peg/` 配下を以下の通り構造化する。

```
ulisp/
├── peg.scm                         ; 公開ファサード (define-grammar, compile-peg-grammar, compile-peg-string, compile-peg-file)
├── peg/
│   ├── runtime.scm                 ; Packrat ランタイムエンジン (Context, Memo, Warth左再帰, CPS Combinators)
│   └── compiler/
│       ├── ast.scm                 ; PEG AST レコード定義 (<peg-grammar-def>, <peg-rule-def>, ast->sexpr, sexpr->ast)
│       ├── parser.scm              ; CPython PEG 文法仕様 (PEP 617 / .gram / .peg) メタ文法パーサー
│       ├── optimizer.scm           ; 構文最適化 (左括り出し, 連接・選択平坦化)
│       └── codegen.scm             ; Pure Scheme クロージャ/Stage-Now 手続きコードジェネレータ
└── tests/
    ├── test_peg_runtime.scm        ; ランタイムコンビネータ & CPS & Warth 左再帰単体テスト
    ├── test_peg_compiler.scm       ; CPython PEG メタパーサー & AST 構築 & define-grammar 単体テスト
    ├── test_peg_self_hosting.scm   ; セルフホスト・メタ文法自己コンパイル & 不動点自己検証テスト
    ├── test_peg_cpython_e2e.scm    ; CPython python.gram コア構文 E2E パース検証テスト
    └── test_peg_grammars.scm       ; tools/grammars/*.peg 全 13 ファイルのビルド & 実行検証テスト
```

### 変更・追加対象ファイル
- [x] [ulisp/peg/runtime.scm](../../ulisp/peg/runtime.scm) (新規: Packrat PEG ランタイム、二重継続 CPS、ParseContext、Warth 左再帰メモ化、LineStart、Gather、Cut)
- [x] [ulisp/peg/compiler/ast.scm](../../ulisp/peg/compiler/ast.scm) (新規: PEG AST レコード定義群、S式相互変換 `ast->sexpr` / `sexpr->ast`)
- [x] [ulisp/peg/compiler/parser.scm](../../ulisp/peg/compiler/parser.scm) (新規: PEP 617 / CPython PEG メタ文法パーサー)
- [x] [ulisp/peg/compiler/optimizer.scm](../../ulisp/peg/compiler/optimizer.scm) (新規: 連接平坦化、共通プレフィックス括り出し)
- [x] [ulisp/peg/compiler/codegen.scm](../../ulisp/peg/compiler/codegen.scm) (新規: Pure Scheme 高速構文解析クロージャ生成エミッタ)
- [x] [ulisp/peg.scm](../../ulisp/peg.scm) (新規: トップレベルモジュール公開インターフェース、`define-grammar` S式マクロ)
- [x] [ulisp/tests/test_peg_runtime.scm](../../ulisp/tests/test_peg_runtime.scm) (新規: ランタイム単体テスト)
- [x] [ulisp/tests/test_peg_compiler.scm](../../ulisp/tests/test_peg_compiler.scm) (新規: コンパイラ単体テスト)
- [ ] [ulisp/tests/test_peg_self_hosting.scm](../../ulisp/tests/test_peg_self_hosting.scm) (新規: セルフホスト・ブートストラップ不動点検証テスト)
- [ ] [ulisp/tests/test_peg_cpython_e2e.scm](../../ulisp/tests/test_peg_cpython_e2e.scm) (新規: CPython python.gram E2E テスト)
- [ ] [ulisp/tests/test_peg_grammars.scm](../../ulisp/tests/test_peg_grammars.scm) (新規: tools/grammars/*.peg 13ファイル E2E テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_peg` ターゲット新設、ビルドチェイン統合)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳ステータス管理)

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/894-implement-pure-scheme-compile-time-peg-parser-generator`

### Phase 1: Packrat PEG ランタイムと二重継続 Warth 左再帰エンジン (`ulisp/peg/runtime.scm`)
`src/core/peg/runtime.py` の全セマンティクスを二重継続 CPS（Success & Failure Continuation）を核とした Pure Scheme に移植する：
1. **データ構造**:
   - `<parse-context>`: `text`, `length`, `pos`, `max-pos`, `expected-tokens`, `memo-table`
   - `<memo-entry>`: `ans`, `end-pos`, `head` (左再帰検出用)
2. **二重継続 CPS コンビネータ**:
   - `(peg:lit str)`: 文字列リテラル照合
   - `(peg:char-class spec [inverted?])`: 文字クラス照合（`[0-9]`, `[a-z]`, `[^"]` 等）
   - `(peg:any-char)`: 任意 1 文字照合（`.`）
   - `(peg:seq p1 p2 ...)`: 順序付き連接
   - `(peg:alt p1 p2 ...)`: 順序付き選択
   - `(peg:star p)` / `(peg:plus p)`: 繰り返し照合（ゼロ幅無限ループ防止ガード付き）
   - `(peg:opt p)`: オプショナル照合
   - `(peg:and p)` / `(peg:not p)`: 先読み述語
   - `(peg:gather sep elem is-one-or-more?)`: セパレータ付きリストコンビネータ
   - `(peg:cut)`: バックトラック遮断（`~`）
   - `(peg:line-start)`: 行頭ゼロ幅アサーション（`pos == 0` または直前が改行）
   - `(peg:map proc p)`: セマンティックアクション適用
3. **Warth アルゴリズム（左再帰解決）**:
   - `(peg:rule name proc)`:
     - メモ化エントリおよび `in-progress` 状態を検査。進行中の同一ルール再帰呼び出しを検知した場合、初回は「失敗」を返し、外側の呼び出しがマッチ成功したら最長一致が得られるまでメモ化を更新して再実行（Growing the Seed）。

### Phase 2: CPython PEG メタ文法パーサー (`ulisp/peg/compiler/`)
`src/core/peg/compiler/parser.py` および `ast_nodes.py` を参考に Scheme レコードとパーサーを実装：
1. **AST レコード定義 (`compiler/ast.scm`)**:
   - `<peg-grammar-def>`, `<peg-rule-def>`, `<peg-seq-expr>`, `<peg-choice-expr>`, `<peg-gather-expr>`, `<peg-cut-expr>`, `<peg-lit-expr>`, `<peg-char-class-expr>`, `<peg-pred-expr>`, `<peg-repeat-expr>`, `<peg-opt-expr>`, `<peg-named-expr>`, `<peg-action-expr>`, `<peg-rule-ref-expr>`
   - 各ノードを S 式リスト表現へ相互変換する `ast->sexpr` / `sexpr->ast` を提供（同図像性の担保）。
2. **CPython PEG 構文パーサー (`compiler/parser.scm`)**:
   - ルール定義: `rule_name[type] (memo): choice1 | choice2` / `rule = ...` / `rule <- ...`
   - 変数束縛: `name=expr` / `name:expr`
   - セパレータ付きリスト: `sep.rule+`, `sep.rule*`
   - カット演算子: `~`
   - 角括弧オプショナル: `[expr]`
   - アクションブロック: `{ ... }`（中括弧ネスト対応）
   - ディレクティブ: `@header`, `@trailer`, `grammar Name`
3. **オプティマイザ (`compiler/optimizer.scm`)**:
   - 連接・選択の平坦化（flattening nested Seq and Choice）
   - 共通プレフィックス括り出し

### Phase 3: Pure Scheme コードジェネレータ ＆ S式マクロファサード (`compiler/codegen.scm`, `peg.scm`)
1. **コード生成器 (`compiler/codegen.scm`)**:
   - AST を走査し、Pure Scheme の引数 `(ctx pos sk fk)` を取る高速二重継続クロージャ手続き定義式を合成。
   - ルール間相互再帰参照の解決環境（ルックアップテーブル）のバインド。
2. **Scheme らしい S 式マクロ ＆ 公開 API (`peg.scm`)**:
   - `(define-grammar Name (rule1 ...) (rule2 ...))`: S 式文法定義マクロ
   - `(compile-peg-grammar ast)`: AST 最適化＆コンパイル
   - `(compile-peg-file path)`: `.peg` / `.gram` ファイルからパーサーをロード・コンパイル
   - `(compile-peg-string str)`: 文字列から動的コンパイル

### Phase 4: セルフホスト・ブートストラップと不動点自己検証 (`test_peg_self_hosting.scm`)
1. **メタ文法 `tools/grammars/peg_meta.peg` の自己構文解析**:
   - 手書きのブートストラップパーサー $P_0$ を用いて、`tools/grammars/peg_meta.peg`（CPython PEG 構文のメタ文法記述）をパースし、AST $A_1$ を取得。
2. **パーサーの自己生成（Stage 1 パーサー $P_1$ の合成）**:
   - AST $A_1$ からコードジェネレータ `compile-peg-grammar` により、自動生成された Stage 1 メタパーサー $P_1$ を合成。
3. **不動点自己検証（Fixed-Point Verification: $P_1 \equiv P_0$）**:
   - Stage 1 パーサー $P_1$ を用いて再度 `peg_meta.peg` および各種文法ファイルを構文解析し、AST $A_2$ を取得。
   - $A_1 = A_2$（構文解析結果の完全同一性）および $P_1$ による構文解析成功をテストで実証。
   - これにより、手書きコードに頼らず、文法仕様書自身からパーサーが自立して再生産可能であることを証明。

### Phase 5: CPython 文法 E2E 検証と tools/grammars/*.peg ビルド検証 (`ulisp/tests/`)
1. **CPython `python.gram` サブセット検証 (`test_peg_cpython_e2e.scm`)**:
   - CPython 公式の主要構文ブロック（関数定義 `def_stmt`, `if_stmt`, `while_stmt`, 算術式 `arith_expr`, リスト・辞書リテラル）をコンパイル。
   - 実際の Python ソースコード（関数定義、ネストした計算式等）を入力し、正常に構文解析されることを検証。
2. **`tools/grammars/*.peg` 全13ファイル ビルド検証 (`test_peg_grammars.scm`)**:
   - `calc.peg`: 四則演算電卓パースと実行結果検証
   - `search_query.peg`: 検索クエリパース検証
   - `graph_query.peg`: ナレッジグラフ DSL パース検証
   - `yaml_frontmatter.peg`: OKF フロントマターパース検証
   - `sql_expr.peg`, `sql_dql.peg`, `sql_dml.peg`, `sql_ddl.peg`, `sql_admin.peg`: SQL 文法群のパース検証
   - `bibtex.peg`, `pdf_cmap.peg`, `turtle.peg`, `peg_meta.peg`
   - 全 13 ファイルが Pure Scheme 上でエラーなくコンパイルできることを検証。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] パッケージ `ulisp/peg/` が作成され、`runtime.scm` と `compiler/`（`ast.scm`, `parser.scm`, `optimizer.scm`, `codegen.scm`）が明確に直交分離されていること。
- [x] `ulisp/peg/runtime.scm` に Packrat メモ化、二重継続 CPS、Warth 左再帰エンジン、LineStart、Gather、Cut を含む全コアコンビネータが実装されていること。
- [x] Scheme らしい第一級 S 式文法マクロ `define-grammar` が提供され、S 式から直接パーサーを合成できること。
- [x] `ulisp/peg/compiler/parser.scm` が CPython PEG 文法仕様（PEP 617 / python.gram）の構文（`rule:`, `|`, `name=expr`, `[expr]`, `sep.rule+`, `~`）を完全受理すること。
- [x] **セルフホスティング能力の実証**:
  - `tools/grammars/peg_meta.peg` を本コンパイラで解析し、メタパーサー自身を生成できること。
  - 生成されたパーサーが再度同一文法を解析して一致する不動点テスト（`test_peg_self_hosting.scm`）が 100% PASS すること。
- [x] CPython `Grammar/python.gram` のコア構文ルールがコンパイルされ、サンプルの Python ソースコードが正しく構文解析できること（`test_peg_cpython_e2e.scm` 100% PASS）。
- [x] Issue #908 で CPython 構文に移行された `tools/grammars/*.peg` 全 13 文法ファイルが Pure Scheme コンパイラでコンパイル・ビルド可能であることがテストで実証されていること（`test_peg_grammars.scm` 100% PASS）。
- [x] CWE-400（バックトラック爆発）および CWE-674（左再帰無限ループ）に対する安全防御がテストで検証されていること。
- [x] `make -C ulisp test_peg` が新設され、すべての PEG テストスイートが 100% PASS すること。
- [x] `make -C ulisp lint_sexpr verify_zero_gauche` がエラー 0 件で PASS すること。
- [x] `make py_compile && make static_analysis` がエラー 0 件で PASS すること。
- [x] すべてのファイルリンクにおいて相対パス規則が厳格に守られていること。
