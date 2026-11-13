---
ID: 769
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] 発火 Picopass 名の来歴追跡 (Provenance Tracking) トレーサと Rule-level Auto-Bisect 自動二分探索デバッグの実装 (DSN-33-01 T6.2) (ID: 769)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 7.2 節（来歴追跡と細粒度 AST Diff）、第 7.3 節（ルール単位の自動二分探索デバッグ）、第 8.4 節、および第 9.2 節タスク **T6.2** に基づき、Pass Fusion 基盤に高度な診断・自己修復デバッグ支援機能（Provenance Tracking & Rule-level Auto-Bisect）を実装する。

先行する Issue #759 〜 #767 の Pass Fusion / Picopass 統廃合により、Frontend 脱糖層（`030_desugar.scm`）や LIR ピープホール（`133_lir_peephole.scm`）において数十個の独立した書き換え規則が単一の走査パス内へ高度に融合された。
しかし、この「超細粒度ルールの単一パス融合」は、コンパイル速度とメモリ消費を劇的に改善した一方で、以下の **観測性・デバッグ性における新たな構造的課題** を生じさせた：

1. **発火ルールの不可視化（ブラックボックス化）**:
   - 融合前の Nanopass 群では「どのパスで AST が変化したか」が 1 パスごとに一目瞭然であったが、Pass Fusion 後は単一の Nanopass 内で複数の Picopass（例: `rule-desugar-letrec`, `rule-desugar-cond`, `rule-desugar-and` 等）が連続して発火するため、出力 AST に異常が発生した際に **「どの Picopass ルールがそのノードを不正に書き換えたのか」** をトレースログから特定することが困難となった。
2. **ルール単位の不具合特定コストの増大**:
   - 最適化有効時（`-O2`）にのみコード生成異常やセグメンテーション違反が発生した場合、融合された数十個の Picopass ルールのうちどれが不具合の原因かを突き止めるために、手動でコードをコメントアウトする極めて時間のかかる試行錯誤が必要となっていた。

本 Issue では、この課題を根本解決するため、以下の 2 大診断基盤を構築する：

1. **Picopass 発火来歴追跡（Provenance Tracking）と拡張 AST Diff**:
   - 各 Picopass ルールがマッチ・発火してノードを変換した際に、発火したルール名（例: `desugar-all :: rule-desugar-letrec`、`lir-peephole :: rule-lir-self-mov-elim`）と発火回数を記録。
   - `nanopass-display-ast-diff` およびコンパイラ診断情報（`compiler_diagnostics`）において、全体差分に加えて **「発火した Picopass ルール内訳と発火回数」** を詳細表示する。
2. **Rule-level Auto-Bisect（ルール単位の自動二分探索 / Delta Debugging）**:
   - 個別の Picopass ルールを名前シンボル単位で動的に有効・無効化する API（`disable-picopass!`, `enable-picopass!`, `picopass-enabled?`, `with-disabled-picopasses`）を整備する。
   - 与えられた候補 Picopass ルール群 $R = [r_1, \dots, r_n]$ とテスト述語関数 `(test-fn)` に対し、Delta Debugging アルゴリズムによる自動二分探索を実行し、**不具合を引き起こしている最小の Picopass ルールを $O(\log_2 n)$ ステップで特定する `(auto-bisect-picopasses candidate-rules test-fn)`** を実装する。

---

## 2. 多角的視点レビュー / Multi-Agent Perspectives

本設計および仕様策定にあたり、専門エージェント群による多角的検討を実施した：

- **Project Manager (PM)**:
  - DSN-33-01 Phase 6 の第 2 タスク（T6.2）として、後続の T6.3（3-Stage セルフホスティング不動点検証 ＆ ベンチマーク測定）の品質ゲートを支える最重要診断ツールとして位置づける。
  - 既存の全テスト（143/143 Cユニットテスト、86/86 Verifier、39/39 All Passes、273/273 Nanopass）および 3-Stage セルフホスティングブートストラップ（35秒以内、Stage 2/3 バイナリ完全一致）を 100% 堅持する。
- **Systems Architect (SA)**:
  - 観測性と実行性能のゼロコスト原則を徹底。通常ビルド（トレース無効時）では発火記録のオーバーヘッドを $O(1)$ 分岐で完全にスキップし、本番コンパイル速度への悪影響を皆無とする。
  - ルール無効化・二分探索エンジンは `pass_manager.scm` の既存アーキテクチャ（`disable-pass!`）と概念的に対称な API 仕様として統一する。
