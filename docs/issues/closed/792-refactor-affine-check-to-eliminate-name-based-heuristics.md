---
ID: 792
種別: Bug
優先度: Medium
ステータス: Closed
完了日: 2026-11-09
---

# [BUG/SEC] Affine 検査における変数名ヒント強制判定の廃止と関数シグネチャ・戻り値型伝播の導入 (ID: 792)

## 1. 概要 / Summary

Synapse の Affine 所有権チェッカー（`pass-synapse-check-affine`、[DSN-37](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) Section 12.2）において、変数名プレフィックス/サフィックスに基づくリニア型判定（名前ヒント）が残存しているため、無関係な変数（例: `result`, `response`）が線形リソースと誤認されて Use-After-Move エラーとなる偽陽性（False-Positive / CWE-843）不具合を解消する。

現在、明示的な型注釈（`(: var type)`）やコンストラクタ（`make-channel` 等）がない場合、フォールバックとして `linear-variable-name-hint?` による判定が行われている。この関数が `"res"` プレフィックスにマッチするため、`(let ((result (compute))) ...)` のように `res` で始まる通常の計算結果変数を複数回参照すると、初回参照で所有権が移転（`'moved`）したと誤判定され、2回目以降の参照でコンパイル時エラー `[AFFINE-LINEARITY-VIOLATION] Use-After-Move detected` が発生する。
一方で、関数の戻り値として受け取ったチャネル（例: `(let ((c (open-pipe))) ...)`）は名前がヒントに合致せず、関数のシグネチャ伝播もないためリニアとして扱われない偽陰性（False-Negative / CWE-416, CWE-775）も生じている。

本 Issue では、`let` 束縛時における変数名ヒントによる強制リニア判定を完全撤廃し、**関数シグネチャ環境 (`sig-env`)** および **戻り値型伝播（Return-Type Propagation）** を導入することで、厳格かつ健全な静的所有権型検査を実現する。

### 再現手順 / Steps to Reproduce
1. ASC カーネル内で以下を記述する：
   ```scheme
   (let ((result (compute-value)))
     (+ result result))
   ```
2. `infer-linear-binding?` が `result`（`res` プレフィックス）を線形変数と誤認する。
3. 2回目の参照で `[AFFINE-LINEARITY-VIOLATION] Use-After-Move detected: variable has already been transferred: result` エラーが発生する。
4. また、`(let ((c (create-new-channel))) (channel-send! c 10) (channel-send! c 20))` のようにチャネル名が `c` の場合、リニア検査を素通りしてしまい Move 検査や RAII Drop 注入が行われない。

