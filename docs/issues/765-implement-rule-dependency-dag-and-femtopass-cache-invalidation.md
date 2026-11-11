---
ID: 765
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] ルール依存関係 DAG (Reads/Writes) 自動構築・独立ルール自動 Fusion・Femtopass 解析キャッシュ維持の実装 (DSN-33-01 T5.1) (ID: 765)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 5.1 節（次元1：パス・ルール依存関係 DAG と自動スケジューリング）および第 9.2 節タスク **T5.1** に基づき、Picopass / Femtopass / Attopass の第一級ルール記述子が保持する `reads`, `writes`, `eliminates` メタデータから **ルール間データ依存 DAG（有向非巡回グラフ）** を自動構築し、以下の 3 つの中核機能を実装する：

1. **独立ルール集合（アンチチェーン）の自動抽出とトポロジカルソート**:
   - 互いに Read/Write 競合を持たない独立ルール群（DAG 上で有向パスを持たないアンチチェーン）を自動検出し、単一 Nanopass 走査への安全な一括融合（Automatic Pass Fusion）を可能にする。
   - 順序依存のあるルール（例: `femto-use-counts` の結果を `rule-cp0-inline` が参照）をトポロジカルソートで正しく直列化・階層化する。
2. **強連結成分（SCC: Strongly Connected Components）検出による局所不動点ループの自動分離**:
   - 相互に構文タグ・属性を生成・消費し合うルール群（サイクル）を Tarjan のアルゴリズムにより検出し、`picopass-fixpoint` として局所反復スコープへ分離する。
3. **Femtopass 解析キャッシュの維持と選択的無効化（Invalidation Tracking）**:
   - 後続の Picopass が変更した構文タグ集合が先行 Femtopass の参照構文タグ集合と直交（交差なし）する場合、あるいは AST ノードが構造共有（`eq?`）により無変更であった場合、計算済みの Femtopass 属性キャッシュを破棄せずにそのまま再利用する。

---

## 2. 背景と課題分析 / Background and Problem Analysis

### 2.1 現行実装におけるパススケジューリングと解析キャッシュの構造的課題

これまで Phase 1 〜 Phase 4（Issue #754 〜 #764）を通じて、微細粒度ルール（Picopass / Femtopass / Attopass）の定義および `fuse-rules` による単一走査融合が実現した。しかし、ルール間の組み合わせや解析結果の管理に関して以下の課題が残存している：

1. **パス・ルール配置の手動依存性（属人化とメンテナンスコスト）**:
   - どのルール同士を同一の `fuse-rules` にまとめて良いか（Read/Write 競合が存在しないか）、どの順序で適用すべきかが開発者の暗黙の知識に依存している。
   - ルール数が増加した際に、誤って順序依存を破壊して不正コード生成や最適化漏れを引き起こすリスクがある。
2. **最適化パスにおける不動点反復ループの手書き固定化**:
   - 定数畳み込みとインライン展開のように、一方の適用が他方の適用機会を新たに創出するルール群に対し、手動で反復ループ（Fixpoint）を記述しなければならず、不要なルールまで反復に巻き込まれてコンパイル時間を悪化させていた。
3. **Femtopass 解析結果の毎パス全破棄と冗長再計算**:
   - 自由変数解析（`free-vars`）、変数使用回数カウント（`use-counts`）、型推論（`infer-types`）、エスケープ解析（`escape-tbaa`）などの非破壊属性計算（Femtopass）は、後続パスが 1 つ実行されるたびに全結果が破棄されている。
   - 例として、100 個のトップレベル関数のうち 1 個の関数内のみが変換された場合でも、残り 99 個の無変更関数を含む全 AST に対して再度ゼロから自由変数解析や型推論が走り、コンパイル時間の 30% 以上を消費していた。

---

## 3. トレーサビリティ / Traceability

- **関連設計書**:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
    - 第 5.1 節（次元1：パス・ルール依存関係 DAG と自動スケジューリング）
    - 第 9.2 節 タスク **T5.1**（ルール依存 DAG 自動構築・自動 Fusion・Femtopass キャッシュ維持）
