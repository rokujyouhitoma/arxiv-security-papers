---
ID: 865
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] SRFI 189 Maybe and Either オプショナルコンテナ ((scheme maybe)) の実装 (ID: 865)

## 1. 概要 / Summary
R7RS-large Hypnos Docket において、関数型プログラミングにおけるオプショナル値（値の存在または非存在）および型安全なエラーハンドリング（成功値または失敗・エラー値）の共通標準として策定されている **SRFI 189 (Maybe and Either: optional container types)** は、従来の例外送出や `#f` への多重責務（真偽値 `#f` とエラー表現の混同）を排除し、堅牢なモナド風コンテナ `Maybe` (`Just` / `Nothing`) および `Either` (`Right` / `Left`) を提供する重要仕様である。

現在、`ulisp/docs/ref_r7rs_compliance.md` §2.4 において SRFI 189 は「× (未サポート)」となっている。
本 Issue では、純粋 Scheme 実装による完全自律型 SRFI 189 ライブラリを [ulisp/lib/maybe.scm](../../ulisp/lib/maybe.scm) に構築し、R7RS-large 標準モジュール `(scheme maybe)` および `(srfi 189)` として提供する。

SRFI 189 の核心的特徴：
1. **排他的直和型 (Disjoint Sum Types)**:
   - `Maybe`: 有効な1つ以上のペイロードをカプセル化する `Just` と、値の非存在を表す唯一のシングルトン `Nothing`。
   - `Either`: 正常計算結果をカプセル化する `Right` と、エラーや失敗情報をカプセル化する `Left`。
2. **多値 (Multiple Values) の自然なカプセル化**:
   - `Just`, `Right`, `Left` は単一の値だけでなく、0個以上の任意個数のペイロードオブジェクトを保持可能。
3. **包括的なプロトコル相互変換 (Protocol Interoperability)**:
   - Scheme 伝統のブール値、リスト、多値、世代（`eof-object`）、例外ハンドリング（`guard`）との双方向変換。
4. **モナド結合と短絡構文マクロ (Monadic Pipelines & Syntax)**:
   - `maybe-bind`, `either-bind`, `maybe-let*`, `either-let*`, `either-guard` による安全で簡潔なパイプライン処理。
5. **3値論理 (Trivalent Kleene Logic)**:
   - `Nothing` を第3の真理値「未知 (Unknown)」として扱うクレーネ3値論理演算 (`tri-and`, `tri-or`, `tri-not`, `tri=?`, `tri-merge`) の完備。

---