- **Software Development / Programming Languages & Compilers (SWD / PLC)**:
  - `define-pass` / `fuse-rules` / `fuse-window-rules` のマクロ展開時において、各規則節にルール名メタデータを保持させ、展開後のディスパッチコード（`nanopass-compile-single-rule-cascade` および `nanopass-compile-window-rule-chain`）に `(picopass-enabled? 'rule-name)` ガードと `(record-picopass-firing! 'rule-name ...)` フックを埋め込む。
  - 二分探索エンジン `auto-bisect-picopasses` は純粋な Scheme 手続きとして実装し、AOT セルフホスト時でも外部依存ゼロで自律動作可能とする。
- **Information Security Specialist (SEC)**:
  - トレースログの無制限蓄積によるヒープ枯渇攻撃（CWE-400）および、二分探索例外時のグローバル無効化フラグ残留によるセキュリティパス・サニタイズパスの脱落（CWE-662, CWE-472）を脅威モデルとして分析し、防御策を策定。
- **Software Quality Assurance Specialist (QA)**:
  - 意図的に不正な変換を行う合成 Picopass（Synthetic Buggy Rule）を混在させたテストケースを設計し、`auto-bisect-picopasses` が $O(\log_2 n)$ の探索ステップで誤りなく単一のバグルールを特定できることを自動検証する。
- **Systems Auditor (AUD) & IT Service Manager (ITSM)**:
  - 障害発生時（CI テスト失敗や AOT コンパイルエラー）の再現ログにおいて、どの Picopass がノードを破壊したかを監査ログから 100% 追跡可能（Provenance Traceability）とする。

---

## 3. 脅威モデリングとセキュリティ要件 / Threat Modeling & Security Requirements

| 脅威 ID | 脅威分類 (STRIDE) | 脆弱性概要 (CWE) | 攻撃シナリオ / 障害リスク | 対策仕様 / 緩和策 |
| :--- | :--- | :--- | :--- | :--- |
| **THREAT-769-1** | **Denial of Service (DoS)** | **CWE-400**: Uncontrolled Resource Consumption | 大規模な S 式プログラムや深い再帰マクロのコンパイル時に、Picopass 発火ごとの AST ノードの全体コピーをログへ無制限に蓄積し、コンパイラのヒープメモリが枯渇（OOM）してクラッシュする。 | `*picopass-firing-log*` には原則としてルール名と発火カウンタ（`*picopass-firing-counts*`）のみを必須とし、AST ノード断片の記録は上限（最大 500 件）または深さ制限（`nanopass-truncate-expr` による深さ 8 制限）を適用。トレース無効時はログ蓄積を完全にバイパス（$O(1)$ 分岐でスキップ）する。 |
| **THREAT-769-2** | **State Confusion / Tampering** | **CWE-662**: Improper Synchronization / State Leakage | `auto-bisect-picopasses` の二分探索実行中、またはユニットテスト実行中にテスト関数 `test-fn` 内で予期せぬ例外が発生した際、`*disabled-picopasses*` が復元されずに無効化状態が残留し、後続のコンパイルで必要な最適化や脱糖が抜けて不正コードを生成する。 | `with-disabled-picopasses` および `auto-bisect-picopasses` において、`dynamic-wind` または例外保護（`with-exception-handler`）を用いて、正常終了・異常終了にかかわらず必ず初期の無効化リストへ復元（Rollback）する。 |
| **THREAT-769-3** | **Impairment of Security Mechanism** | **CWE-472**: Impairment of Security Mechanism | 外部スクリプトや CLI から `disable-picopass!` を呼び出し、境界チェック・型アサーション・未束縛変数検査等のセキュリティ不変条件を検証する必須 Picopass / Attopass（例: `atto-no-unlifted-lambda` 等）を意図的に無効化し、安全性を損なう。 | ルール記述子に `mandatory?`（必須保護フラグ）属性を導入。言語変換スキーマやセキュリティ不変条件の維持に必須のルールに対して `disable-picopass!` が呼び出された場合は警告または拒絶（エラー）する。 |
| **THREAT-769-4** | **Incorrect Computation / Flawed Logic** | **CWE-697**: Incorrect Comparison / Non-deterministic Bisect | 複数の Picopass ルール間に密結合な依存関係（先行ルール A の出力を後続ルール B が前提とする）が存在する場合、ナイーブな二分探索で片方のみを無効化すると偽陽性のクラッシュが発生し、真の原因ルールを見誤る。 | ルール依存関係 DAG（Issue #765 で導入した `reads` / `writes` メタデータ）を尊重し、依存関係を壊すような無効化を防止。また、候補ルールの分割順序をトポロジカル順序に沿って維持する。 |

