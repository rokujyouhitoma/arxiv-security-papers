---
ID: 749
種別: Bug
優先度: Medium
ステータス: Open (In Progress)
---

# [BUG/SEC] 変数名依存を廃止した型・束縛解析に基づく厳格な Affine 線形性検査 (ID: 749)

## 1. 概要 / Summary
コンパイラの Affine 型検査パスにおいて、個別バグは修正されたものの、`linear-variable?` の判定処理が依然として変数名のプレフィックス（`chan`, `rx`, `tx`, `res`, `buf` 等で始まるシンボル名）に依存している。
このため、開発者が一般的な変数名（`c`, `pipe`, `stream` 等）を付与した場合に線形リソース検査がすり抜けて二重消費やリークが発生する一方、通常の変数がたまたま該当プレフィックスを持っていた場合に誤判定される深刻な脆弱性・設計不備が存在する。

### 再現手順 / Steps to Reproduce
1. チャネルを作成し、変数名 `my-connection` に束縛する。
2. 同一チャネルに対して複数回の `channel-close!` や消費操作を行う。
3. 変数名が `chan` 等で始まらないため、コンパイラが `linear-variable?` と判定せずエラーを検出できない。

### 再現環境 / Environment
- OS / Env: All Platforms
- File: `ulisp/compiler/nanopass.scm`, `ulisp/compiler/passes/` (Nanopass affine passes)
- 関連 Issue: Follow-up of #736

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [`ulisp/compiler/nanopass.scm`](../../ulisp/compiler/nanopass.scm)
- [ ] [`ulisp/compiler/passes/test_nanopass_framework.scm`](../../ulisp/compiler/passes/test_nanopass_framework.scm)
- [ ] [`ulisp/tests/passes/test_040_analysis.scm`](../../ulisp/tests/passes/test_040_analysis.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
Nanopass コンパイラフレームワークへの Affine 検査導入時、初期のプロトタイプ実装として簡易的に変数名シンボルの文字列マッチングが採用され、そのまま本流に残存していたため。本来あるべき「生成式（`make-channel` 等）の型情報」および「スコープ束縛メタデータ」に基づく厳密なセマンティクス解析が行われていない。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: リニア型リソースの変数名に必ず規約のプレフィックスを命名する。
* **恒久対策 (Permanent Fix)**: 変数名による文字列マッチングを完全撤廃し、型推論・AST アノテーション情報（`type: linear-resource`）および束縛テーブルに基づく正統な線形性追跡ロジックへ移行する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/749-implement-type-based-affine-linearity-check`

1. `ulisp/compiler/`:
   - 型推論・解析パスにおいて、`make-channel`, `make-buffer` 等の線形リソース生成式の評価結果に `linear-type` 属性を付与する。
   - 変数束縛（`let`, `lambda` 引数等）の環境に型属性を伝播させ、環境ルックアップによって線形性を判定する。
2. `ulisp/compiler/nanopass.scm`:
   - `linear-variable?` のシグネチャを `(linear-variable? var-ast env)` に更新し、環境情報を参照するように改修。
3. `ulisp/tests/`:
   - 任意の名前を持つチャネル変数に対して、二重消費の検出および正当な借用が正しく判定されるユニットテストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 変数名のプレフィックスに基づく線形性判定処理が完全に撤廃されること
- [ ] 任意の変数名であっても、チャネル等の線形リソースの不正な二重消費がコンパイル時に検出されること
- [ ] 通常の変数が名前によって誤って線形変数扱いされないこと
- [ ] Nanopass コンパイラテストスイートがすべて PASS すること

