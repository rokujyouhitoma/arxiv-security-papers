---
ID: 759
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] define-pass 内 fuse-rules 構文と先頭タグ (Head-Tag) 別 O(1) case ディスパッチ生成エンジンの実装 (DSN-33-01 T3.1) (ID: 759)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 4.2 節、第 4.4 節、第 8.4 節、およびタスク **T3.1** に基づき、`define-pass` 内に複数の Picopass / Femtopass / Attopass を単一の走査関数へ融合する **`(fuse-rules ...)`（別名 `fuse-tree-rules`）構文** を導入し、従来の $O(R)$ 線形 `if` カスケード（`nanopass-build-rules-cascade`）を刷新する **先頭タグ（Head Symbol）別 $O(1)$ `case` ディスパッチ生成エンジン** を実装した。

### 1.1 背景とアーキテクチャ上の課題

従来の Nanopass フレームワークでは、`define-pass` 内に定義された $R$ 個の規則が `nanopass-build-rules-cascade` により単純な `if` カスケードとして直列に連結されていた。
例えば、フロントエンド脱糖を統括する `030_desugar.scm` は約 100 個の脱糖規則を保持しているため、構文木中の変数参照 `x` や定数 `42`、あるいは単純な `if` 式を走査する際にも、ノード 1 つあたり毎回最大 100 回のパターン照合（`nanopass-match-clause`）が線形に試行されていた。これにより、AST の総ノード数を $N$、ルール数を $R$ としたとき、$O(N \times R)$ の計算量オーバーヘッドが発生し、コンパイル時間のボトルネックとなっていた。