---

## 4. トレーサビリティ / Traceability

- **関連設計書**:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
    - 第 7.2 節（来歴追跡（Provenance Tracking）と細粒度 AST Diff）
    - 第 7.3 節（ルール単位の自動二分探索デバッグ（Rule-level Auto-Bisect））
    - 第 8.4 節（既存機能の4階層フレームワークへの統廃合・再配置マトリクス）
    - 第 9.2 節 タスク **T6.2**（Provenance 来歴トレースと Rule-level Auto-Bisect 実装）
- **依存関係**:
  - 先行 Issue:
    - [Issue #767 (T5.3: LIR ピープホールの Picopass 化と依存 DAG)](closed/767-migrate-lir-peephole-to-picopass-and-dependency-dag.md) - クローズ済
    - [Issue #768 (T6.1: define-pipeline 用途別パイプライン編成)](closed/768-implement-define-pipeline-for-aot-repl-and-check-modes.md) - クローズ済
  - 後続 Issue:
    - [Issue #770 (T6.3: 3-Stage セルフホスティング不動点検証 ＆ 性能ベンチマーク)](770-verify-stage3-self-hosting-fixed-point-and-benchmark-pass-fusion.md)

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm):
  - `nanopass-extract-fused-clauses` および `nanopass-extract-fused-window-rules` において、展開された各ルール節にルール名シンボル（`rule-name`）を紐付け保持。
  - `nanopass-compile-single-rule-cascade` および `nanopass-compile-window-rule-chain` において、ルールごとの `(picopass-enabled? 'rule-name)` 有効判定コードと、発火時の `(record-picopass-firing! 'rule-name ir-var res-var)` フックコードを生成。
- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm):
  - 来歴追跡データ構造（`*picopass-provenance-enabled*`, `*picopass-firing-log*`, `*picopass-firing-counts*`）および操作 API（`record-picopass-firing!`, `reset-picopass-provenance!`, `get-picopass-firing-counts`）。
  - Picopass ルール無効化データ構造（`*disabled-picopasses*`）および判定述語（`picopass-enabled?`）。
  - `nanopass-display-ast-diff` の拡張：パス全体の AST Diff に加え、そのパス内で発火した Picopass ルール名と発火回数リストを整形出力。
- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm):
  - Picopass 有効・無効化 API（`disable-picopass!`, `enable-picopass!`, `reset-disabled-picopasses!`, `with-disabled-picopasses`）。
  - Delta Debugging 自動二分探索エンジン `(auto-bisect-picopasses candidate-rules test-fn)`。
  - パス実行時の来歴ログ自動リセットと `--trace-picopass` フラグ連携。
- [ ] [ulisp/tests/test_nanopass_tracer.scm](../../ulisp/tests/test_nanopass_tracer.scm):
  - Picopass 発火来歴追跡および拡張 AST Diff 出力のユニットテスト群を追加。
- [ ] [ulisp/tests/test_pass_manager.scm](../../ulisp/tests/test_pass_manager.scm):
  - `disable-picopass!` / `enable-picopass!` / `with-disabled-picopasses` の単体テスト。
  - 合成バグルールを用いた `auto-bisect-picopasses` の二分探索隔離テスト（Group 10）。

---

## 6. 技術設計詳細 / Technical Specifications

### 6.1 来歴追跡（Provenance Tracking）データ構造と API

`ulisp/compiler/nanopass_meta.scm` に以下の来歴追跡状態とユーティリティを定義する：

