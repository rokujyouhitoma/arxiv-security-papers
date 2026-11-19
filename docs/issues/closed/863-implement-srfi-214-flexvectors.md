---
ID: 863
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] SRFI 214 動的可変長ベクタ ((scheme flexvector)) の実装 (ID: 863)

## 1. 概要 / Summary
R7RS-large Hypnos Docket においてシーケンス・コンテナ操作の標準として定められている **SRFI 214 (Flexvectors)** は、動的にサイズ拡張・縮小が可能な拡張ベクタ型（動的配列 / C++ `std::vector` / Java `ArrayList` 相当）を規定する。
Scheme 標準の固定長ベクタ (`vector`) は一度確保すると長さを変更できず、動的な要素蓄積・バッファリングにおいてはリストを用いた `reverse` 連鎖や都度の `vector-copy` による巨大なアロケーションオーバーヘッドが発生する。

SRFI 214 は、内部バッファの幾何学的倍加（Geometric Growth）により、末尾への $O(1)$ 償却挿入・削除 (`flexvector-add-back!`, `flexvector-remove-back!`)、両端キュー操作 (`flexvector-add-front!`, `flexvector-remove-front!`)、任意インデックスへの挿入・削除、部分スライス結合、高階反復、および検索・変換手続き群を提供する。

現行の ULisp においては未実装（`ref_r7rs_compliance.md` §2.4 において `×`）となっており、動的配列が必要なデータ処理やアルゴリズム記述において制限が生じている。
本 Issue では、純粋 Scheme による完全自律型 SRFI 214 実装を [ulisp/lib/flexvector.scm](../../ulisp/lib/flexvector.scm) に構築し、R7RS-large 標準モジュール `(scheme flexvector)` および `(srfi 214)` として提供する。

---

## 2. トレーサビリティ / Traceability
- **関連標準仕様**:
  - R7RS-large Hypnos Docket: `(scheme flexvector)`
  - SRFI 214: [Flexvectors](https://srfi.schemers.org/srfi-214/srfi-214.html) (by Adam Nelson)
  - SRFI 133: [Vector Library](https://srfi.schemers.org/srfi-133/srfi-133.html) (高階関数・探索セマンティクス参照)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.4 (Hypnos Docket 準拠状況: 400 行目)
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/flexvector.scm](../../ulisp/lib/flexvector.scm) (新規作成: レコード定義、幾何学的倍加バッファ管理、全 SRFI 214 手続き群)
- [x] [ulisp/lib/srfi/214.sld](../../ulisp/lib/srfi/214.sld) (新規作成: `(srfi 214)` ライブラリ定義、Traceability ヘッダー)
- [x] [ulisp/lib/scheme/flexvector.sld](../../ulisp/lib/scheme/flexvector.sld) (新規作成: `(scheme flexvector)` ライブラリ定義、Traceability ヘッダー)
- [x] [ulisp/tests/test_srfi_214.scm](../../ulisp/tests/test_srfi_214.scm) (新規作成: コンストラクタ、アクセサ、動的リサイズ、高階反復、探索、変換、境界値・セキュリティテスト)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`test_srfi_214` ターゲット追加、`lint_sexpr`、`test:` ターゲットへの登録)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (SRFI 214 準拠ステータスを `◎` に更新)
- [x] [docs/issues/README.md](README.md) (Issue 台帳更新: ステータス管理)

---

## 4. 仕様定義とアーキテクチャ設計 / Specification & Architecture Design

### 4.1 エクスポート識別子一覧 (SRFI 214 公式全手続き群)
SRFI 214 仕様に基づき、以下のカテゴリに属する全手続きをエクスポートする：