## 2. トレーサビリティ / Traceability
- **関連標準仕様**:
  - R7RS-large Hypnos Docket: `(scheme maybe)`
  - SRFI 189: [Maybe and Either: optional container types](https://srfi.schemers.org/srfi-189/srfi-189.html) (by John Cowan & Wolfgang Corcoran-Mathe)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.4 (Hypnos Docket 準拠状況: 395 行目)
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - 先行関連 Issue:
    - [Issue #864: Implement SRFI 48 Intermediate Format Strings](closed/864-implement-srfi-48-intermediate-format-strings.md)
    - [Issue #863: Implement SRFI 214 Flexvectors](closed/863-implement-srfi-214-flexvectors.md)
    - [Issue #862: Implement SRFI 180 JSON Parser and Serializer](closed/862-implement-srfi-180-json-parser-and-serializer.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/maybe.scm](../../ulisp/lib/maybe.scm) (新規作成: SRFI 189 レコード型定義、コンストラクタ、述語、アクセサ、モナド演算、シーケンス、プロトコル変換、高階反復、3値論理、構文マクロ)
- [x] [ulisp/lib/srfi/189.sld](../../ulisp/lib/srfi/189.sld) (新規作成: `(srfi 189)` ライブラリ定義、Traceability ヘッダー)
- [x] [ulisp/lib/scheme/maybe.sld](../../ulisp/lib/scheme/maybe.sld) (新規作成: `(scheme maybe)` ライブラリ定義、Traceability ヘッダー)
- [x] [ulisp/tests/test_srfi_189.scm](../../ulisp/tests/test_srfi_189.scm) (新規作成: Group 1〜10、モナド則、短絡評価、境界値、型安全性検証テストスイート)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`ULISP_LARGE_LIBS` への `lib/maybe.scm` 追加、`lint_sexpr` への `.sld` 追加、および `test_srfi_189` ターゲット新設)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (SRFI 189 準拠ステータスを `◎` に更新)
- [x] [docs/issues/README.md](README.md) (Issue 台帳更新: ステータス管理)

---

## 4. セキュリティ考慮事項と脅威分析 / Security Considerations & Threat Modeling
コンテナ型およびエラーハンドリング基盤は、システム全般のデータフローおよび信頼境界を跨ぐ値の伝播に利用されるため、以下の脅威ベクトルを分析し防護策を講じる：

1. **型混同とペイロード改ざん (Type Confusion & Payload Tampering)**:
   - *脅威*: 悪意あるコードまたはバグにより、`Just`, `Nothing`, `Right`, `Left` の型タグが偽装されたり、内部ペイロードが破壊的に変更された場合、型の不変性が崩壊する。
   - *対策*: R7RS 標準の `define-record-type` を用いて disjoint かつイミュータブルな4つの型 (`<just>`, `<nothing>`, `<left>`, `<right>`) を定義。ミューテータをエクスポートせず、完全な不変性を担保する。
2. **例外握りつぶしと情報漏洩 (Unchecked Exception Swallowing in `exception->either` & `either-guard`)**:
   - *脅威*: `exception->either` や `either-guard` がシステム重大例外（メモリ枯渇、スタックオーバーフロー、構文解析エラー等）まで無差別に捕捉した場合、不正状態のまま処理が継続する危険がある。
   - *対策*: 述語 `pred` による厳格な例外マッチングを行い、マッチしない例外は再送出 (`raise`) する。捕捉した例外オブジェクトはそのまま `Left` のペイロードに保持し、スタック情報や診断情報の欠落を防ぐ。
3. **リソース枯渇 (DoS via Infinite Unfold / Cyclic Sequence Aggregation)**:
   - *脅威*: `maybe-unfold`, `either-unfold`, `maybe-sequence` に無限シーケンスや循環データが渡された場合、無限ループによるメモリ枯渇や CPU ビジーが発生する。
   - *対策*: `stop?` 述語による適切な停止判定、およびコレクション走査時の有限長前提を徹底する。
4. **多値 (Multiple Return Values) の不整合とスタック破壊**:
   - *脅威*: `values->maybe` や `maybe->values` 等において、0個または複数の戻り値の処理に不整合が生じ、ランタイムのコールスタックが不正になる。
   - *対策*: `call-with-values` を標準機構として用い、0引数・単一値・可変長多値を厳密かつ透過的にリストと相互変換する。

---

## 5. 仕様定義とアーキテクチャ設計 / Specification & Architecture Design

### 5.1 型表現とコンテナ構造
```scheme
;; レコード型の定義 (Disjoint Record Types)
(define-record-type <just>
  (raw-just objs)
  just?
  (objs just-objs))

(define-record-type <nothing>
  (make-nothing)
  nothing?)

(define-record-type <left>
  (raw-left objs)
  left?
  (objs left-objs))

(define-record-type <right>
  (raw-right objs)
  right?
  (objs right-objs))

;; シングルトン Nothing
(define nothing-obj (make-nothing))
(define (nothing) nothing-obj)
```

- `(maybe? obj)`: `(or (just? obj) (nothing? obj))`
- `(either? obj)`: `(or (right? obj) (left? obj))`
- 4つの型はいずれも互いに排他的（disjoint）であり、リストやベクタ等の他の基本型とも混同されない。

### 5.2 全エクスポート手続き一覧 (分類別)

#### A. コンストラクタ & 述語 (Constructors & Predicates)
- `(just obj ...)`: 0個以上の引数をカプセル化した `Just` を生成。
- `(nothing)`: 唯一の `Nothing` オブジェクトを返却。
- `(right obj ...)`: 0個以上の引数をカプセル化した `Right` を生成。
- `(left obj ...)`: 0個以上の引数をカプセル化した `Left` を生成。
- `(maybe? obj)`, `(just? obj)`, `(nothing? obj)`
- `(either? obj)`, `(right? obj)`, `(left? obj)`
- `(maybe= equal maybe1 maybe2 ...)`:
  - すべての引数が `Maybe` であり、すべて `Nothing` であるか、またはすべて同一要素数の `Just` であって各ペイロードが `equal` で等しい場合に `#t`。
- `(either= equal either1 either2 ...)`:
  - すべての引数が `Either` であり、すべて同一要素数の `Right` または同一要素数の `Left` であって各ペイロードが `equal` で等しい場合に `#t`。
- `(either-swap either)`:
  - `Right` のペイロードを `Left` に、`Left` のペイロードを `Right` に反転したコンテナを返却。

#### B. アクセサ & デフォルト値抽出 (Accessors & Extractors)
- `(maybe-ref maybe failure [success])`:
  - `maybe` が `Just` の場合、`(apply success (just-objs maybe))` を末尾呼出し（`success` 省略時は `values`）。
  - `maybe` が `Nothing` の場合、`(failure)` を末尾呼出し。
- `(maybe-ref/default maybe default ...)`:
  - `maybe` が `Just` の場合、そのペイロードを（多値として）返却。
  - `maybe` が `Nothing` の場合、`default ...` を（多値として）返却。
- `(either-ref either failure [success])`:
  - `either` が `Right` の場合、`(apply success (right-objs either))` を末尾呼出し。
  - `either` が `Left` の場合、`(apply failure (left-objs either))` を末尾呼出し。
- `(either-ref/default either default ...)`:
  - `either` が `Right` の場合、そのペイロードを返却。
  - `either` が `Left` の場合、`default ...` を返却。

#### C. モナド結合・平坦化・合成 (Join, Bind & Compose)
- `(maybe-join maybe)`:
  - `maybe` が `Just` でその単一ペイロードが `Maybe` の場合、内部の `Maybe` を返却。それ以外の `Just` は自身を返却。`Nothing` は `Nothing`。
- `(either-join either)`:
  - `either` が `Right` でその単一ペイロードが `Either` の場合、内部の `Either` を返却。それ以外は自身を返却。
- `(maybe-compose mproc ...)`:
  - モナド手続き群を左から右へ合成した手続きを生成（途中で `Nothing` が返れば短絡）。
- `(either-compose mproc ...)`:
  - モナド手続き群を左から右へ合成した手続きを生成（途中で `Left` が返れば短絡）。
- `(maybe-bind maybe mproc ...)`:
  - `(maybe-ref maybe nothing (maybe-compose mproc ...))` に等価。
- `(either-bind either mproc ...)`:
  - `(either-ref either left (either-compose mproc ...))` に等価。

#### D. コレクション & シーケンス操作 (Sequence Operations)
- `(maybe-length maybe)`: `Just` なら 1、`Nothing` なら 0。
- `(either-length either)`: `Right` なら 1、`Left` なら 0。
- `(maybe-filter pred maybe)`:
  - `Just` かつ `(apply pred payload)` が真ならそのまま返却、それ以外は `Nothing`。
- `(maybe-remove pred maybe)`:
  - `Just` かつ `(apply pred payload)` が偽ならそのまま返却、それ以外は `Nothing`。
- `(either-filter pred either obj ...)`:
  - `Right` かつ `(apply pred payload)` が真ならそのまま返却、偽なら `(apply left obj ...)`。
- `(either-remove pred either obj ...)`:
  - `Right` かつ `(apply pred payload)` が偽ならそのまま返却、真なら `(apply left obj ...)`。
- `(maybe-sequence mappable map [aggregator])`:
  - コレクションを `map` で走査。途中で `Nothing` が現れたら `Nothing` を即座に返却。すべて `Just` ならペイロードを `aggregator` で集約して `Just` でラップ。
- `(either-sequence mappable map [aggregator])`:
  - 走査中、最初の `Left` が現れたらそれを即座に返却。すべて `Right` なら集約して `Right` でラップ。

#### E. プロトコル相互変換 (Protocol Converters)
- リスト変換:
  - `(maybe->list maybe)`, `(either->list either)`
  - `(list->maybe list)`, `(list->either list obj ...)`
  - `(list->just list)`, `(list->right list)`, `(list->left list)`
- コンテナ相互変換:
  - `(maybe->either maybe obj ...)`, `(either->maybe either)`
- 真偽値変換:
  - `(maybe->truth maybe)`, `(either->truth either)`
  - `(truth->maybe obj)`, `(truth->either obj fail-obj ...)`
- リストまたは偽 (#f) 変換:
  - `(maybe->list-truth maybe)`, `(either->list-truth either)`
  - `(list-truth->maybe val)`, `(list-truth->either val obj ...)`
- 世代 (EOF オブジェクト) 変換:
  - `(maybe->generation maybe)`, `(either->generation either)`
  - `(generation->maybe obj)`, `(generation->either obj fail-objs ...)`
- 多値 (Multiple Values) 変換:
  - `(maybe->values maybe)`, `(either->values either)`
  - `(values->maybe producer)`, `(values->either producer fail-obj ...)`
  - `(maybe->two-values maybe)`: `(values payload #t)` または `(values #f #f)`。
  - `(two-values->maybe producer)`: 2値を返す `producer` を呼び出し、第2値が真なら `(just val)`、偽なら `Nothing`。
- 例外変換:
  - `(exception->either pred thunk)`: `thunk` を実行し、`pred` に合致する例外が発生した場合は `(left exc)` を返し、正常終了時は `(apply right values)` を返却。合致しない例外は再送出。

#### F. 高階反復・畳み込み・展開 (Map, Fold & Unfold)
- `(maybe-map proc maybe)` / `(either-map proc either)`
- `(maybe-for-each proc maybe)` / `(either-for-each proc either)`
- `(maybe-fold kons nil maybe)` / `(either-fold kons nil either)`
- `(maybe-unfold stop? mapper successor seed ...)` / `(either-unfold stop? mapper successor seed ...)`

#### G. クレーネ 3 値論理演算 (Trivalent Logic)
- `(tri-not maybe)`: `Nothing` なら `Nothing`、真なら `(just #f)`、偽なら `(just #t)`。
- `(tri=? maybe1 maybe2 ...)`: 3値の等価性検査。
- `(tri-and maybe ...)`: 1つでも偽なら `(just #f)`、1つでも `Nothing` があれば `Nothing`、すべて真なら最後の真。
- `(tri-or maybe ...)`: 1つでも真ならその真、1つでも `Nothing` があれば `Nothing`、すべて偽なら `(just #f)`。
- `(tri-merge maybe ...)`: 引数の中で最初の `Just` を返却。すべて `Nothing` なら `Nothing`。

#### H. 構文マクロ (Syntax Forms)
- `(maybe-if maybe-expr just-expr nothing-expr)`
- `(maybe-and expr ...)` / `(either-and expr ...)`
- `(maybe-or expr ...)` / `(either-or expr ...)`
- `(maybe-let* (claw ...) . body)`
- `(either-let* (claw ...) . body)`
- `(maybe-let*-values (claw ...) . body)`
- `(either-let*-values (claw ...) . body)`
- `(either-guard pred-expr . body)`

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/865-implement-srfi-189-maybe-and-either-optional-containers`

1. **コンテナ基盤と核心アルゴリズムの実装 (`ulisp/lib/maybe.scm`)**:
   - `define-record-type` による `<just>`, `<nothing>`, `<left>`, `<right>` 型定義とシングルトン `nothing-obj`。
   - ペイロード操作ヘルパー (`just-objs`, `left-objs`, `right-objs`) と多値バインディング (`call-with-values`)。
   - アクセサ、述語、`maybe=`, `either=`、`either-swap` の実装。
   - モナド合成器 (`maybe-compose`, `either-compose`) および `bind` / `join`。
   - シーケンス操作、全プロトコル変換手続き、マップ・フォールド・アンフォールド。
   - クレーネ 3 値論理関数群 (`tri-*`)。
   - `syntax-rules` による構文マクロ群 (`maybe-if`, `*-let*`, `*-and`, `*-or`, `either-guard`)。
2. **モジュール定義ファイルの作成 (`.sld`)**:
   - `ulisp/lib/srfi/189.sld`: `(srfi 189)` 完全エクスポート。Traceability ヘッダー付与。
   - `ulisp/lib/scheme/maybe.sld`: `(scheme maybe)` 完全エクスポート。Traceability ヘッダー付与。
3. **包括的ユニット・セキュリティテストスイート作成 (`ulisp/tests/test_srfi_189.scm`)**:
   - Group 1: 基本コンストラクタと排他述語 (`just`, `nothing`, `right`, `left`, `maybe?`, `either?`)
   - Group 2: 等価性判定 (`maybe=`, `either=`) およびスワップ (`either-swap`)
   - Group 3: アクセサとデフォルト値抽出 (`maybe-ref`, `maybe-ref/default`, `either-ref`, `either-ref/default`)
   - Group 4: モナド則・平坦化・合成 (`maybe-bind`, `either-bind`, `maybe-join`, `either-join`, `maybe-compose`, `either-compose`)
   - Group 5: シーケンス操作 (`length`, `filter`, `remove`, `sequence`)
   - Group 6: プロトコル相互変換 (リスト, 真偽値, 世代/EOF, 多値, 2値)
   - Group 7: 例外処理連携 (`exception->either`, `either-guard`)
   - Group 8: 高階反復 (`map`, `for-each`, `fold`, `unfold`)
   - Group 9: クレーネ 3 値論理 (`tri-not`, `tri=?`, `tri-and`, `tri-or`, `tri-merge`)
   - Group 10: 構文マクロと短絡評価 (`maybe-if`, `maybe-let*`, `either-let*`, `maybe-let*-values`, `either-let*-values`)
4. **ビルドシステム統合と品質ゲート検証**:
   - `ulisp/Makefile` の `ULISP_LARGE_LIBS` に `lib/maybe.scm` を追加。
   - `lint_sexpr` ターゲットに `lib/srfi/189.sld` と `lib/scheme/maybe.sld` を追加。
   - `test_srfi_189` ターゲットを新設。
   - `make -C ulisp test_srfi_189`, `make -C ulisp lint_sexpr`, `make -C ulisp test_lint_sexpr`, `make -C ulisp test_r7rs_traceability`, `make -C ulisp test` の全件 PASS を確認。
5. **ドキュメント更新**:
   - `ulisp/docs/ref_r7rs_compliance.md` の SRFI 189 ステータスを `◎` に更新。
   - Issue を `docs/issues/closed/` に移動し、`docs/issues/README.md` を完了状態へ反映。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `(scheme maybe)` および `(srfi 189)` の両ライブラリ仕様が定義され、全必須手続き・構文マクロがエクスポートされていること。
- [x] `Just`, `Nothing`, `Right`, `Left` が disjoint な不変レコード型として実装され、シングルトン `nothing-obj` が保証されていること。
- [x] 単一値のみならず、0個および複数個のペイロードオブジェクトを正常にカプセル化・展開できること。
- [x] モナド則（左単位元、右単位元、結合律）および短絡評価が正しく機能すること。
- [x] クレーネ 3 値論理 (`tri-and`, `tri-or`, `tri-not`, `tri=?`, `tri-merge`) が仕様通りに真偽・未知を処理すること。
- [x] `ulisp/tests/test_srfi_189.scm` の全テストケースが 100% PASS すること。
- [x] `make -C ulisp test_srfi_189` および `make -C ulisp test`（ブートストラップを含む全テスト）が PASS すること。
- [x] `make -C ulisp lint_sexpr`、`make -C ulisp test_lint_sexpr`、`make -C ulisp test_r7rs_traceability` が全件 PASS すること。
- [x] 絶対パス参照がゼロ件であること（相対パスのみ使用）。
- [x] `ulisp/docs/ref_r7rs_compliance.md` の SRFI 189 ステータスが `◎` に更新されていること。
- [x] Issue ファイルが `docs/issues/closed/865-implement-srfi-189-maybe-and-either-optional-containers.md` に移動され、`docs/issues/README.md` が更新されていること。
- [x] フィーチャーブランチ `feat/865-implement-srfi-189-maybe-and-either-optional-containers` が `main` にマージされていること。
