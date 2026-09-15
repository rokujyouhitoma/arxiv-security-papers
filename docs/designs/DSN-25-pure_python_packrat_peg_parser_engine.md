# [DSN-25] 純粋 Python 製汎用 Packrat PEG (Parsing Expression Grammar) ランタイム基盤および構文解析エンジン統合設計仕様書
## 〜 線形時間 $O(N)$ パース保証・AST コンビネータ・検索クエリ/SQL/グラフDSL/オントロジー横断適用・将来の事前コード生成 (pegen型) 進化ロードマップ 〜

- **文書番号**: `DSN-25`
- **文書ステータス**: `APPROVED`
- **対象サブシステム**:
  - `src/core/structures/peg.py` (Packrat PEG 共通コアランタイムエンジン)
  - `src/core/structures/__init__.py` (共通構造公開エクスポート)
  - `src/search/query/query_parser.py` (Lucene 風ブーリアン・括弧ネスト検索クエリパーサー換装)
  - `src/database/sql/parser.py` (SQL 式・サブクエリ・構文要素の PEG 移行連携)
  - `src/graph/engine.py` (Canvas / REST API 向け CTI グラフクエリ DSL 拡張)
  - `src/ontology/` (W3C Turtle 1.1 / RDF インジェストパーサー基盤, Issue #199 連携)
  - `tools/peg_compiler/` (将来の事前コード生成型パーサージェネレータ拡張ロードマップ)
- **【主査・報告】 Software Development (SWD) / Systems Architect (SA)**
- **【共同主査】 IT Specialist (NLP & IR) / Database Specialist (DB)**
- **【参画】 15 大専門エージェント全員**:
  - Project Manager (PM), Systems Architect (SA), Information Security Specialist (SC),
  - Software Quality Assurance Specialist (QA), Database Specialist (DB), Network Specialist (NW),
  - IT Specialist (NLP & IR), IT Strategist (ST), IT Service Manager (SM),
  - Embedded Systems Specialist (ES), Systems Auditor (AUD), UI/UX Designer (UI),
  - Education Specialist (EDU), Software Development (SWD), Application Specialist (APS)

---

## 体系目次

- [1. 背景と設計思想 (Design Philosophy)](#1-背景と設計思想-design-philosophy)
  - [1.1 点在する手書き正規表現パーサーの限界と技術的負債](#11-点在する手書き正規表現パーサーの限界と技術的負債)
  - [1.2 なぜ PEG (Parsing Expression Grammar) なのか](#12-なぜ-peg-parsing-expression-grammar-なのか)
  - [1.3 ゼロ外部依存・純 Python (Zero External Dependencies) の原則](#13-ゼロ外部依存純-python-zero-external-dependencies-の原則)
- [2. 15 大専門エージェントによる多角的レビュー ＆ 合意事項](#2-15-大専門エージェントによる多角的レビュー--合意事項)
  - [2.1 エージェント別要求仕様マトリクス](#21-エージェント別要求仕様マトリクス)
  - [2.2 レビュー総括と合意承認](#22-レビュー総括と合意承認)
- [3. 数理的基盤とアルゴリズム設計 (Mathematical Formulation)](#3-数理的基盤とアルゴリズム設計-mathematical-formulation)
  - [3.1 PEG 形式文法仕様と基本演算子](#31-peg-形式文法仕様と基本演算子)
  - [3.2 Packrat メモ化アルゴリズムと線形時間 $O(N)$ の証明](#32-packrat-メモ化アルゴリズムと線形時間-on-の証明)
  - [3.3 構文エラー追跡メカニズム (Max-Position Tracking)](#33-構文エラー追跡メカニズム-max-position-tracking)
- [4. コアランタイムアーキテクチャ (`src/core/structures/peg.py`)](#4-コアランタイムアーキテクチャ-srccorestructurespegpy)
  - [4.1 クラス構造とデータフロー (Mermaid 構成図)](#41-クラス構造とデータフロー-mermaid-構成図)
  - [4.2 コンビネータ API 定義仕様](#42-コンビネータ-api-定義仕様)
  - [4.3 AST 変換フック (Semantic Action `.map()`) 仕様](#43-ast-変換フック-semantic-action-map-仕様)
  - [4.4 遅延評価・相互再帰解決 (`RuleRef`) 仕様](#44-遅延評価相互再帰解決-ruleref-仕様)
- [5. サブシステム横断適用設計 (Cross-System Integration)](#5-サブシステム横断適用設計-cross-system-integration)
  - [5.1 検索プラットフォーム: 括弧ネスト対応ブーリアンクエリパーサー](#51-検索プラットフォーム-括弧ネスト対応ブーリアンクエリパーサー)
  - [5.2 データベースエンジン: SQL 複雑式の PEG 連携](#52-データベースエンジン-sql-複雑式の-peg-連携)
  - [5.3 グラフエンジン: Canvas 向け CTI パスクエリ DSL](#53-グラフエンジン-canvas-向け-cti-パスクエリ-dsl)
  - [5.4 セキュリティオントロジー: W3C Turtle (.ttl) インジェスト構文解析](#54-セキュリティオントロジー-w3c-turtle-ttl-インジェスト構文解析)
- [6. 将来の事前コード生成型パーサージェネレータ (Ahead-of-Time Compiler) 進化ロードマップ](#6-将来の事前コード生成型パーサージェネレータ-ahead-of-time-compiler-進化ロードマップ)
  - [6.1 2段階進化戦略 (Phase 1 ランタイム → Phase 2 コンパイラ)](#61-2段階進化戦略-phase-1-ランタイム--phase-2-コンパイラ)
  - [6.2 PEG メタ文法によるセルフホスティング (ブートストラップ) 仕様](#62-peg-メタ文法によるセルフホスティング-ブートストラップ-仕様)
- [7. AOT コンパイラ実戦投入と本番運用 (Production Deployment) (Phase 2 実装完了: Issue #294)](#7-aot-コンパイラ実戦投入と本番運用-production-deployment-phase-2-実装完了-issue-294)
  - [7.1 W3C Turtle 1.1 パーサーの宣言的 AOT 換装](#71-w3c-turtle-11-パーサーの宣言的-aot-換装)
- [8. セキュリティ分析 (STRIDE Threat Model) と防御策](#8-セキュリティ分析-stride-threat-model-と防御策)
- [9. 非機能要件・品質基準・DoD](#9-非機能要件品質基準dod)
- [10. Phase 3: PEG AOT コンパイラのセルフホスティング（自己完結ブートストラップ化）仕様 (Issue #297)](#10-phase-3-peg-aot-コンパイラのセルフホスティング自己完結ブートストラップ化仕様-issue-297)
  - [10.1 概要と自己完結ブートストラップ哲学](#101-概要と自己完結ブートストラップ哲学)
  - [10.2 ブートストラップ循環依存の解消 (Pragmatic Bootstrapping Pattern)](#102-ブートストラップ循環依存の解消-pragmatic-bootstrapping-pattern)
  - [10.3 セルフホスティング仕様と AST マッピング](#103-セルフホスティング仕様と-ast-マッピング)
  - [10.4 完了条件 (DoD for Phase 3)](#104-完了条件-dod-for-phase-3)

---

## 1. 背景と設計思想 (Design Philosophy)

### 1.1 点在する手書き正規表現パーサーの限界と技術的負債

本プロジェクト (`arxiv-security-papers`) では、自作 RDBMS ([`DSN-05`](DSN-05-database_engine_architecture.md))、検索プラットフォーム ([`DSN-04`](DSN-04-search_engine_and_platform.md))、CTI ナレッジグラフ ([`DSN-18`](DSN-18-property_graph_database_engine.md))、および W3C オントロジー ([`DSN-22`](DSN-22-security_and_threat_ontology_w3c_specification.md)) など、高度なテキスト構文解析を必要とするサブシステムが多数稼働している。

しかし現状は、以下の通り**各コンポーネントがアドホックな手書き正規表現（Regex）や文字列分割（`split` / `strip`）で構文を解析**しており、構造的な限界と脆弱性に直面している：

1. **SQL パーサー ([`src/database/sql/parser.py`](../../src/database/sql/parser.py)) の肥大化**:
   - 約 2,000 行に及ぶ手書き正規表現で SQLite 方言を処理。
   - `GROUP BY` / `HAVING` の追加（Issue #254）において正規表現の境界誤認識によるテーブル名誤パースが発生したように、演算子の優先順位やネストしたサブクエリ（`SELECT * FROM (SELECT ...)`）の維持が困難。
2. **検索クエリパーサー ([`src/search/query/query_parser.py`](../../src/search/query/query_parser.py)) の表現力制限**:
   - 単一の正規表現マッチングでトークンを走査しているため、`(title:ransomware OR title:malware) AND -(tag:crypto OR author:smith)` のような**「括弧による論理演算のネスト構造」をパースできない**。
3. **グラフクエリ ([`src/graph/engine.py`](../../src/graph/engine.py)) のアドホック性**:
   - `q_low.startswith("community:")`, `q_low.startswith("ego:")` など単純な前方一致のみであり、複合条件（`community:0 AND label:ThreatActor`）や Cypher 風のパスマッチングが扱えない。

### 1.2 なぜ PEG (Parsing Expression Grammar) なのか

文脈自由文法（CFG / BNF）および従来の LALR(1) パーサー（Yacc/Bison 等）と比較して、PEG（Bryan Ford, 2004）は以下の決定的な優位性を持つ：

1. **曖昧性の完全排除 (Unambiguous by Design)**:
   - PEG は順序付き選択（Ordered Choice: `/`）を採用するため、常に左側の候補が優先され、文法上の曖昧性（Shift/Reduce 競合や Dangling-Else 問題）が原理的に発生しない。
2. **線形時間解析 $O(N)$ の保証 (Packrat Parsing)**:
   - 再帰下降パーサーにメモ化（Packrat Cache）を適用することで、どれほど複雑なバックトラックを伴う文法であっても入力文字列の長さ $N$ に正比例する線形時間 $O(N)$ で完結する。
3. **字句解析と構文解析の一元化 (Scannerless Parsing)**:
   - 別途 Lexer/Tokenizer を構築してトークン列に切り分ける必要がなく、文字ストリームに対して直接文法規則を適用可能。空白やコメントの扱いが極めて明瞭。
4. **構文述語 (Syntactic Predicates) による無制限先読み**:
   - 肯定先読み（`&e`）および否定先読み（`!e`）により、入力を消費することなく先々の構文パターンを検証できる。

### 1.3 ゼロ外部依存・純 Python (Zero External Dependencies) の原則

リポジトリ最高規程（`.agents/AGENTS.md`）に基づき、`parsimonious`, `lark`, `ply`, `antlr4` などのサードパーティ製ライブラリは一切導入しない。
約 250 行のピュア Python コードにより、軽量かつ極めて高速な Packrat PEG パーサーコアを `src/core/structures/peg.py` として新規開発する。

---

## 2. 15 大専門エージェントによる多角的レビュー ＆ 合意事項

### 2.1 エージェント別要求仕様マトリクス

| 専門エージェント | 視点 / 責務 | 審査コメント ＆ 必須要件 |
| :--- | :--- | :--- |
| **Project Manager (PM)** | ガバナンス・統制 | 段階的移行ロードマップの徹底。いきなり SQL パーサー全行を差し替えるのではなく、まず検索クエリ等で実績を作り安全に拡大すること。 |
| **Systems Architect (SA)** | 全体アーキテクチャ | 共通コア `src/core/structures/` の責務境界を維持。特定ドメイン（SQL や検索）に依存しない汎用抽象コンビネータとすること。 |
| **Information Security (SC)** | 脆弱性・DoS 対策 | 悪意あるネスト入力（例: `((((...))))` 1万段）による RecursionError / スタックオーバーフロー、および ReDoS 攻撃の完全防止策を講じること。 |
| **Software QA (QA)** | テスト・品質保証 | Xenon Grade A ($CC \le 4$) の厳格維持。パース成功時だけでなく、文法エラー時の行番号・列番号・期待トークン特定のアサーションを義務化。 |
| **Database Specialist (DB)** | SQL 適合性 | 将来的に `src/database/sql/parser.py` の複雑な式評価（`Expr` / `WhereClause`）を PEG に部分委譲できるインターフェースの担保。 |
| **Network Specialist (NW)** | 通信プロトコル | HTTP クエリパラメータや REST API URL のパーセントデコード済み文字列を安全かつ高速にパースできること。 |
| **IT Specialist (NLP & IR)** | 検索クエリ解釈 | Lucene/Elasticsearch 互換の括弧ネスト、ブーリアン演算子（`AND`/`OR`/`NOT`）、フレーズ検索（`"..."`）、ワイルドカード（`*`）の完全表現。 |
| **IT Strategist (ST)** | 投資対効果 (ROI) | 1 つの共通コアで検索・SQL・グラフDSL・オントロジーの 4 領域を共通化し、将来のパーサージェネレータ（事前コンパイラ）への進化パスを確保。 |
| **IT Service Manager (SM)** | 運用監視・診断 | パースエラー発生時にユーザーに対して直感的で明確なエラーメッセージ（`Syntax error at line 1, col 12: expected ")"`）を出力すること。 |
| **Embedded Systems (ES)** | メモリフットプリント | Packrat メモ化テーブルがメモリを無制限に消費しないよう、短命スコープでの自動回収、および必要に応じたキャッシュクリア機構。 |
| **Systems Auditor (AUD)** | 決定論・監査性 | 同一入力文字列に対して、実行環境や Python ハッシュシードに関わらず 100% 同一の AST 木を出力することの決定論的保証。 |
| **UI/UX Designer (UI)** | Canvas 連携 | Canvas 検索バーでの高度なクエリ入力（`community:0 AND label:ThreatActor`）を支援するための補完候補トークン抽出の親和性。 |
| **Education Specialist (EDU)** | 可読性・保守性 | PEG の文法定義コードが「読めばそのまま構文仕様書になる」直感的な Python DSL（コンビネータ記法）であること。 |
| **Software Dev (SWD)** | 低レベル実装品質 | 関数呼び出しオーバーヘッドの極小化。スライスを避け、インデックス整数 `pos` の受け渡しによるゼロコピー走査。 |
| **Application Specialist (APS)** | ビジネス機能連携 | Web UI および REST ゲートウェイからのクエリリクエストを低レイテンシ（$< 1\text{ms}$）で AST に変換し検索エンジンへ渡すこと。 |

### 2.2 レビュー総括と合意承認

全 15 大専門エージェントの満場一致により、**「Phase 1: インメモリ・コンビネータ型 Packrat PEG ランタイムコアの実装」および「Phase 2: 事前コード生成型コンパイラ（pegen型）への拡張ロードマップ」** を基本方針として本設計を正式承認（APPROVED）とする。

---

## 3. 数理的基盤とアルゴリズム設計 (Mathematical Formulation)

### 3.1 PEG 形式文法仕様と基本演算子

PEG は 4 つ組 $G = (V_N, V_T, R, e_S)$ で定義される形式文法である：
- $V_N$: 非終端記号の有限集合
- $V_T$: 終端記号（文字・トークン）の有限集合
- $R$: 規則の有限集合（各 $A \in V_N$ に対し一意の規則 $A \leftarrow e$）
- $e_S$: 開始構文式

PEG でサポートする構文式（Parsing Expression）の演算体系は以下の通り：

| 演算子種別 | PEG 表記 | クラス名 | 意味 / 動作 |
| :--- | :---: | :--- | :--- |
| **空文字列** | $\epsilon$ | `Empty()` | 何も消費せず常に成功。 |
| **文字列リテラル** | `"abc"` | `Literal("abc")` | 現在位置が `"abc"` と完全一致すれば消費して成功。 |
| **正規表現トークン** | `/pattern/` | `Regex(pattern)` | 現在位置から正規表現にマッチすれば消費して成功。 |
| **連接 (Sequence)** | $e_1 \ e_2$ | `Seq(e1, e2)` | $e_1$ をパースし、成功したら直後から $e_2$ をパース。 |
| **順序付き選択 (Choice)** | $e_1 \ / \ e_2$ | `Choice(e1, e2)` | $e_1$ を試し、成功すれば確定。失敗時のみ現在位置を復元し $e_2$ を試行。 |
| **0回以上の反復** | $e^*$ | `ZeroOrMore(e)` | $e$ が失敗するまで貪欲に繰り返す（常に成功扱い）。 |
| **1回以上の反復** | $e^+$ | `OneOrMore(e)` | $e$ を最低 1 回パースし、以降失敗するまで反復。 |
| **省略可能 (Optional)** | $e^?$ | `Opt(e)` | $e$ を試し、成功すればその結果、失敗しても消費せず成功扱い。 |
| **肯定先読み (And-Predicate)** | $\&e$ | `AndPred(e)` | $e$ がマッチするか検証するが、**入力は一切消費しない**。 |
| **否定先読み (Not-Predicate)** | $!e$ | `NotPred(e)` | $e$ がマッチ**しない**ことを検証。入力は消費しない。 |

### 3.2 Packrat メモ化アルゴリズムと線形時間 $O(N)$ の証明

#### メモ化テーブル構造
入力文字列の長さを $N$, 文法規則の総数を $K$ とする。Packrat パーサーは以下のキャッシュテーブルを維持する：
$$\text{MemoTable}: (RuleID, Position) \to (\text{ResultNode}, NextPosition) \cup \{\text{FAIL}\}$$

#### 線形時間 $O(N)$ の証明
1. 入力位置は $0$ から $N$ までの $N + 1$ 箇所存在する。
2. 文法内の各規則（またはコンビネータ式）の総数は静的に有限個 $K$ である。
3. したがって、メモ化テーブルのキーの組み合わせ総数は最大でも $(N + 1) \times K$ 個に制限される。
4. ある $(RuleID, Position)$ の評価において、キャッシュヒット時は $O(1)$ で復帰する。キャッシュミス時も各セルは高々 1 回しか計算されない。
5. したがって、全体の時間計算量は $O(K \cdot N) = O(N)$ の厳密な線形時間となり、指数的バックトラックは原理的に発生しない。 $\blacksquare$

### 3.3 構文エラー追跡メカニズム (Max-Position Tracking)

再帰下降パーサーの課題である「どこでパースに失敗したか不明瞭になる」問題を解決するため、グローバルな解析コンテキスト `ParseContext` で最も深い到達位置を追跡する：

パースが全体として失敗した際、`max_pos` を行番号・列番号（1-indexed）へ逆算し、`expected_tokens`（期待されていたトークン群）を列挙した詳細な `PEGSyntaxError` を生成する。

---

## 4. コアランタイムアーキテクチャ (`src/core/structures/peg.py`)

### 4.1 クラス構造とデータフロー (Mermaid 構成図)

```mermaid
classDiagram
    class ParseResult {
        +bool success
        +Any value
        +int next_pos
    }

    class Parser {
        <<abstract>>
        +parse(text: str) Any
        +parse_at(ctx: ParseContext, pos: int) ParseResult*
        +map(transform_fn) Parser
    }

    class Literal {
        -str expected
        +parse_at() ParseResult
    }
    class Regex {
        -Pattern pattern
        +parse_at() ParseResult
    }
    class Sequence {
        -List~Parser~ children
        +parse_at() ParseResult
    }
    class Choice {
        -List~Parser~ alternatives
        +parse_at() ParseResult
    }
    class Repetition {
        -Parser child
        -int min_count
        +parse_at() ParseResult
    }
    class Predicate {
        -Parser child
        -bool is_positive
        +parse_at() ParseResult
    }
    class RuleRef {
        -str name
        -Parser target
        +define(Parser target) None
        +parse_at() ParseResult
    }

    Parser <|-- Literal
    Parser <|-- Regex
    Parser <|-- Sequence
    Parser <|-- Choice
    Parser <|-- Repetition
    Parser <|-- Predicate
    Parser <|-- RuleRef
    Parser ..> ParseResult : returns
```

### 4.2 コンビネータ API 定義仕様

Xenon Grade A（サイクロマティック複雑度 $CC \le 4$）および mypy strict に完全準拠するクラス設計とする。

### 4.3 AST 変換フック (Semantic Action `.map()`) 仕様

構文要素のパース成功と同時に、ドメイン固有の AST ノードへ変換するための `.map()` メソッドを提供する。

### 4.4 遅延評価・相互再帰解決 (`RuleRef`) 仕様

構文解析において不可欠な相互再帰（例: 式の中に括弧があり、括弧の中に式がある）を Python で宣言時に解決するため、遅延参照ラッパー `RuleRef` を提供する。

---

## 5. サブシステム横断適用設計 (Cross-System Integration)

### 5.1 検索プラットフォーム: 括弧ネスト対応ブーリアンクエリパーサー (実装完了: Issue #285)

[`src/search/query/query_parser.py`](../../src/search/query/query_parser.py) を PEG コンビネータで再構築し、任意の深さの論理式ネストに対応。
- 単一語句、フィールド指定 (`title:ransomware`, `year:2024`)、フレーズ検索 (`"supply chain"`、slop `~2`)、ブーリアン演算子 (`AND`, `OR`, `NOT`, `+`, `-`)、および多段括弧ネスト (`(A OR B) AND -(C OR D)`) を Packrat PEG により $O(N)$ 線形時間で AST 構築。
- 関連テスト: [`tests/search/test_query_parser_peg.py`](../../tests/search/test_query_parser_peg.py) (全項目 PASS)

### 5.2 データベースエンジン: SQL パーサーの Packrat PEG 完全換装 (Phase 2)

従来 `src/database/sql/parser.py` は 2,100 行を超えるアドホックな正規表現と文字列置換で実装されており、複雑なネストや演算子優先順位の解釈において ReDoS や構文エラーのリスクを抱えていた。
これを解決するため、Packrat PEG エンジンによる段階的完全換装を実施する。

#### 5.2.1 Phase 2-A: SQL 式（Expression）パーサー (実装完了: Issue #288)
[`src/database/sql/expr_parser.py`](../../src/database/sql/expr_parser.py) を新規開発し、Packrat PEG エンジンによる SQL 式（Expression）パーサーを確立：
- リテラル（数値、シングル/ダブル引用符文字列、`TRUE`/`FALSE`/`NULL`）、列参照（`col`, `table.col`, `col->>'key'`）
- 算術演算子（`+`, `-`, `*`, `/`, `%`）の優先順位制御、単項演算子（`+`, `-`, `NOT`）
- 比較演算子（`=`, `!=`, `<>`, `<`, `<=`, `>`, `>=`）および特殊述語（`IS [NOT] NULL`, `[NOT] BETWEEN ... AND ...`, `[NOT] LIKE ... [ESCAPE ...]`, `[NOT] GLOB`, `[NOT] MATCH`, `[NOT] IN (...)`）
- 論理演算子（`AND`, `OR`）と任意深度の括弧ネスト式（`((a = 1 OR b = 2) AND c = 3)`）
- 関数呼び出し（`COUNT(*)`, `COALESCE(...)`）、CASE 条件分岐式（Searched CASE / Simple CASE）
- 既存 RDBMS 実行エンジンへの透過的ブリッジ（`to_legacy_dict()`）および SQL 再シリアライズ（`to_sql()`）
- 関連テスト: [`tests/database/test_sql_expr_peg.py`](../../tests/database/test_sql_expr_peg.py) (全 21 項目 100% PASS)

#### 5.2.2 Phase 2-B: DQL & 派生クエリ構文の PEG 換装 (実装完了: Issue #289)
`SELECT`, CTE (`WITH [RECURSIVE]`), `FROM` 句（テーブル・派生サブクエリ・JOIN 結合構文）、`WHERE` 句（`expr_parser` 統合）、`GROUP BY`, `HAVING`, ウィンドウ関数（`OVER (...)`）、集合演算（`UNION`, `INTERSECT`, `EXCEPT`）、スタンドアロン `VALUES` 句を PEG 文法として定義。
- [`src/database/sql/dql_parser.py`](../../src/database/sql/dql_parser.py) (全 21 項目テスト PASS)

#### 5.2.3 Phase 2-C: DML 構文の PEG 換装 (実装完了: Issue #290)
`INSERT INTO` / `REPLACE INTO`（VALUES 挿入、SELECT 挿入）、`UPDATE ... FROM`、`DELETE FROM`、`UPSERT` (`ON CONFLICT DO UPDATE/NOTHING`)、`RETURNING` 句を PEG 文法として定義。
- [`src/database/sql/dml_parser.py`](../../src/database/sql/dml_parser.py) (全 16 項目テスト PASS)

#### 5.2.4 Phase 2-D: DDL / TCL / DCL & 管理構文の PEG 換装と完全統合 (実装完了: Issue #291)
`CREATE TABLE` (STRICT / GENERATED ALWAYS AS), `ALTER TABLE`, `CREATE INDEX`, `CREATE VIEW`, `CREATE TRIGGER`, `VIRTUAL TABLE`, `ATTACH/DETACH DATABASE`, `BEGIN/COMMIT/ROLLBACK/SAVEPOINT`, `PRAGMA`, `VACUUM`, `ANALYZE`, `EXPLAIN`, `SHOW`, `GRANT/REVOKE` を PEG 化し、`src/database/sql/parser.py` を Packrat PEG ベースの `SQLParser` として完全一本化。旧正規表現コード（2,000行超）を全廃止。
- [`src/database/sql/ddl_parser.py`](../../src/database/sql/ddl_parser.py) (全 18 項目テスト PASS)
- [`src/database/sql/admin_parser.py`](../../src/database/sql/admin_parser.py)
- [`src/database/sql/parser.py`](../../src/database/sql/parser.py) (純粋 PEG 統合ディスパッチャー)
- データベース全 400 件テスト 100% PASS、Xenon Rank A ($CC \le 4$)、`mypy --strict` 完全適合。

#### 5.2.5 Phase 2-E: 残存手書き正規表現・文字列走査ロジックの完全撤廃と 100% 純粋 PEG 化 (実装完了: Issue #292)
`parser.py` に残存していた WHERE 句述語の手書き正規表現マッチング群（`_WHERE_PARSERS`、`_parse_cmp_clause` 等）、カンマ分割の手書き文字走査ループ（`_split_comma_expressions`）、および `__BETWEEN_AND__` 文字列置換ハックを完全に追放。
- `parser.py` から `import re` を 100% 完全撤廃（行数は 185 行まで極小化）。
- WHERE 句の条件分割および legacy dict マッピングを `SQLExpressionParser` による構文木走査（`_flatten_and_exprs`, `_flatten_or_exprs`）へ一本化。
- `expr_parser.py` における `COLLATE` 句、`EXISTS (SELECT ...)`、`IN (SELECT ...)` サブクエリ、負数定数評価（`_eval_constant`）の PEG サポートを完備。
- データベース全 401 件テスト 100% PASS、Xenon Rank A ($CC \le 4$)、`mypy --strict` 完全適合。

### 5.3 グラフエンジン: Canvas 向け CTI パスクエリ DSL (実装完了: Issue #286)

[`src/graph/query_dsl.py`](../../src/graph/query_dsl.py) を新規開発し、[`src/graph/engine.py`](../../src/graph/engine.py) の `execute_graph_query` に高度な CTI パスクエリ DSL を統合：
- 多段パスマッチング: `APT29 -> [USES] -> Malware -> [EXPLOITS] -> CWE-79`、`A -> B`、逆方向 `<-`、無向 `--`
- 複合条件フィルタ: `community:0 AND label:ThreatActor`
- Packrat PEG で構文解析した AST を既存の BFS / DFS トラバーサルおよび Louvain コミュニティ検出と連動し、誘導部分グラフ（`nodes`, `edges`, `stats`）として即座に Canvas 2D 可視化 / REST API へ返却。
- 関連テスト: [`tests/graph/test_graph_query_dsl.py`](../../tests/graph/test_graph_query_dsl.py) (全項目 PASS)

### 5.4 セキュリティオントロジー: W3C Turtle (.ttl) インジェスト構文解析 (実装完了: Issue #287)

Issue #199（W3C Turtle エクスポート）に続くインポート機能として、W3C 規格準拠の純粋 Python 製 Turtle 1.1 パーサー [`src/ontology/turtle_parser.py`](../../src/ontology/turtle_parser.py) を Packrat PEG 上に新規構築。
- ディレクティブ: `@prefix prefix: <iri> .` および SPARQL 形式 `PREFIX prefix: <iri>`、`@base` / `BASE`
- 主語/述語/目的語: IRI、Prefixed Name (CURIE)、ブランクノード (`_:b1`, `[]`)、キーワード `a` (`rdf:type` 自動展開)
- リテラル: 文字列（エスケープ対応）、言語タグ (`"..."@en`)、型注記 (`"..."^^xsd:date`)、真偽値 (`true`, `false`)、数値（浮動小数点数、整数）
- 省略構文: セミコロン `;`（同一主語の述語リスト展開）およびカンマ `,`（同一述語の目的語リスト展開）
- 関連テスト: [`tests/ontology/test_turtle_parser.py`](../../tests/ontology/test_turtle_parser.py) (全項目 PASS)

---

---

## 6. 事前コード生成型パーサージェネレータ (Ahead-of-Time Compiler) (Phase 2 実装完了: Issue #293)

### 6.1 2段階進化戦略の完遂 (Phase 1 ランタイム → Phase 2 コンパイラ)

```mermaid
graph TD
    subgraph Phase 1 [Phase 1: インメモリ Packrat ランタイム]
        P1_Core["src/core/structures/peg.py<br/>(共通 Packrat PEG エンジン)"]
        Search["検索クエリ DSL (Issue #285)"]
        Graph["CTI グラフパスクエリ (Issue #286)"]
        Turtle["W3C Turtle インジェスト (Issue #287)"]
        SQL["SQL 全層 (Issue #288-292)"]
        P1_Core --> Search
        P1_Core --> Graph
        P1_Core --> Turtle
        P1_Core --> SQL
    end

    subgraph Phase 2 [Phase 2: 事前コード生成コンパイラ (Issue #293)]
        GrammarFile["grammars/*.peg<br/>(文法仕様ファイル)"]
        MetaParser["src/core/structures/peg_compiler/meta_grammar.py<br/>(セルフホスティング・ブートストラップ)"]
        CodeGen["src/core/structures/peg_compiler/codegen.py<br/>(コードエミッター)"]
        CLI["tools/peg_compiler/compile_peg.py<br/>(CLI ツール)"]
        GenParser["generated/*_parser.py<br/>(静的 Python パーサーコード)"]
        
        P1_Core -.->|ブートストラップ<br/>コンビネータによりパース| MetaParser
        GrammarFile --> MetaParser
        MetaParser --> CodeGen
        CodeGen --> GenParser
        CLI --> CodeGen
        GenParser -->|実行時共通基盤として参照| P1_Core
    end
```

### 6.2 PEG メタ文法によるセルフホスティング (ブートストラップ)

[`src/core/structures/peg_compiler/meta_grammar.py`](../../src/core/structures/peg_compiler/meta_grammar.py) は、`src/core/structures/peg.py` の Packrat PEG コンビネータ（`Lit`, `Reg`, `Seq`, `Choice`, `OneOrMore`, `Opt`, `RuleRef`, `NotPred`）を用いて自ら `.peg` 記法を構文解析する。
- 終端トークン: 引用符文字列 (`"..."`, `'...'`)、正規表現 (`/pattern/`)、識別子
- 式演算子: 順序付き選択 (`/`, `|`)、連接、反復 (`*`, `+`)、省略可能 (`?`)、先読み (`&`, `!`)
- 構文拡張: 変数ラベルバインド (`name:expr`)、および多段波括弧ネスト対応セマンティックアクション (`{ python_code }`)
- 先読み防御: ルール宣言先読み (`!Seq(ident, "=")`) により、連続識別子の貪欲消費を完全防止。

### 6.3 静的コードエミッター (`codegen.py`) と CLI ツール

[`src/core/structures/peg_compiler/codegen.py`](../../src/core/structures/peg_compiler/codegen.py) は、`GrammarDef` AST を入力とし、純粋 Python の静的パーサークラスを出力する。
- 自動インデント補正 (`textwrap.dedent`)
- 変数バインドの自動アンパック展開 (`left = val[0]`, `rest = val[1]`)
- 単一式・複数文のセマンティックアクション関数の静的生成
- `tools/peg_compiler/compile_peg.py` による CLI 実行サポート (`-o output.py --class-name CustomParser`)
- 使用シンボルの動的解析による最小インポート生成（`# flake8: noqa` ゼロ方針の完全遵守）

---

## 7. AOT コンパイラ実戦投入と本番運用 (Production Deployment) (Phase 2 実装完了: Issue #294)

### 7.1 W3C Turtle 1.1 パーサーの宣言的 AOT 換装

事前コンパイラの本格運用第1弾として、W3C 規格準拠の **W3C Turtle 1.1 パーサー ([`src/ontology/turtle_parser.py`](../../src/ontology/turtle_parser.py))** を AOT 駆動型へ完全移行。

1. **形式文法定義の宣言的分離 ([`grammars/turtle.peg`](../../grammars/turtle.peg))**:
   - W3C Turtle 1.1 構文仕様（ディレクティブ `@prefix`, `PREFIX`, `@base`, `BASE`、主語・述語・目的語、ブランクノード、リテラル、データ型、コメント）を純粋な宣言的 PEG 仕様として分離。
   - ダブルクォート `"` およびシングルクォート `'` の両方に対応する文字列リテラル規則。
2. **静的パーサー自動生成 ([`src/ontology/generated_turtle_parser.py`](../../src/ontology/generated_turtle_parser.py))**:
   - `tools/peg_compiler/compile_peg.py` により、完全型安全・ゼロ外部依存の静的パーサークラス `TurtleParser` を生成。
3. **ビルドパイプラインへの統合 (`Makefile`)**:
   - `make compile_grammars` ターゲットを新設し、CI/CD・開発ワークフローで文法ファイルから自動コンパイル・整合性検証を担保。
4. **ゼロオーバーヘッドと性能実証 ([`tests/ontology/test_turtle_benchmark.py`](../../tests/ontology/test_turtle_benchmark.py))**:
   - 実行時の動的コンビネータ構築コストを完全排除（50回のインスタンス生成が 0.01 秒未満）。
   - 200件のトリプルを含む複合ドキュメントを 0.2 秒未満で一括解析。
   - 既存の全テスト ([`tests/ontology/test_turtle_parser.py`](../../tests/ontology/test_turtle_parser.py)) と 100% 互換動作。

---

## 8. セキュリティ分析 (STRIDE Threat Model) と防御策

| 脅威分類 (STRIDE) | 潜在リスク・攻撃シナリオ | 本設計における多層防御策 |
| :--- | :--- | :--- |
| **Denial of Service (DoS)** | 悪意ある過度な再帰ネスト（`((((...))))` 1万段）による Python スタック枯渇 (`RecursionError`)。 | `ParseContext` に最大再帰深度ガード（`max_depth=500`）を設け、超過時は即時 `PEGSyntaxError("Maximum parsing recursion depth exceeded")` を送出。 |
| **Denial of Service (DoS)** | バックトラックの多発による CPU リソース枯渇 (ReDoS)。 | Packrat メモ化テーブルにより、全構文ノードの探索回数を高々 1 回に束縛 ($O(N)$ 線形時間保証)。 |
| **Denial of Service (DoS)** | 巨大入力文字列によるメモ化キャッシュのメモリ圧迫 (OOM)。 | 単一パース実行ごとのローカルコンテキスト破棄。最大入力長制限（`max_input_length=65536`）による防御。 |
| **Tampering (改ざん)** | 先読み述語（`&` / `!`）による意図しない文字列消費やオフセットずれ。 | 述語パーサーにおいて `next_pos` を常に試行前位置 `pos` に強制リセットする不変条件の単体テスト検証。 |
| **Information Disclosure** | パース例外メッセージを通じた内部ファイルパス等の漏洩。 | エラーメッセージには入力テキストの行番号・列番号・スニペットのみを含め、システム内部情報は一切出力しない。 |

---

## 9. 非機能要件・品質基準・DoD

### 9.1 非機能要件

1. **ゼロ外部依存**:
   - Python 標準ライブラリ（`typing`, `re`, `dataclasses`, `textwrap`）のみで完結。
2. **極小レイテンシ**:
   - 100 文字程度の典型的な検索クエリを $< 0.2\text{ms}$ でパース完了。
3. **最高水準の静的解析品質**:
   - `make check_format` (`isort`, `black`, `flake8`) 100% 準拠。
   - `xenon --max-absolute A --max-modules A --max-average A`（全関数 $CC \le 4$）。
   - `mypy --strict` エラー 0 件。

### 9.2 完了条件 (Definition of Done)

- [x] `src/core/structures/peg.py` に Packrat PEG コアランタイムエンジンが実装されていること（Issue #284）。
- [x] `src/core/structures/__init__.py` に公開クラスおよびヘルパー関数がエクスポートされていること。
- [x] `tests/core/test_peg.py` に単体テスト（リテラル、正規表現、連接、順序選択、反復、先読み、メモ化線形時間実証、エラー位置追跡、再帰深度リミット）が網羅されていること。
- [x] `src/search/query/query_parser.py` が PEG エンジンを用いて括弧ネスト検索クエリを完全解析できること（Issue #285、`tests/search/test_query_parser_peg.py` PASS）。
- [x] `src/graph/query_dsl.py` に CTI グラフパスクエリ DSL パーサーが実装され、エンジンへ統合されていること（Issue #286、`tests/graph/test_graph_query_dsl.py` PASS）。
- [x] `src/ontology/turtle_parser.py` に W3C Turtle 1.1 / RDF インジェストパーサーが実装され、トリプル抽出・プレフィックス解決ができること（Issue #287、`tests/ontology/test_turtle_parser.py` PASS）。
- [x] `src/database/sql/expr_parser.py` に Packrat PEG SQL 式パーサーが実装され、複雑な論理式・算術式・CASE・関数呼び出しの AST 化ができること（Issue #288、`tests/database/test_sql_expr_peg.py` PASS）。
- [x] `src/database/sql/dql_parser.py` に Packrat PEG DQL パーサーが実装され、SELECT/CTE/JOIN/SET/VALUES の AST 化および既存 SQLParser への委譲ができること（Issue #289、`tests/database/test_sql_dql_peg.py` PASS）。
- [x] `src/database/sql/dml_parser.py` に Packrat PEG DML パーサーが実装され、INSERT/UPDATE/DELETE/UPSERT/RETURNING の AST 化ができること（Issue #290、`tests/database/test_sql_dml_peg.py` PASS）。
- [x] `src/database/sql/ddl_parser.py` および `admin_parser.py` に Packrat PEG DDL/管理構文パーサーが実装され、旧正規表現パーサーが完全撤廃されたこと（Issue #291、`tests/database/test_sql_ddl_peg.py` PASS）。
- [x] `src/database/sql/parser.py` における残存正規表現・WHERE 文字列走査ロジックが完全撤廃され、純粋 PEG AST 走査へ一本化されたこと（Issue #292、全 401 テスト PASS）。
- [x] `src/core/structures/peg_compiler/` に DSN-25 Phase 2 事前コンパイラ（AOT Compiler）が実装され、`.peg` 文法定義ファイルから Python パーサーコードが事前生成できること（Issue #293、`tests/core/test_peg_compiler.py` PASS）。
- [x] `grammars/turtle.peg` が W3C Turtle 1.1 仕様に準拠して定義され、`tools/peg_compiler/compile_peg.py` および `make compile_grammars` により `src/ontology/generated_turtle_parser.py` が自動生成され、`turtle_parser.py` に本番実戦投入されたこと（Issue #294、`tests/ontology/test_turtle_parser.py` & `test_turtle_benchmark.py` PASS）。
- [x] 全品質ゲート（`make check_format` および `make static_analysis`）がエラー 0 件で通過すること。

---

## 10. Phase 3: PEG AOT コンパイラのセルフホスティング（自己完結ブートストラップ化）仕様 (Issue #297)

### 10.1 概要と自己完結ブートストラップ哲学
Phase 2 で構築された PEG AOT コンパイラ（`src/core/structures/peg_compiler/`）の表現力と正当性を自律的に証明するため、PEG メタ文法パーサー自身を PEG 文法記法（`grammars/peg_meta.peg`）で定義し、AOT コンパイラ自身によって生成された Python コード（`src/core/structures/peg_compiler/generated_meta_parser.py`）を用いてメタ文法を解析する**「セルフホスティング（Self-Hosting / Bootstrapping）」**機構を確立する。

```
                    [ メタ文法仕様: grammars/peg_meta.peg ]
                                      │
                                      ▼ (tools/peg_compiler/compile_peg.py)
[ AOT コード生成器: codegen.py ] ──▶ [ 生成コード: generated_meta_parser.py ] (Git 管理)
                                      │
                                      ▼ (優先ロード)
                     [ 統合ファサード: meta_grammar.py ]
                                      │
         ┌────────────────────────────┼────────────────────────────┐
         ▼                            ▼                            ▼
  grammars/turtle.peg         grammars/calc.peg          grammars/boolean_query.peg
         │                            │                            │
         ▼                            ▼                            ▼
generated_turtle_parser.py    GeneratedCalcParser        GeneratedQueryParser
```

### 10.2 ブートストラップ循環依存の解消 (Pragmatic Bootstrapping Pattern)
コンパイラのセルフホスティングにおける典型的な「鶏と卵問題（初回環境構築時の循環依存）」に対し、本システムでは CPython (`pegen`) と同様の**コミット型決定論的ブートストラップ（Committed Deterministic Bootstrapping）**を採用する。

1. **自己生成コードの Git 追跡**:
   - `src/core/structures/peg_compiler/generated_meta_parser.py` は Git 管理下にコミットされる。
   - 新規クローン環境やクリーン CI 環境では、文法コンパイルを必要とせず即座に `GeneratedMetaGrammarParser` が稼働する。
2. **メタ文法更新時の再ブートストラップ**:
   - `grammars/peg_meta.peg` が改定された場合、開発者は `make compile_grammars` を実行することで最新のパーサーコードを再生成する。
3. **Fixpoint（不動点）等価性検証 (`make verify_peg_bootstrap`)**:
   - 生成された `generated_meta_parser.py` を用いて再度 `grammars/peg_meta.peg` をパースし、再コード生成された出力がコミット済みファイルとバイト単位で一致することを自動検証（Fixpoint Invariant）。

### 10.3 セルフホスティング仕様と AST マッピング

`grammars/peg_meta.peg` は以下の主要構文規則を PEG 自身で定義する：

| 構文規則 | PEG 記法例 | 生成 AST ノード |
| :--- | :--- | :--- |
| 文法ヘッダー | `grammar Ident` / `@header { ... }` | `GrammarDef(name, header_code)` |
| 規則定義 | `rule_name = choice_expr` | `RuleDef(name, expr)` |
| 順序選択 (Choice) | `alt1 / alt2 / alt3` | `ChoiceExpr([alt1, alt2, alt3])` |
| 連接 (Sequence) | `item1 item2 item3` | `SeqExpr([item1, item2, item3])` |
| ラベル付き式 | `val:item` | `NamedExpr("val", item)` |
| 肯定先読み述語 | `&item` | `PredExpr(item, is_positive=True)` |
| 否定先読み述語 | `!item` | `PredExpr(item, is_positive=False)` |
| 反復サフィックス | `item*` / `item+` / `item?` | `RepeatExpr(0+)` / `RepeatExpr(1+)` / `OptExpr` |
| 文字列リテラル | `"text"` / `'text'` | `LitExpr("text")` |
| 正規表現リテラル | `/[0-9]+/` | `RegexExpr("[0-9]+")` |
| セマンティックアクション | `{ return AstNode(...) }` | `ActionExpr(expr, code)` |

### 10.4 完了条件 (DoD for Phase 3)
- [x] `grammars/peg_meta.peg` が作成され、PEG メタ文法自身が完全記述されていること。
- [x] `src/core/structures/peg_compiler/generated_meta_parser.py` が自動生成され、Git 管理下に配置されていること。
- [x] `MetaGrammarParser` が自己生成された AOT メタパーサーを優先利用し、既存の全 `.peg` ファイルが透過的にコンパイル可能であること。
- [x] `tests/core/test_peg_bootstrap.py` において、手書きパーサーとの AST 等価性および自己再コンパイル Fixpoint が 100% PASS すること。
- [x] `Makefile` に `verify_peg_bootstrap` が追加され、`make compile_grammars` と共に正常動作すること。