1. **コンストラクタ (Constructors)**:
   - `make-flexvector`: `(make-flexvector size [fill])` - 初期サイズと初期化値（省略時は未規定値）を持つ flexvector を作成。
   - `flexvector`: `(flexvector elt ...)` - 可変長引数から flexvector を生成。
   - `flexvector-unfold`: `(flexvector-unfold p f g seed ...)` - 述語 `p` が真になるまでシードから生成器 `f` と遷移関数 `g` により左から右へ要素を蓄積。
   - `flexvector-unfold-right`: `(flexvector-unfold-right p f g seed ...)` - 右から左へ要素を蓄積。
   - `flexvector-copy`: `(flexvector-copy fv [start [end]])` - 部分範囲 `[start, end)` の浅いコピーを生成。
   - `flexvector-reverse-copy`: `(flexvector-reverse-copy fv [start [end]])` - 部分範囲を逆順にコピー。
   - `flexvector-append`: `(flexvector-append fv ...)` - 複数の flexvector を結合した新規 flexvector を返却。
   - `flexvector-concatenate`: `(flexvector-concatenate list-of-fvs)` - リスト形式の複数 flexvector を結合。
   - `flexvector-append-subvectors`: `(flexvector-append-subvectors fv1 start1 end1 ...)` - 各 flexvector の任意部分範囲を切り出して結合。

2. **述語 (Predicates)**:
   - `flexvector?`: オブジェクトが flexvector であるかを判定する述語。
   - `flexvector-empty?`: 長さが 0 であるかを判定。
   - `flexvector=?`: `(flexvector=? elt=? fv ...)` - 指定された要素等価性述語 `elt=?` を用いて等価性を判定。

3. **セレクタ・要素参照 (Selectors)**:
   - `flexvector-ref`: `(flexvector-ref fv i)` - インデックス `i` の要素を取得（範囲外検査）。
   - `flexvector-front`: `(flexvector-front fv)` - 先頭要素 (`index 0`) を取得（空の場合はエラー）。
   - `flexvector-back`: `(flexvector-back fv)` - 末尾要素 (`index (- len 1)`) を取得（空の場合はエラー）。
   - `flexvector-length`: `(flexvector-length fv)` - 現在の論理要素数を取得。

4. **固定長ミューテータ (Fixed-size Mutators)**:
   - `flexvector-set!`: `(flexvector-set! fv i val)` - 指定位置の要素を破壊的更新。
   - `flexvector-swap!`: `(flexvector-swap! fv i j)` - インデックス `i` と `j` の要素を交換。
   - `flexvector-fill!`: `(flexvector-fill! fv fill [start [end]])` - 範囲 `[start, end)` を指定値で埋める。
   - `flexvector-reverse!`: `(flexvector-reverse! fv [start [end]])` - 範囲 `[start, end)` を反転。
   - `flexvector-copy!`: `(flexvector-copy! to at from [start [end]])` - `from` の範囲を `to` の `at` へ上書きコピー。
   - `flexvector-reverse-copy!`: `(flexvector-reverse-copy! to at from [start [end]])` - 逆順に上書きコピー。

5. **可変長ミューテータ (Variable-size / Dynamic Mutators)**:
   - `flexvector-add!`: `(flexvector-add! fv i val ...)` - インデックス `i` に 1 つ以上の要素を挿入し、後続要素を右シフト。
   - `flexvector-add-front!`: `(flexvector-add-front! fv val ...)` - 先頭へ挿入。
   - `flexvector-add-back!`: `(flexvector-add-back! fv val ...)` - 末尾へ追加（償却 $O(1)$）。
   - `flexvector-remove!`: `(flexvector-remove! fv i)` - インデックス `i` の要素を削除してその値を返却し、後続要素を左シフト。
   - `flexvector-remove-front!`: `(flexvector-remove-front! fv)` - 先頭要素を削除して返却。
   - `flexvector-remove-back!`: `(flexvector-remove-back! fv)` - 末尾要素を削除して返却（償却 $O(1)$）。
   - `flexvector-remove-range!`: `(flexvector-remove-range! fv start [end])` - 部分範囲 `[start, end)` を一括削除。
   - `flexvector-clear!`: `(flexvector-clear! fv)` - 全要素をクリア（長さを 0 にリセット）。
   - `flexvector-trim!`: `(flexvector-trim! fv)` - 内部バッファ容量を現在の長さ `len` まで切り詰め、余剰メモリを解放。
   - `flexvector-set-length!`: `(flexvector-set-length! fv new-len [fill])` - 論理長を変更（拡大時は `fill` で埋め、縮小時は切り捨て）。
   - `flexvector-append!`: `(flexvector-append! fv other ...)` - 他の flexvector の要素を破壊的に末尾へ追加。

