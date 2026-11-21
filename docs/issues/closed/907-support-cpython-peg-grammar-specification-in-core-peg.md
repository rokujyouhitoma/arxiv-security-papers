---
ID: 907
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-11-21
---

# [FEAT/ENH] Support CPython PEG Grammar Specification in src/core/peg (ID: 907)

## 1. 概要 / Summary
[[DSN-25]](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) および [[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) に基づき、`src/core/peg`（Packrat PEG コンパイラおよびランタイム）において、CPython 公式の PEG 文法仕様（PEP 617 / [Grammar/python.gram](https://github.com/python/cpython/tree/main/Grammar)）をファーストクラスでサポートする機能拡張を実装する。

本 Issue の明確なゴールの一つとして、**CPython 公式の文法仕様書（`Grammar/python.gram`）および `tools/grammars/*.peg` をそのままパース・コンパイルできること**を設定する。

現在、`src/core/peg/compiler/parser.py` は Bryan Ford POPL '04 記法（`<-`、`/`、`name:expr`）を中心に対応している。本改修では以下の CPython PEG 構文要素を完全サポートし、同時に既存の Bryan Ford 記法との 100% 後方互換性を厳格に保証する。

1. **ルール定義**: `rule_name[type_opt] (memo_opt): expr`（コロン、戻り値型注釈、ルールオプション）
2. **選択肢**: 行頭/先行パイプ `|` およびインデントされた複数行オルタナティブ
3. **変数束縛**: `name=expr`、型注釈付き束縛 `name[type]=expr`、オプショナル束縛 `name=[expr]`
4. **オプショナル**: 角括弧 `[expr]`（文字クラス `[a-z]` との決定論的分離）および `expr?`
5. **セパレータ付きリスト**: `sep.rule+` および `sep.rule*`（`GatherExpr`）
6. **カット演算子**: `~`（バックトラック遮断 / コミット）
7. **メタディレクティブ**: `@header`, `@trailer`, `@include`, `@subheader`（三重引用符 `'''...'''` / `"""..."""` 対応）
8. **キーワード表記**: `'...'`（予約語）、`"..."`（ソフトキーワード）

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
  - `RuleDef`: `return_type: Optional[str]`, `modifiers: List[str]` フィールドの追加
  - `GrammarDef`: `directives: Dict[str, str]`（`@trailer`, `@include` 等の包括メタデータ保持）
- [x] [src/core/peg/runtime.py](../../src/core/peg/runtime.py)
  - `Gather(Parser[List[T]])`: セパレータ付きリストコンビネータ（空マッチ時の前進ガード付き）
  - `CutOp` / `Cut`: シーケンス内でのバックトラック遮断セマンティクスの確認
- [x] [src/core/peg/compiler/parser.py](../../src/core/peg/compiler/parser.py)
  - ルール定義構文: `rule_name[type] (memo):`（コロン `:`）のサポート、先行パイプ `|` の許容
  - 変数束縛構文: `name=expr`、`name[type]=expr`
  - カット構文: `~`（チルダ）トークンの認識と `CutExpr` 生成
  - オプショナル構文: `[expr]`（角括弧）のパース（文字クラス `[a-z]` との共存判定）
  - セパレータ付きリスト記法: `sep.rule+` および `sep.rule*` のパースと `GatherExpr` 生成
  - メタディレクティブ: `@header`, `@trailer`, `@include`（三重引用符 `'''...'''` 対応）
- [x] [src/core/peg/compiler/backend/python.py](../../src/core/peg/compiler/backend/python.py)
  - `GatherExpr` の Python コード生成ハンドラ追加（`Gather(...)`）
- [x] [src/core/peg/compiler/backend/javascript.py](../../src/core/peg/compiler/backend/javascript.py)
  - `GatherExpr` の JS コード生成ハンドラ追加
- [x] [tests/core/peg/compiler/test_cpython_grammar.py](../../tests/core/peg/compiler/test_cpython_grammar.py)
  - CPython PEG 構文のパース、コード生成、および実行時構文解析の網羅的検証テスト
  - CPython 公式 `python.gram` サンプルの構文解析パス検証
- [x] [docs/issues/README.md](README.md) (Issue 台帳更新)

---

## 4. セキュリティ・堅牢性設計 / Security and Robustness

1. **ReDoS / 悪意ある文法定義の防止**:
   - `Gather` コンビネータにおいて、セパレータまたは要素が 0 文字（空文字列）にマッチして無限ループに陥るケースを検出・防止（空マッチ時の前進ガード）。
2. **スタック枯渇防止**:
   - 深くネストされた括弧や角括弧（`[[[[...]]]]`）に対する再帰深度リミット（`recursion_limit`）。
3. **カット演算子の決定性**:
   - カット演算子 `~` 発動時、コミットフラグを正確に管理し、不正なバックトラックによる計算量増大（指数関数爆発）を確実に遮断。
4. **文字クラスとオプショナル角括弧の決定論的分離**:
   - `[a-z]` や `[^0-9]` 等の正規表現文字クラスと、`[ expr ]`（オプショナル式）の衝突を文脈的に完全分離。
   - `[` の直後が `^` または空白なしの文字範囲表記（`-`）である場合は `CharClassExpr`、識別子や式が続く場合は `OptExpr` として決定論的にディスパッチ。

---

## 5. 詳細実装方針 / Detailed Implementation Plan
Target Branch: `feat/907-support-cpython-peg-grammar-specification-in-core-peg`

### Step 1: AST ノードの拡張 (`ast_nodes.py`)
1. `GatherExpr` ノードの追加:
   ```python
   @dataclass(frozen=True)
   class GatherExpr(Expression):
       """Separator-delimited list expression (e.g. sep.rule+ or sep.rule*)."""
       separator: Expression
       element: Expression
       is_one_or_more: bool = True
   ```
2. `RuleDef` に型注釈・修飾子フィールドを追加:
   ```python
   @dataclass(frozen=True)
   class RuleDef:
       name: str
       expr: Expression
       docstring: str = ""
       return_type: Optional[str] = None
       modifiers: List[str] = field(default_factory=list)
   ```
3. `GrammarDef` にディレクティブ辞書を追加:
   ```python
   @dataclass(frozen=True)
   class GrammarDef:
       name: str
       rules: List[RuleDef] = field(default_factory=list)
       header_code: str = ""
       start_rule: Optional[str] = None
       directives: Dict[str, str] = field(default_factory=dict)
   ```

### Step 2: ランタイムコンビネータの追加 (`runtime.py`)
1. `Gather(Parser[List[T]])` クラスを実装:
   - `__init__(self, separator: Parser[Any], element: Parser[T], is_one_or_more: bool = True, name: Optional[str] = None)`
   - `parse_at`:
     - 最初の `element` をパース。失敗時、`is_one_or_more=False` なら `ParseResult(True, [], pos)`、True なら失敗。
     - 以降、ループで `separator` → `element` を順次パース。
     - セパレータと要素のマッチによって現在位置が進まない場合（空マッチ）、無限ループ防止例外またはパース終了として処理。
2. `CutOp`（`Cut`）のシーケンス内コミット挙動を検証。

### Step 3: Meta-Grammar パーサーの拡張 (`parser.py`)
1. **トークンとレクサーの拡充**:
   - `cut_tok = lex(Lit("~"))`
   - `equal_tok = lex(Lit("="))`
   - `lbracket = lex(Lit("["))`
   - `rbracket = lex(Lit("]"))`
   - `triple_quote_dq = lex(Reg(r'"""(?:[^"\\]|\\.|"(?!"")|""(?!"))*"""'))`
   - `triple_quote_sq = lex(Reg(r"'''(?:[^'\\]|\\.|'(?!'')|''(?!'))*'''"))`
2. **文字クラス vs 角括弧オプショナル式の分離**:
   - `char_class_tok = lex(Reg(r"\[(?:\^)?(?:\\\]|[^ \t\r\n\]])+(?:-(?:\\\]|[^ \t\r\n\]])+)*\]"))`
   - オプショナル式: `opt_bracket_p = Seq(lbracket, choice_ref, rbracket).map(lambda res: OptExpr(res[1]))`
   - `primary` の選択順序で `opt_bracket_p` と `char_class_p` を適切に合成。
3. **カット `~` の認識**:
   - `cut_p = cut_tok.map(lambda _: CutExpr())` をシーケンス要素に追加。
4. **セパレータ付きリスト `sep.rule+` / `sep.rule*`**:
   - `gather_p = Seq(primary, dot_tok, primary, Choice(plus_tok, star_tok))`
   - `+` は `is_one_or_more=True`、`*` は `is_one_or_more=False` として `GatherExpr` を生成。
5. **変数束縛 `name=expr` および型注釈 `name[type]=expr`**:
   - `name_assign = Seq(ident_tok, Opt(bracket_type), Choice(equal_tok, colon_tok), suffixed)`
   - `NamedExpr` を生成（必要に応じて型情報を保持）。
6. **ルール定義 `rule_name[type] (memo):` と先行パイプ**:
   - ルール名直後の `Opt(bracket_type)` および `Opt(rule_modifiers)` をパース。
   - ルール区切り矢印: `arrow_tok = Choice(Lit("<-"), Lit(":"), Lit("="))`
   - `choice_p`: 先頭の `Opt(slash_tok)`（行頭/先頭の `|`）を許容。
7. **メタディレクティブの拡充**:
   - `@header`, `@trailer`, `@include`, `@subheader` 等をパースし、ディレクティブとして AST に格納。

### Step 4: コードジェネレータの対応 (`backend/python.py`, `backend/javascript.py`)
1. **Python バックエンド (`backend/python.py`)**:
   - `GatherExpr` のエミッタ登録:
     ```python
     GatherExpr: lambda self, e, r: f"Gather({self._emit_expr(e.separator, r)}, {self._emit_expr(e.element, r)}, is_one_or_more={e.is_one_or_more})"
     ```
   - `_PEG_SYMBOLS` に `"Gather"` を追加。
2. **JavaScript バックエンド (`backend/javascript.py`)**:
   - `GatherExpr` の JS 生成ハンドラを追加。

### Step 5: 網羅的テストスイートの実装
- `tests/core/peg/compiler/test_cpython_grammar.py` を作成:
  - 1. 単体構文テスト: `rule: a | b`, `name=expr`, `[expr]`, `~`, `','.item+`, `item*`
  - 2. CPython スタイル複数行インデント構文のパースと AST 構築検証
  - 3. 生成パーサーによる実行時構文解析とセマンティックアクション検証
  - 4. CPython 公式 `python.gram` のサブセット（実文法ブロック）を直接パースし、エラーなく GrammarDef AST が生成されることの検証
  - 5. 既存全 75 テスト（Ford 記法含む）の後方互換性テスト実行

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ast_nodes.py` に `GatherExpr` が定義され、`RuleDef`, `GrammarDef` が CPython メタデータに対応していること。
- [x] `runtime.py` に `Gather` コンビネータが実装され、単体で正しく動作すること（空マッチ無限ループ防止を含む）。
- [x] `parser.py` が CPython PEG 構文（`rule:`, `| alt`, `name=expr`, `[expr]`, `~`, `sep.rule+`, `rule[type]:` 等）をエラーなくパースできること。
- [x] `backend/python.py` および `backend/javascript.py` が `GatherExpr` を含む CPython PEG 構文から有効なコードを生成できること。
- [x] Bryan Ford 記法（`<-`, `/`, `name:expr`, `[a-z]`）との 100% 後方互換性が維持されていること。
- [x] CPython 公式 `python.gram` の主要構文ブロックがパース可能であることがテストで実証されていること。
- [x] 新規テスト `tests/core/peg/compiler/test_cpython_grammar.py` を含む全テスト（75+件）が 100% PASS すること（`.venv/bin/pytest tests/core/peg/`）。
- [x] `make py_compile && make static_analysis` がエラー 0 件で PASS すること。
- [x] すべてのファイル参照において相対パス規則が厳格に守られていること。
