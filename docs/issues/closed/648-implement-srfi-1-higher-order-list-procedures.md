---
ID: 648
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] R7RS-large (SRFI 1 Lists) 高階リスト操作手続き群の実装 (ID: 648)

## 1. 概要 / Summary
R7RS-large (Red Edition) の中核仕様である **SRFI 1 (List Library)** の主要高階関数・リスト処理手続き群を ULisp 標準ライブラリ（`ulisp/lib/list.scm`）および独立モジュール（`(srfi 1)` / `(scheme list)`）に実装する。

ULisp は現在、R7RS-small §6.4 に準拠した基礎的なリスト操作（`cons`, `car`, `cdr`, `list`, `length`, `append`, `reverse`, `list-tail`, `list-ref`, `list-set!`, `memq`, `assq`, `map`, `for-each` 等）を提供しているが、現代的な関数型プログラミングおよび Scheme アプリケーション（AST 変換・走査・最適化・構文脱糖）で不可欠となる `fold`, `fold-right`, `unfold`, `filter`, `remove`, `partition`, `take`, `drop`, `any`, `every`, `find`, `list-index` 等の高階リスト操作 API が未整備である。

本機能の実装により、ULisp コンパイラ自身の内部 Nanopass パスの可読性と記述力を飛躍的に向上させるとともに、R7RS-large Red Edition 準拠度を大幅に前進させる。

---