6. **反復・高階関数 (Iteration & Higher-Order)**:
   - `flexvector-fold`, `flexvector-fold-right`: 複数 flexvector 対応の左／右畳み込み。
   - `flexvector-map`, `flexvector-map!`: 射影変換（純粋返却およびインプレース更新）。
   - `flexvector-map/index`, `flexvector-map/index!`: インデックス付き射影変換。
   - `flexvector-append-map`, `flexvector-append-map/index`: 射影結果（flexvector）を連結。
   - `flexvector-for-each`, `flexvector-for-each/index`: 副作用走査。
   - `flexvector-filter`, `flexvector-filter!`: 述語によるフィルタリング（新規生成およびインプレース）。
   - `flexvector-filter/index`, `flexvector-filter/index!`: インデックス付きフィルタリング。
   - `flexvector-remove`: 述語を満たす要素を除外した新規 flexvector を返却。
   - `flexvector-count`: 述語を満たす要素数をカウント。
   - `flexvector-cumulate`: 累積スキャン（prefix sum）。
   - `flexvector-partition`: 述語による 2 分割（2 つの値を返却）。

7. **探索 (Searching)**:
   - `flexvector-index`, `flexvector-index-right`: 述語を満たす最初の／最後のインデックスを探索（見つからない場合は `#f`）。
   - `flexvector-skip`, `flexvector-skip-right`: 述語を満たさない最初の／最後のインデックスを探索。
   - `flexvector-binary-search`: ソート済み flexvector に対する二分探索。
   - `flexvector-any`: いずれかの要素が述語を満たすか判定（最後の真値を返却）。
   - `flexvector-every`: 全要素が述語を満たすか判定。

8. **相互変換 (Conversions)**:
   - `vector->flexvector`, `flexvector->vector`: Scheme ベクタとの相互変換。
   - `list->flexvector`, `reverse-list->flexvector`: リストからの変換。
   - `flexvector->list`, `reverse-flexvector->list`: リストへの変換。
   - `generator->flexvector`: SRFI 158 / R7RS ジェネレータからの変換。
   - `flexvector->generator`: flexvector を順次読み出すジェネレータの生成。

---

### 4.2 内部レコード設計と幾何学的倍加アルゴリズム
1. **内部データ構造**:
   - `(define-record-type :flexvector ...)` を用いてカプセル化：
     ```scheme
     (define-record-type <flexvector>
       (%make-raw-flexvector vec len)
       flexvector?
       (vec %flexvector-vec %flexvector-vec-set!)
       (len %flexvector-len %flexvector-len-set!))
     ```
   - `vec`: 内部固定長 Scheme ベクタバッファ（容量 = `(vector-length vec)`）。
   - `len`: 有効要素数（論理長、`0 <= len <= capacity`）。
2. **容量拡張ポリシー (Geometric Doubling)**:
   - 初期容量: デフォルト `4`（または指定サイズ）。
   - 要素追加時に `len + k > capacity` となる場合、新容量を `(max (+ len k) (max 4 (* 2 capacity)))` として新規バッファをアロケートし、既存要素をコピー。
   - これにより、連続した `flexvector-add-back!` 操作の償却計算量は厳格に $O(1)$ を維持する。
