---
ID: 757
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] Picopass 関数合成コンビネータ群 (picopass-seq / choice / fixpoint / when) の実装と単体テスト整備 (DSN-33-01 T2.2) (ID: 757)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 3.3 節、第 7.1 節、およびタスク **T2.2** に基づき、第一級ルール（`Rule Descriptor`）同士を関数合成して新たな複合ルールを構築する **4つの戦略コンビネータ（Strategy Combinators）** を実装する。

先行タスク [Issue #756](756-implement-rule-descriptor-and-picopass-femtopass-attopass-dsl.md) で確立された第一級ルール記述子（`nanopass-make-rule-descriptor`）および三権分立 DSL（`define-picopass`, `define-femtopass`, `define-attopass`）を基礎とし、個別の局所規則を疎結合のまま組み合わせることで、高階な脱糖規則・最適化パイプライン・契約検証規則を宣言的に構築可能にする。

### 提供する4大コンビネータ

1. **`picopass-seq`（直列合成: $p_1 \triangleright p_2$）**:
   - $p_1$ を入力 $ir$ に適用し、マッチして書き換えが発生した場合（結果 $ir'$ が非 `#f` の場合）、その $ir'$ に対して続けて $p_2$ を適用する。
   - $p_1$ がマッチしなかった（`#f` を返した）場合、直列合成はマッチなし（`#f`）として即座にフォールスルーする。
   - $p_1$ がマッチし $p_2$ がマッチしなかった場合は、$p_1$ の生成結果 $ir'$ を安全に保持して返す（部分適用の成功保証）。
   - 複数規則の直列適用版として固定1引数の `(picopass-compose-list rules)` を提供する。
2. **`picopass-choice`（優先選択合成: $p_1 \oplus p_2$）**:
   - 特殊規則 $p_1$ を先に試し、マッチして非 `#f` を返した場合はその結果を採用する。
   - $p_1$ がマッチしなかった（`#f` を返した）場合のみ、汎用規則 $p_2$ を入力 $ir$ に適用してその結果を返す。
   - 複数規則の選択版として固定1引数の `(picopass-choice-list rules)` を提供する。
3. **`picopass-fixpoint`（局所不動点反復: $p^*$）**:
   - 単一ノード上でルール $p$ がマッチしなくなるまで（または変換結果が直前の式と `equal?` になるまで）反復適用する。
   - 最初の試行で一度もマッチしなかった場合は `#f` を返し、一度でも書き換えが行われた場合は最終的な不動点 AST を返す。
   - 発散・無限ループ防止のため、反復回数上限 `max-steps`（デフォルト: 64）を超えた場合は `picopass-fail` により構造化例外を送出する。上限を明示指定可能な `(picopass-fixpoint-limit rule max-steps)` も提供する。
4. **`picopass-when`（契約・条件付き適用: $\text{guard} \Rightarrow \text{pico}$）**:
   - 前提条件（`guard`）が真（非 `#f`）を返したときのみ、本体の `picopass` を適用する。
   - `guard` には `define-attopass` 検査規則、真偽値を返す述語関数、または `(lambda (ir) ...)` を指定可能。
   - `guard` が偽（`#f`）を返した場合は、本体ルールを実行せず即座に `#f`（非マッチ）を返す。

---

## 2. トレーサビリティ / Traceability

- **関連設計書**:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 3.3 節, 第 7.1 節, 第 9.2 節 タスク **T2.2**)
- **依存関係**:
  - **先行 Issue**: [Issue #756 (T2.1: Rule Descriptor と Picopass DSL 実装)](756-implement-rule-descriptor-and-picopass-femtopass-attopass-dsl.md) (Closed)
  - **後続 Issue**:
    - [Issue #758 (T2.3: Pass 015 への新 DSL 統合)](../758-integrate-picopass-dsl-into-pass-015-expander.md)
    - [Issue #759 (T3.1: fuse-rules と O(1) ディスパッチ)](../759-implement-fuse-rules-and-head-tag-o1-dispatch.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler/nanopass_meta.scm](../../../ulisp/compiler/nanopass_meta.scm)
  - ルールメタデータ合成ヘルパー群（`nanopass-combine-head-tags`, `nanopass-combine-sets`）。
  - 基本コンビネータ実装（`picopass-seq`, `picopass-choice`, `picopass-fixpoint`, `picopass-fixpoint-limit`, `picopass-when`）。
  - リスト版コンビネータ実装（`picopass-compose-list`, `picopass-choice-list`）。
  - 合成された規則への第一級 `Rule Descriptor` 付与およびレジストリ自動登録。
- [x] [ulisp/compiler/nanopass.scm](../../../ulisp/compiler/nanopass.scm)
  - ホスト・インタプリタ向けマクロ定義（`picopass-seq*`, `picopass-choice*`）。
- [x] [ulisp/tests/test_nanopass_framework.scm](../../../ulisp/tests/test_nanopass_framework.scm)
  - Section 17 として各コンビネータ（`seq`, `choice`, `fixpoint`, `when`）の単体テストおよび合成ルールのリフレクション検査を追加。
- [x] [ulisp/compiler.scm](../../../ulisp/compiler.scm)
  - `make -C ulisp compiler` による結合コンパイラソース更新。

---

## 4. 詳細設計 / Detailed Design

### 4.1 コンビネータの戻り値と第一級リフレクション契約

各コンビネータが返す値は、**直接引数を取って実行可能な Scheme 手続き** であると同時に、`nanopass-lookup-rule` / `rule-descriptor` によって完全なメタデータを引くことができる **第一級ルール** である。

```scheme
;; 合成ルールの手続きオブジェクトから記述子を取得可能
(let* ((composed (picopass-seq rule-case rule-or))
       (desc (rule-descriptor composed)))
  (assert-true "composed rule has valid descriptor" (rule-descriptor? desc))
  (assert-equal "composed rule-kind is 'pico" 'pico (rule-kind desc)))
```

### 4.2 メタデータ合成規則 (Metadata Fusion Algebra)

合成されたルールの記述子は、構成要素 $R_1, R_2$ のメタデータを以下の代数に従って自動融合する。

| メタデータ項目 | `picopass-seq` ($R_1 \triangleright R_2$) | `picopass-choice` ($R_1 \oplus R_2$) | `picopass-fixpoint` ($R^*$) | `picopass-when` ($G \Rightarrow R$) |
| :--- | :--- | :--- | :--- | :--- |
| `rule-kind` | `'pico` | `'pico` (双方一致時はその種別) | `'pico` | `'pico` |
| `rule-head-tags` | $R_1$ の `head-tags`（初段でマッチが必要なため） | $R_1 \cup R_2$ の `head-tags`（いずれかが `'*` なら `'*`） | $R$ の `head-tags` | $R$ の `head-tags` |
| `rule-reads` | $R_1.\text{reads} \cup R_2.\text{reads}$ | $R_1.\text{reads} \cup R_2.\text{reads}$ | $R.\text{reads}$ | $G.\text{reads} \cup R.\text{reads}$ |
| `rule-writes` | $R_2.\text{writes}$（$R_2$ 空時は $R_1.\text{writes}$） | $R_1.\text{writes} \cup R_2.\text{writes}$ | $R.\text{writes}$ | $R.\text{writes}$ |
| `rule-eliminates`| $R_1.\text{elim} \cup R_2.\text{elim}$ | $R_1.\text{elim} \cup R_2.\text{elim}$ | $R.\text{elim}$ | $R.\text{elim}$ |
| `rule-clauses` | $R_1.\text{clauses} \cup R_2.\text{clauses}$ | $R_1.\text{clauses} \cup R_2.\text{clauses}$ | $R.\text{clauses}$ | $R.\text{clauses}$ |

### 4.3 自己ホスト制約 (Self-Hosting Constraints) の遵守

ULisp コンパイラ自身のブートストラップ過程（特に Pass 060 LVN および Pass 090 Rtyper）で安全にコンパイル・実行されるよう、以下の規約を厳守する。

1. **固定アリティの徹底**:
   - `nanopass_meta.scm` 内の実装関数はすべて固定引数とする。可変長ドットリスト `(define (f a . rest) ...)` は一切使用しない。
   - 任意個数のルール合成には、リストを1引数で受け取る `picopass-compose-list` および `picopass-choice-list` を使用する。
2. **`raise` による例外送出**:
   - 不動点発散時のエラー送出には、`picopass-fail`（R7RS `raise` 準拠）を使用し、上位の `guard` 構文で安全に捕捉・診断可能とする。

---

## 5. セキュリティ考慮事項 / Security Considerations

1. **無限再帰・スタック枯渇の防止 (CWE-400 対策)**:
   - `picopass-fixpoint` において、`A -> B -> A` のような循環書き換え規則が与えられた場合にプロセスがハング・スタックオーバーフローしないよう、既定のステップ上限（`max-steps = 64`）で安全にフェイルクローズ停止（`picopass-fail` 送出）させる。
2. **Fail-Closed な契約評価 (CWE-392 対策)**:
   - `picopass-when` はガード述語が例外を送出した場合、あるいは `#f` を返した場合に本体変換を絶対に実行せず安全側に倒す（変換不実行 / `#f` 返却）。
3. **固定アリティによるコンパイラ ABI 破壊防止 (CWE-704 対策)**:
   - 可変長引数の不完全展開による自己ホストコンパイラ内部クラッシュ（`pair required, but got extra` の再発）を完全に排除する。

---

## 6. 実装手順 / Implementation Steps

Target Branch: `feat/757-implement-picopass-combinators`

### Step 1: ブランチ作成とベース環境確認
- `git checkout -b feat/757-implement-picopass-combinators`
- 直前のテストスイートおよびブートストラップが PASS することを確認。

### Step 2: メタデータ合成ヘルパー群の実装 (`ulisp/compiler/nanopass_meta.scm`)
- `nanopass-combine-head-tags`（タグ集合の結合、`'*` ワイルドカードの吸収）。
- `nanopass-combine-sets`（シンボルリストの和集合演算）。
- ルール解決ユーティリティ `nanopass-resolve-rule-proc`（記述子、シンボル名、手続きオブジェクトの正規化）。

### Step 3: 戦略コンビネータ基本手続きの実装 (`ulisp/compiler/nanopass_meta.scm`)
- `picopass-seq`: 2引数直列合成。
- `picopass-compose-list`: リスト直列合成。
- `picopass-choice`: 2引数優先選択合成。
- `picopass-choice-list`: リスト優先選択合成。
- `picopass-fixpoint-limit`: 上限指定付き局所不動点反復。
- `picopass-fixpoint`: デフォルト上限 (64) 付き局所不動点反復。
- `picopass-when`: ガード付き条件適用。
- 各コンビネータ内で合成 Rule Descriptor を生成し、`nanopass-register-rule!` で自動登録。

### Step 4: ホストマクロの配備 (`ulisp/compiler/nanopass.scm`)
- `picopass-seq*`, `picopass-choice*` マクロを定義。

### Step 5: コンパイラ単一結合ソースの再生成
- `make -C ulisp compiler` を実行し、S 式括弧バランスおよび結合の正常性を検証。

### Step 6: 単体テストスイートの拡充 (`ulisp/tests/test_nanopass_framework.scm`)
- Section 17 を新設し、以下のテストケースを配備:
  1. `picopass-seq` による多段脱糖テスト（`case` $\to$ `let`/`or` $\to$ `if`）。
  2. `picopass-choice` による特殊規則優先試行とフォールスルー検証。
  3. `picopass-fixpoint` による入れ子 `begin` 平坦化および多重ネスト脱糖。
  4. `picopass-fixpoint` の発散ガード（上限ステップ到達時の `picopass-fail` 送出確認）。
  5. `picopass-when` によるガード条件成立時の書き換え実行および不成立時の `#f` 返却。
  6. 合成ルールから `rule-descriptor` へのメタデータ照合（`head-tags`, `reads`, `writes`, `eliminates`）。

### Step 7: 品質ゲート検証とブートストラップ
- `make -C ulisp test_nanopass` (100% PASS)
- `make -C ulisp test_pass_manager test_verifier test_lir_verifier` (100% PASS)
- `make -C ulisp bootstrap` (Stage 1 -> Stage 2 -> Stage 3 固定小数点ビット完全一致)
- `make py_compile static_analysis` (0 エラー合格)

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/compiler/nanopass_meta.scm` に `picopass-seq`, `picopass-compose-list`, `picopass-choice`, `picopass-choice-list`, `picopass-fixpoint`, `picopass-fixpoint-limit`, `picopass-when` がすべて固定アリティで実装されていること。
- [x] 各コンビネータで生成された複合ルールが、単一 S 式引数を取り直接適用可能であること。
- [x] 各コンビネータで生成された複合ルールが有効な `Rule Descriptor` を保持し、`head-tags`, `reads`, `writes`, `eliminates` が正しく引き継がれること。
- [x] `picopass-fixpoint` が発散規則に対して `max-steps`（既定 64）で安全にフェイルクローズ停止すること。
- [x] `ulisp/tests/test_nanopass_framework.scm` に Section 17 単体テストが追加され、全件 PASS すること（`make -C ulisp test_nanopass`）。
- [x] `make -C ulisp bootstrap` が Stage 1 から Stage 3 まで 100% 成功し、ビット完全一致の固定小数点検証を通過すること。
- [x] `docs/issues/README.md` および本 Issue ファイルのステータスが整合して更新されていること。

---

## 8. 完了報告 / Implementation & Verification Report

### 8.1 実装内容サマリー
1. **メタデータ合成代数ヘルパー群の実装 (`ulisp/compiler/nanopass_meta.scm`)**:
   - `nanopass-resolve-rule-proc`, `nanopass-resolve-rule-descriptor`: シンボル・手続き・記述子からのルール正規化解決。
   - `nanopass-combine-sets`: 重複を排除したシンボル集合の和集合。
   - `nanopass-combine-head-tags`: ワイルドカード `'*` を考慮した先頭タグ集合の安全な融合。
2. **戦略コンビネータ群の提供 (`ulisp/compiler/nanopass_meta.scm`, `ulisp/compiler/nanopass.scm`)**:
   - `picopass-seq`, `picopass-compose-list`: 部分適用の安全保持と直列パイプライン実行。
   - `picopass-choice`, `picopass-choice-list`: 特殊規則優先・フォールスルー選択実行。
   - `picopass-fixpoint`, `picopass-fixpoint-limit`: 不動点反復およびステップ上限超過時の `picopass-fail` 構造化例外送出によるフェイルクローズ。
   - `picopass-when`: アトミック契約検証ガードによる条件付きルール実行。
   - ホスト環境用マクロ構文 `picopass-seq*`, `picopass-choice*` を整備。
   - すべての手続きを ULisp 自己ホスト制約に準拠した完全固定アリティで定義。
3. **単体テストスイートの整備 (`ulisp/tests/test_nanopass_framework.scm`)**:
   - Section 17 として全 27 アサーションの包括的テストを追加。全 130 件の Nanopass フレームワークテストを 100% PASS。

### 8.2 検証結果
- **Nanopass Unit Tests**:
  - `make -C ulisp test_nanopass`: 130 / 130 PASSED (100%)
  - `make -C ulisp test_nanopass_tracer`: 31 / 31 PASSED (100%)
  - `make -C ulisp test_pass_manager`: 61 / 61 assertions PASSED (100%)
  - `make -C ulisp test_lir_verifier`: 46 / 46 PASSED (100%)
  - `make -C ulisp test_verifier`: 27 / 27 PASSED (100%)
- **Self-Hosting Bootstrap**:
  - `make -C ulisp bootstrap`: Stage 1 (Native Seed) $\to$ Stage 2 $\to$ Stage 3 すべて成功。
  - Stage 2 (`stage2_compiler.s`) と Stage 3 (`stage3_compiler.s`) の出力アセンブリは**ビット完全一致**（固定小数点到達）。
  - 生成されたネイティブバイナリによるスモークテスト (`smoke_test_bootstrap.bin`) 実行成功 (exit code 42)。
  - `ulisp/bin/ulisp-boot` シードバイナリの更新を完了。
- **リポジトリ静的解析 & 品質ゲート**:
  - `make py_compile static_analysis`: 617 files scanned, 0 issues, Radon/Xenon 複雑度ランク A (100% PASS)。
