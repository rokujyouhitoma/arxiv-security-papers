---
ID: 853
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] SRFI 133 ベクタ操作ライブラリおよび (scheme vector) モジュールの完全実装 (ID: 853)

## 1. 概要 / Summary
R7RS-large (Red Edition) において中核データ構造仕様として定められている **SRFI 133 (Vector Library / R7RS-compatible)** は、先行する SRFI 43 の改善版であり、ベクタの生成、展開、畳み込み、述語、探索（二分探索含む）、反転、変換等の包括的な高階関数 API（全40種の手続き）を規定する。

現状の ULisp では、基礎的なベクタ操作（`make-vector`, `vector-ref`, `vector-set!`, `vector-length`）および R7RS-small §6.8 相当の一部手続き（`vector-copy`, `vector-copy!`, `vector-append`, `vector->list`, `list->vector`）が `ulisp/lib/vector.scm` に存在するものの、SRFI 133 / `(scheme vector)` の要件を満たす高階関数群（`vector-unfold`, `vector-fold`, `vector-binary-search`, `vector-partition`, `vector-swap!`, `vector-cumulate` 等）や複数ベクタの並列イテレーション、部分スライス反転コピーが未整備である。また、R7RS ライブラリ宣言である `(scheme vector)` および `(srfi 133)`（`.sld` ファイル）が存在しない。

本 Issue では、SRFI 133 に規定される全手続きを完全実装し、R7RS-large Red Edition 準拠の `(scheme vector)` および `(srfi 133)` モジュールを提供するとともに、厳密な境界値検査と単体テストスイートを配備する。

---

