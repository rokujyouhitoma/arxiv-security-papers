---
ID: 885
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] マイクロ言語による第1二村射影平坦化（Tower Collapse）の E2E 実証 (ID: 885)

## 1. 概要 / Summary
DSN-33-03 §1.2, §2.1, §8.1 (Phase P4) に基づき、スタック型マイクロバイトコードインタプリタを定義し、部分評価器 `stage-poly-lower`（第1二村射影）を適用して目的コードを導出する。導出された残余コードからバイトコードディスパッチループ（オペコード判定・フェッチサイクル）が 100% 消滅し、直接的な演算・分岐 ANF（Tower Collapse）へと平坦化されていることを E2E テストで実証する。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §1.2 (フラクタル構造と実行時平坦化 Tower Collapse)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#12-フラクタル構造メタ循環タワーと実行時平坦化tower-collapse)
  - [DSN-33-03 §2.1 (第1二村射影：ステージ多相辞書による残余化)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#21-第1二村射影ステージ多相辞書による残余化-residualization)
- 関連 Issue:
  - #872 (eval-in-stage コアループ)
  - #879 (stage-poly-lower Nanopass)
  - #880 (文法完全消去アサーション)
  - #881 (3重差分テストオラクル)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/tests/test_futamura_projection.scm](ulisp/tests/test_futamura_projection.scm) - マイクロ言語の定義、第1二村射影 E2E 実証テスト
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_futamura_projection` ターゲット追加
- [x] [docs/issues/README.md](docs/issues/README.md) - 台帳ステータス更新

---

## 4. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/885-demonstrate-e2e-first-futamura-projection-on-micro-language`

### 4.1 マイクロバイトコードインタプリタの定義
- オペコード: `PUSH-CONST`, `LOAD-VAR`, `ADD`, `SUB`, `MUL`, `IF-ZERO`, `HALT`
- 静的バイトコード列と動的環境（変数テーブル）を受け取る評価ループ。

### 4.2 第1二村射影の適用
- `(stage-poly-lower (interp-generator bytecode) env)` を適用。
- バイトコードのデコード・分岐処理が静的（Now）に展開・畳み込まれる。

### 4.3 Tower Collapse のアサーション
- 生成された残余 AST 内に `PUSH-CONST`, `LOAD-VAR`, `ADD` などのバイトコードシンボルやディスパッチ `case` / `cond` が一切存在しないこと（`assert-false`）。
- 実行結果がインタプリタ直実行結果と完全一致すること（`assert-equal`）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 生成コードにインタプリタのディスパッチループやオペコード判定が 0 件であること。
- [x] 第1二村射影によって平坦化された目的コードが正しい計算結果を出力すること。
- [x] `make -C ulisp test_futamura_projection` が 0件エラー PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。
