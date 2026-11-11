---
ID: 766
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] HIR/MIR Hash-Consing Term DAG と訪問済みノード O(1) メモ化走査および CP0/Contify の Picopass 化 (DSN-33-01 T5.2) (ID: 766)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 5.2 節（(1) HIR / MIR における Hash-Consing Term DAG と $O(1)$ メモ化走査）、第 6.2 節、および第 9.2 節タスク **T5.2** に基づき、Nanopass 走査ドライバに **共有部分木（Shared Term DAG）の $O(1)$ メモ化走査機構** を導入するとともに、MIR 最適化パス群（`050_cp0.scm`, `100_contify.scm`）の主要最適化規則を `define-picopass` / `define-femtopass` として再構築する。

マクロ展開やインライン展開によって同一の部分式が複数箇所で共有（DAG 化）された際、従来の木走査では同じ部分木を重複して変換・解析していたが、走査ドライバが Picopass から分離されたことにより、ドライバ側の `eq?` メモ化テーブル1つで共有ノードの重複走査を完全にゼロ化できる。さらに、定数畳み込み・分岐刈り込み・不要束縛除去（CP0）および局所クロージャ脱糖（Contify）を微細粒度第一級ルール記述子へ移行し、パイプライン全体の宣言的融合とトレーサビリティを確立する。

---

## 2. 背景と課題分析 / Background and Problem Analysis

### 2.1 現行実装における AST 冗長走査とモノリシック MIR 最適化の課題

これまでの Nanopass 基盤整備（Phase 1 〜 Phase 4, Issue #754 〜 #765）により、フロントエンド脱糖パス（026〜030）の Picopass 化とルール依存 DAG の自動解析が完成した。しかし、中間表現（HIR / MIR）処理において以下の構造的課題が依然として残されている：

1. **共有部分木（Term DAG）に対する $O(N)$ 重複走査の頻発**:
   - マクロ展開や `let` 展開、共通部分式で同一の AST ノード（不変 S 式）が複数個所に埋め込まれた際、従来の再帰木走査（Catamorphism）はノードがメモリ上で同一（`eq?`）であっても毎回枝全体を再帰下降して重複走査する。
   - 大規模な式や深層ネストにおいて同一部分式の評価・変換が指数関数的に重複し、コンパイル時間の顕著な劣化を招いていた。
2. **`050_cp0.scm` のモノリシック肥大化**:
   - 定数畳み込み（`fold-const-op`）、真偽値分岐簡約（`(if #t a b) -> a`）、`begin` 扁平化、`let` 不活性変数除去、および `letrec` 強連結成分 DCE が単一の `cp0-opt` 関数内に混在しており、個別のルール単位での依存性解析や部分無効化が不可能であった。
3. **`100_contify.scm` の手書き走査ループ**:
   - `100_contify.scm` 内で `contify-subst` および `contify-expr` が独自の `case` 式手動再帰走査を保持しており、Nanopass フレームワークの標準カタモルフィズムおよび構造共有（`nanopass-cons-sharing`）の恩恵を享受できていなかった。
4. **不変構文ノードの重複アロケーション**:
   - 同一のリテラルや同一の純粋演算 S 式がコードベース内で何度も新規 `cons` アロケーションされ、GC プレッシャーおよびキャッシュ局所性の悪化を引き起こしていた。

---

## 3. トレーサビリティ / Traceability

- **関連設計書**:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
    - 第 5.2 節（(1) HIR / MIR における Hash-Consing Term DAG と $O(1)$ メモ化走査）
    - 第 6.2 節（ミドルエンド最適化の垂直統合）
    - 第 9.2 節 タスク **T5.2**（HIR / MIR Hash-Consing Term DAG と訪問済みノード $O(1)$ メモ化）