### 再現環境 / Environment
- OS / Arch: Linux x86-64 / uLisp Nanopass Compiler
- 対象ファイル: `ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm`
- 関連仕様書: [DSN-37 Section 12.2](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#122-check-affine-types-型束縛解析ベースの厳格アフィン線形性検査と自動-raii-drop)

---

## 2. 脅威モデル分析とセキュリティ影響 (STRIDE & CWE)

| 脅威分類 (STRIDE) | 対象 CWE | 深刻度 | 脅威シナリオと影響メカニズム |
| :--- | :--- | :---: | :--- |
| **Tampering (改ざん)** / **Elevation of Privilege** | **CWE-416**: Use After Free / Use After Move | High | 関数戻り値として受け取ったチャネル（例: `c`）が名前ヒントに合致しない場合、非線形として扱われて所有権移動検査（Move 検査）がバイパスされ、二重送信やデータ破壊（競合送信）が発生する。 |
| **Denial of Service (サービス拒否)** | **CWE-775**: Missing Release of Resource after Effective Lifetime | High | 関数戻り値チャネルが非規約名（`c`, `pipe` 等）である場合、未消費スコープ離脱時に自動 RAII drop (`%affine-drop!`) が注入されず、チャネル資源やバッファがリークしてデッドロックやメモリ枯渇に至る。 |
| **Integrity Violation (整合性侵害)** | **CWE-843**: Access of Resource Using Incompatible Type | Medium | 通常の計算結果変数（`result`, `response`, `resume` 等）が `"res"` プレフィックスにより線形リソースと誤認され、正当な複数回参照がコンパイルエラーとして拒絶され、また不要な `%affine-drop!` が注入されてランタイム破壊を招く。 |

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [pass_check_affine.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm)
  - `linear-variable-name-hint?` の `"res"` プレフィックス照合を `"resource"` に厳格化
  - `infer-linear-binding?` から変数名フォールバック強制判定（Rule 6）の完全削除
  - 関数シグネチャ環境 (`sig-env`)・既知シグネチャ辞書 (`*default-affine-signatures*`) の導入
  - 関数呼び出し戻り値型の導出（`lookup-function-return-type` / `linear-return-type?`）の実装
  - `check-affine-pass` におけるトップレベルシグネチャ抽出（`scan-form-signatures`）の統合
- [ ] [check_affine.sld](../../ulisp/lib/ulisp/concurrency/passes/check_affine.sld)
  - `lookup-affine-signature`, `register-affine-signature!`, `*default-affine-signatures*` 等のエクスポート追加
- [ ] [test_pass_check_affine.scm](../../tests/concurrency/test_pass_check_affine.scm)
  - Group 9: 変数名 `result` / `response` の複数回参照正常性テスト
  - Group 9: 関数戻り値チャネル `c` に対するシグネチャ伝播および Use-After-Move / RAII Drop 検証テスト
  - Group 9: 型注釈付きトップレベルシグネチャ（`(: f (-> () channel))`）の連携テスト
- [ ] [DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
  - Section 12.2 の記述更新（Issue 792 のシグネチャ型伝播アプローチを明記）

---

## 4. 根本原因分析 (RCA) / Root Cause Analysis

1. **`linear-variable-name-hint?` における過剰プレフィックス一致 (L59)**:
   ```scheme
   (%str-starts-with? "res" s)
   ```
   線形リソース (`resource`) を意図したプレフィックス `"res"` が、Lisp/Scheme で極めて一般的に用いられる `result`, `response`, `resume`, `reset` 等の変数名と前方一致してしまう。
2. **`infer-linear-binding?` における名前ヒントのフォールバック強制判定 (L121-123)**:
   ```scheme
   ((and (symbol? var) (linear-variable-name-hint? var))
    #t)
   ```
   右辺式 `val-expr` がリテラルや基本算術（`+`, `-`, `*` 等）でない場合（例: 関数呼び出し `(compute-value)`）、Rule 5 を抜けて Rule 6 に到達し、変数名がマッチすれば無条件に `#t`（線形型）と判定される。
3. **関数戻り値型の追跡環境 (`sig-env`) の欠如**:
   外部関数やユーザー定義関数がチャネルや線形リソースを返す場合、関数のシグネチャや戻り値型を追跡する仕組みが存在しなかったため、名前ヒントに頼らざるを得ない構造となっていた。

---

## 5. 恒久対策アーキテクチャ設計 (Architecture & Design)

### 5.1 変数名ヒント強制判定の撤廃と名前正規化
- `infer-linear-binding?` から `linear-variable-name-hint?` による強制 `#t` 判定を完全撤廃する。
- 変数名が何であれ、右辺式（RHS）の型または明示的アノテーションが存在しない限り、線形リソースとして推論しない。
- `linear-variable-name-hint?` 内の `"res"` は `"resource"` に変更し、後方互換用またはカーネル引数（Formals）ヒントとしてのみ安全に機能させる。

### 5.2 シグネチャ環境 (`sig-env`) と既知シグネチャマップ
- 既知のチャネル生成・線形リソース返却関数のデフォルトシグネチャテーブルを整備：
  ```scheme
  (define *default-affine-signatures*
    '((make-channel . channel)
      (make-spsc-channel . spsc-channel)
      (make-bounded-channel . channel)
      (make-channel-internal . channel)
      (make-channel-pair . channel-pair)
      (channel-pair . channel-pair)))
  ```
- 動的シグネチャ登録および探索 API:
  - `(register-affine-signature! fname return-type)`
  - `(lookup-affine-signature fname sig-env)`

### 5.3 トップレベル定義およびアノテーションのシグネチャ抽出
- `check-affine-pass` の前処理で、トップレベルの `forms` を走査してシグネチャマップを自動構築：
  1. 明示的シグネチャ宣言:
     `(: fname (-> (arg-types ...) return-type))`
     `(: fname return-type)`
  2. 型アノテーション付き定義:
     `(define (: fname return-type) ...)`
     `(define (fname args...) : return-type body...)`
  3. 末尾式が既知線形コンストラクタである関数の戻り値型自動導出:
     `(define (open-pipe) (make-channel 16))` → 戻り値型 `'channel`
- 束縛式右辺におけるシグネチャ伝播:
  - `(let ((c (open-pipe))) ...)` において、`open-pipe` のシグネチャが `'channel` であれば `c` を線形リソースとして `lin-env` に追加。

### 5.4 明示的型アノテーションの強化
- `(let (((: c channel) expr)) ...)`
- `(let ((c (: channel expr))) ...)`
- `(let ((c (!linear expr))) ...)`
これらを第一級で判定し、シグネチャ未定義の外部手続きに対しても安全に線形性を付与可能とする。

---

## 6. 実装方針とステップ詳細 / Implementation Plan

Target Branch: `fix/792-affine-check-signature-based-type-inference`

### Step 1: `pass_check_affine.scm` の改修
1. `linear-variable-name-hint?` の `"res"` を `"resource"` に置換。
2. `*default-affine-signatures*` 定義および `lookup-affine-signature` / `register-affine-signature!` の実装。
3. `infer-linear-binding?` を改修：
   - Rule 6（名前ヒントによる強制 `#t`）を削除。
   - 関数呼び出し式 `(fn args...)` に対する `lookup-affine-signature` 判定を追加。
4. `scan-form-signatures` を実装し、`check-affine-pass` で `forms` からシグネチャを抽出して各カーネルの検査へ渡す。
5. `validate-affine-ast-internal` および `transform-affine-expr` で `sig-env` を伝播可能にする。

### Step 2: `check_affine.sld` のエクスポート更新
- `lookup-affine-signature`, `register-affine-signature!`, `*default-affine-signatures*` を追加。

### Step 3: `tests/concurrency/test_pass_check_affine.scm` のテスト拡充
- **Group 9: Elimination of Name-Based Heuristics & Signature Propagation (Issue #792)** を追加：
  1. `(let ((result (compute))) (+ result result))` が Use-After-Move エラーとならず正常に `ok` を返すことの検証。
  2. `(let ((response (fetch-data))) (list response response))` が正常に検証通過することの検証。
  3. `result` 変数に対して不要な `%affine-drop!` が注入されないことの検証。
  4. 戻り値型 `'channel` を持つ関数 `create-pipe` を呼び出した短縮名変数 `(let ((c (create-pipe))) ...)` に対し、二重送信で `use-after-move` が正確に検出されることの検証。
  5. 短縮名変数 `c` が未消費のままスコープを抜ける際、自動 RAII drop (`%affine-drop! c`) が注入されることの検証。
  6. トップレベルシグネチャ `(: create-worker-chan (-> () channel))` からの戻り値型伝播検証。

### Step 4: 品質ゲート検証
- `make -C ulisp test_pass_check_affine`
- `make -C ulisp test_passes`
- `make verify_quality`

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `(let ((result (compute))) (+ result result))` 等、`result` や `response` を複数回参照するコードで Use-After-Move エラーが発生しないこと。
- [x] 非線形変数 `result` / `response` に対して不要な `%affine-drop!` が注入されないこと。
- [x] 既知コンストラクタまたはシグネチャ付き関数の戻り値を受け取る任意名の変数（`c` など）に対し、二重消費検出（Use-After-Move）と未消費 RAII Drop 注入が正しく動作すること。
- [x] `linear-variable-name-hint?` の `"res"` が `"resource"` に正規化され、既存のテスト（Group 1〜8）に一切の回帰がないこと。
- [x] `make -C ulisp test_pass_check_affine` が 100% PASS すること（テストケース追加後も全件合格）。
- [x] `make -C ulisp test_passes` および `make verify_quality` が 100% PASS すること。
