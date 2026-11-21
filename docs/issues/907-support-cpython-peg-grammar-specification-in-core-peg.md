---
ID: 907
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] Support CPython PEG Grammar Specification in src/core/peg (ID: 907)

## 1. 概要 / Summary
[[DSN-25]](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) および [[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) に基づき、`src/core/peg`（Packrat PEG コンパイラおよびランタイム）において、CPython 公式の PEG 文法仕様（PEP 617 / [Grammar/python.gram](https://github.com/python/cpython/tree/main/Grammar)）をファーストクラスでサポートする機能拡張を実装する。

現在、`src/core/peg/compiler/parser.py` は Bryan Ford POPL '04 記法（`<-` によるルール定義、`/` による選択、`name:expr` による変数束縛）を中心に対応している。本 Issue では、CPython の標準 PEG 構文であるコロンによるルール定義（`rule: e1 | e2`）、パイプ記号による複数行/先頭選択（`| alt`）、イコールによる変数束縛（`name=expr` や `(name=expr)`）、カット演算子（`~`）、角括弧によるオプショナル（`[expr]`）、セパレータ付きリスト（`','.expr+` / `sep.rule+` / `sep.rule*`）、および Warth 左再帰を完全サポートし、CPython の `.gram` 構文および `tools/grammars/*.peg` をそのままコンパイル可能にする。

既存の Bryan Ford 記法（`<-`, `/`, `name:expr`, `[a-z]` 文字クラス）との 100% 後方互換性を厳格に維持する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-25] Pure Python Packrat PEG Parser Engine Specification](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
  - [[DSN-33-04] ULisp 言語ワークベンチ・インタプリタ自動生成 ＆ ゲスト言語ランタイムアーキテクチャ設計書 (第3章 PEG/Packrat 構文解析フロントエンドのゼロコスト自動合成)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
- 外部標準:
  - PEP 617: New PEG parser for CPython
  - CPython Grammar Specification (`Grammar/python.gram`)
- 後続 Issue:
  - [Issue #908: tools/grammars/*.peg 全文法ファイルの CPython PEG 構文への統一マイグレーション](908-migrate-tools-grammars-to-cpython-peg-grammar-syntax.md)
  - [Issue #894: Pure Scheme コンパイル時 PEG パーサージェネレータの実装](894-implement-pure-scheme-compile-time-peg-parser-generator.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/core/peg/compiler/ast_nodes.py](../../src/core/peg/compiler/ast_nodes.py)
  - `GatherExpr`: セパレータ付きリスト AST ノード（`separator: Expression`, `element: Expression`, `is_one_or_more: bool`）
  - `CutExpr`: 既存ノードの活用・検証
- [x] [src/core/peg/runtime.py](../../src/core/peg/runtime.py)
  - `Gather`: セパレータ付きリストコンビネータ（`Gather(separator, element, is_one_or_more=True)`）
  - `CutOp` / `Cut`: シーケンス内でのバックトラック遮断セマンティクスの確認
- [x] [src/core/peg/compiler/parser.py](../../src/core/peg/compiler/parser.py)
  - ルール定義構文: `rule: ...`（コロン `:`）のサポート、先行パイプ `|` の許容
  - 変数束縛構文: `name=expr`（イコール `=`）のサポート
  - カット構文: `~`（チルダ）トークンの認識と `CutExpr` 生成
  - オプショナル構文: `[expr]`（角括弧）のパース（文字クラス `[a-z]` との共存）
  - セパレータ付きリスト記法: `sep.rule+` および `sep.rule*` のパースと `GatherExpr` 生成
- [x] [src/core/peg/compiler/backend/python.py](../../src/core/peg/compiler/backend/python.py)
  - `GatherExpr` のコード生成ハンドラ追加（`Gather(...)` またはループ展開）
- [x] [tests/core/peg/compiler/test_cpython_grammar.py](../../tests/core/peg/compiler/test_cpython_grammar.py)
  - CPython PEG 構文のパース、コード生成、および実行時構文解析の網羅的検証テスト
- [x] [docs/issues/README.md](README.md) (Issue 台帳更新)

---

## 4. セキュリティ・堅牢性設計 / Security and Robustness
1. **ReDoS / 悪意ある文法定義の防止**:
   - `Gather` コンビネータにおいて、セパレータまたは要素が 0 文字（空文字列）にマッチして無限ループに陥るケースを検出・防止（空マッチ時の前進ガード）。
2. **スタック枯渇防止**:
   - 深くネストされた括弧や角括弧（`[[[[...]]]]`）に対する再帰深度リミット（`recursion_limit`）。
3. **カット演算子の決定性**:
   - カット演算子 `~` 発動時、コミットフラグを正確に管理し、不正なバックトラックによる計算量増大（指数関数爆発）を確実に遮断。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/907-support-cpython-peg-grammar-specification-in-core-peg`

### Step 1: AST ノードの追加 (`ast_nodes.py`)
- `GatherExpr(Expression)` を定義:
  ```python
  @dataclass(frozen=True)
  class GatherExpr(Expression):
      """Separator-delimited list expression (e.g. sep.rule+ or sep.rule*)."""
      separator: Expression
      element: Expression
      is_one_or_more: bool = True
  ```

### Step 2: ランタイムコンビネータの追加 (`runtime.py`)
- `Gather(Parser[List[T]])` クラスを定義:
  - `separator: Parser[Any]`, `element: Parser[T]`, `is_one_or_more: bool = True`
  - `parse_at`: 最初の要素をパース後、`(separator, element)` の反復をパースして結果のリストを蓄積。空前進をチェックして無限ループを防止。

### Step 3: Meta-Grammar パーサーの拡張 (`parser.py`)
1. **トークン定義の追加**:
   - `cut_tok = lex(Lit("~"))`
   - `equal_tok = lex(Lit("="))`
   - `lbracket = lex(Lit("["))`
   - `rbracket = lex(Lit("]"))`
2. **オプショナル角括弧 `[expr]` と文字クラス `[a-z]` の共存**:
   - `[` の後に文字クラス仕様（正規表現的レンジ等、空白なし）としてパースできなければ、`Seq(lbracket, choice_ref, rbracket).map(lambda r: OptExpr(r[1]))` としてパース。
3. **カット `~` の認識**:
   - `cut_tok.map(lambda _: CutExpr())` を primary または要素に追加。
4. **セパレータ付きリスト `sep.rule+` / `sep.rule*`**:
   - `sep_dot = Seq(primary, dot_tok, primary, Choice(plus_tok, star_tok))`
   - `GatherExpr` を生成。
5. **変数束縛 `name=expr`**:
   - `Seq(ident_tok, Choice(colon_tok, equal_tok), suffixed).map(_make_named)`
6. **ルール定義 `rule: expr` と先行パイプ**:
   - `arrow_tok` を `Choice(Lit("<-"), Lit(":"), Lit("="))` に拡張。
   - `choice_p` において、先頭の `Opt(slash_tok)`（行頭/先頭の `|`）を許容。

### Step 4: Python コードジェネレータの対応 (`backend/python.py`)
- `GatherExpr` のエミッタを追加:
  ```python
  GatherExpr: lambda self, e, r: f"Gather({self._emit_expr(e.separator, r)}, {self._emit_expr(e.element, r)}, is_one_or_more={e.is_one_or_more})"
  ```
- `_PEG_SYMBOLS` に `"Gather"` を追加。

### Step 5: 網羅的テストスイートの実装
- `tests/core/peg/compiler/test_cpython_grammar.py` を作成:
  - CPython スタイルの文法定義（複数行 `|`、`name=expr`、`[expr]`、`~`、`sep.rule+`）のパース。
  - 生成された Python パーサーコードの実行と動作検証。
  - 既存の全 PEG テスト（75件）の後方互換性検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `ast_nodes.py` に `GatherExpr` が定義されていること。
- [ ] `runtime.py` に `Gather` コンビネータが実装され、単体で正しく動作すること。
- [ ] `parser.py` が CPython PEG 構文（`rule:`, `| alt`, `name=expr`, `[expr]`, `~`, `sep.rule+`, `sep.rule*`）をパースできること。
- [ ] `backend/python.py` が `GatherExpr` を含む CPython PEG 構文から有効な Python コードを生成できること。
- [ ] Bryan Ford 記法（`<-`, `/`, `name:expr`）との 100% 後方互換性が維持されていること。
- [ ] 新規テスト `tests/core/peg/compiler/test_cpython_grammar.py` を含む全テストが 100% PASS すること（`.venv/bin/pytest tests/core/peg/`）。
- [ ] `make py_compile && make static_analysis` がエラー 0 件で PASS すること。
- [ ] 相対パス規則が厳格に守られていること。
