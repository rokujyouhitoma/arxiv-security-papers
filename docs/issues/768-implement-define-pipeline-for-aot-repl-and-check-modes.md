---
ID: 768
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] define-pipeline による用途別パイプライン (AOT / REPL / Check-only) の宣言的編成と動的切り替え (DSN-33-01 T6.1) (ID: 768)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 2.1 節〜第 2.3 節（最上位：Pipeline 層）、第 5.1 節、およびタスク **T6.1** に基づき、`ulisp/compiler/pass_manager.scm` に最上位の配線・実行計画 DSL である **`define-pipeline`** を実装する。

これまで ULisp コンパイラのパス管理は、単一のグローバルレジストリ（`*pass-registry*`）に全パスが直列に並び、最適化レベル（`-O0` / `-O1` / `-O2`）と無効化リスト（`disabled-list`）のフィルタリングのみで実行パスを決定する固定的な設計であった。この構造では、以下の課題が存在していた：

1. **用途ごとの最適パイプライン編成が不能**:
   - AOT（ネイティブ ELF / AArch64 / C コード生成）では全最適化パスと LIR / ピープホールが必要だが、対話型 REPL / `eval` では重い最適化（CP0 / LVN / Contify / Alias Escape / LIR ピープホール等）をスキップし、Frontend $\to$ 最小コード生成または AST 直接評価へ即座に繋ぐ超低レイテンシ性が求められる。
   - 言語サーバ（LSP）や静的検証（`--check`）では、Frontend $\to$ スコープ解決 $\to$ アリティ・型推論・所有権検証までを行い、LIR / バックエンド生成を一切行わずに AST の整合性と診断情報を瞬時に返却することが望ましい。
2. **言語推移整合性（Language Continuity）の静的検証欠如**:
   - パス $P_i$ の出力言語 $L_{\text{out}}(P_i)$ と次段パス $P_{i+1}$ の入力言語 $L_{\text{in}}(P_{i+1})$ が一致している保証がなく、パスの並べ替えや無効化時に実行時クラッシュ（未束縛パターンエラー）を引き起こす危険性があった。

本 Issue では、共通の Pass / Nanopass 部品群から用途に応じた名前付きパイプライン（`aot-native-pipeline`, `repl-fast-pipeline`, `static-check-pipeline`）を宣言的に定義・登録・検証・切り替え可能とする基盤を構築する。

---

## 2. 多角的視点レビュー / Multi-Agent Perspectives

本設計および仕様策定にあたり、専門エージェント群による多角的検討を実施した：

- **Project Manager (PM)**:
  - DSN-33-01 Phase 6 の起点タスク（T6.1）としてスケジュール管理。
  - 既存の `make test`（143/143 C言語ユニットテスト、40/40 + 46/46 verifier、39/39 all passes、242/242 nanopass）および `bootstrap.sh --modular` 35秒不動点検証を破壊しない後方互換性を厳格に要求。
- **Systems Architect (SA)**:
  - 4階層アーキテクチャ（Pipeline $\to$ Pass $\to$ Nanopass $\to$ Picopass）の最上位責務を明確化。
  - Pipeline 自身は変換処理を持たず、Pass の順序決定・依存関係検証・スキーマ境界検証・時間/メモリ計測・IR ダンプのオーケストレーションに専念する「三権分立」を維持。
- **Software Development / Programming Languages & Compilers (SWD / PLC)**:
  - `define-pipeline` DSL を Scheme マクロおよび `015_dsl_expander.scm` の両方で展開可能とし、ホスト環境（Chez / Gauche / TinyScheme / 既存 ULisp）とセルフホスティングコンパイラの両環境で無条件動作することを保証。
  - パイプライン記述子（`pipeline-descriptor`）を第一級オブジェクトとし、`register-pipeline!`, `lookup-pipeline`, `select-pipeline!`, `run-named-pipeline` を提供。
