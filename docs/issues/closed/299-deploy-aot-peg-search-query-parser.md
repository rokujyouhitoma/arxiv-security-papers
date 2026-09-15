---
ID: 299
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] AOT PEG コンパイラ実戦投入第2弾: 検索クエリパーサーの search_query.peg 化と本番パイプライン統合 (ID: 299)

## 1. 概要 / Summary
Packrat PEG 事前コンパイラ（AOT Compiler: Issue #293, #294, #297, #298, DSN-25）の実戦投入第2弾として、検索プラットフォームのクエリパーサー（`src/search/query/query_parser.py`）を宣言的 PEG 文法ファイルからの静的コンパイル（AOT 駆動型）へ全面換装する。

これまでプロトタイプとして存在していた `grammars/boolean_query.peg` を、検索クエリ全体の機能（フィールド指定、フレーズ、スロップ、プレフィックス、ファジー、修飾子 `+/-/NOT`、多段括弧ネスト）を包含する適切な名称 **`grammars/search_query.peg`** に改称・拡充する。Bryan Ford 論文（POPL '04）準拠構文（`<-`, `[...]`, `.`）に基づきセマンティックアクション付きで完全記述し、AOT コンパイラにより `src/search/query/generated_search_query_parser.py` を事前生成する。

これにより、検索クエリ実行時ごとの動的コンビネータ木構築オーバーヘッドを完全撤廃し、インスタンス化コストゼロ・極小レイテンシ（$< 0.1\text{ms}$）のエンタープライズ検索クエリ構文解析を実現する。

### 主な提供機能
1. **文法ファイルのリネームと本番完全定義 (`grammars/search_query.peg`)**:
   - `boolean_query.peg` を `search_query.peg` へ改称。
   - 単なる Boolean 演算だけでなく、Lucene/Elasticsearch 風のフル機能（フィールド指定、フレーズ、スロップ `~N`、プレフィックス `*`、ファジー `~N`、修飾子 `+`/`-`/`NOT`、括弧ネスト `(...)`）を Bryan Ford POPL '04 構文（`<-`, `[...]`）で網羅。
   - セマンティックアクション `{ ... }` により直接 `QueryClause` AST オブジェクトを構築。
2. **静的パーサーコード生成 (`src/search/query/generated_search_query_parser.py`)**:
   - `tools/peg_compiler/compile_peg.py` により、完全型安全・ゼロ外部依存の静的パーサークラス `SearchQueryParser` を事前生成。
3. **本番クエリパーサーの AOT 換装 (`src/search/query/query_parser.py`)**:
   - 動的 PEG コンビネータ構築関数 `_build_peg_query_grammar` を AOT 生成パーサーの呼び出しに置換。
   - 既存の `EnterpriseQueryParser` および `QueryContext` のパブリック API、フォールバック機構、フィールド解決ロジックとの 100% 互換性を担保。
4. **ビルドパイプライン統合 (`Makefile`)**:
   - `make compile_grammars` に `grammars/search_query.peg` $\to$ `src/search/query/generated_search_query_parser.py` の自動生成ステップを追加。
5. **ベンチマークと性能実証 (`tests/search/test_query_benchmark.py`)**:
   - AOT 化による高速起動・パース性能（インスタンス化ゼロオーバーヘッド、多段クエリ高速解析）を検証するテストを追加。
6. **DSN-25 設計仕様書・ドキュメントの更新**:
   - DSN-25 に Phase 2 検索クエリ AOT 換装の完了を追記。

---

## 2. 15 大専門エージェントによる多角的レビュー ＆ 合意事項 / Multi-Agent Review Matrix

リポジトリ統治規程（`.agents/AGENTS.md`）に基づき、全 15 専門エージェントによる多角的な設計審査を実施・合意した：