```scheme
;;; -----------------------------------------------------------------------
;;; Picopass Provenance Tracking & Firing History
;;; -----------------------------------------------------------------------

(define *picopass-provenance-enabled* (cons #f '()))
(define (picopass-provenance-enabled?) (car *picopass-provenance-enabled*))
(define (enable-picopass-provenance!) (set-car! *picopass-provenance-enabled* #t))
(define (disable-picopass-provenance!) (set-car! *picopass-provenance-enabled* #f))

;; Firing counts alist: ((rule-name . count) ...)
(define *picopass-firing-counts* (cons '() '()))

;; Firing log entries: list of (rule-name old-ir new-ir)
(define *picopass-firing-log* (cons '() '()))
(define *picopass-max-log-entries* 500)

(define (reset-picopass-provenance!)
  (set-car! *picopass-firing-counts* '())
  (set-car! *picopass-firing-log* '()))

(define (record-picopass-firing! rule-name old-ir new-ir)
  (when (car *picopass-provenance-enabled*)
    ;; 1. Update firing counter
    (let* ((counts (car *picopass-firing-counts*))
           (entry (assq rule-name counts)))
      (if entry
          (set-cdr! entry (+ (cdr entry) 1))
          (set-car! *picopass-firing-counts* (cons (cons rule-name 1) counts))))
    ;; 2. Bounded log append
    (let ((log (car *picopass-firing-log*)))
      (when (< (length log) *picopass-max-log-entries*)
        (set-car! *picopass-firing-log*
                  (cons (list rule-name
                              (nanopass-truncate-expr old-ir 6 10)
                              (nanopass-truncate-expr new-ir 6 10))
                        log))))))

(define (get-picopass-firing-counts)
  (car *picopass-firing-counts*))

(define (get-picopass-firing-log)
  (reverse (car *picopass-firing-log*)))
```

### 6.2 融合コード生成器への発火フック埋め込み

`nanopass.scm` において、`fuse-rules` および `fuse-window-rules` で各ルールが展開される際、節データにルール名シンボルを付加する：

1. **節構造の拡張**:
   - 既存の各ルール節: `(pat vars guard-expr body-expr)`
   - 拡張後のルール節: `(pat vars guard-expr body-expr rule-name)`
2. **`nanopass-compile-single-rule-cascade` でのコード生成**:
   - 各ルールの先頭で `(picopass-enabled? 'rule-name)` を検査。無効化されている場合はマッチングを行わず即座に `fallback-expr` へ遷移。
   - ルールがマッチし、変換後ノード `res-var` が得られた際、Provenance が有効であれば `(record-picopass-firing! 'rule-name ir-var res-var)` を呼び出す：

```scheme
;; 生成される展開コードの概念イメージ
(if (not (picopass-enabled? 'rule-desugar-letrec))
    fallback-expr
    (let ((__m_ (nanopass-match-clause '(letrec ((,x ,e) ...) ,b) ir vars 'Expr)))
      (if __m_
          (let ((res (begin
                       (record-picopass-firing! 'rule-desugar-letrec ir transformed-expr)
                       transformed-expr)))
            (if (or (eq? res ir) (equal? res ir))
                res
                (__redispatch_loop_ res (- __fuel_ 1))))
          fallback-expr)))
```

### 6.3 Picopass ルール単位の有効・無効化 API

`ulisp/compiler/pass_manager.scm` および `nanopass_meta.scm` に以下の無効化 API を提供する：

```scheme
;;; -----------------------------------------------------------------------
;;; Picopass Rule Disabling API
;;; -----------------------------------------------------------------------

(define *disabled-picopasses* (cons '() '()))
(define (disabled-picopasses) (car *disabled-picopasses*))

(define (picopass-enabled? rule-name)
  (not (memq rule-name (car *disabled-picopasses*))))

(define (disable-picopass! rule-name)
  (let ((desc (nanopass-lookup-rule rule-name)))
    (when (and desc (rule-mandatory? desc))
      (error "disable-picopass!: cannot disable mandatory rule" rule-name)))
  (if (not (memq rule-name (car *disabled-picopasses*)))
      (set-car! *disabled-picopasses* (cons rule-name (car *disabled-picopasses*)))))

(define (enable-picopass! rule-name)
  (set-car! *disabled-picopasses*
            (let loop ((rs (car *disabled-picopasses*)))
              (cond
                ((null? rs) '())
                ((eq? (car rs) rule-name) (loop (cdr rs)))
                (else (cons (car rs) (loop (cdr rs))))))))

(define (reset-disabled-picopasses!)
  (set-car! *disabled-picopasses* '()))

(define (with-disabled-picopasses rules thunk)
  (let ((saved (car *disabled-picopasses*)))
    (dynamic-wind
      (lambda ()
        (for-each disable-picopass! rules))
      thunk
      (lambda ()
        (set-car! *disabled-picopasses* saved)))))
```