- **Information Security Specialist (SEC)**:
  - 動的パイプライン定義・切り替えにおける「パイプライン改ざん（Pipeline Tampering）」「不正なパススキップによる不変条件バイパス」「未初期化パスレジストリによる任意の関数実行」を脅威モデルとして分析し、検証ガードを設計。
- **Software Quality Assurance Specialist (QA)**:
  - `test_pass_manager.scm` を拡張し、複数パイプラインの独立性、言語スキーマ連続性不一致の即座検出（Rejection）、動的切り替え前後の副作用ゼロ（純粋性）を単体テストで網羅。
- **Systems Auditor (AUD) & IT Service Manager (ITSM)**:
  - `--time-passes` および `--trace` のパイプライン単位での追跡可能性（Observability）を担保。各パイプラインの実行ログに来歴とプロファイルを出力可能とする。

---

## 3. 脅威モデリングとセキュリティ要件 / Threat Modeling & Security Requirements

| 脅威 ID | 脅威分類 (STRIDE) | 脆弱性概要 (CWE) | 攻撃シナリオ / 障害リスク | 対策仕様 / 緩和策 |
| :--- | :--- | :--- | :--- | :--- |
| **THREAT-768-1** | **Tampering / Elevation of Privilege** | **CWE-472**: Impairment of Security Mechanism | 悪意あるプラグインやコードがパイプライン定義を改ざんし、型検査（Pass 040）やサニタイズパスをスキップして未検証 AST を LIR 生成へ渡す。 | パイプライン登録時に `validate-pipeline-prerequisites` を必須化。セキュリティ検証パスをバイパスする不正な順序定義をコンパイル時／登録時に即座に拒絶（`error` 送出）する。 |
| **THREAT-768-2** | **Tampering / Denial of Service** | **CWE-843**: Access of Resource Using Incompatible Type / **CWE-704**: Incorrect Type Conversion | パス $P_i$ の出力言語（例: `L_core`）と $P_{i+1}$ の入力言語（例: `L_lifted`）が不整合なパイプラインを定義し、パターンマッチ失敗によるセグメンテーション違反や無限ループを誘発する。 | パイプライン定義時に **言語連続性検証（`validate-pipeline-continuity`）** を実行。$L_{\text{out}}(P_i) = L_{\text{in}}(P_{i+1})$ が成立しない場合はパイプライン登録を拒絶する。 |
| **THREAT-768-3** | **Information Disclosure / State Confusion** | **CWE-662**: Improper Synchronization / State Leakage | 異なるパイプライン（例: `repl-fast-pipeline` から `aot-native-pipeline`）へ動的に切り替えた際、前のパスのキャッシュ（`femto-cache`, `nanopass-term-memo`）やグローバル状態が残留し、誤った中間表現をコンパイルしてしまう。 | `run-named-pipeline` の開始時に必ずキャッシュリセット（`femto-cache-reset!`, `nanopass-term-memo-reset!`, `reset-nanopass-verification-cache!`）を一括実行し、実行環境を隔離（Clean Slate）する。 |
| **THREAT-768-4** | **Repudiation** | **CWE-778**: Insufficient Logging | どのパイプラインでコンパイルされたバイナリ／AST か特定できず、障害時の原因究明が困難となる。 | `*current-pipeline-name*` を記録し、`--time-passes` プロファイル出力および IR ダンプヘッダーにアクティブなパイプライン名を明記する。 |

---

## 4. トレーサビリティ / Traceability

- **関連設計書**:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
    - 第 2.1 節〜第 2.3 節（最上位：Pipeline 層の責務と境界定義）
    - 第 5.1 節（メタレベル：パス・ルール依存関係 DAG と自動スケジューリング）
    - 第 9.2 節 タスク **T6.1**（`define-pipeline` による用途別パイプライン分離）
