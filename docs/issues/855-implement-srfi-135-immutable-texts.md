---
ID: 855
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] SRFI 135 不変テキストライブラリ ((scheme text)) の実装 (ID: 855)

## 1. 概要 / Summary
R7RS-large (Red Edition) において規定される **SRFI 135 (Immutable Texts)** は、不変（Immutable）な文字シーケンスデータ型である **text** および標準文字列（string）との統合概念である **textual** を定義し、最悪計算量 $O(1)$ の文字ランダムアクセス（`text-ref`）、$O(1)$ の部分テキストスライシング（`subtext`, `subtextual`）、および効率的な構造共有（Structural Sharing）を保証する規格である。

従来の Scheme 標準文字列（`string`）は可変（Mutable）であり、部分文字列の抽出（`substring`）や文字列連結（`string-append`）を行うたびに新規バッファの確保と全文字コピーが発生する。また、並行・並列実行環境における競合やコンパイラ最適化の阻害要因となっていた。

現状の ULisp では、[ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1 において「× (未実装)」となっており、R7RS-large Red Edition のライブラリ宣言 `(scheme text)` および `(srfi 135)`（`.sld` ファイル群）が存在しない。また、木構造（Rope / Chunked text）に基づく不変テキスト基本手続き群、選択・置換・比較・接頭辞接尾辞・探索・大文字小文字変換・畳み込み・写像・反復分割・UTF 変換手続き群（全 82 種）が未実装である。

本 Issue では、SRFI 135 に規定される全 82 種の手続きおよび R7RS-large Red Edition 準拠の `(scheme text)` および `(srfi 135)` モジュールを完全実装し、厳密な境界値検査、二分木・スライス構造共有アルゴリズム、および単体テストスイートを配備する。

---

## 2. トレーサビリティ / Traceability
- **関連仕様**:
  - R7RS-large Red Edition: `(scheme text)`
  - SRFI 135: Immutable Texts (William D. Clinger)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連 Issue**:
  - [Issue #648: SRFI 1 List Library](closed/648-implement-srfi-1-higher-order-list-procedures.md)
  - [Issue #701: SRFI 128 Comparators](closed/701-implement-srfi-128-comparators.md)
  - [Issue #710: SRFI 116 Immutable Lists and SRFI 134 Immutable Deques](closed/710-implement-srfi-116-immutable-lists-and-srfi-134-immutable-deques.md)
  - [Issue #853: SRFI 133 Vector Library and (scheme vector)](closed/853-implement-srfi-133-vector-library-and-scheme-vector-module.md)
  - [Issue #854: SRFI 101 Purely Functional Random-Access Lists](closed/854-implement-srfi-101-purely-functional-random-access-lists.md)

---

## 3. 実装対象 API 一覧 / Target API Specification (全 82 種)

SRFI 135 では、対象オブジェクトの型規則として以下の 2 系統が定義される:
- **`text`**: SRFI 135 にて導入される不変テキストオブジェクト（`text?` が `#t`、標準 `string?` とは排他）。
- **`textual`**: 不変テキストまたは標準 Scheme 文字列（`string`）のいずれかを表す共用型（`textual?` が `#t`）。

### 3.1 Predicates (述語 全 5 種)
1. `(text? obj)` : `obj` が不変テキスト型であれば `#t`、そうでなければ `#f` を返却。
2. `(textual? obj)` : `obj` が不変テキストまたは文字列であれば `#t`、そうでなければ `#f` を返却。
3. `(textual-null? textual)` : `textual` の文字長が 0 であれば `#t`、そうでなければ `#f` を返却。
4. `(textual-every pred textual [start [end]])` : 区間内の全文字が単項述語 `pred` を満たすか検査。短絡評価（途中で `#f` になれば即座に `#f`）。末尾適用結果または空時 `#t` を返却。
5. `(textual-any pred textual [start [end]])` : 区間内のいずれかの文字が単項述語 `pred` を満たすか検査。短絡評価（真値になれば即座にその真値を返却）。該当なしまたは空時 `#f`。

### 3.2 Constructors (構築子 全 5 種)
6. `(make-text len [char])` : 長さ `len` の不変テキストを生成。文字 `char`（省略時は空白 `#\space`）で埋める。
7. `(text char ...)` : 与えられた文字群からなる不変テキストを生成。
8. `(text-tabulate len proc)` : インデックス `0` から `len - 1` に対して `(proc i)` を呼び出し、得られた文字群から不変テキストを構築。
9. `(text-unfold stop? mapper successor seed)` : 初期シード `seed` から開始し、`stop?` が成立するまで `mapper` で文字を生成し、`successor` でシードを更新して不変テキストを生成。
10. `(text-unfold-right stop? mapper successor seed)` : 右から左方向（末尾から先頭）へアンフォールドして不変テキストを生成。

### 3.3 Conversion (相互変換 全 16 種)
11. `(textual->text textual)` : `textual` を不変テキストに変換（すでに不変テキストであれば自身を返却）。
12. `(textual->string textual [start [end]])` : `textual` の指定区間を標準可変文字列に変換。
13. `(textual->vector textual [start [end]])` : `textual` の指定区間を文字ベクタに変換。
14. `(textual->list textual [start [end]])` : `textual` の指定区間を文字リストに変換。
15. `(string->text string [start [end]])` : 文字列の指定区間から不変テキストを生成。
16. `(vector->text vector [start [end]])` : 文字ベクタの指定区間から不変テキストを生成。
17. `(list->text list)` : 文字リストから不変テキストを生成。
18. `(reverse-list->text list)` : 文字リストを反転した順序で不変テキストを生成。
19. `(textual->utf8 textual [start [end]])` : `textual` の指定区間を UTF-8 バイトベクタにエンコード。
20. `(textual->utf16be textual [start [end]])` : `textual` の指定区間を UTF-16 Big-Endian バイトベクタにエンコード。
21. `(textual->utf16le textual [start [end]])` : `textual` の指定区間を UTF-16 Little-Endian バイトベクタにエンコード。
22. `(textual->utf16 textual [start [end]])` : `textual` の指定区間を UTF-16（システム既定または BOM 付き）バイトベクタにエンコード。
23. `(utf8->text bytevector [start [end]])` : UTF-8 バイトベクタの指定区間をデコードして不変テキストを生成。
24. `(utf16be->text bytevector [start [end]])` : UTF-16BE バイトベクタの指定区間をデコードして不変テキストを生成。
25. `(utf16le->text bytevector [start [end]])` : UTF-16LE バイトベクタの指定区間をデコードして不変テキストを生成。
26. `(utf16->text bytevector [start [end]])` : UTF-16 バイトベクタの指定区間をデコードして不変テキストを生成。

### 3.4 Selection (選択・スライス・パディング・トリム 全 16 種)
27. `(text-length text)` : 不変テキストの文字長を返却。最悪計算量 $O(1)$。
28. `(textual-length textual)` : `textual` の文字長を返却。
29. `(text-ref text idx)` : 不変テキストの `idx` 番目（0-origin）の文字を取得。最悪計算量 $O(1)$（または対数深さ）。
30. `(textual-ref textual idx)` : `textual` の `idx` 番目の文字を取得。
31. `(subtext text start end)` : 不変テキストの `[start, end)` 区間を抽出。構造共有により新規文字コピーなしで $O(1)$。
32. `(subtextual textual start end)` : `textual` の `[start, end)` 区間を抽出して不変テキストを返却。
33. `(textual-copy textual [start [end]])` : `textual` の指定区間の浅いコピーを不変テキストとして返却。
34. `(textual-take textual nchars)` : `textual` の先頭 `nchars` 文字からなる不変テキストを返却。
35. `(textual-drop textual nchars)` : `textual` の先頭 `nchars` 文字を除いた残余不変テキストを返却。
36. `(textual-take-right textual nchars)` : `textual` の末尾 `nchars` 文字からなる不変テキストを返却。
37. `(textual-drop-right textual nchars)` : `textual` の末尾 `nchars` 文字を除いた残余不変テキストを返却。
38. `(textual-pad textual len [char [start [end]]])` : 指定区間の左側を `char` で埋めて長さ `len` に揃えた不変テキストを生成（元の長さが `len` 以上なら右側を切り詰め）。
39. `(textual-pad-right textual len [char [start [end]]])` : 指定区間の右側を `char` で埋めて長さ `len` に揃えた不変テキストを生成。
40. `(textual-trim textual [pred [start [end]]])` : 先頭の `pred`（省略時は文字空白）にマッチする文字をトリムした不変テキストを返却。
41. `(textual-trim-right textual [pred [start [end]]])` : 末尾の `pred` にマッチする文字をトリムした不変テキストを返却。
42. `(textual-trim-both textual [pred [start [end]]])` : 先頭および末尾の `pred` にマッチする文字をトリムした不変テキストを返却。

### 3.5 Replacement (置換 全 1 種)
43. `(textual-replace textual1 start1 end1 textual2 [start2 [end2]])` : `textual1` の `[start1, end1)` 区間を `textual2` の `[start2, end2)` 区間で置き換えた新規不変テキストを生成。

### 3.6 Comparison (比較 全 10 種)
44. `(textual=? textual1 textual2 ...)` : 全ての引数が辞書順・文字コード順で同一であるか判定。
45. `(textual<? textual1 textual2 ...)` : 引数列が厳密な昇順であるか判定。
46. `(textual>? textual1 textual2 ...)` : 引数列が厳密な降順であるか判定。
47. `(textual<=? textual1 textual2 ...)` : 引数列が広義の昇順であるか判定。
48. `(textual>=? textual1 textual2 ...)` : 引数列が広義の降順であるか判定。
49. `(textual-ci=? textual1 textual2 ...)` : 大文字小文字を区別せず同一であるか判定（Case-insensitive）。
50. `(textual-ci<? textual1 textual2 ...)` : 大文字小文字を区別せず昇順であるか判定。
51. `(textual-ci>? textual1 textual2 ...)` : 大文字小文字を区別せず降順であるか判定。
52. `(textual-ci<=? textual1 textual2 ...)` : 大文字小文字を区別せず広義の昇順であるか判定。
53. `(textual-ci>=? textual1 textual2 ...)` : 大文字小文字を区別せず広義の降順であるか判定。

### 3.7 Prefixes & Suffixes (接頭辞・接尾辞 全 4 種)
54. `(textual-prefix-length textual1 textual2 [start1 [end1 [start2 [end2]]]])` : 2つのテキスト区間の最長共通接頭辞の文字数を返却。
55. `(textual-suffix-length textual1 textual2 [start1 [end1 [start2 [end2]]]])` : 2つのテキスト区間の最長共通接尾辞の文字数を返却。
56. `(textual-prefix? textual1 textual2 [start1 [end1 [start2 [end2]]]])` : `textual1` の区間が `textual2` の区間の接頭辞であるか判定。
57. `(textual-suffix? textual1 textual2 [start1 [end1 [start2 [end2]]]])` : `textual1` の区間が `textual2` の区間の接尾辞であるか判定。

### 3.8 Searching (探索 全 6 種)
58. `(textual-index pred textual [start [end]])` : `[start, end)` 内を左から右へ探索し、述語 `pred` を満たす最初の文字インデックスを返却（存在しなければ `#f`）。
59. `(textual-index-right pred textual [start [end]])` : 右から左へ探索し、述語 `pred` を満たす最初の文字インデックスを返却。
60. `(textual-skip pred textual [start [end]])` : `[start, end)` 内を左から右へ探索し、述語 `pred` を満たさない最初の文字インデックスを返却。
61. `(textual-skip-right pred textual [start [end]])` : 右から左へ探索し、述語 `pred` を満たさない最初の文字インデックスを返却。
62. `(textual-contains textual1 textual2 [start1 [end1 [start2 [end2]]]])` : `textual1` の指定区間内で `textual2` の指定区間が最初に出現する開始インデックスを返却（見つからなければ `#f`）。
63. `(textual-contains-right textual1 textual2 [start1 [end1 [start2 [end2]]]])` : `textual1` の指定区間内で `textual2` の指定区間が最後に出現する開始インデックスを返却。

### 3.9 Case Conversion (大文字小文字変換 全 4 種)
64. `(textual-upcase textual)` : Unicode 全角・半角大文字変換を適用した不変テキストを返却。
65. `(textual-downcase textual)` : 小文字変換を適用した不変テキストを返却。
66. `(textual-foldcase textual)` : ケース折りたたみ（Case-folding）を適用した不変テキストを返却。
67. `(textual-titlecase textual)` : タイトルケース変換（単語先頭大文字）を適用した不変テキストを返却。

### 3.10 Concatenation (連結 全 4 種)
68. `(textual-append textual ...)` : 与えられた `textual` 群を連結した不変テキストを生成。
69. `(textual-concatenate textual-list)` : `textual` のリストを連結した不変テキストを生成。
70. `(textual-concatenate-reverse textual-list [final-textual [end]])` : `textual` リストを逆順に連結し、末尾に `final-textual` を付加した不変テキストを生成。
71. `(textual-join textual-list [delimiter [grammar]])` : 区切り文字 `delimiter`（省略時は空白）および文法規則 `grammar`（`'infix`, `'strict-infix`, `'prefix`, `'suffix'`）に基づいて要素群を連結。

### 3.11 Fold, Map & Friends (高階関数・畳み込み・写像・フィルタ 全 9 種)
72. `(textual-fold kons knil textual [start [end]])` : 指定区間の文字を左から右へアキュムレータと畳み込み。
73. `(textual-fold-right kons knil textual [start [end]])` : 指定区間の文字を右から左へ畳み込み。
74. `(textual-map proc textual1 textual2 ...)` : 引数の各 `textual` の文字に対して `proc` を適用した結果（文字・文字列・テキスト）からなる新規不変テキストを生成。
75. `(textual-for-each proc textual1 textual2 ...)` : 引数の各 `textual` の文字に対して `proc` を順次適用（副作用目的）。
76. `(textual-map-index proc textual [start [end]])` : 各文字インデックスに対して `proc` を呼び出し、結果群を連結した不変テキストを生成。
77. `(textual-for-each-index proc textual [start [end]])` : 各文字インデックスに対して順次 `proc` を適用。
78. `(textual-count pred textual [start [end]])` : 指定区間内で述語 `pred` を満たす文字数を計数。
79. `(textual-filter pred textual [start [end]])` : 指定区間内で述語 `pred` を満たす文字のみを抽出した不変テキストを生成。
80. `(textual-remove pred textual [start [end]])` : 指定区間内で述語 `pred` を満たす文字を除去した不変テキストを生成。

### 3.12 Replication & Splitting (反復・分割 全 2 種)
81. `(textual-replicate textual from to [start [end]])` : `textual` の指定区間を巡回反復し、範囲 `[from, to)` に相当する不変テキストを生成。
82. `(textual-split textual delimiter [grammar [limit [start [end]]]])` : 区切り文字または述語 `delimiter` で指定区間を分割し、不変テキストのリストを返却。

---

## 4. アルゴリズムおよびデータ構造設計 (Tree-Structured Immutable Texts / Rope & Slice Nodes)

### 4.1 ノード表現 (Node Representation)
ULisp における不変テキスト型 `text` は、効率的なメモリ共有と高速なスライシング・連結を実現するため、以下のタグ付きベクタ（Tagged Vector）を用いた Rope 構造を採用する:

```scheme
;; 1. Flat Leaf Node (平坦文字列リーフ)
;; len: 文字列長, str: 内部不変文字列
#(ulisp-text-leaf len str)

;; 2. Subtext Slice Node (スライスノード - コピー不要 O(1))
;; len: スライス長, src: ソース text, start: 開始位置, end: 終了位置
#(ulisp-text-slice len src start end)

;; 3. Concatenation Node (連結ノード - 左右部分木結合 O(1))
;; len: 合計長, left: 左 text, right: 右 text, depth: 木の深さ
#(ulisp-text-concat len left right depth)

;; 4. Repeated Character Node (単一文字反復ノード - 省メモリ O(1))
;; len: 反復長, char: 保持文字
#(ulisp-text-repeat len char)
```

### 4.2 計算量特性と構造共有 (Structural Sharing)
- **`text-length`**: 全てのノード型の第 1 要素に長さ `len` がキャッシュされているため、最悪計算量 **$O(1)$**。
- **`subtext` / `subtextual`**:
  - `start = 0` かつ `end = len` の場合はオブジェクト自身をそのまま返却（完全共有）。
  - 部分スライス時は、`#(ulisp-text-slice len src start end)` を生成し、既存の文字列や木構造を一切コピーしないため、最悪計算量 **$O(1)$**、メモリ割り当て **$O(1)$**。
  - スライスノードに対するさらなるスライス（ネストスライス）は、インデックス加算により 1 段の親参照に平坦化（Path Compression）。
- **`textual-append`**:
  - 空テキストとの結合時は他方をそのまま返却。
  - 左右のテキストを `#(ulisp-text-concat len left right depth)` で結合。計算量 **$O(1)$**。
  - 木の深さ `depth` が一定閾値（例: 32）を超えた場合、または短いテキスト同士の結合時は自動的に平坦化（Flattening）を行い、探索コストを $O(\log n)$ または定数時間内に抑制。
- **`text-ref`**:
  - リーフノード: `(string-ref str idx)` による即時アクセス。
  - スライスノード: `(text-ref src (+ start idx))` による委譲。
  - 結合ノード: 左部分木の長さ `(text-length left)` と比較し、左または右の木へ降下。最大探索深さは $O(\text{depth}) \le 32$ であり、事実上の定数時間アクセスを保証。

### 4.3 プレーン文字列との相互運用性
- 述語 `(text? x)` はベクタ長 $\ge 3$ かつ第 0 要素が `'ulisp-text-leaf`, `'ulisp-text-slice`, `'ulisp-text-concat`, `'ulisp-text-repeat` のいずれかであるかを判定。
- 述語 `(textual? x)` は `(or (text? x) (string? x))` で判定。
- 各種手続きが `textual` を受け取る際、文字列であれば必要に応じてリーフノード `(string->text x)` にラッピングするか、直接文字列走査を行うことでオーバーヘッドを最小化。

---

## 5. セキュリティおよび堅牢性設計 / Security & Robustness Design

### 5.1 メモリ境界外アクセス防止 (CWE-125 / CWE-787 Mitigation)
- **厳密なインデックスおよび区間検査**:
  - `text-ref`, `textual-ref`, `subtext`, `subtextual`, `textual-take`, `textual-drop` 等において、`start` および `end` の有効範囲（$0 \le start \le end \le length$）をエントリポイントで検証。
  - 負のインデックスや長さを超える境界外指定に対しては即座に安全なエラー（`error` 送出）を発生させ、未定義メモリ参照やクラッシュを防止。
- **不変性 (Immutability) の保証**:
  - 外部からテキスト内の文字を変更する手段を一切提供せず、部分書き換え（`textual-replace`）も新規ノード生成（Path Copying / Structural Sharing）として実行。並行アクセス時における競合状態（Race Condition）を原理的に排除。

### 5.2 DoS / スタック枯渇・過剰メモリ消費対策 (CWE-400 Mitigation)
- **再帰深度の有界化と自動平坦化**:
  - 連結ノードの深さが閾値を超えた場合、走査時にスタックオーバーフローを起こさないよう平坦な文字列リーフに再パック。
- **末尾再帰 (TCO) による反復**:
  - `textual-fold`, `textual-for-each`, `textual-every`, `textual-any` などの高階関数は末尾再帰ループとして実装し、テキスト長 $N$ に対してスタック消費量 $O(1)$ を保証。
- **大量スライス時の循環参照・メモリリーク防止**:
  - スライスのネストは開始オフセットの加算により単一親ノードへの参照へ正規化。

### 5.3 整数オーバーフロー対策 (CWE-190 Mitigation)
- テキスト長の加算（`textual-append`, `textual-replicate`）において、ULisp の FIXNUM 範囲上限を超えないかを検証。

---

## 6. 影響範囲と関連ファイル / Scope and Affected Files

### 6.1 実装ファイル
- `ulisp/lib/text.scm` (新規作成) : SRFI 135 全 82 種の手続きおよび Rope/Slice コア実装
- `ulisp/lib/scheme/text.sld` (新規作成) : `(scheme text)` R7RS-large ライブラリ定義
- `ulisp/lib/srfi/135.sld` (新規作成) : `(srfi 135)` R7RS ライブラリ定義

### 6.2 ビルド & ドキュメント
- `ulisp/Makefile` : `ULISP_LARGE_LIBS` への `lib/text.scm` 追加、`lint_sexpr` への登録、単体テストターゲット `test_srfi_135` の新設
- `ulisp/docs/ref_r7rs_compliance.md` : SRFI 135 のステータスを `×` から `◎` に更新

### 6.3 テストファイル
- `ulisp/tests/test_srfi_135.scm` (新規作成) : 全 82 手続きを網羅する包括的テストスイート（12 グループ、正常系・境界値・不変性・構造共有・大規模テキストスライス・パディング・探索）

---

## 7. 実装手順 / Implementation Plan

Target Branch: `feat/855-implement-srfi-135-immutable-texts`

- [ ] **Step 1: コアデータ構造・述語・基本構築子の実装 (`ulisp/lib/text.scm`)**
  - タグ付き表現（`ulisp-text-leaf`, `ulisp-text-slice`, `ulisp-text-concat`, `ulisp-text-repeat`）の定義。
  - `text?`, `textual?`, `textual-null?`, `make-text`, `text`, `text-tabulate`, `text-unfold`, `text-unfold-right` の実装。
  - `text-length`, `textual-length`, `text-ref`, `textual-ref` の実装。
- [ ] **Step 2: 選択・スライス・パディング・トリム・置換の実装 (`ulisp/lib/text.scm`)**
  - `subtext`, `subtextual` ($O(1)$ スライスノード生成および正規化）。
  - `textual-copy`, `textual-take`, `textual-drop`, `textual-take-right`, `textual-drop-right`。
  - `textual-pad`, `textual-pad-right`, `textual-trim`, `textual-trim-right`, `textual-trim-both`。
  - `textual-replace` の実装。
- [ ] **Step 3: 比較・接頭接尾・探索・大文字小文字変換の実装 (`ulisp/lib/text.scm`)**
  - 辞書順比較 `textual=?`, `textual<?`, `textual>?`, `textual<=?`, `textual>=?` および大文字小文字無視版 (`-ci`)。
  - `textual-prefix-length`, `textual-suffix-length`, `textual-prefix?`, `textual-suffix?`。
  - `textual-index`, `textual-index-right`, `textual-skip`, `textual-skip-right`, `textual-contains`, `textual-contains-right`。
  - `textual-upcase`, `textual-downcase`, `textual-foldcase`, `textual-titlecase`。
- [ ] **Step 4: 連結・高階関数・反復分割・エンコーディング相互変換の実装 (`ulisp/lib/text.scm`)**
  - `textual-append`, `textual-concatenate`, `textual-concatenate-reverse`, `textual-join`。
  - `textual-fold`, `textual-fold-right`, `textual-map`, `textual-for-each`, `textual-map-index`, `textual-for-each-index`, `textual-count`, `textual-filter`, `textual-remove`。
  - `textual-replicate`, `textual-split`。
  - 文字列・ベクタ・リスト・UTF-8 / UTF-16 相互変換群（全 16 種）。
- [ ] **Step 5: R7RS / SRFI ライブラリ定義の配備**
  - `ulisp/lib/scheme/text.sld` : `(scheme text)` モジュール定義
  - `ulisp/lib/srfi/135.sld` : `(srfi 135)` モジュール定義
  - Traceability ヘッダー規約（`Traceability: ulisp/docs/ref_r7rs_compliance.md`）の遵守。
- [ ] **Step 6: 単体テストスイートの作成と Makefile 統合**
  - `ulisp/tests/test_srfi_135.scm` を作成し、全 12 カテゴリ、82 手続きの網羅テストを実装。
  - `ulisp/Makefile` に `test_srfi_135` ターゲットを追加し、`ULISP_LARGE_LIBS` と `lint_sexpr` に登録。
- [ ] **Step 7: 品質ゲート検証とドキュメント更新**
  - `make -C ulisp lint_sexpr` および `make -C ulisp test_r7rs_traceability` の 100% PASS を確認。
  - `make -C ulisp test_srfi_135` の実行および全 PASS 確認。
  - `ulisp/docs/ref_r7rs_compliance.md` の SRFI 135 ステータスを `◎` に更新。

---

## 8. 完了条件 / Definition of Done (DoD)
- [ ] `ulisp/lib/text.scm` に SRFI 135 の全 82 種の手続きが完全実装されていること。
- [ ] `text-length` が $O(1)$、`subtext` が $O(1)$（構造共有）、`text-ref` が対数または定数時間で動作すること。
- [ ] `(scheme text)` および `(srfi 135)` が正常にインポート可能であること。
- [ ] `ulisp/tests/test_srfi_135.scm` のテストケースがすべて PASS すること。
- [ ] `make -C ulisp lint_sexpr` および `make -C ulisp test_r7rs_traceability` が正常に通過すること。
- [ ] `ulisp/docs/ref_r7rs_compliance.md` が最新のステータスに更新されていること。
- [ ] ドキュメント内のすべての内部リンクが相対パスで記述されていること。
