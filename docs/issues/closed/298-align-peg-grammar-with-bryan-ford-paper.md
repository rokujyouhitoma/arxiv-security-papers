---
ID: 298
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] Bryan Ford 論文（POPL '04）準拠 PEG 文法仕様への改定と実用的拡張の実装 (ID: 298)

## 1. 概要 / Summary
Packrat PEG ランタイムエンジンおよび事前コンパイラ（AOT Compiler: Issue #284, #293, #294, #297, DSN-25）の構文仕様を、Bryan Ford 氏の元祖 PEG 論文 **"Parsing Expression Grammars: A Recognition-Based Syntactic Foundation" (POPL '04)** の公式定義（Figure 1: Hierarchical syntax of parsing expression grammars）に正式準拠させる。

現在のリポジトリ内 PEG 構文は代入記号に `=` を用いており、文字クラス `[...]` や任意文字マッチ `.` がネイティブ構文として未実装（正規表現リテラル `/[0-9]+/` に依存）であった。本改定により、論文標準の規則定義記号 `<-` (LEFTARROW)、文字クラス `[...]` / 否定文字クラス `[^...]`、任意1文字マッチ `.` を第一級構文（First-Class Citizens）としてコアランタイム・AST・コードジェネレータ・メタ文法・セルフホスティングパーサーの全階層に統合する。

同時に、実用パーサー生成に不可欠な拡張機能（セマンティックアクション `{ ... }`、名前付きラベル `label:expr`、正規表現リテラル、ディレクティブ `@header` 等）との完全な調和を実現し、既存文法（`calc.peg`, `boolean_query.peg`, `turtle.peg`, `peg_meta.peg`）を新文法へ移行した上で、セルフホスティングの決定論的再現性（Fixpoint Invariant）を証明する。

### 主な提供機能
1. **規則定義記号 `<-` (LEFTARROW) の第一級サポート**:
   - Bryan Ford 論文の核心表記である `A <- e` 構文を導入。後方互換性維持のため従来の `A = e` も継続許容。
2. **文字クラス `[...]` および否定文字クラス `[^...]` の Pure Python ネイティブサポート**:
   - `[a-z0-9]`, `[^a-z]`, `[ \t\r\n]`, `[\-\]]` などの文字範囲・エスケープ表記を $O(1)$ 判定する `CharClass` コンビネータを新規実装。ReDoS のリスクを完全排除。
3. **任意1文字マッチ `.` (DOT) コンビネータの実装**:
   - 入力の現在位置から任意の 1 文字を消費・マッチする `AnyChar` コンビネータおよび AST ノード `AnyCharExpr` を追加。
4. **実用的拡張（Semantic Actions / Named Labels / Directives）の調和**:
   - セマンティックアクション `{ ... }`、名前付き変数バインド `label:expr`、`grammar Name`、`@header { ... }` を Bryan Ford 構文体系とシームレスに結合。
5. **既存文法ファイル（.peg）の論文スタイル移行**:
   - `grammars/calc.peg`, `grammars/boolean_query.peg`, `grammars/turtle.peg`, `grammars/peg_meta.peg` を `<-` および `[...]` 記法にリファクタリング。
6. **セルフホスティング再生成 & Fixpoint 保証**:
   - 新構文で記述された `grammars/peg_meta.peg` から `generated_meta_parser.py` を再生成し、自己パース・再コンパイル結果が完全一致すること（Fixpoint）を検証。
7. **DSN-25 設計仕様書の改定**:
   - Bryan Ford POPL '04 構文マッピングテーブルおよび実用拡張仕様を追記・更新。

---

## 2. Bryan Ford 論文（POPL '04）構文仕様と本リポジトリ文法仕様の対照分析 / Syntax Alignment Analysis

Bryan Ford 論文 Figure 1 の階層構文と、本リポジトリの実装対照マトリクスを以下に定義する：

