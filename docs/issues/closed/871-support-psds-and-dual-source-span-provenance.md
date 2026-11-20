---
ID: 871
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] PSDS（部分静的データ構造）と二重 Source Span 出自追跡の実装 (ID: 871)

## 1. 概要 / Summary
DSN-33-03 §3.4 に基づき、骨格（コンスセル・クロージャコードポインタ）はコンパイル時既知で葉（要素・環境ポインタ）が動的な**部分静的データ構造（PSDS: Partially Static Data Structures）**を表現する `<stage-val>` レコードを `ulisp/compiler/eval_in_language.scm` に実装する。

PSDS ペアに対する `stage-car` および `stage-cdr` の静的簡約により、インタプリタの環境探索ループを残余コードから 100% 消去する。また、二村射影によってインタプリタが蒸発（Collapse）した後のデバッグ性を保証するため、`host-span`（インタプリタ側）と `guest-span`（DSL側）を保持する**二重ソース位置情報（Dual Source Span / Provenance Stack）**を統合する。

---

## 2. トレーサビリティ / Traceability
- **上位設計書**:
  - [DSN-33-03 §3.4: 部分静的データ構造（PSDS）と二重ソース位置情報（Dual Source Span）](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#34-部分静的データ構造psdsと二重ソース位置情報dual-source-span)
  - [DSN-33-03 §4.3: コンパイル時診断 S式仕様（Dual Span 伝播 Reporter #833 準拠）](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#43-コンパイル時診断-s式仕様dual-span-伝播-reporter-833-準拠)
  - [DSN-33-03 §3.7: 評価器自身のセルフホスト記述規約（No-set! / Fixed-Arity）](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#37-評価器自身のセルフホスト記述規約no-set--fixed-arity--box化規準)
- **関連個別仕様書**:
  - [DSN-33-02 §3.1: 第一級ソース位置情報 (Source Span) と来歴追跡 (Issue #824)](docs/designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md#31-第一級ソース位置情報-source-span-と来歴追跡-issue-824)
- **関連 Issue**: #870 (<stage-dict>), #872 (eval-in-stage), #876 (CSP Validator)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm) - コア実装ファイル（<stage-val>, PSDS 還元ルール）
- [ ] [ulisp/compiler/binding.scm](ulisp/compiler/binding.scm) - 統一束縛・識別子連携
- [ ] [ulisp/tests/test_psds_provenance.scm](ulisp/tests/test_psds_provenance.scm) - 新規単体テストスイート
- [ ] [ulisp/Makefile](ulisp/Makefile) - テストターゲット追加

---

## 4. セキュリティ要件と制約 / Security Requirements and Constraints
1. **出自曖昧性排除（CWE-704 / 不正な型・コンテキスト混同の防止）**:
   - 二村射影によってインタプリタと対象 DSL コードが単一残余 AST に融合した際、エラー箇所の帰属が混同されないよう、常に `host-span` と `guest-span` を明示的に分離管理する。
2. **セルフホスト規律（No-set! / Fixed-Arity 準拠）**:
   - `<stage-val>` の生成・走査において、破壊的 `set!` を完全排除。
   - ディスパッチおよびアクセサは固定アリティの純粋手続きとして構成。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/871-support-psds-and-dual-source-span-provenance`

### Step 1: `<stage-val>` レコード型の定義
- フィールド:
  1. `tag`: 型タグ (`'integer`, `'boolean`, `'pair`, `'closure`, `'unknown` 等)
  2. `kind`: 束縛時間種別 (`'pure-static`, `'partially-static`, `'pure-dynamic`)
  3. `payload`: 実際の値（静的値、PSDS ペア、または動的 AST 式）
  4. `host-span`: インタプリタ側のソース位置 (`<source-span>` または `#f`)
  5. `guest-span`: 対象言語 DSL 側のソース位置 (`<source-span>` または `#f`)
- 述語群:
  - `stage-val?`, `stage-val-pure-static?`, `stage-val-partially-static?`, `stage-val-pure-dynamic?`
- リフティングヘルパー:
  - `make-static-val`, `make-dynamic-val`, `make-psds-val`

### Step 2: PSDS ペア操作と静的還元ルールの実装
1. **`stage-cons car-sv cdr-sv host-sp guest-sp`**:
   - `car-sv` と `cdr-sv` が共に `pure-static` の場合:
     直接 Scheme ネイティブのペア `(cons (stage-val-payload car-sv) (stage-val-payload cdr-sv))` を構築し、`pure-static` な `<stage-val>` として返却。
   - いずれかが `pure-dynamic` または `partially-static` の場合:
     `<stage-val>` を要素とするメタペア `(cons car-sv cdr-sv)` を payload に保持する `partially-static` な `<stage-val>` を生成。
2. **`stage-car dict sv loc`**:
   - `pure-static` $\implies$ 即座に `car` を取得して静的値を返却。
   - `partially-static` $\implies$ 保持している静的ペアの `car`（`<stage-val>`）を即座に取得して返却。**残余コードに `car` 命令は 1 行も発行されない！**
   - `pure-dynamic` $\implies$ `(stage-apply-prim-1 dict 'car (stage-val-payload sv))` を実行して残余 AST ノードを発行し、`pure-dynamic` な `<stage-val>` を返却。
3. **`stage-cdr dict sv loc`**:
   - `stage-car` と同様に完全対称に対称実装。

### Step 3: 出自情報（Provenance Stack）ヘルパーの実装
- `stage-val-provenance`:
  `(list (cons 'guest guest-sp) (cons 'host host-sp))` を生成し、残余 AST ノードにメタデータとして付与する機構。

### Step 4: 単体テストと回帰検証
- `ulisp/tests/test_psds_provenance.scm` を作成し、以下を検証:
  - PSDS ペアの生成と `stage-car`/`stage-cdr` の即時消去。
  - 静的骨格（リスト）の中に動的変数 `x` が入っている場合、リスト走査がコンパイル時に蒸発し、`x` のみが残余化されること。
  - 二重 Span が消滅せずに伝播すること。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `<stage-val>` レコード型およびアクセサ群が正しく定義されていること。
- [x] `stage-cons` で作成された PSDS ペアに対し、`stage-car` および `stage-cdr` を適用した際、コンパイル時に要素が即座に取り出され、残余コードに `car`/`cdr` が一切残らないこと。
- [x] 動的 `<stage-val>` に対する `stage-car` では、正しく残余命令 `(car ...)` が発行されること。
- [x] `host-span` と `guest-span` の双方が保持され、出自情報が正しく抽出できること。
- [x] `make -C ulisp test_psds_provenance` が 100% PASS すること。
- [x] `make py_compile` および `make static_analysis` がエラー 0 件で PASS すること。
