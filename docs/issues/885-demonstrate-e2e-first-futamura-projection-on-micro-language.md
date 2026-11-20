---
ID: 885
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] マイクロ言語による第1二村射影平坦化（Tower Collapse）の E2E 実証 (ID: 885)

## 1. 概要 / Summary
DSN-33-03 §8.1 (Phase P4) に基づき、スタック型バイトコードインタプリタまたはミニ Lisp を記述し、`eval-in-stage`（第1二村射影）を適用してネイティブ ELF / C99 バイナリを自動生成する。生成コード内に `while-switch` ディスパッチループが一切なく、直接分岐・加算命令へと平坦化されていることを E2E テストで実証する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §1.2, §2.1, §8.1](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#21-第1二村射影ステージ多相辞書による残余化-residualization)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/tests/test_futamura_projection.scm](ulisp/tests/test_futamura_projection.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/885-demonstrate-e2e-first-futamura-projection-on-micro-language`

1. 簡単な四則演算・条件分岐バイトコードインタプリタを記述。
2. 対象バイトコード列を与えて `stage-poly-lower` を実行。
3. 生成されたアセンブリ / C コードを検証し、ディスパッチループが完全に消滅していることを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 生成バイナリがインタプリタオーバーヘッドなしで高速実行できること。
- [ ] 生成コードにディスパッチループが存在しないことがアサーション確認できること。