| 構文要素 | Bryan Ford (POPL '04) 定義 | 改定前 (Before) | 改定後 (Target Specification) | 備考 / 互換性方針 |
| :--- | :--- | :--- | :--- | :--- |
| **規則定義** | `Ident <- Expr` | `ident = expr` | `Ident <- Expr`<br>*(互換: `Ident = Expr`)* | `<-` を正式標準とし、既存コード保護のため `=` も認識 |
| **順序付き選択** | `e1 / e2` | `e1 / e2` / `e1 \| e2` | `e1 / e2` / `e1 \| e2` | 論文準拠の `/` を推奨。BNF 風 `\|` も継続サポート |
| **連接** | `e1 e2` | `e1 e2` | `e1 e2` | 空白区切り連接（完全一致） |
| **反復・省略** | `e*`, `e+`, `e?` | `e*`, `e+`, `e?` | `e*`, `e+`, `e?` | 論文仕様と完全一致 |
| **構文述語** | `&e` (肯定), `!e` (否定) | `&e`, `!e` | `&e`, `!e` | 論文仕様と完全一致（入力不消費） |
| **文字クラス** | `Class <- '[' (!']' Range)* ']'`<br>`Range <- Char '-' Char / Char` | 未対応<br>*(正規表現 `/[a-z]/` 代用)* | `[a-z0-9]`, `[^a-z]`, `[ \t\r\n]` | `CharClass` による Pure Python $O(1)$ 高速判定 |
| **任意文字** | `DOT <- '.' Spacing` | 未対応 | `.` (DOT) | `AnyChar()` による 1 文字消費 |
| **文字列リテラル**| `'literal'`, `"literal"` | `'literal'`, `"literal"` | `'literal'`, `"literal"` | 論文仕様と完全一致 |
| **名前付きラベル**| *(論文外の実用的拡張)* | `name:expr` | `name:expr` | セマンティックアクションへの変数注入用（維持） |
| **アクション** | *(論文外の実用的拡張)* | `{ ... }` | `{ ... }` | Python コードによる AST 構築フック（維持） |
| **ディレクティブ**| *(論文外の実用的拡張)* | `grammar`, `@header` | `grammar`, `@header` | パーサークラス名およびヘッダー定義（維持） |

---

## 3. 15 大専門エージェントによる多角的レビュー ＆ 合意事項 / Multi-Agent Review Matrix

リポジトリ統治規程（`.agents/AGENTS.md`）に基づき、全 15 専門エージェントによる多角的な設計審査を実施・合意した：

| エージェント | 専門領域 | レビュー所見・合意事項 | 合意状況 |
| :--- | :--- | :--- | :---: |
| **1. Project Manager (PM)** | 統治・進行管理 | 論文準拠への改定と実用拡張の調和を承認。既存パーサーを壊さない後方互換性（`=` の維持）を最重要要求とする。 | **APPROVED** |
| **2. Information Security (SC)** | 脅威分析・堅牢化 | 文字クラスの Pure Python 化により ReDoS を根絶。文字クラス内エスケープ（`\]`, `\\`, `\-`）の安全な字句解析を義務付け。 | **APPROVED** |
| **3. Systems Architect (SA)** | アーキテクチャ整合 | コンビネータコア (`peg.py`)、ASTノード (`ast_nodes.py`)、コード生成 (`codegen.py`)、メタ文法 (`meta_grammar.py`) の責務分離を確認。 | **APPROVED** |
| **4. Software QA Specialist (QA)** | テスト・品質保証 | 単体テスト（`test_peg_paper_syntax.py`）の新設と、ブートストラップ Fixpoint（自己再コンパイル完全一致）の 100% 合格を要求。 | **APPROVED** |
| **5. Database Specialist (DB)** | SQL構文連携 | 将来的な SQL 方言の文字クラス認識（識別子・リテラル抽出）において、本 `CharClass` の性能優位性を確認。 | **APPROVED** |
| **6. Network Specialist (NW)** | 通信・プロトコル | ネットワークパーシング（HTTP / URI / RFC 3986 準拠の文字分類）に PEG 文字クラスが有効であることを確認。 | **APPROVED** |
| **7. IT Specialist (NLP & IR)** | 自然言語・検索 | 検索クエリ DSL のトークナイザーにおいて、文字クラスと `.` による正規表現依存度低減を歓迎。 | **APPROVED** |
| **8. IT Strategist (ST)** | 標準化・技術戦略 | Bryan Ford POPL '04 原著準拠により、学術的・国際的標準への整合性と OSS コミュニティでの可読性が向上。 | **APPROVED** |
| **9. IT Service Manager (SM)** | 運用監視・ロギング | AOT コンパイラ生成物の実行時オーバーヘッドゼロ（外部呼出なし）および構文エラー時の位置特定精度（行・列）の維持を承認。 | **APPROVED** |
| **10. Embedded Systems (ES)** | 低レイヤ・フットプリント | $O(1)$ テーブル探索による文字クラス判定が CPU キャッシュ効率とメモリ効率に優れていることを評価。 | **APPROVED** |
| **11. Systems Auditor (AUD)** | 監査・トレーサビリティ | POPL '04 論文 Figure 1 との対照トレーサビリティ、および DSN-25 改定による設計正当性の担保を確認。 | **APPROVED** |
| **12. UI/UX Designer (UI)** | 開発者体験 (DX) | 文法ファイル（`.peg`）の記述が学術標準と一致することで、文法定義作成者の認知負荷が大幅に低減。 | **APPROVED** |
| **13. Education Specialist (EDU)** | 教育・解説性 | Bryan Ford 論文の PEG 定義をそのまま解説教材・仕様書に転記可能となり、ドキュメントの教育的価値が向上。 | **APPROVED** |
| **14. Software Dev (SWD)** | コア実装・アルゴリズム | `CharClass`、`AnyChar`、AST ノード、コード生成ディスパッチテーブルの実装方針を策定。Xenon Grade A ($CC \le 4$) 遵守。 | **APPROVED** |
| **15. Application Specialist (APS)**| アプリ統合・Turtle | `turtle.peg` および `calc.peg` の新構文移行が既存の W3C RDF インジェストや CLI 動作に影響しないことを確認。 | **APPROVED** |

---

## 4. セキュリティ分析 (STRIDE Threat Model) と防御策 / Security Analysis & STRIDE Mitigations

| 脅威分類 (STRIDE) | 潜在リスク・攻撃ベクトル | 具体的防御策・実装仕様 |
| :--- | :--- | :--- |
| **Spoofing (なりすまし)** | 文法定義内の不正なルール名による内部名前空間汚染 | 識別子トークンを `[A-Za-z_][A-Za-z0-9_]*` に制限し、Python 予約語との衝突防止サフィックスを付与。 |
| **Tampering (改ざん)** | 不正な文字クラスエスケープによる境界逸脱・パース結果改ざん | 文字クラスのパース時に `\\` によるエスケープシーケンス（`\]`, `\-`, `\\`, `\n`, `\t`, `\r`）を厳格に正規化・無毒化。 |
| **Repudiation (否認)** | 構文エラー時の不正確なエラー位置による原因特定困難 | `ParseContext` の Max-Position Tracking により、最も深い失敗位置の行番号・列番号・周辺スニペットを正確に出力。 |
| **Information Disclosure (情報漏洩)**| 文法ファイル解析時の未処理例外による内部スタックトレース露出 | `PEGSyntaxError` に構文診断情報を封じ込め、外部入力に起因するクラッシュを防止。 |
| **Denial of Service (DoS / ReDoS)** | 複雑な文字クラス定義に対する正規表現エンジンの破局的バックトラッキング | `CharClass` は範囲リストおよび文字セットによる直接 $O(1)$ 数値・文字比較（Pure Python）を行い、正規表現エンジンをバイパスして ReDoS を根絶。 |
| **Elevation of Privilege (権限昇格)** | セマンティックアクション `{ ... }` への不正な Python コード注入 | AOT コンパイルは信頼できる `.peg` ファイル（静的リソース）のみを対象とし、動的 `eval`/`exec` は実行時パーサーで一切行わない。 |

---

## 5. トレーサビリティ / Traceability
- 発端: PEG の `.peg` ファイル記述が Bryan Ford 論文と異なっていることに対する調査および論文準拠・実用化要請
- 関連標準・先行技術:
  - Bryan Ford (POPL '04): *Parsing Expression Grammars: A Recognition-Based Syntactic Foundation*
  - PEP 617: New PEG parser for CPython
  - DSN-25: 純粋 Python 製汎用 Packrat PEG ランタイム基盤および構文解析エンジン統合設計仕様書
- 先行 Issue:
  - Issue #284: Packrat PEG コアランタイム基盤の実装
  - Issue #293: PEG 事前コンパイラ (AOT Compiler) 基盤の実装
  - Issue #294: W3C Turtle 1.1 パーサーの AOT 化と運用パイプライン統合
  - Issue #297: PEG AOT コンパイラのセルフホスティング（自己完結ブートストラップ化）

---

## 6. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [MODIFY] `src/core/structures/peg.py` (`AnyChar`, `CharClass` コンビネータおよびファクトリの追加)
- [x] [MODIFY] `src/core/structures/peg_compiler/ast_nodes.py` (`CharClassExpr`, `AnyCharExpr` ASTノード追加)
- [x] [MODIFY] `src/core/structures/peg_compiler/codegen.py` (新ノードのコード生成対応、インポートシンボル更新)
- [x] [MODIFY] `src/core/structures/peg_compiler/meta_grammar.py` (`<-`, `[...]`, `.` のパース対応)
- [x] [MODIFY] `grammars/peg_meta.peg` (メタ文法自身の論文スタイル改訂: `<-`, `[...]`, `.` 適用)
- [x] [MODIFY] `src/core/structures/peg_compiler/generated_meta_parser.py` (ブートストラップ再コンパイル生成)
- [x] [MODIFY] `grammars/calc.peg` (`<-` & `[...]` 記法適用)
- [x] [MODIFY] `grammars/boolean_query.peg` (`<-` 記法適用)
- [x] [MODIFY] `grammars/turtle.peg` (`<-` 記法適用)
- [x] [NEW] `tests/core/test_peg_paper_syntax.py` (論文準拠構文網羅テスト)
- [x] [MODIFY] `tests/core/test_peg_bootstrap.py` (新構文下での Fixpoint 検証)
- [x] [MODIFY] `docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md` (構文対照表および仕様追記)
- [x] [MODIFY] `docs/issues/README.md` (台帳ステータス更新)
- [x] [MODIFY] `docs/README.md`
- [x] [MODIFY] `README.md`

---

## 7. 実装方針 / Implementation Plan
Target Branch: `feat/298-align-peg-grammar-with-bryan-ford-paper`

### Step 1: コアランタイムコンビネータの拡張 (`src/core/structures/peg.py`)
1. **`AnyChar` コンビネータの実装**:
   - 入力が EOF でなければ現在位置の 1 文字を消費し `ParseResult(True, ch, pos + 1)` を返却。EOF 時は失敗。
   - ファクトリ関数 `Dot()` の提供。
2. **`CharClass` コンビネータの実装**:
   - 仕様: `CharClass(spec: str, inverted: bool = False, name: Optional[str] = None)`
   - 内部で `spec` 文字列から文字範囲 `(start, end)` のリストおよび単一文字の集合をパース。
   - `\n`, `\t`, `\r`, `\\`, `\]`, `\-` のエスケープシーケンスを安全に解決。
   - `inverted=True` の場合は否定文字クラス `[^...]` として動作。
   - $O(1)$ の直接数値・文字境界比較を行い、ReDoS を原理的に排除。
   - ファクトリ関数 `Class(spec, inverted=False)` の提供。

### Step 2: AST ノードの追加 (`src/core/structures/peg_compiler/ast_nodes.py`)
1. **`AnyCharExpr(Expression)`**:
   - 任意1文字マッチを表すデータクラス。
2. **`CharClassExpr(Expression)`**:
   - `raw_spec: str` および `inverted: bool = False` を保持するデータクラス。

### Step 3: コードジェネレータの拡張 (`src/core/structures/peg_compiler/codegen.py`)
1. `_PEG_SYMBOLS` に `"AnyChar"`, `"CharClass"`, `"Dot"`, `"Class"` を追加。
2. `_EXPR_EMITTERS` に以下を登録：
   - `AnyCharExpr`: `lambda self, e, r: "Dot()"` (または `"AnyChar()"`)
   - `CharClassExpr`: `lambda self, e, r: f"Class({cast(CharClassExpr, e).raw_spec!r}, inverted={cast(CharClassExpr, e).inverted})"`
3. Xenon Grade A ($CC \le 4$) を維持。

### Step 4: メタ文法パーサーの拡張 (`src/core/structures/peg_compiler/meta_grammar.py`)
1. 規則定義記号の拡張:
   - `rule_arrow = Choice(Lit("<-"), Lit("="))`
   - `new_rule_head = Seq(ident_tok, Choice(Lit("<-"), Lit("=")))`
2. 文字クラスパーサー `char_class_tok` の追加:
   - `[` から `]` までの文字列走査（エスケープ `\]` を考慮）。
   - `^` で始まる場合は `inverted=True` として `CharClassExpr` を生成。
3. 任意文字 `dot_tok`:
   - `.` を認識し `AnyCharExpr` を生成。
4. `primary` チョイスに `char_class_tok` および `dot_tok` を統合。

### Step 5: メタ文法ファイル自体の論文スタイル改定 (`grammars/peg_meta.peg`)
1. 規則定義をすべて `<-` に更新。
2. 文字クラス記法 `[...]` および `.` を導入：
   - 例: `ident <- name:[A-Za-z_][A-Za-z0-9_]* ws { return name }`
   - 規則ヘッダー認識の更新: `new_rule_head <- ident ("<-" / "=")`
3. セマンティックアクション `{ ... }` を維持。

### Step 6: AOT メタパーサーの再生成 (`src/core/structures/peg_compiler/generated_meta_parser.py`)
1. `python3 tools/peg_compiler/compile_peg.py grammars/peg_meta.peg -o src/core/structures/peg_compiler/generated_meta_parser.py` を実行。
2. 生成コードの整合性と文法検証。

### Step 7: 既存文法ファイルの論文スタイル移行
1. `grammars/calc.peg`:
   - `expr <- ...`, `term <- ...`, `factor <- ...`
   - `number <- raw:[0-9]+ { return int(raw) }`
   - `add_op <- op:[+-] { return op }`
   - `mul_op <- op:[*/] { return op }`
2. `grammars/boolean_query.peg`:
   - すべての規則定義を `<-` に移行。
3. `grammars/turtle.peg`:
   - すべての規則定義を `<-` に移行。

### Step 8: 包括的テストスイートの構築
1. `tests/core/test_peg_paper_syntax.py` の新規作成:
   - `A <- e` および `A = e` のパーステスト。
   - `[...]` 文字クラス（範囲、エスケープ、特殊文字、否定 `[^...]`）の単体・結合テスト。
   - `.` (AnyChar) の動作テスト（通常文字、特殊記号、EOF 時の失敗）。
   - 新構文でコンパイルされた `CalcParser` の四則演算実行テスト。
2. `tests/core/test_peg_bootstrap.py` の実行:
   - 全文法のパース確認、AST 等価性、Fixpoint 不変性の完全通過を確認。

### Step 9: ドキュメント改定と品質ゲート
1. `docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md` に Bryan Ford POPL '04 構文仕様整合の章を追記。
2. `make format`, `make static_analysis` (xenon Grade A, mypy --strict, flake8 0 errors, no noqa), `make test` を実行し全件合格。

---

## 8. 完了条件 / Success Criteria (DoD)
- [x] `src/core/structures/peg.py` に `AnyChar` および `CharClass` コンビネータが実装され、単体テストで正常動作すること。
- [x] `src/core/structures/peg_compiler/` (AST, Codegen, MetaGrammar) が `<-`, `[...]`, `[^...]`, `.` を完全サポートすること。
- [x] `grammars/peg_meta.peg` が Bryan Ford 論文スタイル（`<-` 等）で改定され、`generated_meta_parser.py` が決定論的に再生成できること。
- [x] `grammars/calc.peg`, `grammars/boolean_query.peg`, `grammars/turtle.peg` が新構文へ移行し、既存アプリケーション機能（検索・Turtle・計算）が 100% 正常動作すること。
- [x] 新規テスト `tests/core/test_peg_paper_syntax.py` および `tests/core/test_peg_bootstrap.py` を含む全テストが 100% PASS すること。
- [x] `docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md` が改定され、POPL '04 整合仕様が明文化されていること。
- [x] `make format`, `make static_analysis` (xenon Grade A $CC \le 4$, mypy --strict, flake8 0 errors, `# flake8: noqa` 追加なし) および `make test` に完全合格すること。
- [x] `docs/issues/README.md` 台帳に本 Issue が適切に反映されていること。