- **依存関係**:
  - 先行 Issue:
    - [Issue #756 (T2.1: 第一級ルール記述子と define-picopass/femtopass/attopass DSL 実装)](closed/756-implement-rule-descriptor-and-picopass-femtopass-attopass-dsl.md)
    - [Issue #760 (T3.2: 局所再ディスパッチとスキーマ整合性検証)](closed/760-implement-local-redispatch-and-extends-eliminates-validation.md)
    - [Issue #763 (T4.2: 030_desugar.scm の fuse-rules 置換)](closed/763-replace-desugar-030-duplicate-rules-with-fuse-rules.md)
    - [Issue #764 (T4.3: verifier.scm の define-attopass 化と三重走査解消)](closed/764-migrate-verifier-to-attopass-and-eliminate-triple-traversal.md)
  - 後続 Issue:
    - [Issue #766 (T5.2: HIR/MIR Hash-Consing Term DAG と訪問済みノード O(1) メモ化走査)](766-implement-hash-consing-term-dag-and-memoized-catamorphism.md)
    - [Issue #767 (T5.3: LIR ピープホールの Picopass 化と命令データ依存 DAG 走査)](767-migrate-lir-peephole-to-picopass-and-dependency-dag.md)
    - [Issue #768 (T6.1: define-pipeline による用途別パイプライン分離)](768-implement-define-pipeline-for-aot-repl-and-check-modes.md)

---

## 4. アーキテクチャと専門エージェント多角的審議 / Multi-Agent Perspectives

1. **Systems Architect (方式設計)**:
   - ルール記述子（`rule-descriptor`）の `reads`, `writes`, `eliminates` 集合論的直積演算から有向辺集合 $E$ を $O(\|V\|^2)$ で自動抽出し、隣接リスト表現のグラフを構成する。
   - トポロジカルソートとアンチチェーン分割（Dilworth の定理に基づく DAG の最小パス被覆・層別化）により、安全に並行融合可能なルールクラスタを導出する。
2. **Software Development (SWD / コア実装)**:
   - `ulisp/compiler/nanopass_meta.scm` に DAG コアアルゴリズム（`nanopass-build-rule-dag`, `nanopass-rule-dag-topological-sort`, `nanopass-rule-dag-scc`, `nanopass-rule-dag-antichains`）を純粋 Scheme で自己完結実装。
   - Femtopass 属性キャッシュテーブル `*femto-analysis-cache*` および `(femto-get-cached-attr attr-name node compute-thunk)` を導入し、`eq?` ポインタ同一性による $O(1)$ ヒットを実現する。
3. **IT Specialist (Programming Languages & Compilers / PLC)**:
   - ルール $A \to B$ の有向辺判定条件：
     $$\text{Edge}(A \to B) \iff (\text{writes}(A) \cap \text{reads}(B) \neq \emptyset) \lor (\text{eliminates}(A) \cap \text{reads}(B) \neq \emptyset)$$
   - 変更構文タグ集合 $\Delta T$ によるキャッシュ無効化条件：
     $$\text{Invalidate}(\text{attr}) \iff \Delta T \cap \text{depends-on}(\text{attr}) \neq \emptyset$$
     構文木が変更されていない関数・式（`eq?`）の属性は無条件に維持される。
4. **Information Security Specialist (セキュリティ検証)**:
   - 循環ルール群（SCC）の不動点反復が無限ループに陥るリスク（CWE-400 リソース枯渇）に対し、既存の Fuel Guard（`*nanopass-redispatch-limit*`）を適用して上限反復を強制遮断。
   - キャッシュの誤ヒットによる古い属性の不正参照（CWE-345 データの完全性検証不備）を防止するため、ノードまたはタグの変更時は確実に該当エントリを無効化。
5. **Software Quality Assurance Specialist (品質保証)**:
   - DAG 構築、サイクル検出、アンチチェーン分解の正確性を独立した単体テスト（`test_nanopass_framework.scm`）で網羅的に検証。
   - キャッシュヒット／ミス／無効化統計（`femto-cache-stats`）の計量テストを追加。

---

## 5. 脅威モデル分析とセキュリティ要件 / Threat Modeling & Security Requirements

| 脅威 ID | 対象 | 脆弱性区分 | 脅威シナリオ | 緩和策・セキュリティ要件 |
| :--- | :--- | :--- | :--- | :--- |
| **THREAT-765-01** | ルール依存 DAG 解析 | CWE-400 (Resource Exhaustion) | ルール記述子に循環依存が存在し、無限ループやスタックオーバーフローでコンパイルがハングする。 | Tarjan の強連結成分（SCC）検出により閉路を即座に特定し、循環成分には有界な Fuel カウンタを強制設定する。 |
| **THREAT-765-02** | Femtopass 解析キャッシュ | CWE-345 (Insufficient Verification of Data Authenticity) | 先行パスで AST が改変されたにもかかわらず古い Femtopass 属性（自由変数や型情報）が誤ヒットし、不正なアセンブリが生成される。 | 変更された AST ノード（非 `eq?`）および変更タグ交差による選択的無効化プロトコル（Tag-based Invalidation Protocol）を厳格に適用。 |

---

## 6. 詳細設計仕様 / Detailed Technical Specifications

### 6.1 ルール依存関係 DAG 構築器 (`nanopass-build-rule-dag`)

入力されたルール仕様リスト（名前または記述子）から DAG レコードを生成する：

```scheme
;;; DAG レコード構造:
;;; (list 'rule-dag nodes edges in-degrees out-degrees rule-map)
(define (nanopass-build-rule-dag rule-specs) ...)
```

- **有向辺判定ロジック**:
  - ルール $A$ とルール $B$ に対し、以下のいずれかが真の場合に辺 $A \to B$ を張る：
    1. `(nanopass-set-intersects? (rule-writes A) (rule-reads B))`
    2. `(nanopass-set-intersects? (rule-eliminates A) (rule-reads B))`
    3. `(and (rule-head-tags B) (nanopass-set-intersects? (rule-writes A) (rule-head-tags B)))`

### 6.2 トポロジカルソートと深さ層別化 (`nanopass-rule-dag-topological-sort`)

- 入力 DAG が非巡回（Acyclic）の場合、Kahn のアルゴリズムにより依存順の線形リストを返す。
- 同時に深さ階層（Level-stratified Layers）を算出し、同一階層内のルール群を返す。
- 閉路が存在する場合は `#f` またはエラーを返し、SCC 解析への移行を促す。

### 6.3 強連結成分（SCC）検出 (`nanopass-rule-dag-scc`)

- Tarjan のアルゴリズムに基づき、グラフ内の全強連結成分を $O(\|V\| + \|E\|)$ で検出する。
- 要素数が 2 以上の強連結成分（あるいは自己ループを持つノード）を「相互依存・不動点反復ルール群（Cycle Group）」として分類し、`picopass-fixpoint` 生成メタ情報として出力する。

### 6.4 独立ルール集合（アンチチェーン）の自動抽出 (`nanopass-rule-dag-antichains`)

- DAG 上で互いに有向パスを持たないノード集合（アンチチェーン）を抽出する。
- これにより、ユーザーが手動で個別に指定しなくても、直交する最適化 Picopass 群を自動的に安全な単一 Nanopass 走査（`fuse-rules`）へとクラスタリングする。

### 6.5 Femtopass 属性キャッシュと選択的無効化 (`*femto-analysis-cache*`)

```scheme
;;; グローバル Femtopass キャッシュテーブル
;;; 各エントリ: (cons (cons node attr-name) cached-val)
;;; 補助インデックス: 属性依存タグマップ *femto-attr-tag-dependencies*
(define *femto-analysis-cache* (cons '() '()))
(define *femto-cache-stats* (cons 0 0)) ; (cons hits misses)

;;; キャッシュアクセサ API
(define (femto-cache-reset!) ...)
(define (femto-get-cached-attr attr-name node compute-thunk) ...)
(define (femto-cache-invalidate-tags! changed-tags) ...)
(define (femto-cache-invalidate-node! node) ...)
(define (femto-cache-stats) ...)
```

- **`femto-get-cached-attr` 動作規約**:
  1. キャッシュ探索: `(node, attr-name)` をキーとして探索（`eq?` によるノード比較）。
  2. キャッシュヒット: ヒット数を加算し、計算済みの属性値を即座に返す（$O(1)$）。
  3. キャッシュミス: ミス数を加算し、`compute-thunk` を評価して結果を記録・返却する。
- **選択的無効化規約**:
  - パスが構文タグ集合 `changed-tags` を書き換えた場合、そのタグを参照する Femtopass 属性（例: `use-count` は変数参照の変更時に無効化、`free-vars` は束縛/参照の変更時に無効化）のみを破棄。
  - AST ノード単位の無効化（`femto-cache-invalidate-node!`）により、書き換えが発生したノード配下のみを無効化し、無変更ノードのキャッシュを永続化。

---

## 7. 実装手順と対象ファイル / Implementation Steps & Affected Files

Target Branch: `feat/765-rule-dependency-dag-and-analysis-cache`

### 7.1 対象ファイル一覧
- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)（DAG 構築・トポロジカルソート・SCC・アンチチェーン抽出・Femtopass キャッシュ実装）
- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm)（パイプライン実行前後のキャッシュ初期化・無効化フックの導入）
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm)（DAG 解析・SCC・トポロジカルソート・キャッシュ無効化の単体テスト）
- [ ] [ulisp/tests/test_pass_manager.scm](../../ulisp/tests/test_pass_manager.scm)（パイプライン結合テスト）

### 7.2 ステップ別実装計画
- [ ] **Step 1: ルール依存 DAG 構築器・解析エンジンの実装** (`ulisp/compiler/nanopass_meta.scm`):
  - `nanopass-build-rule-dag`, `nanopass-rule-dag-nodes`, `nanopass-rule-dag-edges`, `nanopass-rule-dag-in-degrees`, `nanopass-rule-dag-out-degrees`
  - `nanopass-rule-dag-topological-sort`, `nanopass-rule-dag-scc`, `nanopass-rule-dag-antichains`
- [ ] **Step 2: Femtopass 属性キャッシュと Invalidation API の実装** (`ulisp/compiler/nanopass_meta.scm`):
  - `*femto-analysis-cache*`, `femto-cache-reset!`, `femto-get-cached-attr`
  - `femto-cache-invalidate-tags!`, `femto-cache-invalidate-node!`, `femto-cache-stats`
- [ ] **Step 3: Pass Manager へのキャッシュライフサイクル統合** (`ulisp/compiler/pass_manager.scm`):
  - `run-pass-pipeline` 開始時の `(femto-cache-reset!)` 呼び出し
  - 各 Nanopass 実行前後のタグ変更監視と選択的無効化
- [ ] **Step 4: 単体テスト群の追加** (`ulisp/tests/test_nanopass_framework.scm`):
  - 直列依存ルール（`R1 -> R2`）のトポロジカルソート検証
  - 独立ルール（`R1, R2`）のアンチチェーン自動抽出検証
  - 相互依存ルール（`R1 <-> R2`）の SCC 閉路検出検証
  - 無変更 AST に対する `femto-get-cached-attr` キャッシュヒット（ヒット率 100%）検証
  - 変更タグ指定による選択的無効化（特定属性のみミス、無関係属性はヒット維持）検証
- [ ] **Step 5: 全品質ゲートとセルフホスティング検証**:
  - `make -C ulisp compiler` 再ビルド
  - `make -C ulisp test_nanopass`, `make -C ulisp test_verifier`, `make -C ulisp test_passes`, `make -C ulisp test_all_passes`
  - `make -C ulisp test_c` (全 143 件 PASS)
  - `make -C ulisp test` (ブートストラップ不動点検証含む)
  - `make py_compile && make static_analysis` (Xenon AAA / mypy strict)

---

## 8. 完了条件 / Success Criteria (DoD)

1. [ ] **DAG 自動構築・解析機能**:
   - `nanopass-build-rule-dag` がルールの `reads`/`writes`/`eliminates` から有向依存辺を正しく生成すること。
   - `nanopass-rule-dag-topological-sort` が線形依存グラフを正しい実行順でソートできること。
   - `nanopass-rule-dag-scc` が閉路（強連結成分）を正確に検出し、非循環部分と分離できること。
   - `nanopass-rule-dag-antichains` が互いに独立なルール集合を抽出できること。
2. [ ] **Femtopass キャッシュ機能**:
   - `femto-get-cached-attr` が同一ノード（`eq?`）に対して再計算をスキップし、キャッシュヒットすること。
   - `femto-cache-invalidate-tags!` が指定タグに関連する属性のみを選択的に破棄し、直交する属性を維持すること。
3. [ ] **テスト完全 PASS**:
   - `ulisp/tests/test_nanopass_framework.scm` の新規 DAG・キャッシュテスト全件が PASS すること。
   - 既存の全 Nanopass 単体テスト、C バックエンドテスト、全パスバッチテストが 100% PASS すること。
4. [ ] **ブートストラップ・品質ゲート**:
   - `make -C ulisp bootstrap` による Stage 2 / Stage 3 の bit-for-bit 完全一致が保証されること。
   - `make py_compile` および `make static_analysis` がエラー 0 件で PASS すること。
   - ドキュメント内の全リンクが相対パス規約に準拠していること。