- **依存関係**:
  - 先行 Issue:
    - [Issue #765 (T5.1: ルール依存 DAG 自動構築)](765-implement-rule-dependency-dag-and-femtopass-cache-invalidation.md) - クローズ済
    - [Issue #766 (T5.2: Hash-Consing Term DAG と $O(1)$ メモ化)](766-implement-hash-consing-term-dag-and-memoized-catamorphism.md) - クローズ済
    - [Issue #767 (T5.3: LIR ピープホールの Picopass 化と依存 DAG)](767-migrate-lir-peephole-to-picopass-and-dependency-dag.md) - クローズ済
  - 後続 Issue:
    - [Issue #769 (T6.2: Provenance 来歴追跡と Auto-Bisect)](769-implement-picopass-provenance-tracing-and-auto-bisect.md)
    - [Issue #770 (T6.3: 3-Stage セルフホスティング不動点検証 ＆ 性能ベンチマーク)](770-verify-stage3-self-hosting-fixed-point-and-benchmark-pass-fusion.md)

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm): パイプライン記述子、レジストリ、言語連続性検証エンジン、3大標準プロファイル定義、実行エンジン。
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm): `nanopass-expand-define-pipeline` マクロ展開器およびホストマクロ `define-pipeline` の定義。
- [ ] [ulisp/frontend/015_dsl_expander.scm](../../ulisp/frontend/015_dsl_expander.scm): `define-pipeline` DSL 構文を Pass 015 で早期展開対象に追加。
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm): CLI オプション（`--mode=aot`, `--mode=repl`, `--mode=check` 等）に応じたパイプライン選択の連動。
- [ ] [ulisp/tests/test_pass_manager.scm](../../ulisp/tests/test_pass_manager.scm): パイプライン登録・連続性検証・プロファイル別実行の網羅的ユニットテスト（Group 9）。

---

## 6. 技術設計詳細 / Technical Specifications

### 6.1 `define-pipeline` DSL 構文仕様

コンパイラ開発者および外部拡張モジュールが、以下のようにパイプラインを宣言的に定義できる DSL を策定する：

```scheme
(define-pipeline aot-native-pipeline
  (doc "Full AOT compilation pipeline with complete optimization and LIR generation")
  (target-ir lir)
  (passes
    pass-010-library
    pass-015-dsl-expander
    pass-020-macro-expander
    pass-025-top-level
    pass-030-desugar
    pass-035-scope-resolve
    pass-040-analysis
    pass-050-cp0
    pass-060-lvn
    pass-070-anf
    pass-080-annotator
    pass-090-rtyper
    pass-100-contify
    pass-110-closure-convert
    pass-120-alias-escape
    pass-130-lir
    pass-128-lir-branch-fusion
    pass-133-lir-peephole))

(define-pipeline repl-fast-pipeline
  (doc "Ultra-low-latency REPL evaluation pipeline skipping heavy middle-end optimizations")
  (target-ir lir)
  (passes
    pass-010-library
    pass-015-dsl-expander
    pass-020-macro-expander
    pass-025-top-level
    pass-030-desugar
    pass-035-scope-resolve
    pass-070-anf
    pass-110-closure-convert
    pass-130-lir))

(define-pipeline static-check-pipeline
  (doc "Static verification pipeline for diagnostics and LSP without code emission")
  (target-ir ast)
  (passes
    pass-010-library
    pass-015-dsl-expander
    pass-020-macro-expander
    pass-025-top-level
    pass-030-desugar
    pass-035-scope-resolve
    pass-040-analysis))
```

### 6.2 パイプライン記述子とレジストリ API

`ulisp/compiler/pass_manager.scm` に以下のデータ構造および操作 API を導入する：

```scheme
;; 1. Pipeline Descriptor Tuple
;; (list 'pipeline-descriptor name doc passes target-ir options)
(define (make-pipeline-descriptor name doc passes target-ir options)
  (list 'pipeline-descriptor name doc passes target-ir options))

(define (pipeline-descriptor? obj)
  (and (pair? obj) (eq? (car obj) 'pipeline-descriptor)))

(define (pipeline-desc-name p) (cadr p))
(define (pipeline-desc-doc p) (caddr p))
(define (pipeline-desc-passes p) (cadddr p))
(define (pipeline-desc-target-ir p) (car (cddddr p)))
(define (pipeline-desc-options p) (cadr (cddddr p)))

;; 2. Named Pipeline Registry
(define *pipeline-registry* (cons '() '()))

(define (pipeline-registry) (car *pipeline-registry*))
(define (reset-pipeline-registry!) (set-car! *pipeline-registry* '()))

(define (register-pipeline! desc)
  (let* ((name (pipeline-desc-name desc))
         (current (car *pipeline-registry*))
         (filtered (let loop ((ps current))
                     (cond
                       ((null? ps) '())
                       ((eq? (pipeline-desc-name (car ps)) name) (loop (cdr ps)))
                       (else (cons (car ps) (loop (cdr ps))))))))
    ;; 登録時に整合性検証を実施
    (validate-pipeline-prerequisites-by-ids (pipeline-desc-passes desc))
    (validate-pipeline-continuity-by-ids (pipeline-desc-passes desc))
    (set-car! *pipeline-registry* (append filtered (list desc)))
    name))

(define (lookup-pipeline name)
  (let loop ((ps (car *pipeline-registry*)))
    (cond
      ((null? ps) (error "lookup-pipeline: unknown pipeline" name))
      ((eq? (pipeline-desc-name (car ps)) name) (car ps))
      (else (loop (cdr ps))))))

(define (pipeline-registered? name)
  (let loop ((ps (car *pipeline-registry*)))
    (cond
      ((null? ps) #f)
      ((eq? (pipeline-desc-name (car ps)) name) #t)
      (else (loop (cdr ps))))))
```

### 6.3 言語推移整合性検証（Language Continuity Validation）

隣接するパス $P_i$ と $P_{i+1}$ において、$L_{\text{out}}(P_i)$ と $L_{\text{in}}(P_{i+1})$ が一致しているか、または上位言語の正当な拡張（サブタイプ）であるかを検査する：

```scheme
(define (validate-pipeline-continuity-by-ids pass-ids)
  (let loop ((ids pass-ids) (prev-desc #f))
    (if (null? ids)
        #t
        (let* ((curr-id (car ids))
               (curr-desc (lookup-pass curr-id)))
          (if prev-desc
              (let ((out-lang (pass-out-lang prev-desc))
                    (in-lang (pass-in-lang curr-desc)))
                ;; 言語スキーマが一致しているか、または継承・許容関係にあるかをチェック
                (if (not (nanopass-language-compatible? out-lang in-lang))
                    (error "validate-pipeline-continuity: language schema mismatch between passes"
                           (list 'from (pass-id prev-desc) 'out-lang out-lang
                                 'to curr-id 'in-lang in-lang)))))
          (loop (cdr ids) curr-desc)))))
```

### 6.4 パイプライン動的選択と実行

```scheme
(define *current-pipeline-name* (cons 'aot-native-pipeline '()))
(define (current-pipeline-name) (car *current-pipeline-name*))
(define (select-pipeline! name)
  (if (not (pipeline-registered? name))
      (error "select-pipeline!: pipeline not registered" name))
  (set-car! *current-pipeline-name* name)
  name)

(define (run-named-pipeline name forms verify-mode trace-mode)
  (let* ((desc (lookup-pipeline name))
         (pass-ids (pipeline-desc-passes desc))
         (passes (map lookup-pass pass-ids)))
    (reset-nanopass-verification-cache!)
    (femto-cache-reset!)
    (nanopass-term-memo-reset!)
    (nanopass-hash-cons-reset!)
    (if verify-mode
        (begin
          (enable-verifier!)
          (if (eq? verify-mode 'strict)
              (set-verifier-strict! #t))))
    (reset-pass-timings!)
    (let loop ((ps passes) (current-ast forms))
      (if (null? ps)
          current-ast
          (let ((next-ast (run-single-pass (car ps) current-ast verify-mode trace-mode)))
            (loop (cdr ps) next-ast))))))
```

### 6.5 既存 `run-pass-pipeline` の後方互換性保証

既存の `(run-pass-pipeline forms verify-mode trace-mode)` は、内部でアクティブなパイプライン（デフォルト `aot-native-pipeline`）または `-O` レベル指定に応じたパイプラインへ透過的に委譲し、既存のすべての呼び出し元（`driver.scm` や各テスト）が一切修正なしで動作し続けることを保証する。

---

## 7. 実装計画 / Step-by-Step Implementation Plan

Target Branch: `feat/768-implement-define-pipeline`

- [ ] **Phase 1: Pipeline Descriptor と Named Registry の基盤実装** (`ulisp/compiler/pass_manager.scm`)
  - `make-pipeline-descriptor`, `pipeline-descriptor?`, および各アクセサを定義。
  - `*pipeline-registry*`, `register-pipeline!`, `lookup-pipeline`, `pipeline-registered?`, `select-pipeline!` を実装。
- [ ] **Phase 2: 言語整合性検証エンジンの実装** (`ulisp/compiler/pass_manager.scm`)
  - `validate-pipeline-continuity-by-ids` を実装。
  - `nanopass-language-compatible?` ヘルパーを連携し、不整合なパス順序の登録を厳格に拒絶。
- [ ] **Phase 3: `define-pipeline` DSL Expander 実装** (`ulisp/compiler/nanopass.scm`, `ulisp/frontend/015_dsl_expander.scm`)
  - `nanopass-expand-define-pipeline` を実装し、マクロおよび Pass 015 手続き型展開器の両方から呼び出し可能にする。
  - ホスト Scheme 用の `(define-macro (define-pipeline . args) ...)` を追加。
- [ ] **Phase 4: 3大標準パイプラインプロファイルの組み込み** (`ulisp/compiler/pass_manager.scm`)
  - `init-default-pass-registry!` 内で `aot-native-pipeline`, `repl-fast-pipeline`, `static-check-pipeline` をデフォルト登録。
  - `run-named-pipeline` および `select-pipeline!` と `run-pass-pipeline` の統合。
- [ ] **Phase 5: ユニットテスト拡張と検証** (`ulisp/tests/test_pass_manager.scm`)
  - Group 9 として `define-pipeline` DSL テスト、プロファイル別動作確認、言語スキーマ不整合の拒絶テストを追加。
  - `make -C ulisp test_c`, `test_verifier`, `test_all_passes`, `test_nanopass`, および `bootstrap.sh --modular` の全件 PASS を確認。

---

## 8. 完了条件 / Definition of Done (DoD)

- [ ] **1. `define-pipeline` DSL 完全動作**:
  - `(define-pipeline ...)` 記法により名前付きパイプラインを定義・登録できること。
  - `015_dsl_expander.scm` による事前展開が正常に行われ、セルフホスティングコンパイラでも同一に展開されること。
- [ ] **2. 言語スキーマ整合性検証**:
  - $L_{\text{out}}(P_i) \neq L_{\text{in}}(P_{i+1})$ となる不正なパイプライン定義が登録時にエラーとして即座に拒絶されること。
- [ ] **3. 3大プロファイルの独立実行**:
  - `aot-native-pipeline`: フル最適化を経て正しい `%lir-program` を出力すること。
  - `repl-fast-pipeline`: 重い最適化をスキップしつつ、正しく `%lir-program` を出力すること。
  - `static-check-pipeline`: LIR変換を行わず、Pass 040 の静的検査済み AST を出力すること。
- [ ] **4. 既存テストおよび不動点の 100% PASS**:
  - `ulisp/tests/test_pass_manager.scm` に新規テスト（Group 9）が追加され、全件 PASS すること。
  - 既存の `make -C ulisp test_all_passes`, `test_verifier`, `test_nanopass`, `test_c` がすべて PASS すること。
  - `make py_compile` および `make static_analysis` がエラー 0 件であること。
  - 相対パス規律（絶対パス 0 件）を遵守していること。