## 2. トレーサビリティ / Traceability
- **R7RS-large 仕様**: Red Edition / SRFI 1 (List Library)
- **仕様リファレンス**: [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1
- **関連 Issue**:
  - [Issue #551: R7RS standard library extension](../../docs/issues/closed/551-expand-r7rs-standard-library-procedures.md)
  - [Issue #555: R7RS list accessors](../../docs/issues/closed/555-implement-r7rs-list-accessors-list-tail-ref-set.md)
  - [Issue #610: R7RS base core procedures (map / for-each multi-arg)](../../docs/issues/closed/610-implement-r7rs-base-core-procedures.md)

---

## 3. 実装対象 API 一覧 / Target API Specification

### 3.1 Constructors (構築子)
- `(xcons d a)` : 引数を反転させた `cons`。`(cons a d)` と等価。
- `(cons* elt1 elt2 ...)` : 末尾要素を cdr とするペア連鎖を生成。
- `(list-tabulate n init-proc)` : `0` から `n-1` までの各インデックスに `init-proc` を適用したリストを生成。
- `(iota count [start [step]])` : `start` から `step` 刻みで `count` 個の数値を並べたリストを生成（デフォルト: `start=0`, `step=1`）。

### 3.2 Predicates (述語)
- `(proper-list? x)` : 終端が空リスト `'()` である正規リストか否かを判定（循環・ドット対を排除）。
- `(circular-list? x)` : フロイドの循環検出アルゴリズム（ウサギとカメ）による循環リスト判定。
- `(dotted-list? x)` : 末尾がペアでも空リストでもない非正規リストか否かを判定。
- `(not-pair? x)` : `(not (pair? x))` と等価。
- `(null-list? l)` : 空リスト判定（ペアなら `#f`、空リストなら `#t`、非ペア非リストは型エラー）。
- `(list= elt= list1 ...)` : 要素比較述語 `elt=` を用いてリスト群の同値性を判定。

### 3.3 Selectors (セレクタ・アクセス手続き)
- `(first clist)`, `(second clist)`, `(third clist)`, `(fourth clist)`, `(fifth clist)`, `(sixth clist)`, `(seventh clist)`, `(eighth clist)`, `(ninth clist)`, `(tenth clist)` : 1〜10 番目要素のアクセサ。
- `(car+cdr pair)` : `(values (car pair) (cdr pair))` を多値として返却。
- `(take clist k)` : 先頭 `k` 個の要素からなる新リストを生成。
- `(drop clist k)` : 先頭 `k` 個の要素を除いた残りのリストを返却（`list-tail` と同等）。
- `(take-right clist k)` : 末尾 `k` 個の要素からなるサブリストを返却。
- `(drop-right clist k)` : 末尾 `k` 個の要素を除いた新リストを生成。
- `(split-at clist k)` : `(values (take clist k) (drop clist k))` を多値として返却。
- `(last clist)` : リストの最後の要素を返却。
- `(last-pair clist)` : リストの最後のペアを返却。

### 3.4 Fold, Unfold & Reductions (畳み込み・展開)
- `(count pred clist1 clist2 ...)` : `pred` が真を返す要素の総数をカウント。
- `(fold kons knil clist1 clist2 ...)` : 左畳み込み。TCO（末尾再帰）による $O(1)$ スタック保証。複数リスト引数対応。
- `(fold-right kons knil clist1 clist2 ...)` : 右畳み込み。複数リスト引数対応。
- `(unfold p f g seed [tail-gen])` : `p` が真になるまで `g` でシードを更新し `f` で要素を生成するリスト構築手続き。
- `(unfold-right p f g seed [tail])` : 逆順リスト構築手続き（末尾再帰・TCO）。
- `(reduce f ridentity list)` : 初期値フォールバック付き簡約。
- `(reduce-right f ridentity list)` : 初期値フォールバック付き右簡約。

### 3.5 Searching & Filtering (探索・フィルタリング)
- `(filter pred list)` : `pred` を満たす要素のみを抽出した新リストを生成（TCO ループ + 反転）。
- `(remove pred list)` : `pred` を満たさない要素のみを抽出した新リストを生成。
- `(partition pred list)` : `(values (filter pred list) (remove pred list))` を多値として返却。
- `(find pred clist)` : `pred` を満たす最初の要素を返却（存在しない場合は `#f`）。
- `(find-tail pred clist)` : `pred` を満たす最初の要素を car とするペアを返却（存在しない場合は `#f`）。
- `(any pred clist1 clist2 ...)` : いずれかの要素で `pred` が真になった時点でその結果を即座に返却（TCO 短絡評価）。
- `(every pred clist1 clist2 ...)` : すべての要素で `pred` が真か判定し、最後の結果を返却（TCO 短絡評価）。
- `(list-index pred clist1 clist2 ...)` : `pred` を満たす最初のインデックス（0-based）を返却（存在しない場合は `#f`）。
- `(take-while pred clist)` : `pred` が真である間、先頭から要素を抽出。
- `(drop-while pred clist)` : `pred` が真である間、先頭の要素を読み飛ばす。
- `(span pred clist)` : `(values (take-while pred clist) (drop-while pred clist))` を多値返却。
- `(break pred clist)` : `(values (take-while (lambda (x) (not (pred x))) clist) (drop-while (lambda (x) (not (pred x))) clist))` を多値返却。

### 3.6 Deletion & Association Lists (削除・連想リスト)
- `(delete x list [=])` : `list` から `x` と一致する要素を削除した新リストを返却（デフォルト比較: `equal?`）。
- `(delete-duplicates list [=])` : 重複要素を排除した新リストを生成（デフォルト比較: `equal?`）。
- `(alist-cons key datum alist)` : `(cons (cons key datum) alist)` と等価。
- `(alist-copy alist)` : 連想リストの浅い複製。
- `(alist-delete key alist [=])` : 連想リストから指定キーのエントリを削除（デフォルト比較: `equal?`）。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ulisp/lib/list.scm](../../ulisp/lib/list.scm) : SRFI 1 手続き群の実装追加
- [ulisp/lib/srfi/1.sld](../../ulisp/lib/srfi/1.sld) : 新規 `(srfi 1)` ライブラリ定義ファイルの策定
- [ulisp/lib/scheme/list.sld](../../ulisp/lib/scheme/list.sld) : 新規 `(scheme list)` (R7RS-large Red Edition) ライブラリ定義ファイルの策定
- [ulisp/lib/scheme/base.sld](../../ulisp/lib/scheme/base.sld) : 基本手続きとの調和確認
- [ulisp/tests/test_srfi1.scm](../../ulisp/tests/test_srfi1.scm) : SRFI 1 包括的ユニットテストスイート新規作成
- [ulisp/Makefile](../../ulisp/Makefile) : `lint_sexpr` およびテストターゲットへの登録
- [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) : SRFI 1 準拠ステータスおよび詳細記述の更新

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/648-implement-srfi-1-higher-order-list-procedures`

### 5.1 アーキテクチャおよび設計原則
1. **厳密な TCO (末尾再帰最適化) の担保**:
   - `fold`, `any`, `every`, `find`, `find-tail`, `list-index`, `take`, `drop`, `take-while`, `drop-while` 等は名前付き `let` ループを用いてすべて末尾呼び出し形式とし、スタック空間量 $O(1)$ を保証する。
   - `filter`, `remove` などのリスト生成系は、アキュムレータを用いた末尾再帰ループで逆順に収集した上で `reverse` するイディオムを採用し、数万要素の巨大リストでもコールスタックを消費しない構造とする。
2. **多値 (Multiple Values) の透過的連携**:
   - `car+cdr`, `split-at`, `partition`, `span`, `break` は `values` を呼び出し、呼び出し元が `call-with-values` や `let-values` / `let*-values` で直接多値を受け取れるようにする。
3. **可変長引数ディスパッチ (`case-lambda`)**:
   - `fold`, `fold-right`, `any`, `every`, `count`, `list-index`, `list=` などの可変長引数手続きは、単一リスト・2リスト高速走査パスと汎用可変長リスト走査パス（`%any-null?`, `%cars`, `%cdrs`, `%apply-list`）を分離し、高頻度ユースケースでのオーバーヘッドを最小化する。
   - `iota`, `delete`, `delete-duplicates`, `alist-delete` などの省略可能引数は `case-lambda` によるデフォルト引数補完を行う。
4. **モジュール解決**:
   - `ulisp/frontend/010_library.scm` の `library-name->sld-path` 機構により、`(import (srfi 1))` は `lib/srfi/1.sld`、`(import (scheme list))` は `lib/scheme/list.sld` に自動マッピングされるため、これらを定義して外部モジュールとして透過的にインポート可能にする。
   - `ulisp/lib/list.scm` に手続き本体を配置することで、`ULISP_STD_LIBS` としてコンパイルされる通常環境でも即座に全手続きが利用可能となる。

---

## 6. テスト・検証計画 / Verification Plan

1. **単体テストスイート (`ulisp/tests/test_srfi1.scm`)**:
   - Constructors: `xcons`, `cons*`, `list-tabulate`, `iota` (0引数、1引数、2引数、3引数、負のステップ)
   - Predicates: `proper-list?`, `circular-list?`, `dotted-list?`, `null-list?`, `list=`
   - Selectors: `first`〜`tenth`, `car+cdr`, `take`, `drop`, `take-right`, `drop-right`, `split-at`, `last`, `last-pair` (境界値 $k=0, k=len$, エラーハンドリング)
   - Fold/Unfold: `fold`, `fold-right` (単一リスト、複数リスト、空リスト), `unfold`, `unfold-right`, `reduce`, `reduce-right`
   - Searching/Filtering: `filter`, `remove`, `partition` (多値受取), `find`, `find-tail`, `any`, `every` (短絡評価、真値返却), `list-index`, `take-while`, `drop-while`, `span`, `break`
   - Deletion/Alist: `delete`, `delete-duplicates`, `alist-cons`, `alist-copy`, `alist-delete`
2. **静的検証**:
   - `python3 scripts/lint_sexpr.py` による S 式括弧整合性・構文チェック。
3. **リグレッションおよびブートストラップ検証**:
   - `make -C ulisp test_all_passes` (全 Nanopass 単体テスト 100% PASS)
   - `./ulisp/test.sh` (x86_64 AOT ネイティブコンパイル・Exact GC・3-Stage セルフホスティング固定点ブートストラップ 100% PASS)
   - `./ulisp/test_c.sh` (C バックエンド回帰テスト 100% PASS)

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/lib/list.scm` に SRFI 1 の主要手続き群（Constructors, Predicates, Selectors, Fold/Unfold, Searching/Filtering, Deletion/Alist）が漏れなく実装されていること。
- [x] すべてのループ・反復処理が TCO（末尾再帰最適化）を遵守し、スタックオーバーフローを起こさないこと。
- [x] 多値を返却する手続き（`partition`, `car+cdr`, `split-at`, `span`, `break`）が `let-values` や `call-with-values` で正しく値を受け取れること。
- [x] `ulisp/lib/srfi/1.sld` および `ulisp/lib/scheme/list.sld` が策定され、`(import (srfi 1))` および `(import (scheme list))` が正常に動作すること。
- [x] `ulisp/tests/test_srfi1.scm` が作成され、全テストケースが 100% PASS すること。
- [x] `make -C ulisp test_all_passes` および `./ulisp/test.sh` が 100% PASS すること。
- [x] `ulisp/docs/ref_r7rs_compliance.md` の SRFI 1 準拠ステータスが更新されていること。
- [x] S 式 Linter（`lint_sexpr`）のチェックに合格すること。