### 6.4 Delta Debugging 自動二分探索エンジン (`auto-bisect-picopasses`)

不具合を引き起こす最小の Picopass ルールを自動特定するアルゴリズムを `ulisp/compiler/pass_manager.scm` に実装する：

```scheme
;;; -----------------------------------------------------------------------
;;; Delta Debugging Auto-Bisect Engine
;;; (auto-bisect-picopasses candidate-rules test-fn)
;;;
;;; test-fn: (lambda () -> boolean)
;;;   #t = PASS (Test succeeds / bug is absent)
;;;   #f = FAIL (Test fails / bug is present)
;;;
;;; Returns:
;;;   - A single rule symbol (e.g. 'rule-desugar-bad) if isolated
;;;   - A list of rule symbols if an interaction bug requires multiple rules
;;;   - #f if test-fn passes even with all rules enabled (no bug reproduced)
;;;   - 'cannot-isolate-all-disabled-still-fails if test-fn fails even with all rules disabled
;;; -----------------------------------------------------------------------

(define (auto-bisect-picopasses candidate-rules test-fn)
  (reset-disabled-picopasses!)
  ;; 1. Base check: does it fail with all rules enabled?
  (if (test-fn)
      #f  ; Bug not reproduced with all rules active
      ;; 2. Sanity check: does it pass with all candidate rules disabled?
      (let ((passes-when-all-disabled?
             (with-disabled-picopasses candidate-rules test-fn)))
        (if (not passes-when-all-disabled?)
            'cannot-isolate-all-disabled-still-fails
            ;; 3. Delta debugging binary search
            (let bisect ((rules candidate-rules))
              (cond
                ((null? rules) #f)
                ((= (length rules) 1)
                 (car rules)) ; Single isolated culprit rule!
                (else
                 (let* ((mid (quotient (length rules) 2))
                        (r1 (list-head rules mid))
                        (r2 (list-tail rules mid)))
                   ;; Disable r1 and test.
                   ;; If it still FAILS, the bug is inside r2 (r1 is not needed for the bug).
                   (let ((fails-without-r1?
                          (not (with-disabled-picopasses r1 test-fn))))
                     (if fails-without-r1?
                         (bisect r2)
                         ;; Otherwise, disable r2 and test.
                         (let ((fails-without-r2?
                                (not (with-disabled-picopasses r2 test-fn))))
                           (if fails-without-r2?
                               (bisect r1)
                               ;; Both subsets individually pass when disabled -> multiple rule interaction!
                               (list 'interaction r1 r2)))))))))))))
```

### 6.5 AST Diff トレーサ（`nanopass-display-ast-diff`）への統合表示

`nanopass-display-ast-diff` において、パス全体の S 式差分に続けて、そのパス内で発火した Picopass ルールと発火回数を ANSI カラーで一覧表示する：

```
--- [PASS: desugar-all] -----------------------------------------------------
- (letrec ((f (lambda (x) (+ x 1)))) (f 10))
+ ((lambda (f) (begin (set! f (lambda (x) (+ x 1))) (f 10))) #f)
  [Picopass Firings]:
    * rule-desugar-letrec: 1 hit(s)
    * rule-desugar-begin: 0 hit(s)
----------------------------------------------------------------------
```

---

## 7. 実装方針と段階的計画 / Implementation Plan

Target Branch: `feat/769-picopass-provenance-and-auto-bisect`

- [ ] **Phase 1: 来歴追跡データ構造と Picopass 有効/無効化 API の実装**
  - `ulisp/compiler/nanopass_meta.scm` に `*picopass-provenance-enabled*`, `*picopass-firing-counts*`, `*picopass-firing-log*`, `record-picopass-firing!`, `reset-picopass-provenance!`, `*disabled-picopasses*`, `picopass-enabled?` を定義。
  - `ulisp/compiler/pass_manager.scm` に `disable-picopass!`, `enable-picopass!`, `reset-disabled-picopasses!`, `with-disabled-picopasses` を実装・エクスポート。
