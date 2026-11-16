---
ID: 854
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] SRFI 101 純粋関数型ランダムアクセスリスト ((scheme rlist)) の実装 (ID: 854)

## 1. 概要 / Summary
R7RS-large (Red Edition) において規定される **SRFI 101 (Purely Functional Random-Access Pairs and Lists)** は、Chris Okasaki の Skew Binary Random-Access Lists に基づき、最悪計算量 $O(1)$ の先頭操作（`cons`, `car`, `cdr`）と $O(\log n)$ のランダムアクセス（`list-ref`, `list-set`, `list-ref/update`）を両立する不変（純粋関数型）データ構造仕様である。

現状の ULisp では、[ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1 において「× (未実装)」となっており、R7RS-large Red Edition のライブラリ宣言 `(scheme rlist)` および `(srfi 101)`（`.sld` ファイル群）が存在しない。また、標準リストと相互運用可能なランダムアクセスリスト基本手続き群（`ra-cons`, `ra-car`, `ra-cdr`, `ra-list-ref`, `ra-list-set`, `list->rlist`, `rlist->list` 等）が未実装である。

本 Issue では、SRFI 101 に規定される全手続き（全 50 種）および構文を完全実装し、R7RS-large Red Edition 準拠の `(scheme rlist)` および `(srfi 101)` モジュールを提供するとともに、厳密な境界値検査、Okasaki スキュー二分木アルゴリズム、および単体テストスイートを配備する。

---

## 2. トレーサビリティ / Traceability
- **関連仕様**:
  - R7RS-large Red Edition: `(scheme rlist)`
  - SRFI 101: Purely Functional Random-Access Pairs and Lists
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連 Issue**:
  - [Issue #648: SRFI 1 List Library](closed/648-implement-srfi-1-higher-order-list-procedures.md)
  - [Issue #710: SRFI 116 Immutable Lists and SRFI 134 Immutable Deques](closed/710-implement-srfi-116-immutable-lists-and-srfi-134-immutable-deques.md)
  - [Issue #853: SRFI 133 Vector Library and (scheme vector)](closed/853-implement-srfi-133-vector-library-and-scheme-vector-module.md)

---

## 3. 実装対象 API 一覧 / Target API Specification (全50種 + 構文)

### 3.1 Constructors (構築子)
1. `(cons obj1 obj2)` / `(ra-cons obj1 obj2)` : 先頭に要素を追加した新規ペアを生成。最悪計算量 $O(1)$。
2. `(list obj ...)` / `(ra-list obj ...)` : 与えられた要素群からなるランダムアクセスリストを生成。$O(k)$。
3. `(make-list k [obj])` / `(ra-make-list k [obj])` : 長さ $k$ のリストを生成（要素は $obj$、省略時は初期値）。$O(k)$。
4. `(quote datum)` / `(ra-quote datum)` : リテラルランダムアクセスリストを表現する構文。

### 3.2 Predicates (述語)
5. `(pair? obj)` / `(ra-pair? obj)` : オブジェクトがランダムアクセスペアか否かを判定。$O(1)$。
6. `(null? obj)` / `(ra-null? obj)` : 空リスト `'()` か否かを判定。$O(1)$。
7. `(list? obj)` / `(ra-list? obj)` : 適格なランダムアクセスリストか否かを判定。$O(k)$。
8. `(length<=? obj k)` / `(ra-length<=? obj k)` : `obj` が少なくとも $k$ 個のペアを持つか判定。$O(\log(\min(k, n)))$。

### 3.3 Selectors (セレクタ & 複合アクセサ 全30種)
9. `(car pair)` / `(ra-car pair)` : ペアの先頭要素を取得。最悪計算量 $O(1)$。
10. `(cdr pair)` / `(ra-cdr pair)` : ペアの後続リストを取得。最悪計算量 $O(1)$。
11. `(caar pair)` .. `(cddr pair)` : 2段複合アクセサ（全4種: `caar`, `cadr`, `cdar`, `cddr`）。
12. `(caaar pair)` .. `(cdddr pair)` : 3段複合アクセサ（全8種: `caaar`, `caadr`, `cadar`, `caddr`, `cdaar`, `cdadr`, `cddar`, `cdddr`）。
13. `(caaaar pair)` .. `(cddddr pair)` : 4段複合アクセサ（全16種: `caaaar` 〜 `cddddr`）。
14. `(list-ref pair k)` / `(ra-list-ref pair k)` : $k$ 番目の要素を取得。最悪計算量 $O(\log n)$。
15. `(list-tail pair k)` / `(ra-list-tail pair k)` : 先頭から $k$ 個スキップした残余ペアを取得。最悪計算量 $O(\log n)$。

### 3.4 Updaters (純粋関数型更新 全2種)
16. `(list-set pair k obj)` / `(ra-list-set pair k obj)` : $k$ 番目の要素を `obj` に置き換えた新規リストを生成（引数は不変、副作用なし）。最悪計算量 $O(\log n)$。
17. `(list-ref/update pair k proc)` / `(ra-list-ref/update pair k proc)` : $k$ 番目の要素 $v$ と、その要素に `(proc v)` を適用して置き換えた新規リストの2値を返却 `(values v updated-list)`。最悪計算量 $O(\log n)$。

### 3.5 Iteration & Higher-Order Procedures (反復・高階関数)
18. `(length list)` / `(ra-length list)` : リストの長さを取得。フォレスト各木の要素数の総和から $O(\log n)$。
19. `(append list ... obj)` / `(ra-append list ... obj)` : 複数のランダムアクセスリストを連結。
20. `(reverse list)` / `(ra-reverse list)` : リストの要素順を反転した新規リストを生成。$O(n)$。
21. `(map proc list1 list2 ...)` / `(ra-map proc list1 list2 ...)` : 各要素に `proc` を適用した結果からなる新規リストを生成（同木構造保持により効率的適用）。
22. `(for-each proc list1 list2 ...)` / `(ra-for-each proc list1 list2 ...)` : 各要素に副作用として `proc` を順次適用。

### 3.6 Conversion (相互変換 全4種)
23. `(random-access-list->linear-access-list ra-list)` : ランダムアクセスリストを標準線形リストに変換。
24. `(linear-access-list->random-access-list la-list)` : 標準線形リストをランダムアクセスリストに変換。
25. `(rlist->list ra-list)` : `random-access-list->linear-access-list` のエイリアス。
26. `(list->rlist la-list)` : `linear-access-list->random-access-list` のエイリアス。

---

## 4. アルゴリズムおよびデータ構造設計 (Okasaki Skew Binary Trees)

### 4.1 Skew Binary Number System と完全二分木フォレスト
- **スキュー二分表現 (Skew Binary Representation)**:
  - 任意の自然数は基数 $w_i = 2^{i+1} - 1$ ($1, 3, 7, 15, 31, \dots$) の重み付き和として一意に表現される（係数は $\{0, 1, 2\}$、値 $2$ を持つことができるのは最小重みの非ゼロ桁のみ）。
- **フォレスト構造**:
  - ランダムアクセスリストは完全二分木のフォレストとして表現される。
  - 各木 $T$ は要素数 $w = 2^{k+1}-1$ を持ち、根の値 $x$ と等しい大きさ $(w-1)/2$ の左右部分木を持つ。
  - リストヘッド `kons` は `(fields size tree rest)` を保持。
- **最悪計算量保証**:
  - `cons`: 先頭の2つの木のサイズが等しい場合、両者を左右部分木とし新しい要素を根とするサイズ $2w+1$ の木を生成して結合。等しくない場合はサイズ $1$ の木を追加。いずれも $O(1)$。
  - `car` / `cdr`: 先頭木の根を取り出し、サイズ $> 1$ の場合は左右の子（それぞれサイズ $(w-1)/2$）をフォレスト先頭に展開して復元。$O(1)$。
  - `list-ref` / `list-set`: 該当要素を含む木をフォレスト走査で特定（最大木数 $O(\log n)$）、特定した木内を二分探索降下（木高 $O(\log n)$）。合計最悪 $O(\log n)$。

### 4.2 ULisp における内部表現
ULisp のヒープオブジェクト表現と整合させるため、以下のタグ付きベクタを採用する:
```scheme
;; ペア / リストノード: #(ulisp-ra-pair-tag size tree rest)
(define (%make-ra-pair size tree rest) ...)

;; 木の内部節点: #(ulisp-ra-node-tag val left right)
(define (%make-ra-node val left right) ...)
```
- サイズ 1 の木の葉ノードは中間ラッパーなしで直接要素値を保持し、アロケーション負荷を最小化。
- `ra-pair?` はベクタ長 4 かつ第 0 要素が `'ulisp-ra-pair-tag` であるかを判定。

---

## 5. セキュリティおよび堅牢性設計 / Security & Robustness Design

### 5.1 メモリ境界外アクセス防止 (CWE-125 / CWE-787 Mitigation)
- **厳密なインデックス検査**:
  - `list-ref`, `list-set`, `list-ref/update`, `list-tail` において、インデックス $k$ が負数またはリスト長以上の場合は即座に安全なエラー（または境界違反ハンドリング）を送出し、未定義メモリ参照を防止。
- **不変性 (Immutability) の強制**:
  - すべての更新操作（`list-set`, `list-ref/update`）は元のデータ構造を変更せず、変更経路のノードのみを新たに生成（構造共有 / Path Copying）。マルチスレッド・並行環境下でのデータ競合を原理的に排除。

### 5.2 DoS / スタック枯渇対策 (CWE-400 Mitigation)
- **再帰深度の対数有界化**:
  - 木の探索・更新における再帰深度は最大でも完全二分木の高さ $\lceil \log_2(n+1) \rceil \le 64$ に厳密に制限され、スタックオーバーフローのリスクを排除。
- **フォレスト走査の末尾再帰化 (TCO)**:
  - 木のフォレスト走査（`length`, `list-tail`, `list->rlist`, `rlist->list`）は末尾呼び出し最適化（TCO）ループとして実装し、$O(1)$ スタックメモリを保証。
- **多引数関数の最小長同期**:
  - `map`, `for-each` において複数リストが渡された場合、長さ不一致による無限ループや未定義動作を防止。

---

## 6. 影響範囲と関連ファイル / Scope and Affected Files

### 6.1 実装ファイル
- `ulisp/lib/rlist.scm` (新規作成) : SRFI 101 全手続きのコア実装（Okasaki Skew Binary Trees）
- `ulisp/lib/scheme/rlist.sld` (新規作成) : `(scheme rlist)` R7RS-large ライブラリ定義
- `ulisp/lib/srfi/101.sld` (新規作成) : `(srfi 101)` R7RS ライブラリ定義

### 6.2 ビルド & ドキュメント
- `ulisp/Makefile` : `ULISP_LARGE_LIBS` への `lib/rlist.scm` 追加、`lint_sexpr` への登録、単体テストターゲット `test_srfi_101` の新設
- `ulisp/docs/ref_r7rs_compliance.md` : SRFI 101 のステータスを `×` から `◎` に更新

### 6.3 テストファイル
- `ulisp/tests/test_srfi_101.scm` (新規作成) : SRFI 101 全手続きの包括的テストスイート（正常系・境界値・不変性・大規模 10,000 要素ランダムアクセス・計算量特性）

---

## 7. 実装手順 / Implementation Plan

Target Branch: `feat/854-implement-srfi-101-purely-functional-random-access-lists`

- [x] **Step 1: コアデータ構造と基本プリミティブの実装 (`ulisp/lib/rlist.scm`)**
  - タグ付き表現（`ulisp-ra-pair-tag`, `ulisp-ra-node-tag`）、ビットシフト計算 `half`、`ra-cons` ($O(1)$)、`ra-car+cdr`、`ra-car`、`ra-cdr` の実装。
  - 全 28 種の cxr 複合アクセサ（`ra-caar` 〜 `ra-cddddr`）の配備。
- [x] **Step 2: ランダムアクセス・更新および高階関数の実装 (`ulisp/lib/rlist.scm`)**
  - `ra-list-ref` ($O(\log n)$)、`ra-list-tail` ($O(\log n)$)、`ra-list-set` ($O(\log n)$)、`ra-list-ref/update` ($O(\log n)$) の実装。
  - `ra-length<=?` ($O(\log(\min(k,n)))$)、`ra-length`、`ra-append`、`ra-reverse`、`ra-map`、`ra-for-each` の実装。
  - 相互変換 `linear-access-list->random-access-list` / `list->rlist`、`random-access-list->linear-access-list` / `rlist->list` の実装。
- [x] **Step 3: R7RS / SRFI ライブラリ定義の配備**
  - `ulisp/lib/scheme/rlist.sld` : `(scheme rlist)` モジュール定義
  - `ulisp/lib/srfi/101.sld` : `(srfi 101)` モジュール定義
  - Traceability ヘッダー規約（`Traceability: ulisp/docs/ref_r7rs_compliance.md`）の遵守。
- [x] **Step 4: 単体テストスイートの作成と Makefile 統合**
  - `ulisp/tests/test_srfi_101.scm` を作成し、基本操作、大規模リストアクセス（10,000 要素超）、不変性検証、境界値ケースを網羅。
  - `ulisp/Makefile` に `test_srfi_101` ターゲットを追加し、`ULISP_LARGE_LIBS` と `lint_sexpr` に登録。
- [x] **Step 5: 品質ゲート検証とドキュメント更新**
  - `make -C ulisp lint_sexpr` および `make -C ulisp test_r7rs_traceability` の 100% PASS を確認。
  - `make -C ulisp test_srfi_101` の実行および全 PASS 確認。
  - `ulisp/docs/ref_r7rs_compliance.md` の SRFI 101 ステータスを `◎` に更新。

---

## 8. 完了条件 / Definition of Done (DoD)
- [x] `ulisp/lib/rlist.scm` に SRFI 101 の全 50 種の手続きが完全実装されていること。
- [x] `cons`, `car`, `cdr` が最悪計算量 $O(1)$、`list-ref`, `list-set`, `list-ref/update` が $O(\log n)$ で動作すること。
- [x] `(scheme rlist)` および `(srfi 101)` が正常にインポート可能であること。
- [x] `ulisp/tests/test_srfi_101.scm` のテストケースがすべて PASS すること。
- [x] `make -C ulisp lint_sexpr` および `make -C ulisp test_r7rs_traceability` が正常に通過すること。
- [x] `ulisp/docs/ref_r7rs_compliance.md` が最新のステータスに更新されていること。
- [x] ドキュメント内のすべての内部リンクが相対パスで記述されていること。
