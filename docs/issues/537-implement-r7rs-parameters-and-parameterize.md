---
ID: 537
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] コンパイラコンテキスト動的スコープ制御のための R7RS パラメータ (make-parameter / parameterize) の実装 (ID: 537)

## 1. 概要 / Summary
コンパイラやパイプラインの機能拡張に伴い、「現在のコンパイルターゲット」「GC モード」「最適化レベル」「現在の出力先ポート」等のコンテキスト情報を、深層の下請け関数へ引数として渡し回す（引数のバケツリレー）コードが増加し、保守性の低下を招いている。
本 Issue では、R7RS Section 4.2.6（Dynamic bindings: `make-parameter`, `parameterize`）に準拠した動的束縛パラメータ機構を実装する。
動的環境の安全な巻き戻しを保証し、例外送出時や通常脱出時にも確実に以前の値へ復元されるクリーンなコンテキスト切り替えを可能にする。

---

## 2. トレーサビリティ / Traceability
- **関連規格**:
  - R7RS Section 4.2.6 (Dynamic bindings: `make-parameter`, `parameterize`)
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第2章 ナノパスコンパイラアーキテクチャ)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連先行 Issue**:
  - Issue #531: 軽量大域脱出ハンドラスタックに基づく R7RS 例外処理機構の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/parameter.scm](../../ulisp/lib/parameter.scm) (新規作成: `make-parameter` 手続きおよび動的スタック連鎖)
- [ ] [ulisp/passes/02_desugar.scm](../../ulisp/passes/02_desugar.scm) (`parameterize` 構文の展開および unwind-protect / guard 統合)
- [ ] [ulisp/passes/08_driver.scm](../../ulisp/passes/08_driver.scm) (ドライバ内部フラグのパラメータ化リファクタリング)
- [ ] [tests/test_bare_metal_ulisp.py](../../tests/test_bare_metal_ulisp.py) (パラメータ動的スコープ・巻き戻し E2E テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/537-ulisp-r7rs-parameters`

1. **パラメータ手続きの表現**:
   - `(make-parameter init [converter])`: 内部セルを保持するクロージャを生成。
   - 引数なし呼出 `(p)` で現在値を取得、引数あり呼出 `(p new-val)` で値を更新。
2. **`parameterize` の脱糖と安全な復元**:
   - `(parameterize ((param1 val1) ...) body ...)` を以下のように展開：
     ```scheme
     (let ((old1 (param1)) ...)
       (dynamic-wind
         (lambda () (param1 val1) ...)
         (lambda () body ...)
         (lambda () (param1 old1) ...)))
     ```
   - 簡易実装（動的 unwind スタックまたは Issue #531 の例外ハンドラ機構と連携）により、ブロック脱出時に確実に旧値を復元。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(define p (make-parameter 10))` において、`(p)` が `10` を返すこと。
- [ ] `(parameterize ((p 20)) (p))` が `20` を返し、ブロック脱出後に `(p)` が `10` に戻ること。
- [ ] `parameterize` ブロック内で例外が `raise` された場合も、捕捉側で旧値 `10` に復元されていること。
- [ ] 自己ホスティング固定点ブートストラップが完全一致でパスすること。