- **依存関係**:
  - 先行 Issue:
    - [Issue #755 (T1.3: 未変更部分木の構造共有とトレース統一)](closed/755-implement-catamorphism-structural-sharing-and-unify-trace-hooks.md)
    - [Issue #756 (T2.1: 第一級ルール記述子と define-picopass/femtopass/attopass DSL 実装)](closed/756-implement-rule-descriptor-and-picopass-femtopass-attopass-dsl.md)
    - [Issue #765 (T5.1: ルール依存関係 DAG 自動構築と Femtopass キャッシュ維持)](closed/765-implement-rule-dependency-dag-and-femtopass-cache-invalidation.md)
  - 後続 Issue:
    - [Issue #767 (T5.3: LIR 分岐融合・ピープホールの Picopass 化と命令データ依存 DAG 走査)](767-migrate-lir-peephole-to-picopass-and-dependency-dag.md)
    - [Issue #768 (T6.1: define-pipeline による用途別パイプライン編成)](768-implement-define-pipeline-for-aot-repl-and-check-modes.md)
    - [Issue #770 (T6.3: 3-Stage セルフホスティング不動点検証およびベンチマーク)](770-verify-stage3-self-hosting-fixed-point-and-benchmark-pass-fusion.md)

---

## 4. アーキテクチャと専門エージェント多角的審議 / Multi-Agent Perspectives

1. **Systems Architect (方式設計)**:
   - Term DAG の $O(1)$ メモ化走査は、Nanopass カタモルフィズム実行コンテキストにスコープ付きメモ化テーブル（`*nanopass-term-memo*`）を設ける。
   - `unique-symbol` やスコープ束縛変数名の置換など、文脈依存（Context-sensitive）または新鮮なシンボル生成を伴うパスではメモ化を局所的に無効化（Bypass）できる制御フラグ `*nanopass-memo-enabled?*` を配備する。
2. **Software Development (SWD / コア実装)**:
   - `ulisp/compiler/nanopass_meta.scm` に `nanopass-hash-cons` コンストラクタおよび `nanopass-memoized-catamorphism` ドライバを追加。
   - `050_cp0.scm` を `rule-cp0-const-fold`, `rule-cp0-prune-if`, `rule-cp0-flatten-begin`, `rule-cp0-dead-let`, `rule-cp0-dead-letrec` 等の `define-picopass` 群に分割し、`fuse-rules` で合成。
   - `100_contify.scm` の `escapes?`, `tail-calls-only?`, `contifiable-binding?` を `define-femtopass` として定義し、置換処理を `define-picopass` へ統一。
3. **IT Specialist (Programming Languages & Compilers / PLC)**:
   - Hash-Consing の健全性（Soundness）:
     可変セル（`set-car!`, `set-cdr!`）の対象となる対は Hash-Consing の対象外とし、純粋不変 S 式（定数リテラル、純粋適用、正準構文ノード）のみを intern 対象とする。
   - ポインタ等価性（`eq?`）の伝播:
     DAG 化されたノード $T$ に対する走査 $P(T)$ の結果 $T'$ は、走査完了後にメモ化テーブル `(cons T T')` に格納され、同一走査内で再び $T$ に遭遇した際は $T'$ が $O(1)$ で返却される。これにより木が DAG であっても走査の総時間計算量はノード数 $|V|$ に対して線形 $O(|V|)$ に抑えられる。
4. **Information Security Specialist (セキュリティ検証)**:
   - メモ化テーブルのスコープ境界漏洩防止（CWE-662 不適切な同期 / 状態汚染）:
     パス走査完了時にメモ化テーブルが確実に解放・リセットされるよう、動的巻き戻しガード（`guard` / `set!` リセット）を適用し、他コンパイル単位への誤キャッシュヒットを遮断。
5. **Software Quality Assurance Specialist (品質保証)**:
   - 共有ノードを持つ合成 Term DAG に対し、メモ化走査有効時と無効時で出力 AST が構造的に完全一致（`equal?`）し、かつ訪問関数呼び出し回数が共有ノード数分厳密に削減されることを単体テストで検証。
   - 既存の `test_050_cp0.scm`, `test_060_lvn.scm`, `test_100_contify.scm`, `test_all_passes` が 100% PASS することを保証。

---

## 5. 脅威モデル分析とセキュリティ要件 / Threat Modeling & Security Requirements

| 脅威 ID | 対象 | 脆弱性区分 | 脅威シナリオ | 緩和策・セキュリティ要件 |
| :--- | :--- | :--- | :--- | :--- |
| **THREAT-766-01** | メモ化キャッシュスコープ | CWE-662 (Improper Synchronization / State Pollution) | 異なる関数やパス間でメモ化キャッシュが残留し、文脈の異なるスコープの変換結果が誤ヒットして不正コードが生成される。 | メモ化スコープを走査単位に厳格に限定し、`with-nanopass-term-memo` の終了時にテーブルを完全にリセット。 |
| **THREAT-766-02** | 可変 S 式の Hash-Consing | CWE-345 (Insufficient Verification of Data Authenticity) | 後続パスで変更される可能性のある可変リストが Hash-Consing され、エイリアス変更が他の無関係な構文木を破壊する。 | 不変式（リテラルおよび正準 AST 式）のみを intern 対象とし、可変ペアのアロケーションは通常の `cons` を強制。 |
| **THREAT-766-03** | メモ化テーブルのメモリ肥大化 | CWE-400 (Resource Exhaustion) | 大規模コードベースのコンパイル時にメモ化テーブルが解放されず、ヒープメモリが枯渇する。 | パス走査完了ごとの即時アンバインドおよび短命アロケーションを採用。 |

---

## 6. 詳細設計仕様 / Detailed Technical Specifications

### 6.1 Hash-Consing コンストラクタ (`nanopass-hash-cons`)

```scheme
;;; 純粋不変ノードのための Hash-Consing テーブル
(define *nanopass-hash-cons-table* '())

(define (nanopass-hash-cons-reset!)
  (set! *nanopass-hash-cons-table* '()))

;;; (car . cdr) の構造等価エントリを探索し、存在すれば既存ポインタを返す
(define (nanopass-hash-cons a d)
  (let ((key (cons a d)))
    (let ((existing (assoc key *nanopass-hash-cons-table*)))
      (if existing
          (cdr existing)
          (let ((new-pair (cons a d)))
            (set! *nanopass-hash-cons-table*
                  (cons (cons key new-pair) *nanopass-hash-cons-table*))
            new-pair)))))
```

### 6.2 訪問済みノード $O(1)$ メモ化カタモルフィズム (`nanopass-memoized-catamorphism`)

```scheme
;;; 走査単位のノードメモ化テーブル
(define *nanopass-term-memo* '())
(define *nanopass-term-memo-enabled?* #t)

(define (nanopass-term-memo-reset!)
  (set! *nanopass-term-memo* '()))

(define (with-nanopass-term-memo thunk)
  (let ((old-memo *nanopass-term-memo*))
    (set! *nanopass-term-memo* '())
    (let ((res (guard (ex (else (set! *nanopass-term-memo* old-memo) (raise ex)))
                 (thunk))))
      (set! *nanopass-term-memo* old-memo)
      res)))

;;; メモ化対応の AST 走査ヘルパー
(define (nanopass-memoize-step node transform-fn)
  (if (or (not *nanopass-term-memo-enabled?*) (not (pair? node)))
      (transform-fn node)
      (let ((hit (assq node *nanopass-term-memo*)))
        (if hit
            (cdr hit)
            (let ((res (transform-fn node)))
              (set! *nanopass-term-memo*
                    (cons (cons node res) *nanopass-term-memo*))
              res)))))
```

### 6.3 `050_cp0.scm` の Picopass 分割と自動融合

1. **`rule-cp0-const-fold`**:
   - `(+ c1 c2)`, `(* c1 c2)`, `(- c1 c2)`, `(zero? c)` などの定数計算を `fold-const-op` により定数ノードへ置換。
2. **`rule-cp0-prune-if`**:
   - `(if #t then else) -> then`
   - `(if #f then else) -> else`
   - `(if test then #f)` の正規化
3. **`rule-cp0-flatten-begin`**:
   - ネストした `begin` 式のインライン平坦化。
4. **`rule-cp0-dead-let`**:
   - `(let ((x e) ...) body)` において、`pure-expr?` かつ `body` 内で出現しない不要変数を削除。全変数が削除された場合は `body` へ退化。
5. **`rule-cp0-dead-letrec`**:
   - `dce-letrec` アルゴリズムを適用し、到達不能な相互再帰関数を刈り込み。
6. **`rule-cp0-call-values`**:
   - `%call-with-values` と `%values` の直接束縛展開。

### 6.4 `100_contify.scm` の Femtopass / Picopass 移行

1. **`femto-contifiable?`**:
   - 対象関数がエスケープせず、かつ全呼び出し箇所が末尾位置にあるかを判定する非破壊属性解析。
2. **`rule-contify-calls`**:
   - 対象関数呼び出しを `(%cont-call var . args)` へ置換する第一級 Picopass。
3. **`rule-contify-letrec`**:
   - 単一束縛の `letrec` を `%cont-fun` 構文ノードへ昇格する Picopass。

---

## 7. 実装手順と対象ファイル / Implementation Steps & Affected Files

Target Branch: `feat/766-term-dag-memoization-and-mir-picopass`

### 7.1 対象ファイル一覧
- [x] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)（Hash-Consing コンストラクタ、Term DAG メモ化走査ドライバ、スコープリセット API）
- [x] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm)（with-nanopass-term-memo 統合およびパイプラインリセット）
- [x] [ulisp/frontend/050_cp0.scm](../../ulisp/frontend/050_cp0.scm)（CP0 規則の define-picopass 化とトップレベル関数分解）
- [x] [ulisp/frontend/100_contify.scm](../../ulisp/frontend/100_contify.scm)（Contify 判定の define-femtopass 化および置換の define-picopass 化）
- [x] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm)（Term DAG メモ化・Hash-Consing Section 23 単体テスト追加）
- [x] [ulisp/tests/passes/test_050_cp0.scm](../../ulisp/tests/passes/test_050_cp0.scm)（Pass 050 単体テスト検証）
- [x] [ulisp/tests/passes/test_100_contify.scm](../../ulisp/tests/passes/test_100_contify.scm)（Pass 100 単体テスト検証）

### 7.2 ステップ別実装計画
- [x] **Step 1: Hash-Consing コンストラクタと Term DAG メモ化機構の実装** (`ulisp/compiler/nanopass_meta.scm`, `ulisp/compiler/pass_manager.scm`):
  - `nanopass-hash-cons`, `nanopass-hash-cons-list`, `nanopass-hash-cons-reset!`, `nanopass-term-memo-reset!`
  - `nanopass-memoize-step`, `with-nanopass-term-memo`, `nanopass-term-memo-stats`, `nanopass-term-memo-hit-rate`
- [x] **Step 2: `050_cp0.scm` の Picopass 分割と合成**:
  - `rule-cp0-prune-if-3`, `rule-cp0-prune-if-2`, `rule-cp0-flatten-begin`, `rule-cp0-dead-let`, `rule-cp0-dead-letrec`, `rule-cp0-call-values`, `rule-cp0-const-fold` を `define-picopass` として定義。
  - `cp0-opt` をこれら第1級 Picopass 規則を用いて再編成。
- [x] **Step 3: `100_contify.scm` の Femtopass / Picopass 化**:
  - `femto-contifiable?` (Femtopass) および `rule-contify-letrec` (Picopass) の第一級ルール記述子化。
  - `contify-letrec` を `rule-contify-letrec` へ統合。
- [x] **Step 4: 単体テスト群の拡充と検証**:
  - `test_nanopass_framework.scm` に Section 23 (Term DAG & Memoized Catamorphism) テストを追加。
  - 共有部分木に対する変換で、子ノードの変換が正確に1回のみ実行されることを計量検証。
  - `test_050_cp0.scm`, `test_100_contify.scm`, `test_passes`, `test_all_passes` の PASS 確認。
- [x] **Step 5: 全品質ゲートとセルフホスティング検証**:
  - `make -C ulisp compiler`
  - `make -C ulisp test_nanopass`, `make -C ulisp test_verifier`, `make -C ulisp test_passes`, `make -C ulisp test_all_passes`
  - `make -C ulisp test_c` (全 143 件 PASS)
  - `make -C ulisp test` (3ステージブートストラップ不動点 bit-for-bit IDENTICAL PASS)
  - `make py_compile && make static_analysis` (Xenon AAA / mypy strict PASS)

---

## 8. 完了条件 / Success Criteria (DoD)

1. [x] **Hash-Consing と Term DAG メモ化走査**:
   - `nanopass-hash-cons` が構造的に等しい不変式に対して同一のポインタ（`eq?`）を返却すること。
   - 共有ノードを持つ Term DAG に対し、`with-nanopass-term-memo` 環境下で同一ノードの重複走査が $O(1)$ キャッシュヒットにより完全に抑止されること。
2. [x] **`050_cp0.scm` の Picopass 適合**:
   - 定数畳み込み、分岐刈り込み、DCE が独立した第一級ルール記述子（`define-picopass`）として定義され、`cp0-optimize` が全既存 CP0 テストをパスすること。
3. [x] **`100_contify.scm` の Picopass 適合**:
   - 局所関数の脱糖および呼び出し置換が `define-picopass` / `define-femtopass` として定義され、全既存 Contify テストをパスすること。
4. [x] **テスト完全 PASS & 品質ゲート保証**:
   - `ulisp/tests/test_nanopass_framework.scm` の新テストを含む全単体テストが PASS すること。
   - `make -C ulisp test_c` (全 143 件 PASS) および `make -C ulisp test` (ブートストラップ不動点 bit-for-bit 一致) が保証されること。
   - `make py_compile` および `make static_analysis` がエラー 0 件で PASS すること。
   - 全ての内部ドキュメントリンクが相対パス規約に準拠していること。

---

## 9. 検証結果記録 / Verification Results

- **`make -C ulisp compiler`**: S式括弧整合性・モジュール結合 100% PASS。
- **`make -C ulisp test_nanopass`**: Section 23 (Term DAG Hash-Consing & Memoized Catamorphism) を含む全単体テスト 100% PASS。
- **`make -C ulisp test_verifier`**: Canonical LIR Verifier 全テスト 100% PASS。
- **`make -C ulisp test_passes` & `make -C ulisp test_all_passes`**: 全 39 個の Nanopass 単体テスト (Pass 010〜160, CP0, Contify) 100% PASS (0 failures)。
- **`make -C ulisp test_c`**: Portable C バックエンド全 143 件 PASS (zero warnings)。
- **`make -C ulisp test`**: 3-Stage セルフホスティングブートストラップ検証完了。Stage 2 と Stage 3 の生成コードが bit-for-bit 完全一致 (IDENTICAL)。
- **`make py_compile && make static_analysis`**: mypy --strict (617 source files 0 issues), Xenon AAA, isort 100% PASS。
- **相対パスリンク整合性**: 全ドキュメント参照が相対パスに準拠。

