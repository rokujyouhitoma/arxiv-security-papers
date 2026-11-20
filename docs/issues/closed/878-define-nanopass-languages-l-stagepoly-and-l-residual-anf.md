---
ID: 878
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] Nanopass 中間言語 L-StagePoly および L-Residual-ANF の定義 (ID: 878)

## 1. 概要 / Summary
DSN-33-03 §6.1 および §6.2 に基づき、メタステージ構文（`stage-now`, `stage-later`, `stage-lift`, `stage-quasiquote`）を第一級構文として含む中間言語 `L-StagePoly` と、ステージ多相部分評価および BTA 簡約を経てメタ構文を文法規則から完全除外（`-`）した純粋 A-Normal Form 中間言語 `L-Residual-ANF` を Nanopass フレームワーク上に定義する。
これにより、コンパイラパイプライン内でのステージ消去（Tower Collapse）が文法定義レベルで形式的に検証可能となる。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §6.1, §6.2 (Nanopass Languages L-StagePoly & L-Residual-ANF)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#6-nanopass-差分言語extendsによる階層消去証明)
  - [DSN-33-01 §3.1 (Nanopass Intermediate Languages Specification)](docs/designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
- 関連 Issue:
  - #877 (特殊化メモ化エンジンと Widening)
  - #879 (ステージ多相部分評価 Nanopass stage-poly-lower)
  - #880 (Pass Manager への Nanopass 文法完全消去アサーションの組み込み)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/frontend/frontend_lang.scm](ulisp/frontend/frontend_lang.scm) - `L-StagePoly` および `L-Residual-ANF` 言語定義の配備
- [x] [ulisp/tests/test_nanopass_stagepoly_lang.scm](ulisp/tests/test_nanopass_stagepoly_lang.scm) - 両言語の文法定義・パース・extends 差分検証単体テスト
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_nanopass_stagepoly_lang` ターゲット追加
- [x] [docs/issues/README.md](docs/issues/README.md) - 台帳ステータス更新

---

## 4. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/878-define-nanopass-languages-l-stagepoly-and-l-residual-anf`

### 4.1 `L-StagePoly` 言語仕様 (DSN-33-03 §6.1)
```scheme
(define-language L-StagePoly
  (terminals
    (symbol (x var lbl))
    (constant (c))
    (primitive (prim)))
  (Expr (e)
    x
    c
    (if e0 e1 e2)
    (let ((x e)) body)
    (lambda (x ...) body)
    (prim e ...)
    (call e0 e1 ...)
    ;; メタステージ構文 (Meta-Stage Forms)
    (stage-now e)
    (stage-later e)
    (stage-lift e)
    (stage-quasiquote e)))
```

### 4.2 `L-Residual-ANF` 言語仕様 (DSN-33-03 §6.2)
```scheme
(define-language L-Residual-ANF
  (extends L-StagePoly)
  (Expr (e)
    ;; メタ構文の完全抹消 (Subtractive Elimination)
    (- (stage-now e)
       (stage-later e)
       (stage-lift e)
       (stage-quasiquote e)
       (call e0 e1 ...)
       (let ((x e)) body))
    ;; 純粋 A-Normal Form の導入 (Additive ANF Production)
    (+ (let-anf ((x (prim e-atom ...))) body)
       (let-call ((x (call-target e-atom ...))) body)
       (atom-value e-atom)))
  (Atom (e-atom)
    x
    c))
```

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `L-StagePoly` が `nanopass-lookup-language` にて正しく登録・取得できること。
- [x] `L-StagePoly` が `stage-now`, `stage-later`, `stage-lift`, `stage-quasiquote` の構文節を認識すること。
- [x] `L-Residual-ANF` が `(extends L-StagePoly)` で定義され、メタ構文4種および多段 `call`/`let` が文法規則から完全除外されていること。
- [x] `L-Residual-ANF` が `let-anf`, `let-call`, `atom-value` の ANF 構文節を受け入れること。
- [x] `make -C ulisp test_nanopass_stagepoly_lang` が 0件エラー PASS すること。
- [x] 全既存テスト（`test_specialization_widening` 含む）が PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。
