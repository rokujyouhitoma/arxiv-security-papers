---
ID: 879
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] ステージ多相部分評価 Nanopass (stage-poly-lower) の実装 (ID: 879)

## 1. 概要 / Summary
DSN-33-03 §2.1, §3.3, §6.2 に基づき、中間言語 `L-StagePoly` から `L-Residual-ANF` へのステージ多相部分評価 Nanopass `stage-poly-lower` を実装する。
`eval-in-stage`（Later 辞書）と 4値 BTA、特殊化メモ化エンジン、CSP 越境バリデータを一気通貫でパイプライン結合し、静的項（Now）およびメタ構文（`stage-now`, `stage-later`, `stage-lift`, `stage-quasiquote`）を完全に消去・畳み込み、純粋な残余 ANF 構造（`L-Residual-ANF`）へと平坦化（Tower Collapse）する。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §2.1, §3.3, §6.2 (Stage-Polymorphic Lowering & Residual ANF Generation)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#62-l-residual-anf-言語定義メタ構文の完全除外--)
  - [DSN-33-01 §3.2 (Nanopass Pass Pipeline)](docs/designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
- 関連 Issue:
  - #872 (eval-in-stage コアループ)
  - #874 (4値束縛時間束 BTA)
  - #875 (動的分岐配下の純粋性解析と投機的例外自動降格)
  - #876 (CSP 越境バリデータと Dual Span 診断レポーター)
  - #877 (特殊化メモ化エンジンと Widening)
  - #878 (Nanopass 中間言語 L-StagePoly および L-Residual-ANF)
  - #880 (Pass Manager への Nanopass 文法完全消去アサーションの組み込み)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm) - `stage-poly-lower` コア変換プロシージャおよび ANF 正規化エミッタの実装
- [x] [ulisp/compiler/pass_manager.scm](ulisp/compiler/pass_manager.scm) - Pass 定義・登録およびパイプライン統合
- [x] [ulisp/tests/test_stage_poly_lower.scm](ulisp/tests/test_stage_poly_lower.scm) - メタ構文完全消去・定数畳み込み・ANF 正規化の単体テスト
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_stage_poly_lower` ターゲット追加
- [x] [docs/issues/README.md](docs/issues/README.md) - 台帳ステータス更新

---

## 4. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/879-implement-stage-poly-lower-nanopass-partial-evaluator`

### 4.1 部分評価 Lowering コア `(stage-poly-lower expr env)`
1. **メタステージ構文の解釈と消去**:
   - `(stage-now e)`: Now 辞書で即時評価し、結果を静的リテラル（`atom-value` / quote）として残余化。
   - `(stage-later e)`: Later 辞書で残余コード生成。
   - `(stage-lift e)`: 静的式 `e` を評価した値を `later-dict-lift-val` 経由で残余リテラルへ昇格。
   - `(stage-quasiquote e)`: テンプレート式を展開し、埋め込まれた `(stage-now ...)` や `(stage-lift ...)` を置換。
2. **`L-Residual-ANF` 構文木への整流化**:
   - 残余化された式を走査し、`let-anf`（プリミティブ演算バインディング）、`let-call`（動的関数呼び出しバインディング）、`atom-value`（アトム参照）の規約に適合させる。
   - 刈り取られた死滅分岐（Dead Branch）は出力 AST に一切現れない。

### 4.2 停止性および例外安全性の保証
- 内部で `make-spec-memo-table` を管理し、再帰関数の多重特殊化上限（8）および深度（4）を超過した場合は Widening 降格を適用。
- 動的条件分岐配下の例外・副作用は Speculative Trap Prevention により自動的に残余コードへ降格。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `stage-now` 式がコンパイル時に完全に計算され、結果の定数のみが残余コードに出力されること。
- [x] `stage-later` 式内の動的計算が正しく残余化されること。
- [x] `stage-lift` による静的値の昇格が正常に行われ、可変セル等の不正昇格は遮断されること。
- [x] 出力された AST から `stage-now`, `stage-later`, `stage-lift`, `stage-quasiquote` の全メタ構文が 100% 消去されていること。
- [x] `make -C ulisp test_stage_poly_lower` が 0件エラー PASS すること。
- [x] 全既存テスト（`test_nanopass_stagepoly_lang` 含む）が PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。
