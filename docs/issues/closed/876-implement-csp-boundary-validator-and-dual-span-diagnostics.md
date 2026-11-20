---
ID: 876
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] CSP 越境バリデータと Dual Span 診断レポーターの実装 (ID: 876)

## 1. 概要 / Summary
DSN-33-03 §4.2 および §4.3 に基づき、Control Plane の可変セル（`set!` / Box）やホスト継続（`call/cc`）、不透明ホストクロージャが不正に Data Plane（残余コード）へ持ち込まれるのを厳格に遮断する CSP（Cross-Stage Persistence）越境バリデータを実装する。
境界違反を検知した際には、DSN-33-02 §3.4 および Issue #833（Diagnostic Reporter）に準拠した構造化 S式 `(compiler-diagnostic ...)` を構築し、二重ソースマップ（`guest-span` と `host-span`）を含む高精度な診断レポートを出力する。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §4.2, §4.3 (Cross-Stage Persistence & Dual-Span Diagnostic Reporter)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#43-コンパイル時診断-s式仕様dual-span-伝播-reporter-833-準拠)
  - [DSN-33-02 §3.4 (Integrated Pretty Diagnostic Reporter)](docs/designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md#34-統合-pretty-diagnostic-reporter-issue-833)
- 関連 Issue:
  - #871 (PSDS & Dual Source Span Provenance)
  - #872 (eval-in-stage コアループ)
  - #874 (4値束縛時間束 BTA)
  - #875 (動的分岐配下の純粋性解析と投機的例外自動降格)
  - #877 (特殊化メモ化 Widening エンジン)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm) - CSP 越境バリデータ述語、`compiler-diagnostic` S式ジェネレータ、Dual-Span 抽出・正規化ロジック
- [x] [ulisp/tests/test_csp_boundary_validator.scm](ulisp/tests/test_csp_boundary_validator.scm) - CSP 越境遮断と Dual-Span 診断 S式の包括的単体テスト
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_csp_boundary_validator` ターゲットの追加
- [x] [docs/issues/README.md](docs/issues/README.md) - 台帳ステータス更新

---

## 4. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/876-implement-csp-boundary-validator-and-dual-span-diagnostics`

### 4.1 CSP 越境バリデータ（Boundary Validator）
1. **オブジェクト分類と昇格検証**:
   - `(csp-valid-lift-target? val)`:
     - 昇格可能（Valid）:
       - 数値、真偽値、文字、文字列、空リスト `()`
       - シンボル
       - イミュータブルなペア・リスト（再帰的に全要素が昇格可能）
       - 不変ベクタ（全要素が昇格可能）
       - PSDS `<stage-val>`（内部の static 値または dynamic 式が妥当）
     - 昇格禁止（Illegal Cross-Stage Persistence Violations）:
       - 可変セル / Box オブジェクト (`box?` / `mutable-cell`) $\implies$ `CSP-001-ILLEGAL-MUTABLE-LIFT`
       - ホスト継続 (`continuation?`) $\implies$ `CSP-002-ILLEGAL-CONTINUATION-LIFT`
       - 不透明ホストクロージャ / プロシージャ（残余化直列化不可能な関数） $\implies$ `CSP-003-OPAQUE-PROCEDURE-LIFT`
2. **`later-dict-lift-val` への統合**:
   - `lift` 対象が静的値であっても、可変セルや継続、不透明クロージャである場合は、即座に CSP エラーシグナルを発行。

### 4.2 DSN-33-03 §4.3 準拠 `compiler-diagnostic` S式
1. **診断 S式フォーマット**:
   ```scheme
   (compiler-diagnostic
     (version "1.0")
     (severity error)
     (phase "bta-csp-guard")
     (rule "CSP-001-ILLEGAL-MUTABLE-LIFT")
     (message "Prohibited cross-stage lift of mutable object to residual code.")
     (details
       ((variable . <var-or-#f>)
        (source-stage . 1)
        (target-stage . 0)
        (binding-time . dynamic)
        (inferred-type . mutable-cell)))
     (provenance
       ((guest-span
          ((file . "...")
           (line . ...)
           (column . ...)))
        (host-span
          ((file . "...")
           (line . ...)
           (column . ...)))))
     (remediation "..."))
   ```
2. **Dual Span の正規化**:
   - `span-stack` から `guest-span` と `host-span` を抽出。
   - `source-span` レコード、`source-loc`、`(span file line col)` リストのいずれであっても `((file . "...") (line . N) (column . M))` 形式へ正規化。
   - スパン情報が存在しない場合はフォールバック値（例: `((file . "unknown") (line . 0) (column . 0))`）を提供。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 可変セル（Box）の Data Plane への昇格が `CSP-001-ILLEGAL-MUTABLE-LIFT` で遮断されること。
- [x] ホスト継続（`call/cc`）の昇格が `CSP-002-ILLEGAL-CONTINUATION-LIFT` で遮断されること。
- [x] 不透明ホストプロシージャの昇格が `CSP-003-OPAQUE-PROCEDURE-LIFT` で遮断されること。
- [x] 違反時に返却される構造化 S式が DSN-33-03 §4.3 準拠の `compiler-diagnostic` であること。
- [x] `provenance` に `guest-span` と `host-span` の二重位置情報が正しく展開されること。
- [x] `make -C ulisp test_csp_boundary_validator` が 0件エラー PASS すること。
- [x] 全既存テスト（`test_speculative_trap_demotion`, `test_bta_lattice`, `test_single_source_oracle`, `test_eval_in_stage`, `test_stage_dict`, `test_psds_provenance`, `test_eval_in_language`）が PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。
