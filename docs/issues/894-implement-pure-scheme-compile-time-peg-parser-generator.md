---
ID: 894
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] Implement Pure Scheme Compile-Time PEG Parser Generator (ID: 894)

## 1. 概要 / Summary
[[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) 第 3 章（構文解析フロントエンドのゼロコスト自動合成）および [[DSN-25]](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) に基づき、Pure Scheme / ULisp マクロ体系による **Compile-Time Packrat PEG 構文解析器ジェネレータ** を実装する。

特に、**CPython 公式の PEG 文法仕様（[Grammar/python.gram](https://github.com/python/cpython/tree/main/Grammar) / PEP 617）をコンパイルし、Python ソースコードを構文解析できる能力を獲得することを主要なマイルストーンゴール**とする。
さらに、[[Issue #907]](907-support-cpython-peg-grammar-specification-in-core-peg.md) および [[Issue #908]](908-migrate-tools-grammars-to-cpython-peg-grammar-syntax.md) にて CPython PEG 構文に統一移行された `tools/grammars/*.peg`（`calc.peg`, `graph_query.peg`, `sql_*.peg`, `yaml_frontmatter.peg` 等）についても、本ジェネレータを通じて Pure Scheme 上で直接コンパイル・ビルド可能とし、クロスランゲージな文法共有基盤を確立する。

従来の構文解析生成器（Yacc/Bison/ANTLR 等）は外部バイナリ依存や複雑な C コード生成を必要とし、生成されたパーサーもヒープ上に大量の中間 AST 木を構築するためメモリ負荷が高い。本 Issue では二村射影とステージ多相コンパイルの数理モデルを活用し、宣言的文法定義（`define-grammar` または CPython 形式の `.gram`）から手書き再帰下降パーサー並みの $O(1)$ ディスパッチ表と Warth 左再帰メモ化ループを備えた構文解析ルーチンを Pure Scheme で完全自動生成する。さらに、セマンティックアクションを CPS で直結することで中間 AST 確保を完全に消去（Zero-Allocation Stream Parsing）する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-04] ULisp 言語ワークベンチ・インタプリタ自動生成 ＆ ゲスト言語ランタイムアーキテクチャ設計書 (第3章 PEG/Packrat 構文解析フロントエンドのゼロコスト自動合成)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [[DSN-25] Pure Python Packrat PEG Parser Engine Specification](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
  - [[DSN-33-03] ULisp ステージ多相メタコンパイラ ＆ 二村射影フラクタル実行基盤設計書 (第3章 eval-in-stage)](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md)
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
- 外部標準・仕様:
  - PEP 617: New PEG parser for CPython (Guido van Rossum, Lysandros Nikolaou, Pablo Galindo Salgado)
  - Warth et al., "Packrat Parsers Can Support Left Recursion", PEPM 2008.

---

## 3. セキュリティ分析と脅威モデル / Security Threat Analysis
構文解析器は外部の信頼できない入力を直接受け取る第 1 境界（Attack Surface）であるため、以下の脆弱性に対する堅牢な多層防御を組み込む。

1. **CWE-400: Uncontrolled Resource Consumption (指数的バックトラック / ReDoS / メモ化メモリ爆発)**:
   - *脅威*: 悪意を持って細工された深い入れ子構造や曖昧な選択肢（e.g. `(a*)*`）により、パーサーが指数時間のバックトラックに陥るか、Packrat メモ化キャッシュがメモリを枯渇させる。
   - *防御策*:
     - **Packrat メモ化保証**: 各 `(Rule, Position)` ペアの結果を線形空間 $O(N)$ でメモ化し、最悪時間計算量を厳格に $O(N)$ に束縛。
     - **カット演算子（`~` / Commit）**: 確定したプレフィックスに対するバックトラックを明示的に遮断し、メモリ消費を即座に回収。
     - **Fuel / 再帰深度ハードリミット**: 構文解析ループに最大反復上限（燃料モデル）を導入し、無限ループを確実に遮断。
2. **CWE-674: Uncontrolled Recursion (スタックオーバーフロー)**:
   - *脅威*: 直接・間接の左再帰（Left Recursion: `expr: expr '+' term`）が無限再帰を引き起こしスタックを食いつぶす。
   - *防御策*:
     - **Warth アルゴリズムの適用**: メモ化テーブルに一時的な「失敗」をシードとして記録し、成長ループ（Growing the Seed）により最長一致が得られるまで反復拡張する反復的左再帰解決を実装。
3. **CWE-125 / CWE-787: Out-of-Bounds Read / Memory Safety**:
   - *脅威*: 入力文字列の末尾を超えた先読みやインデックス参照による不正アクセス。
   - *防御策*: Pure Scheme の文字列走査境界ガード（`0 <= pos <= len`）を強制し、`EOF` 境界を厳格に判定。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/workbench/peg.scm](../../ulisp/workbench/peg.scm) (新規: Packrat PEG コアエンジン、Warth 左再帰メモ化、CPython .gram コンパイラ)
- [ ] [ulisp/frontend/015_dsl_expander.scm](../../ulisp/frontend/015_dsl_expander.scm) (`define-grammar` マクロ構文拡張の登録)
- [ ] [ulisp/tests/test_workbench_peg.scm](../../ulisp/tests/test_workbench_peg.scm) (新規: PEG 単体、左再帰、および CPython 文法サブセット検証テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`COMPILER_BASE` への `workbench/peg.scm` 追加および `test_workbench_peg` ターゲット新設)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳ステータス更新)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/894-implement-pure-scheme-compile-time-peg-parser-generator`

### Phase 1: Packrat PEG コアエンジンと Warth 左再帰基盤 (`ulisp/workbench/peg.scm`)
1. **構文解析コンビネータ群の実装**:
   - `(peg-match-char c pos str)` / `(peg-match-string s pos str)`: 終端リテラル照合
   - `(peg-seq e1 e2 ...)`: 順序付き連結（Sequence）
   - `(peg-alt e1 e2 ...)`: 順序付き選択（Ordered Choice）
   - `(peg-opt e)`: オプショナル照合（`?` または `[e]`）
   - `(peg-star e)`: 0回以上繰り返し（`*`）
   - `(peg-plus e)`: 1回以上繰り返し（`+`）
   - `(peg-and e)`: ポジティブ先読み（`&e`）
   - `(peg-not e)`: ネガティブ先読み（`!e`）
   - `(peg-cut)`: バックトラック遮断コミット（`~`）
2. **Warth メモ化左再帰エンジン**:
   - メモ化エントリ: `<peg-memo-entry>` （結果、進んだ位置、左再帰検出ヘッド）
   - 左再帰検出: ルール適用開始時にメモ化テーブルへマーク。同一位置で同一ルールが再帰呼び出しされた場合、左再帰と判定しシード反復成長モードへ遷移。

### Phase 2: CPython PEG 文法仕様（PEP 617 / `.gram`）の構文解析 ＆ コンパイラ
1. **CPython `.gram` メタ文法パーサーの実装**:
   - ルール定義構文: `rule_name: alt1 | alt2 | ...`
   - 変数束縛: `a=expr` や `(a=expr)`
   - 先読み・カット: `&expr`, `!expr`, `~`
   - セパレータ付きリスト: `','.expr+` や `','.expr*`
   - セマンティックアクション: `{ action_expr }`
2. **中間表現（Grammar AST）から Scheme 手続きへのコンパイル**:
   - 各非終端記号を Pure Scheme の引数 `(pos str memo)` を取る高速クロージャ群へコンパイル。
   - 先頭文字（First Set）に基づくディスパッチ分岐を生成し、不要なマッチ試行を $O(1)$ でスキップ。

### Phase 3: Stage-Now / CPS ゼロアロケーションセマンティックアクション直結
1. **ストリーム構文解析と意味論の融合**:
   - 構文木（Tree）をヒープに一切割り当てず、マッチ成功と同時に CPS 継続または LIR ビルダー手続きを直接キック。
   - `stage-poly-lower` と連携し、文法規則が静的定数の場合はディスパッチとルール照合ループを残余コードから消去。

### Phase 4: CPython 文法（`Grammar/python.gram`）の検証とテストスイート (`ulisp/tests/test_workbench_peg.scm`)
1. **Group 1: 基本 PEG コンビネータ単体テスト**:
   - 終端文字列、文字範囲、選択、繰り返し、先読みの照合精度検証。
2. **Group 2: Warth 左再帰 ＆ 指数バックトラック回避テスト**:
   - 左再帰文法（算術式 `expr: expr '+' term | term` 等）の優先順位・結合規則の正確な解決検証。
   - カット演算子 `~` によるバックトラック刈り取り検証。
3. **Group 3: CPython `.gram` 文法コンパイラ E2E テスト**:
   - CPython のコア構文ルール（関数定義 `def ...`, 条件分岐 `if ...`, 式 `a + b * c`, リスト `[...]`, 辞書 `{...}`）を `.gram` 定義からコンパイル。
   - 実際の Python ソースコード断片を入力し、構文木または AST 構造が 100% 正確に抽出されることをアサーション検証。
4. **Group 4: セキュリティ境界テスト (CWE-400 / CWE-125 防御)**:
   - 深い再帰入力に対するスタック枯渇防止、入力境界超過時の安全遮断検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp/workbench/peg.scm` が新規作成され、Packrat PEG コンビネータおよび Warth 左再帰エンジンが実装されていること。
- [ ] CPython の PEG 文法規則（`python.gram` 準拠の左再帰、先読み、カット、変数束縛、リストセパレータ）を解釈・コンパイルできること。
- [ ] コンパイルされたパーサーにより、CPython サブセット（関数定義、制御フロー、算術式等）の Python コードが正常に構文解析できること。
- [ ] Issue #908 で CPython 構文に移行された `tools/grammars/*.peg`（`calc.peg` や `graph_query.peg` 等）を本ジェネレータで正常にコンパイル・ビルドできること。
- [ ] CWE-400（バックトラック爆発）および CWE-674（左再帰無限ループ）に対する安全防御がテストで実証されること。
- [ ] `make -C ulisp test_workbench_peg` が 100% PASS すること。
- [ ] `make -C ulisp lint_sexpr verify_zero_gauche` が PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
- [ ] [docs/issues/README.md](README.md) のステータスが `進行中 (In Progress)` に更新されていること。
