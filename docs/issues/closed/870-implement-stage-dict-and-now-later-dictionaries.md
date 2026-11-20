---
ID: 870
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] <stage-dict> レコードおよび Now/Later ステージ辞書の実装 (ID: 870)

## 1. 概要 / Summary
DSN-33-03 §3.1, §3.2, §3.3, §3.7 に基づき、二村射影とステージ多相評価（Stage-Polymorphic Evaluation）の第一級インフラとなる `<stage-dict>` レコード、およびホスト即時評価を行う `Now` 辞書、残余 MIR-ANF コードを生成する `Later` 辞書を `ulisp/compiler/eval_in_language.scm` に実装する。

コンパイラ自身のセルフホスト制約（No-set! 規律、固定長引数ディスパッチ、cons Box 化）に厳格に準拠し、CWE-400（リソース枯渇）防止ガードを内蔵する。

---

## 2. トレーサビリティ / Traceability
- **上位設計書**:
  - [DSN-33-03 §3.1: <stage-dict> レコードと辞書渡しプロトコル](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#31-stage-dict-レコードと辞書渡しプロトコル)
  - [DSN-33-03 §3.2: Now 辞書（即時計算・CTFE・オラクル評価）](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#32-now-辞書即時計算ctfeオラクル評価)
  - [DSN-33-03 §3.3: Later 辞書（残余化・MIR-ANF 生成）](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#33-later-辞書残余化mir-anf-生成)
  - [DSN-33-03 §3.7: 評価器自身のセルフホスト記述規約（No-set! / Fixed-Arity / Box化規準）](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#37-評価器自身のセルフホスト記述規約no-set--fixed-arity--box化規準)
- **関連個別仕様書**:
  - [DSN-33-01 §2.2: フラクタルな包含・合成構造](docs/designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md#22-フラクタルな包含合成構造)
  - [DSN-33-02 §3.3: AST 定数式評価器 (eval-in-language)](docs/designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md#33-ast-定数式評価器-eval-in-language--コンパイル時計算-ctfe-issue-825)
- **関連 Issue**: #825 (eval-in-language), #871 (PSDS), #872 (eval-in-stage), #873 (Oracle Verify)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm) - コア実装ファイル
- [ ] [ulisp/compiler/nanopass_meta.scm](ulisp/compiler/nanopass_meta.scm) - セルフホスト統合・エクスポート
- [ ] [ulisp/tests/test_stage_dict.scm](ulisp/tests/test_stage_dict.scm) - 新規単体テストスイート

---

## 4. セキュリティ要件と制約 / Security Requirements and Constraints
1. **CWE-400 (リソース枯渇・サービス不能の防止)**:
   - 辞書操作および評価において、Fuel ステップ上限（デフォルト 10,000）および再帰深度 Depth 上限（デフォルト 256）の減算・バウンドを必須とする。
2. **セルフホスト制約 (No-set! 規約)**:
   - トップレベルおよび局所 `set!` を完全排除。
   - 変更可能なテンポラリ変数カウンタ等の内部状態は `(cons 0 '())` のコンスセル Box で保持し、`set-car!` / `set-cdr!` のみで更新。
3. **固定長ディスパッチ (Fixed-Arity 規約)**:
   - 可変長引数（`. rest`）構文および `apply` を排除。
   - プリミティブ関数適用スロットは `apply-prim-1`, `apply-prim-2`, `apply-prim-3`, `apply-prim-4` として静的に個別定義。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/870-implement-stage-dict-and-now-later-dictionaries`

### Step 1: `<stage-dict>` レコードの定義
- レコード型名: `<stage-dict>`
- フィールド一覧:
  1. `name`: シンボル (`'now` または `'later`)
  2. `stage-level`: 整数 (`0` は実行時/Later、`1` はコンパイル時/Now、`2+` はメタ層)
  3. `apply-prim-1`: `(dict op arg1) -> val`
  4. `apply-prim-2`: `(dict op arg1 arg2) -> val`
  5. `apply-prim-3`: `(dict op arg1 arg2 arg3) -> val`
  6. `bind-let`: `(dict var rhs-thunk body-thunk) -> result`
  7. `emit-if`: `(dict test-sv then-thunk else-thunk) -> result`
  8. `emit-call`: `(dict callee-sv arg-svs) -> result`
  9. `lift-val`: `(dict static-val loc) -> dynamic-expr`
  10. `signal-csp-error`: `(dict reason loc) -> diagnostic`

### Step 2: `make-now-dict`（即時計算辞書）の実装
- `apply-prim-1..3`: ホスト Scheme の算術・リスト操作（`+`, `-`, `*`, `car`, `cdr` 等）を直接インライン実行。
- `bind-let`: `rhs-thunk` を評価して値を得た後、環境を拡張して `body-thunk` を即座に評価。
- `emit-if`: `test-sv` の真偽値に基づき、真節または偽節のどちらか一方のみを評価（未実行節は破棄）。
- `lift-val`: 静的値をそのまま透過（ID 変換）。

### Step 3: `make-later-dict`（残余 ANF 生成辞書）の実装
- テンポラリ変数生成器 `(make-temp-var-generator)` を cons Box カウンタ `(cons 0 '())` で配備（`t0`, `t1`, `t2`... を生成）。
- `apply-prim-1..3`: 新規テンポラリ変数 `t_n` を割り当て、`(let-anf ((t_n (op arg ...))) body)` の AST ノードを発行。
- `bind-let`: 残余コードの `(let-anf ((var rhs)) body)` を構築。
- `emit-if`: 動的分岐として両節を評価し、`(if-anf test-sv then-ast else-ast)` を生成。
- `lift-val`: 静的定数を残余コードのリテラル `(quote val)` または即値形式へ昇格。

### Step 4: 単体テストと回帰検証
- `ulisp/tests/test_stage_dict.scm` を作成し、同一の加算・条件分岐式を `Now` 辞書（即時計算）と `Later` 辞書（ANF 生成）の双方に渡し、結果の整合性を検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `<stage-dict>` レコードおよびアクセサ群が正しく定義されていること。
- [x] `make-now-dict` で加算 `(+ 1 2)` を評価した際、即値 `3` が返却されること。
- [x] `make-later-dict` で加算 `(+ 1 x)` を評価した際、残余 ANF 構造 `(let-anf ((t0 (+ 1 x))) ...)` が返却されること。
- [x] セルフホスト規律（No-set! / Fixed-Arity）を 100% 遵守していること。
- [x] `make py_compile` および `make static_analysis` がエラー 0 件で PASS すること。
- [x] 既存の `eval-in-language` および CTFE テストに一切のデグレがないこと。