- [ ] **Phase 2: コード生成器への発火記録と無効化ガードの埋め込み**
  - `ulisp/compiler/nanopass.scm`:
    - `nanopass-extract-fused-clauses` および `nanopass-extract-fused-window-rules` で各ルール節にルール名シンボルを付加。
    - `nanopass-compile-single-rule-cascade` および `nanopass-compile-window-rule-chain` で `(picopass-enabled? 'rule-name)` によるスキップ分岐と、発火時の `(record-picopass-firing! 'rule-name ir-var res-var)` フックをコード生成。
- [ ] **Phase 3: AST Diff トレーサの Provenance 拡張**
  - `nanopass-display-ast-diff`（`ulisp/compiler/nanopass_meta.scm`）において、発火回数リスト `(get-picopass-firing-counts)` を整形表示するセクションを追加。
  - パス実行開始時に `reset-picopass-provenance!` を呼び出し、パス境界ごとの発火内訳を独立集計。
- [ ] **Phase 4: Delta Debugging 自動二分探索エンジンの実装**
  - `ulisp/compiler/pass_manager.scm` に `(auto-bisect-picopasses candidate-rules test-fn)` を実装。
  - 単一ルール特定、複数ルール相互作用（`interaction`）、全無効化時継続失敗の各ケースを堅牢にハンドリング。
- [ ] **Phase 5: ユニットテスト群の拡充と検証**
  - `ulisp/tests/test_nanopass_tracer.scm`:
    - Provenance 有効化時の発火カウンタ計測、AST Diff 内への Picopass 名表示のテストを追加。
  - `ulisp/tests/test_pass_manager.scm`:
    - `disable-picopass!` / `enable-picopass!` による単一ルール無効化テスト。
    - 意図的に壊れた AST を出力するダミー Picopass を混入させ、`auto-bisect-picopasses` が $O(\log_2 n)$ ステップでそのルール名を 100% 正確に特定する二分探索テスト（Group 10）を追加。
- [ ] **Phase 6: 3-Stage セルフホスティングブートストラップ ＆ 品質ゲート検証**
  - `make test`（C言語、Verifier、All Passes、Nanopass 全スイート PASS）。
  - `bash ulisp/bootstrap.sh --modular` を実行し、Stage 2 と Stage 3 の生成バイナリが完全一致（Fixed-Point）することを確認。
  - `make py_compile && make static_analysis` による品質ゲート全項目 PASS を確認。

---

## 8. 完了条件 / Success Criteria (DoD)

1. **Picopass 発火来歴追跡（Provenance Tracking）の完全動作**:
   - `enable-picopass-provenance!` 有効時、`fuse-rules` / `fuse-window-rules` 内で発火したルール名と回数が `(get-picopass-firing-counts)` に正確に記録されること。
   - `nanopass-display-ast-diff` 実行時に、差分情報とともに発火 Picopass ルール名と発火回数が表示されること。
   - Provenance 無効時（デフォルト）に発火記録のオーバーヘッドが最小（$O(1)$ 分岐でスキップ）であること。
2. **Picopass 単位の動的有効・無効化の動作**:
   - `disable-picopass!` で指定した Picopass ルールのみがピンポイントで無効化され、他の融合ルールに影響を与えないこと。
   - `with-disabled-picopasses` の実行終了後、正常・例外発生問わず無効化状態が元の状態に復元されること。
3. **Auto-Bisect 自動二分探索の特定精度**:
   - 複数の Picopass ルール候補群に 1 つのバグルールが含まれるテストにおいて、`auto-bisect-picopasses` が二分探索によりそのルール名を正確に特定して返却すること。
4. **テストスイート ＆ セルフホスティング不動点保証**:
   - `ulisp/tests/test_nanopass_tracer.scm` および `ulisp/tests/test_pass_manager.scm` の全テストが PASS すること。
   - `ulisp/bootstrap.sh --modular` による 3-Stage セルフホスティングブートストラップが 35 秒以内に完了し、Stage 2 と Stage 3 の生成コードが 1 バイトの差異もなく完全一致すること。
5. **リポジトリ品質ゲート 100% 適合**:
   - `make py_compile` および `make static_analysis` が 0 エラーで合格すること。
   - すべての Markdown ファイル内のリンクが相対パス規約に厳格に従っていること。