| エージェント | 専門領域 | レビュー所見・合意事項 | 合意状況 |
| :--- | :--- | :--- | :---: |
| **1. Project Manager (PM)** | 統治・進行管理 | Turtle に続く第2の AOT 実践例として承認。`.peg` の名称を実態に即した `search_query.peg` に改める方針を強く支持。 | **APPROVED** |
| **2. Information Security (SC)** | 脅威分析・堅牢化 | 悪意ある過度な括弧ネスト入力に対する再帰深度ガード、および文字クラス $O(1)$ 判定による ReDoS 根絶を確認。 | **APPROVED** |
| **3. Systems Architect (SA)** | アーキテクチャ整合 | `search/query/` 内部で自己完結し、外部公開 API（`EnterpriseQueryParser.parse`, `create_context`）に破壊的変更を与えないことを確認。 | **APPROVED** |
| **4. Software QA Specialist (QA)** | テスト・品質保証 | 既存の `test_query_parser_peg.py` 全件 PASS に加え、ベンチマークテストでの性能向上実証を義務付け。 | **APPROVED** |
| **5. Database Specialist (DB)** | データ連携 | 将来の SQL 式パーサー AOT 化に向けた知見蓄積（AST マッピングとディスパッチ）としての有効性を評価。 | **APPROVED** |
| **6. Network Specialist (NW)** | 通信・プロトコル | REST API や Web Gateway 経由で流入する URL エンコード済み/デコード済みクエリの低レイテンシ処理に寄与することを確認。 | **APPROVED** |
| **7. IT Specialist (NLP & IR)** | 自然言語・検索 | フレーズスロップ、プレフィックス、ブースト、ファジー、フィールド制約が既存検索エンジン（BM25/ベクトル）と完全連動することを確認。 | **APPROVED** |
| **8. IT Strategist (ST)** | 標準化・技術戦略 | DSN-25 ロードマップの着実な履行。Turtle に次ぐ検索クエリの AOT 化により、コードベースの宣言的純化を促進。 | **APPROVED** |
| **9. IT Service Manager (SM)** | 運用監視・ロギング | クエリ文法エラー時の行・列特定およびフォールバック機構（手動正規表現）が正しく動作し、検索サービスが中断しないことを確認。 | **APPROVED** |
| **10. Embedded Systems (ES)** | 低レイヤ・フットプリント | 検索リクエストごとの動的メモリ確保（コンビネータオブジェクト生成）が完全ゼロになり、GC 負荷が大幅軽減されることを高く評価。 | **APPROVED** |
| **11. Systems Auditor (AUD)** | 監査・トレーサビリティ | `compile_grammars` によるコード生成の再現性（バイト単位一致）と DSN-25 との完全なトレーサビリティを承認。 | **APPROVED** |
| **12. UI/UX Designer (UI)** | ユーザー体験 | Web UI の検索バー入力に対するレスポンスが高速化し、複雑な括弧クエリの体感レイテンシが向上。 | **APPROVED** |
| **13. Education Specialist (EDU)** | 教育・解説性 | `search_query.peg` を見れば誰でも本システムの検索クエリ文法体系を即座に理解できる教育的価値を評価。 | **APPROVED** |
| **14. Software Dev (SWD)** | コア実装・アルゴリズム | POPL '04 論文構文 `<-`, `[...]` を適用し、Xenon Grade A ($CC \le 4$)・mypy strict を遵守するコード生成を確認。 | **APPROVED** |
| **15. Application Specialist (APS)**| アプリ統合・Web UI | Web Gateway (`/api/search`) および Supervisor の自動検索タスクとの完全な後方互換性を担保。 | **APPROVED** |

---

## 3. セキュリティ分析 (STRIDE Threat Model) と防御策 / Security Analysis & STRIDE Mitigations

| 脅威分類 (STRIDE) | 潜在リスク・攻撃ベクトル | 具体的防御策・実装仕様 |
| :--- | :--- | :--- |
| **Spoofing (なりすまし)** | 不正なフィールド名偽装による内部プロパティアクセス | `ALLOWED_FIELDS` および `FIELD_ALIAS` による厳格なホワイトリスト検証をセマンティックアクション内で実施。不正フィールドは無視/デフォルトフォールバック。 |
| **Tampering (改ざん)** | クエリインジェクションや構文境界破壊 | PEG の順序付き選択 `/` と明示的括弧グルーピングにより、構文解釈の曖昧性を原理的に排除。 |
| **Repudiation (否認)** | パースエラー時の位置不整合による監査ログ記録失敗 | `PEGSyntaxError` による正確なエラー位置（行・列）の取得、および安全な `_fallback_regex_parse` へのフォールバック。 |
| **Information Disclosure**| 不正なクエリによるスタックトレースや内部エラーの外部露出 | 文法エラー時は `PEGSyntaxError` を捕捉し、安全なフォールバックパースを実行。内部例外を Web API レスポンスに漏洩させない。 |
| **Denial of Service (DoS / ReDoS)** | 1) 悪意ある深層括弧ネスト（`((((...))))` 1万段）によるスタック枯渇<br>2) バックトラック爆発 (ReDoS) | 1) コアコンテキストの最大再帰深度ガード（`max_depth=500`）により即時遮断。<br>2) Packrat メモ化による線形時間 $O(N)$ パース保証および `CharClass` による $O(1)$ 文字判定。 |
| **Elevation of Privilege** | セマンティックアクションへのコード注入 | `.peg` 文法ファイルは静的リソースであり、外部入力から動的にパーサーコードを生成・実行（`eval`/`exec`）することは一切ない。 |

---

