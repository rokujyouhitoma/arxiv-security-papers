---
ID: 792
種別: Bug
優先度: Medium
ステータス: Open (New)
---

# [BUG/SEC] Affine 検査における変数名ヒント強制判定の廃止と関数シグネチャ・戻り値型伝播の導入 (ID: 792)

## 1. 概要 / Summary
Synapse の Affine 所有権チェッカー（`pass-synapse-check-affine`）において、変数名プレフィックス/サフィックスに基づくリニア型判定（名前ヒント）が残存しているため、無関係な変数（例: `result`）が線形リソースと誤認されて Use-After-Move エラーとなる偽陽性（False-Positive）不具合を解消する。

現在、明示的な型注釈（`(: var type)`）やコンストラクタ（`make-channel` 等）がない場合、フォールバックとして `linear-variable-name-hint?` による判定が行われている。このため、`(let ((result (compute))) ...)` のように `res` で始まる通常の計算結果変数を複数回参照すると誤ってコンパイルエラーとなる。一方で、関数の戻り値として受け取ったチャネル（例: `c`）は名前に該当しないためリニアとして扱われない偽陰性（False-Negative）も生じている。

### 再現手順 / Steps to Reproduce
1. ASC カーネル内で `(let ((result (compute-value))) (+ result result))` を記述する。
2. Affine チェッカーが `result` をリニア変数と誤認し、2回目の参照で `[AFFINE-LINEARITY-VIOLATION] Use-After-Move detected: variable has already been transferred` エラーを発生させる。
3. また、`(let ((c (create-new-channel))) (channel-send! c 10) (channel-send! c 20))` のようにチャネル名が `c` の場合、リニア検査を素通りしてしまい Move 検査が行われない。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / ULisp Nanopass Compiler
- File: `ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [pass_check_affine.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm)
- [ ] [test_pass_check_affine_runner.scm](../../ulisp/build/test_pass_check_affine_runner.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm` の `linear-variable-name-hint?`（行 52-65）にて、`chan`, `rx`, `tx`, `res`, `buf`, `*-res` 等をマッチングしている。
- `infer-linear-binding?`（行 120-123）において、非線形リテラルや基本算術演算に該当しない場合、変数名が上記ヒントに合致していれば無条件に `#t`（リニア変数）と判定している。
- 関数の戻り値型情報を伝播・参照する型環境が存在しないため、変数名という不確実なヒューリスティクスに依存している。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 計算結果変数の名前を `ans`, `val`, `out` など `res` を含まない名前に変更する。
* **恒久対策 (Permanent Fix)**:
  - 変数名による強制的なリニア判定を廃止（名前ヒントは注釈推奨の警告 Warning にのみ格下げ）。
  - 関数のシグネチャおよび戻り値の型アノテーションを関数呼び出し側へ伝播する仕組みを導入し、関数の戻り値がリニア型であるかを型ベースで決定する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/792-affine-check-signature-based-type-inference`

1. `pass_check_affine.scm` の `infer-linear-binding?` から変数名による強制 `#t` 判定を削除。
2. 既知のチャネル生成関数やシグネチャ注釈付き関数の戻り値型を追跡する型伝播マップを導入。
3. `result` や `response` 等の一般的な変数名を複数回使用するコードが正常にコンパイルを通ることを確認するテストを追加。
4. 関数の戻り値としてチャネルを受け取る変数 `c` に対し、型注釈またはシグネチャ経由で正しくリニア検査が適用されることを検証するテストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `(let ((result ...)) ...)` が複数回参照されても Use-After-Move エラーが発生しないこと。
- [ ] 短縮名（`c` など）であっても型注釈または戻り値型伝播により線形性が正しく保証されること。
- [ ] `pass_check_affine` の単体テストスイートが 100% PASS すること。