3. **メモリ回収と切り詰め (`flexvector-trim!`)**:
   - 不要になった余剰バッファ領域を `(vector-copy vec 0 len)` により現在の長さへ再アロケートし、ガベージコレクションを支援。

---

### 4.3 セキュリティ脅威分析と対策 (Threat Model & Mitigations)

| 脅威 ID | 脅威分類 (CWE) | 脅威シナリオ | 具体的防御策 (Mitigation) |
| :--- | :--- | :--- | :--- |
| **THREAT-863-1** | **CWE-400 / CWE-770**<br>Uncontrolled Resource Consumption via Unbounded Growth | 巨大なサイズ指定 (`(make-flexvector 1000000000000)`) や悪意ある無限ループによる `add-back!` 呼び出しによるメモリ枯渇 (OOM)。 | 負のサイズ指定を拒絶する厳格な型・範囲検証を実装。また `make-vector` のランタイム制限と連携し、異常な割り当て要求に対しては明確な `error` を送出する。 |
| **THREAT-863-2** | **CWE-125 / CWE-787**<br>Out-of-Bounds Indexing & Buffer Underflow/Overflow | `(flexvector-ref fv -1)` や `(flexvector-ref fv (flexvector-length fv))`、`flexvector-add!` / `remove!` での範囲外インデックス指定による未定義動作・情報漏洩。 | 全アクセサ・ミューテータにおいて `0 <= i < len`（挿入時は `0 <= i <= len`）の境界チェックを徹底し、境界外アクセスは即座に `error` を送出する。 |
| **THREAT-863-3** | **CWE-843**<br>Type Confusion on Non-Flexvector Arguments | 他のオブジェクト型（通常の `vector`, `list`, `pair`）を flexvector 手続きに渡し、内部スロット破壊やクラッシュを引き起こす攻撃。 | `%ensure-flexvector` ガード手続きを配備し、全公開 API のエントリポイントで `flexvector?` を検証して型安全性を保証する。 |
| **THREAT-863-4** | **CWE-674 / CWE-835**<br>Uncontrolled Iteration on Malformed Generators | 停止しない無限ジェネレータや循環構造を `generator->flexvector` や `flexvector-unfold` に与えた場合の無限ループ・ハング。 | ジェネレータが `eof-object` を返却するまで、または停止述語 `p` が満たされるまで反復する標準規則を遵守。 |

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/863-implement-srfi-214-flexvectors`

1. **基本基盤とレコード定義 (`ulisp/lib/flexvector.scm`)**:
   - `define-record-type` による `<flexvector>` 型定義と内部アクセサの実装。
   - 引数検証ユーティリティ (`%ensure-flexvector`, `%ensure-index`, `%ensure-valid-range`) の整備。
   - 容量拡張ヘルパー (`%flexvector-ensure-capacity!`) の実装。
2. **コンストラクタ・述語・基本セレクタの実装**:
   - `make-flexvector`, `flexvector`, `flexvector-unfold`, `flexvector-unfold-right`, `flexvector-copy`, `flexvector-reverse-copy`, `flexvector-append`, `flexvector-concatenate`, `flexvector-append-subvectors`。
   - `flexvector?`, `flexvector-empty?`, `flexvector=?`。
   - `flexvector-ref`, `flexvector-front`, `flexvector-back`, `flexvector-length`。
3. **固定長・可変長ミューテータの実装**:
   - `flexvector-set!`, `flexvector-swap!`, `flexvector-fill!`, `flexvector-reverse!`, `flexvector-copy!`, `flexvector-reverse-copy!`。
   - `flexvector-add!`, `flexvector-add-front!`, `flexvector-add-back!`。
   - `flexvector-remove!`, `flexvector-remove-front!`, `flexvector-remove-back!`, `flexvector-remove-range!`。
   - `flexvector-clear!`, `flexvector-trim!`, `flexvector-set-length!`, `flexvector-append!`。
4. **高階反復・探索・相互変換手続きの実装**:
   - `flexvector-fold`, `flexvector-fold-right`, `flexvector-map`, `flexvector-map!`, `flexvector-map/index`, `flexvector-map/index!`。
   - `flexvector-for-each`, `flexvector-for-each/index`, `flexvector-append-map`, `flexvector-append-map/index`。
   - `flexvector-filter`, `flexvector-filter!`, `flexvector-filter/index`, `flexvector-filter/index!`, `flexvector-remove`, `flexvector-count`, `flexvector-cumulate`, `flexvector-partition`。
   - `flexvector-index`, `flexvector-index-right`, `flexvector-skip`, `flexvector-skip-right`, `flexvector-binary-search`, `flexvector-any`, `flexvector-every`。
   - `vector->flexvector`, `flexvector->vector`, `list->flexvector`, `reverse-list->flexvector`, `flexvector->list`, `reverse-flexvector->list`, `generator->flexvector`, `flexvector->generator`。
5. **モジュール定義ファイル (`.sld`) の配備**:
   - `ulisp/lib/srfi/214.sld`: `(srfi 214)` ライブラリ定義。
   - `ulisp/lib/scheme/flexvector.sld`: `(scheme flexvector)` ライブラリ定義。
   - Traceability ヘッダー (`;;; Traceability: ulisp/docs/ref_r7rs_compliance.md`) の付与。
6. **包括的テストスイートの構築 (`ulisp/tests/test_srfi_214.scm`)**:
   - Group 1: コンストラクタと基本述語 (`make-flexvector`, `flexvector`, `flexvector?`, `flexvector-empty?`)
   - Group 2: 要素参照と固定長変更 (`ref`, `set!`, `swap!`, `fill!`, `reverse!`, `front`, `back`)
   - Group 3: 動的変更（追加・削除・トリム）(`add-back!`, `add-front!`, `add!`, `remove-back!`, `remove-front!`, `remove!`, `remove-range!`, `trim!`, `set-length!`, `append!`)
   - Group 4: コピー・連結・サブベクタ (`copy`, `reverse-copy`, `append`, `concatenate`, `append-subvectors`)
   - Group 5: 高階関数と反復 (`fold`, `fold-right`, `map`, `map!`, `for-each`, `filter`, `filter!`, `remove`, `count`, `partition`, `cumulate`)
   - Group 6: 探索アルゴリズム (`index`, `index-right`, `skip`, `skip-right`, `binary-search`, `any`, `every`)
   - Group 7: 相互変換 (`vector->flexvector`, `flexvector->vector`, `list->flexvector`, `flexvector->list`, `generator` 連携)
   - Group 8: セキュリティ境界・異常系テスト (インデックス範囲外例外、空ベクタ front/back 例外、型エラー検証)
7. **ビルドシステム統合と品質検証**:
   - `ulisp/Makefile` への `test_srfi_214` ターゲット追加および `test:` への登録。
   - `make -C ulisp test_srfi_214` および `make -C ulisp test` の全 PASS。
   - `ulisp/docs/ref_r7rs_compliance.md` の SRFI 214 ステータスを `◎` に更新。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `(scheme flexvector)` および `(srfi 214)` がエクスポートされ、全仕様手続きが利用可能であること。
- [x] 幾何学的倍加により `flexvector-add-back!` および `flexvector-remove-back!` が $O(1)$ 償却計算量で高速動作すること。
- [x] 境界値・インデックス範囲外・型不整合に対する堅牢な例外送出が行われること。
- [x] `ulisp/tests/test_srfi_214.scm` が新規作成され、全テストケースが 100% PASS すること。
- [x] `ulisp/Makefile` に `test_srfi_214` が追加され、`make -C ulisp test` で自動実行されること。
- [x] `ulisp/docs/ref_r7rs_compliance.md` の SRFI 214 ステータスが `◎` に更新されていること。
- [x] すべてのファイル内リンクが相対パスで記述され、絶対パスが 0 件であること。