## 4. トレーサビリティ / Traceability
- 関連標準・先行技術:
  - Bryan Ford (POPL '04): *Parsing Expression Grammars: A Recognition-Based Syntactic Foundation*
  - Apache Lucene Query Parser Syntax Specification
  - DSN-25: 純粋 Python 製汎用 Packrat PEG ランタイム基盤および構文解析エンジン統合設計仕様書
  - DSN-04: 検索プラットフォーム・クエリエンジン設計書
- 先行 Issue:
  - Issue #284: Packrat PEG コアランタイム基盤の実装
  - Issue #285: 検索クエリパーサーの Packrat PEG 換装 (Phase 1 動的コンビネータ)
  - Issue #293: PEG 事前コンパイラ (AOT Compiler) 基盤の実装
  - Issue #294: W3C Turtle 1.1 パーサーの AOT 化と運用パイプライン統合
  - Issue #297: PEG AOT コンパイラのセルフホスティング
  - Issue #298: Bryan Ford 論文（POPL '04）準拠 PEG 文法仕様への改定

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [NEW] `grammars/search_query.peg` (適切な名称で新設される検索クエリ完全文法仕様)
- [x] [DELETE] `grammars/boolean_query.peg` (旧プロトタイプ文法の削除・移行)
- [x] [NEW] `src/search/query/generated_search_query_parser.py` (AOT 自動生成パーサーコード)
- [x] [MODIFY] `src/search/query/query_parser.py` (AOT パーサーへの切り替えと動的ビルダーの廃止)
- [x] [MODIFY] `Makefile` (`compile_grammars` への `search_query.peg` 追加)
- [x] [MODIFY] `tests/search/test_query_parser_peg.py` (既存テストの AOT 整合確認)
- [x] [NEW] `tests/search/test_query_benchmark.py` (AOT パーサー起動・パースベンチマークテスト)
- [x] [MODIFY] `docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md` (DSN-25 設計書の更新)
- [x] [MODIFY] `docs/issues/README.md` (台帳ステータス更新)

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/299-deploy-aot-peg-search-query-parser`

### Step 1: `grammars/search_query.peg` の作成
1. `grammars/boolean_query.peg` を `grammars/search_query.peg` へ発展的改名。
2. POPL '04 論文仕様（`<-`, `[...]`, `.`）に基づき、以下の構文規則を完全定義：
   - `@header` で `QueryClause` のインポートおよびヘルパー関数の宣言。
   - `query <- ws expr:disjunction ws`
   - `disjunction <- left:conjunction rest:(ws or_op ws conjunction)*`
   - `conjunction <- first:factor rest:(sep factor)*`
   - `factor <- mod:modifier? prim:primary`
   - `primary <- field_expr / phrase_expr / plain_expr / nested_parens`
   - `field_expr <- f:field_name ":" target:field_target`
   - `phrase_expr <- '"' s:[^"]* '"' slop:slop_suffix?`
   - `plain_expr <- !reserved word:[^\s"():]+`
3. セマンティックアクション内で `QueryClause` オブジェクトを直接構築。

### Step 2: AOT コード生成と Makefile 連携
1. `tools/peg_compiler/compile_peg.py` を用いて `src/search/query/generated_search_query_parser.py` を生成。
2. `Makefile` の `compile_grammars` ターゲットに `grammars/search_query.peg` を追加。
3. 生成コードが `isort`, `black`, `flake8`, `mypy --strict` を完全通過することを確認。

### Step 3: `src/search/query/query_parser.py` の AOT 換装
1. `generated_search_query_parser.py` から `SearchQueryParser` をインポート。
2. `EnterpriseQueryParser` クラス内で、動的に `_build_peg_query_grammar` を組み立てる処理を廃止し、`SearchQueryParser` インスタンスへ処理を委譲。
3. `EnterpriseQueryParser.parse()`、`create_context()` のシグネチャおよび戻り値の完全互換を維持。

### Step 4: テストとベンチマーク
1. `tests/search/test_query_parser_peg.py` を実行し、全項目 PASS を確認。
2. `tests/search/test_query_benchmark.py` を作成し、AOT パーサーの高速インスタンス化・低レイテンシパースを実証。

### Step 5: ドキュメント改定と品質ゲート
1. `DSN-25` に検索クエリパーサーの AOT 換装完了を追記。
2. `make format`, `make static_analysis`, `make test` のトリプル品質ゲートを完全通過。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `grammars/search_query.peg` が Bryan Ford POPL '04 論文仕様準拠（`<-`, `[...]` 等）で作成され、旧 `boolean_query.peg` が適切に移行・削除されていること。
- [x] `src/search/query/generated_search_query_parser.py` が AOT コンパイラにより決定論的に生成されていること。
- [x] `Makefile` の `compile_grammars` に `search_query.peg` が追加され、`make compile_grammars` で正常に再コンパイルできること。
- [x] `src/search/query/query_parser.py` が AOT 生成パーサーに全面換装され、実行時の動的コンビネータ構築が廃止されていること。
- [x] `tests/search/test_query_parser_peg.py` および新規 `tests/search/test_query_benchmark.py` を含む全テストが 100% PASS すること。
- [x] DSN-25 設計仕様書が改定されていること。
- [x] `make format`, `make static_analysis` (xenon Grade A $CC \le 4$, mypy --strict, flake8 0 errors), `make test` に完全合格すること。
- [x] `docs/issues/README.md` 台帳に本 Issue が適切に反映されていること。