本タスク（T3.1）では、先行タスク [Issue #756](756-implement-rule-descriptor-and-picopass-femtopass-attopass-dsl.md)、[Issue #757](757-implement-picopass-strategy-combinators.md)、および [Issue #758](758-integrate-picopass-dsl-into-pass-015-expander.md) で確立された第一級ルール記述子（`Rule Descriptor`）を活用し、以下の2つのコア機能を実現した：

1. **先頭タグ別 $O(1)$ `case` ディスパッチ生成エンジン**:
   - パターンの先頭シンボル（`head-tags`）ごとに規則をバケット分類し、アトムの即時除外と `(case (car ir) ...)` による $O(1)$ 直撃分岐コードを生成する。
   - ルール数が 10 個から 100 個、あるいは 300 個へと増加しても、1 ノードあたりのディスパッチコストを $O(1)$ 一定に抑制する。
   - `fuse-rules` 経由のルールだけでなく、既存の全 `define-pass` のインライン規則に対しても透過的に適用し、コンパイラ全体の走査速度を底上げする。
2. **`define-pass` 内の `(fuse-rules ...)` / `(fuse-tree-rules ...)` 構文**:
   - `define-pass` 内で独立した複数の `define-picopass`（および合成ルール）を指定可能にし、コンパイル時に記述子レジストリ `*nanopass-rules*` からメタデータと展開済みパターン節を自動解決して単一の高速走査関数へ融合する。

---

## 2. トレーサビリティ / Traceability

- **関連設計書**:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
    - 第 4.2 節（先頭タグによる $O(1)$ ディスパッチ生成）
    - 第 4.4 節（2種類の走査ドライバ: `fuse-tree-rules` と `fuse-window-rules`）
    - 第 4.5 節（性能予測モデル: $O(P \times N \times R) \to O(P_{\text{fused}} \times N \times 1)$）
    - 第 8.4 節（既存機能統廃合マトリクス）
    - 第 9.2 節（Phase 3 タスク **T3.1**）
- **依存関係**:
  - **先行 Issue**:
    - [Issue #756 (T2.1: Rule Descriptor と Picopass DSL 実装)](756-implement-rule-descriptor-and-picopass-femtopass-attopass-dsl.md) (Closed)
    - [Issue #757 (T2.2: 関数合成コンビネータ群の実装)](757-implement-picopass-strategy-combinators.md) (Closed)
    - [Issue #758 (T2.3: Pass 015 への新 DSL 統合)](758-integrate-picopass-dsl-into-pass-015-expander.md) (Closed)
  - **後続 Issue**:
    - [Issue #760 (T3.2: 局所再適用と extends (-) 対 eliminates 整合性検証)](../760-implement-local-redispatch-and-extends-eliminates-validation.md)
    - [Issue #761 (T3.3: LIR 向け fuse-window-rules スライディングウィンドウ走査)](../761-implement-fuse-window-rules-for-lir-sliding-window.md)
    - [Issue #762 (T4.1: フロントエンド脱糖パス 026〜029 の Picopass 化)](../762-migrate-desugar-passes-026-to-029-to-picopass.md)
    - [Issue #763 (T4.2: 030_desugar.scm の fuse-rules 完全置換)](../763-replace-desugar-030-duplicate-rules-with-fuse-rules.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
  - `nanopass-build-rules-cascade` を Head-Tag $O(1)$ ディスパッチコード生成エンジンへ刷新。
  - `nanopass-parse-nt-clause` および `nanopass-expand-define-pass-with-trace` において `(fuse-rules ...)` / `(fuse-tree-rules ...)` 節の解析とルール記述子インライン展開を実装。
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm)
  - `make -C ulisp compiler` による結合ソース再生成と括弧バランス検証。
- [x] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm)
  - Section 18 として `fuse-rules` 構文の単体テスト、Head-Tag $O(1)$ `case` 分岐生成の検証、複数 Picopass 融合実行の検証を追加（19 テスト追加、全 149 テスト PASS）。

---

## 4. 詳細設計 / Detailed Design

### 4.1 先頭タグ分類アルゴリズム (Head-Tag Bucketing)

入力されたルール列 $R = [r_1, r_2, \dots, r_k]$（各ルールは `(pat vars guard-expr body-expr)` 形式）を走査し、以下の3カテゴリへと分類する：

1. **固定先頭シンボルルール群 (`head-buckets`)**:
   - パターンが `(sym ...)` 形式（`sym` はシンボルであり、かつ `unquote`, `_`, `...` ではない具象キーワード）であるもの。
   - `sym` ごとのバケット（連想リスト: `((sym1 . (r1 r2 ...)) (sym2 . (r3 ...)))`）に格納する。
   - 同一タグ内でのルールの出現順序（優先度）は厳密に維持される。
2. **ペア汎用フォールバックルール群 (`pair-fallbacks`)**:
   - パターンがペアであるが、先頭が `,op`（変数束縛）や `((,a ...) ...)`（入れ子ペア）など動的・汎用的なもの。
3. **アトム／ワイルドカードルール群 (`atom-rules`)**:
   - パターンがペアでないもの（`,x` などの単一変数パターン、数値・真偽値・文字列等のリテラル定数）。

```scheme
(define (nanopass-rule-head-symbol pat)
  (cond
    ((not (pair? pat)) #f)
    ((eq? (car pat) 'unquote) #f)
    ((eq? (car pat) '_) #f)
    ((eq? (car pat) '...) #f)
    ((symbol? (car pat)) (car pat))
    (else #f)))
```

### 4.2 生成される $O(1)$ ディスパッチコードの構造

分類されたバケット群に基づき、以下の構造を持つ Scheme コードを展開する：

```scheme
;; 生成されるディスパッチコードの論理構造
(if (pair? ir)
    (if (symbol? (car ir))
        (case (car ir)
          ((cond)
           <subcascade for cond rules, fallback: pair-fallback-expr>)
          ((if)
           <subcascade for if rules, fallback: pair-fallback-expr>)
          ((letrec)
           <subcascade for letrec rules, fallback: pair-fallback-expr>)
          ...
          (else
           pair-fallback-expr))
        pair-fallback-expr)
    atom-fallback-expr)
```

- **アトム高速パス**: `(not (pair? ir))` の場合、1回の述語判定で即座に `atom-fallback-expr` へ跳び、ペア用パターンマッチ（何十〜何百個のルール）を完全にバイパスする。
- **具象タグ直撃**: `(car ir)` がシンボルかつ `case` のキーに存在する場合、他の無関係な構文タグを一切評価せず該当バケットの数個のルールのみを試行する。
- **安全なフォールスルー**: 該当タグ内でマッチしなかった場合、またはタグが未知である場合は、`pair-fallback-expr` $\to$ `nanopass-catamorphism-step` へとシームレスにフォールスルーする。

### 4.3 `(fuse-rules ...)` の構文仕様と解決フロー

`define-pass` において以下の2種類の指定方法をサポートする：

#### (1) トップレベル `fuse-rules` 指定
```scheme
(define-pass desugar-bindings : L_src (ir) -> L_core ()
  (fuse-rules rule-let* rule-letrec rule-named-let))
```
- 非終端記号の明示的な括りを省略した場合、各ルールの `rule-nt-name`（既定: `'Expr`）に基づいて自動的に非終端記号別バケットへ振り分け、エントリ非終端記号（`Expr`）の走査手続きを合成する。

#### (2) 非終端記号句内でのインライン `fuse-rules` 指定
```scheme
(define-pass desugar-special : L_src (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    (fuse-rules rule-cond rule-case)
    ((special-tag ,x) `(handled ,x))))
```
- `fuse-rules` で指定された Picopass の `expanded-rules` 節と、同一句内にインライン記述された個別ルールをシームレスに結合し、一括して Head-Tag バケット分類に投入する。

#### (3) ルール解決プロシージャ
- 引数としてシンボル `'rule-name` が与えられた場合、Pass 015 で登録された `(nanopass-lookup-rule 'rule-name)` から記述子を取得し、その `rule-clauses` を抽出してインライン展開する。

---

## 5. セキュリティ考慮事項 ＆ 脅威分析 (Security Considerations)

1. **計算量爆発・コンパイル DoS の根本防止 (CWE-400 対策)**:
   - ルール数 $R$ の増加に伴うパターン照合回数が $O(R)$ から $O(1)$ へと劇的に低減される。悪意ある巨大・深層 AST や大量のマクロ展開が入力された場合でも、コンパイラが CPU タイムアウト（DoS）に陥るリスクを構造的に排除する。
2. **型混同および非ペアへの不正アクセス防止 (CWE-704 対策)**:
   - `(car ir)` を評価する前に、必ず `(pair? ir)` および `(symbol? (car ir))` の安全ガードを挟む。シンボル・数値・真偽値等のアトムや、不完全リスト・非シンボル先頭ペア（`((lambda ...) ...)`）に対して `case` ディスパッチが異常終了しない防御的設計を徹底する。
3. **決定論的評価順序の保護 (CWE-697 対策)**:
   - 同一タグバケット内（例: `if` の定数条件最適化ルールと汎用 `if` ルール）において、ユーザーが定義した記述順序がソートやセット化によって崩れないよう、先頭から順次試行する決定論的カスケードを厳密に保証する。

---

## 6. 実装手順 / Implementation Steps

Target Branch: `feat/759-implement-fuse-rules-o1-dispatch`

### Step 1: ブランチ作成とベースライン確認
- `git checkout -b feat/759-implement-fuse-rules-o1-dispatch`
- `make -C ulisp test_all_passes` および `make -C ulisp bootstrap` が正常であることを確認。

### Step 2: Head-Tag バケット分類ヘルパーの実装 (`ulisp/compiler/nanopass.scm`)
- `nanopass-rule-head-symbol`（パターンの先頭シンボル判定）。
- `nanopass-partition-rules`（具象シンボルバケット、ペア汎用、アトムの3分割）。

### Step 3: $O(1)$ ディスパッチ生成エンジン `nanopass-build-rules-cascade` の刷新
- バケットが空でない場合は `(if (pair? ir) (if (symbol? (car ir)) (case ...) ...) ...)` を構築。
- バケットが空の場合は従来のフラットなカスケードを生成。

### Step 4: `define-pass` 構文展開器への `fuse-rules` 節の統合
- `nanopass-expand-define-pass-with-trace` において：
  - `(fuse-rules r1 r2 ...)` / `(fuse-tree-rules r1 r2 ...)` 節の検知とパース。
  - ルール記述子（`Rule Descriptor`）からの `rule-clauses` 抽出と非終端記号へのマージ。

### Step 5: コンパイラ結合ソース再生成と単体テスト整備
- `make -C ulisp compiler` を実行し、括弧バランスを検証。
- `ulisp/tests/test_nanopass_framework.scm` に Section 18 を新設し、19 件の単体テストを実装。

### Step 6: 品質ゲートおよびセルフホスティングブートストラップ検証
- `make -C ulisp test_nanopass` (149 tests 100% PASS)
- `make -C ulisp test_passes` (全 39 Nanopass 1:1 単体テスト PASS)
- `make -C ulisp test_pass_manager test_lir_verifier test_verifier` (100% PASS)
- `make -C ulisp bootstrap` (Stage 1 Native Seed $\to$ Stage 2 $\to$ Stage 3 ビット完全一致)
- `make py_compile static_analysis` (0 エラー合格)

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `define-pass` 内で `(fuse-rules r1 r2 ...)` および `(fuse-tree-rules r1 r2 ...)` 構文が受け付けられ、登録済み Picopass 群が単一走査関数へ正しく融合されること。
- [x] 生成されるディスパッチコードが、先頭シンボルを持つ規則群に対して `(case (car ir) ...)` による $O(1)$ 分岐構造を形成していること。
- [x] アトム（定数・シンボル）に対してペア用規則が試行されず、即座にアトム処理またはカタモルフィズムへバイパスされること。
- [x] 既存の全 `define-pass` パスがリグレッションなく動作し、テストスイート（`test_nanopass`, `test_passes`）が 100% PASS すること。
- [x] `make -C ulisp bootstrap` が Stage 1 から Stage 3 まで 100% 成功し、ビット完全一致の固定小数点検証を通過すること。
- [x] `docs/issues/README.md` および本 Issue ファイルのステータスが整合して更新されていること。

---

## 8. 完了報告 / Completion Report

- **完了日**: 2026-11-11
- **担当エージェント**: Systems Architect & IT Specialist (PLC / Compilers)
- **マージコミット**: `feat/759-implement-fuse-rules-o1-dispatch`
- **成果サマリー**:
  1. `ulisp/compiler/nanopass.scm` において、`nanopass-rule-head-symbol`, `nanopass-rule-can-match-pair?`, `nanopass-rule-can-match-atom?`, `nanopass-add-rule-to-bucket`, `nanopass-partition-rules` を実装。
  2. `nanopass-build-rules-cascade` を先頭タグ別 $O(1)$ `case` ディスパッチ生成エンジンへと刷新。アトムの即時バイパスと具象タグへの $O(1)$ 直撃分岐を実現。
  3. `define-pass` において `(fuse-rules ...)` および `(fuse-tree-rules ...)` をトップレベルおよび非終端記号節内の両方で受理し、コンパイル時記述子レジストリ `*nanopass-rules*` から展開済み規則節を自動解決・インライン化する機構を統合。
  4. `ulisp/tests/test_nanopass_framework.scm` に Section 18 を追加し、トップレベル融合・インライン融合・Head-Tag ディスパッチ・アトム高速パス・同一タグ順序維持の 19 件の単体テストを網羅（130 件 $\to$ 149 件 100% PASS）。
  5. `make -C ulisp bootstrap` による Stage 1 $\to$ Stage 2 $\to$ Stage 3 の bit-for-bit 完全一致固定小数点自己ホスティング検証に 100% 合格。
  6. `make py_compile static_analysis` による 617 ファイルの静的解析（Xenon Rank A、エラー 0 件）に合格。