## 2. トレーサビリティ / Traceability
- **関連仕様**:
  - R7RS-large Red Edition: `(scheme vector)`
  - SRFI 133: Vector Library (R7RS-compatible)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連 Issue**:
  - [Issue #536: R7RS vector operations](../../docs/issues/closed/536-implement-r7rs-vector-operations.md)
  - [Issue #648: SRFI 1 List Library](../../docs/issues/closed/648-implement-srfi-1-higher-order-list-procedures.md)
  - [Issue #710: SRFI 116 / SRFI 134 Immutable Data Structures](../../docs/issues/closed/710-implement-srfi-116-immutable-lists-and-srfi-134-immutable-deques.md)

---

## 3. 実装対象 API 一覧 / Target API Specification (全40種)

### 3.1 Constructors (構築子)
1. `(make-vector size [fill])` : 長さ `size` のベクタを生成（オプションで `fill` 初期値）。
2. `(vector elt ...)` : 与えられた要素を含む新規ベクタを生成。
3. `(vector-unfold f length seed ...)` : シード値群からインデックス `0` 〜 `length-1` まで `f` を順次適用して新規ベクタを構築。`f` は `(f i seed ...)` を評価し、`(values elt next-seed ...)` を返却。
4. `(vector-unfold-right f length seed ...)` : インデックス `length-1` から `0` に向けて逆順に評価・構築。
5. `(vector-copy vec [start [end]])` : `vec` の指定区間 `[start, end)` のコピーを新規ベクタとして返却。
6. `(vector-reverse-copy vec [start [end]])` : 指定区間 `[start, end)` の要素を逆順にしたコピーを新規生成。
7. `(vector-append vec ...)` : 複数ベクタを連結した新規ベクタを生成。
8. `(vector-concatenate list-of-vectors)` : ベクタのリストを単一ベクタに平坦化連結。
9. `(vector-append-subvectors [vec start end] ...)` : 複数ベクタの各指定区間を連結した新規ベクタを生成。

### 3.2 Predicates (述語)
10. `(vector? obj)` : オブジェクトがベクタか否かを判定。
11. `(vector-empty? vec)` : ベクタの長さが `0` か否かを判定。
12. `(vector= elt=? vec ...)` : 要素比較述語 `elt=?` を用いて、すべてのベクタの長さおよび各要素が等しいかを判定。引数0個または1個の場合は `#t`。

### 3.3 Selectors (セレクタ)
13. `(vector-ref vec i)` : インデックス `i` の要素を取得。
14. `(vector-length vec)` : ベクタの長さを取得。

### 3.4 Iteration (反復・高階関数)
15. `(vector-fold kons knil vec1 vec2 ...)` : 左から右への畳み込み。`(kons state elt1 elt2 ...)` を各要素に対して評価。複数ベクタの場合は最短長で終了。TCO による $O(1)$ スタック保証。
16. `(vector-fold-right kons knil vec1 vec2 ...)` : 右から左への畳み込み。
17. `(vector-map f vec1 vec2 ...)` : 各要素に `(f elt1 elt2 ...)` を適用した結果からなる新規ベクタを生成（複数ベクタ並列適用対応、最短長で終了）。
18. `(vector-map! f target vec1 vec2 ...)` : `target` ベクタをインプレースで更新（各インデックスに `(f elt1 elt2 ...)` を代入）。
19. `(vector-for-each f vec1 vec2 ...)` : 各要素に副作用として `(f elt1 elt2 ...)` を適用。
20. `(vector-count pred? vec1 vec2 ...)` : `pred?` が真を返す要素組の総数をカウント。
21. `(vector-cumulate f knil vec)` : 前置累積和（running accumulations）からなる同一長の新規ベクタを生成。`i` 番目の要素は `(f acc_i-1 (vector-ref vec i))`。

### 3.5 Searching (探索・条件分岐)
22. `(vector-index pred? vec1 vec2 ...)` : `pred?` を満たす最初のインデックス（左から走査）を返却（存在しない場合は `#f`）。
23. `(vector-index-right pred? vec1 vec2 ...)` : `pred?` を満たす最初のインデックス（右から走査）を返却（存在しない場合は `#f`）。
24. `(vector-skip pred? vec1 vec2 ...)` : `pred?` を満たさない（偽となる）最初のインデックス（左から走査）を返却。
25. `(vector-skip-right pred? vec1 vec2 ...)` : `pred?` を満たさない最初のインデックス（右から走査）を返却。
26. `(vector-binary-search vec value cmp [start [end]])` : ソート済みベクタ `vec` の区間 `[start, end)` から、三値比較関数 `(cmp a b)` （負、0、正）を用いて `value` を二分探索。見つかった場合はインデックス、見つからなかった場合は `#f` を返却。
27. `(vector-any pred? vec1 vec2 ...)` : 左から右へ評価し、`pred?` が最初に真値を返した時点でその値を返却（真となるものがなければ `#f`）。
28. `(vector-every pred? vec1 vec2 ...)` : すべての要素組で `pred?` が真であるかを検証。最後の真値（空の場合は `#t`）を返却。途中で `#f` になれば即座に `#f` を返却。
29. `(vector-partition pred? vec)` : `pred?` を満たす要素群を前方に、満たさない要素群を後方に集約した新規ベクタと、満たす要素数を多値 `(values new-vec count)` として返却。

### 3.6 Mutators (破壊的変更・インプレース操作)
30. `(vector-set! vec i val)` : インデックス `i` に `val` を代入。
31. `(vector-swap! vec i j)` : インデックス `i` と `j` の要素を入れ替え。
32. `(vector-fill! vec fill [start [end]])` : 区間 `[start, end)` の全要素を `fill` で上書き。
33. `(vector-reverse! vec [start [end]])` : 区間 `[start, end)` の要素順をインプレースで反転。
34. `(vector-copy! target tstart source [sstart [send]])` : `source` の区間 `[sstart, send)` を `target` の `tstart` 以降にコピー。同一ベクタの重複領域にも安全に対応。
35. `(vector-reverse-copy! target tstart source [sstart [send]])` : `source` の指定区間を逆順に `target` の `tstart` 以降にインプレースコピー。同一ベクタの重複領域にも安全に対応。
36. `(vector-unfold! f target start end seed ...)` : `target` の区間 `[start, end)` を `f` の展開結果でインプレース上書き。
37. `(vector-unfold-right! f target start end seed ...)` : `target` の区間 `[start, end)` を逆順（`end-1` から `start`）に `f` でインプレース上書き。

### 3.7 Conversion (相互変換)
38. `(vector->list vec [start [end]])` : 区間 `[start, end)` からリストを生成。
39. `(reverse-vector->list vec [start [end]])` : 区間 `[start, end)` の要素を逆順にしたリストを生成。
40. `(list->vector list [start [end]])` : リストの指定区間からベクタを生成。
41. `(reverse-list->vector list [start [end]])` : リストの指定区間を逆順にしたベクタを生成。
42. `(string->vector str [start [end]])` : 文字列の指定区間から文字ベクタを生成。
43. `(vector->string vec [start [end]])` : 文字ベクタの指定区間から文字列を生成。

---

## 4. セキュリティおよび堅牢性設計 / Security & Robustness Design

### 4.1 メモリ境界外アクセス防止 (CWE-125 / CWE-787 Mitigation)
- **インデックス境界事前検証**:
  - `start`, `end`, `tstart`, `sstart`, `send` などの区間引数について、`0 <= start <= end <= (vector-length vec)` の不変条件を厳密に検査。
  - 不正な負数や範囲外アクセスに対しては安全にエラー通知または保護を行う。
- **重複スライスコピーの安全転送 (Overlapping Aliasing)**:
  - `vector-copy!`: `target == source` かつ `tstart > sstart` の場合は後方からコピー、それ以外は前方からコピーすることでメモリ破壊・値の自己破壊（clobbering）を完全防止。
  - `vector-reverse-copy!`: 同一ベクタ内の一時領域退避または非干渉インデックス順序での安全な反転書き込みアルゴリズムを採用。
- **二分探索のオーバーフロー回避**:
  - `vector-binary-search` の中央インデックス計算において、`mid = start + (quotient (- end start) 2)` を用いることで整数オーバーフローを構造的に回避。

### 4.2 DoS / リソース枯渇対策 (CWE-400 Mitigation)
- **無限ループおよびスタックオーバーフロー防止**:
  - すべての反復（fold, unfold, map, for-each, index, any, every）は末尾再帰（TCO）ループとして実装し、$O(1)$ スタックメモリを保証。
  - 複数ベクタ引数を受け取る手続き（`vector-map`, `vector-for-each`, `vector-fold`, `vector-index` 等）では、各ベクタの最小長（minimum length）を基準とすることで、長さ不一致ベクタ入力時の境界外参照や無限反復を防止。

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

### 5.1 実装ファイル
- `ulisp/lib/vector.scm` : SRFI 133 全手続きの実装および R7RS §6.8 拡張
- `ulisp/lib/scheme/vector.sld` (新規作成) : `(scheme vector)` R7RS-large ライブラリ定義
- `ulisp/lib/srfi/133.sld` (新規作成) : `(srfi 133)` R7RS ライブラリ定義

### 5.2 テストファイル
- `ulisp/tests/test_srfi_133.scm` (新規作成) : SRFI 133 全40種の手続きの包括的テストスイート（正常系・境界値・重複領域コピー・多引数並列処理・二分探索）

### 5.3 ビルド・品質・ドキュメント設定
- `ulisp/Makefile` :
  - `test_srfi_133` ターゲットの新設
  - `test` ターゲットへの登録
  - `scripts/lint_sexpr.py` 検査対象への `lib/scheme/vector.sld`, `lib/srfi/133.sld`, `tests/test_srfi_133.scm` 追加
- `ulisp/docs/ref_r7rs_compliance.md` : SRFI 133 および `(scheme vector)` の適合性ステータスを更新

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/853-implement-srfi-133-vector-library-and-scheme-vector-module`

### Step 1: `ulisp/lib/vector.scm` の拡張
1. **補完ヘルパー関数の整備**:
   - 区間正規化ヘルパー: `vector-normalize-range`（デフォルト値 `start=0`, `end=len` の補完と境界チェック）
   - 複数ベクタ最短長算出: `vectors-min-length`
2. **Constructors**:
   - `vector-unfold`, `vector-unfold-right`, `vector-reverse-copy`, `vector-concatenate`, `vector-append-subvectors` の実装。
3. **Predicates & Selectors**:
   - `vector-empty?`, `vector=` の実装。
4. **Iteration**:
   - `vector-fold`, `vector-fold-right`, `vector-map` (多引数化), `vector-map!`, `vector-for-each` (多引数化), `vector-count`, `vector-cumulate` の実装。
5. **Searching**:
   - `vector-index`, `vector-index-right`, `vector-skip`, `vector-skip-right`, `vector-binary-search`, `vector-any`, `vector-every`, `vector-partition` の実装。
6. **Mutators**:
   - `vector-swap!`, `vector-reverse!`, `vector-reverse-copy!`, `vector-unfold!`, `vector-unfold-right!` の実装。
7. **Conversion**:
   - `reverse-vector->list`, `reverse-list->vector` の実装。

### Step 2: ライブラリ宣言の作成
1. `ulisp/lib/scheme/vector.sld`:
   - `(define-library (scheme vector) ...)` を定義。SRFI 133 の全シンボルを export。
2. `ulisp/lib/srfi/133.sld`:
   - `(define-library (srfi 133) ...)` を定義。`(import (scheme vector))` を re-export または直接 include。

### Step 3: 単体テストスイート `ulisp/tests/test_srfi_133.scm` の作成
- 全手続き群についてグループ別の網羅的アサーションを実装:
  - Group 1: Constructors (unfold, unfold-right, reverse-copy, concatenate, append-subvectors)
  - Group 2: Predicates (vector-empty?, vector=)
  - Group 3: Iteration (fold, fold-right, multi-vector map/map!, for-each, count, cumulate)
  - Group 4: Searching (index, index-right, skip, skip-right, binary-search, any, every, partition)
  - Group 5: Mutators (swap!, reverse!, reverse-copy!, unfold!, unfold-right!, 重複領域 copy!)
  - Group 6: Conversion (reverse-vector->list, reverse-list->vector)

### Step 4: ビルドシステム統合と静的解析検証
1. `ulisp/Makefile` に `test_srfi_133` を追加し、`test` ターゲットに結合。
2. `scripts/lint_sexpr.py` に新規 S 式ファイルを登録し、S 式インデント・構文エラー 0 件を検証。
3. `make -C ulisp test_srfi_133` および `make -C ulisp test` を実行し、全件 PASS を確認。

### Step 5: ドキュメント更新
- `ulisp/docs/ref_r7rs_compliance.md` の SRFI 133 / `(scheme vector)` の記述を最新状態に更新。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] SRFI 133 規定の全40種の手続きが `ulisp/lib/vector.scm` に実装されていること。
- [x] `(scheme vector)` および `(srfi 133)` の `.sld` ライブラリ宣言から全シンボルが正常にエクスポート可能であること。
- [x] `vector-copy!` および `vector-reverse-copy!` が同一ベクタの重複領域に対してもメモリ破壊なく正しく動作すること。
- [x] `vector-binary-search` が境界値（空ベクタ、先頭、末尾、不一致要素）において正確なインデックスまたは `#f` を返却すること。
- [x] `vector-fold`, `vector-unfold`, `vector-partition`, `vector-cumulate` 等の高階関数が $O(1)$ スタックメモリで安全に動作すること。
- [x] 新規テストスイート `ulisp/tests/test_srfi_133.scm` が作成され、`make -C ulisp test_srfi_133` が全件 PASS すること。
- [x] `python scripts/lint_sexpr.py` の S 式構文検証が 0 警告 / 0 エラーで PASS すること。
- [x] `make -C ulisp test` の全体回帰テストが PASS すること。
- [x] `ulisp/docs/ref_r7rs_compliance.md` が最新仕様に更新されていること。
