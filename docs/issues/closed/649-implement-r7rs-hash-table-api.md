---
ID: 649
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] R7RS-large (SRFI 69 / 125) 汎用ハッシュテーブル API の実装 (ID: 649)

## 1. 概要 / Summary
R7RS-large (Red Edition) の主要仕様である **SRFI 69 (Basic Hash Tables)** および **SRFI 125 (Intermediate Hash Tables)** / `(scheme hash-table)` に準拠した汎用ハッシュテーブルデータ型および完全な手続き群を ULisp 標準ライブラリ（`ulisp/lib/hashtable.scm`）および独立モジュールとして実装する。

現在、ULisp コンパイラ内部ではシンボルインターン用および LIR ラベル検証用の固定長ハッシュセット/テーブル（`make-symbol-hash-table` 等）がアドホックに存在しているが、一般ユーザーや高レベル Scheme アプリケーション（AST 辞書、環境フレーム、LVN / グローバル共通部分式削除、セキュリティオントロジーグラフ解析）から自由に利用可能なファーストクラスのハッシュテーブル型は未提供であった。

本機能により、O(1) 償却時間でのキー・値アクセス、動的リハッシュ（自動リサイズ）、多様なキー型（シンボル、文字列、数値、ペア、任意オブジェクト）に対応した決定論的ハッシュ関数群、および完全な SRFI 69 / 125 互換 API を提供し、R7RS-large 準拠度を飛躍的に高める。

---

## 2. トレーサビリティ / Traceability
- **R7RS-large 仕様**: Red Edition / SRFI 125 (Intermediate Hash Tables) & SRFI 69 (Basic Hash Tables)
- **仕様リファレンス**: [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1, §2.3
- **関連 Issue**:
  - [Issue #549: R7RS define-record-type macro](../../docs/issues/closed/549-implement-r7rs-define-record-type-macro.md)
  - [Issue #551: R7RS standard library extension](../../docs/issues/closed/551-expand-r7rs-standard-library-procedures.md)
  - [Issue #648: R7RS-large SRFI 1 higher-order list procedures](../../docs/issues/closed/648-implement-srfi-1-higher-order-list-procedures.md)

---

## 3. 実装対象 API 一覧 / Target API Specification

### 3.1 Constructors (構築子)
- `(make-hash-table [equal? [hash [size]]])` : 指定された等価性述語・ハッシュ関数・初期バケットサイズでハッシュテーブルを生成（デフォルト: `equal?`, 汎用 `hash`, 初期バケット数 64）。
- `(hash-table comparator [arg ...])` : SRFI 125 互換構築子（またはキー・値ペア列からの構築）。
- `(alist->hash-table alist [equal? [hash [size]]])` : 連想リストからハッシュテーブルを構築。

### 3.2 Predicates (述語)
- `(hash-table? obj)` : ハッシュテーブル型述語。
- `(hash-table-contains? ht key)` / `(hash-table-exists? ht key)` : キーが存在するか判定。
- `(hash-table-empty? ht)` : ハッシュテーブルが空か判定。
- `(hash-table=? value=? ht1 ht2)` : 2つのハッシュテーブルが同一のキー・値マッピングを持つか判定。

### 3.3 Accessors & Mutators (参照・更新・削除)
- `(hash-table-ref ht key [failure-thunk [success-proc]])` : キーの値を参照。非存在時は failure-thunk 呼び出しまたはエラー。
- `(hash-table-ref/default ht key default)` : キーが存在しない場合に `default` 値を返却。
- `(hash-table-set! ht key value ...)` : キー・値ペアを挿入または更新（複数キー・値ペアの一括指定対応）。
- `(hash-table-delete! ht key ...)` : キーに対応するエントリを削除（非存在時は無視）。
- `(hash-table-update! ht key updater [failure-thunk [success-proc]])` : 値を `(updater (hash-table-ref ht key))` で更新。
- `(hash-table-update!/default ht key updater default)` : デフォルト値付き更新。
- `(hash-table-clear! ht)` : すべてのエントリを削除して初期化。
- `(hash-table-pop! ht)` : 任意のエントリを1つ取り出して削除し、`(values key value)` を多値返却。

### 3.4 Whole-Table Operations (全体走査・変換)
- `(hash-table-size ht)` : 格納されているエントリ総数を取得。
- `(hash-table-keys ht)` : 全キーのリストを返却。
- `(hash-table-values ht)` : 全値のリストを返却。
- `(hash-table->alist ht)` : `((key . value) ...)` 連想リストに変換。
- `(hash-table-copy ht [mutable?])` : ハッシュテーブルの複製。
- `(hash-table-merge! ht1 ht2)` : `ht2` の全エントリを `ht1` に上書きマージ。

### 3.5 Iteration & Mapping (反復・高階操作)
- `(hash-table-for-each proc ht)` / `(hash-table-walk ht proc)` : `(proc key value)` を全エントリに適用。
- `(hash-table-map proc ht)` : 各エントリを `(proc key value)` で変換した新しいハッシュテーブルを生成。
- `(hash-table-map->list proc ht)` : 各エントリに `(proc key value)` を適用したリストを生成。
- `(hash-table-fold ht kons knil)` : `(kons key value acc)` で全エントリを左畳み込み。

### 3.6 Standard Hash Functions (標準ハッシュ関数群)
- `(string-hash str [bound])` : 文字列 djb2 ハッシュ（0 〜 bound-1 の整数、デフォルト bound は $2^{30}-1$）。
- `(string-ci-hash str [bound])` : 大小文字無視文字列ハッシュ。
- `(symbol-hash sym [bound])` : シンボル名 djb2 ハッシュ。
- `(number-hash num [bound])` : 数値ハッシュ（Fixnum の値そのものをミキシング）。
- `(hash obj [bound])` : 任意オブジェクト用決定論的汎用ハッシュ（型タグ・再帰走査深さ制限付き）。
- `(hash-by-identity obj [bound])` : `eq?` 向けポインタ／即値不変ハッシュ。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ulisp/lib/hashtable.scm](../../ulisp/lib/hashtable.scm) : 汎用ハッシュテーブル本体（新規作成）
- [ulisp/lib/srfi/69.sld](../../ulisp/lib/srfi/69.sld) : `(define-library (srfi 69) ...)` モジュール定義（新規作成）
- [ulisp/lib/srfi/125.sld](../../ulisp/lib/srfi/125.sld) : `(define-library (srfi 125) ...)` モジュール定義（新規作成）
- [ulisp/lib/scheme/hash-table.sld](../../ulisp/lib/scheme/hash-table.sld) : `(define-library (scheme hash-table) ...)` R7RS-large モジュール定義（新規作成）
- [ulisp/Makefile](../../ulisp/Makefile) : `ULISP_STD_LIBS` への追加、`test_hashtable` ターゲットおよび `lint_sexpr` への登録
- [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) : SRFI 69 / 125 準拠ステータスの更新
- [ulisp/tests/test_hashtable.scm](../../ulisp/tests/test_hashtable.scm) : 包括的ユニットテストスイート（新規作成）

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/649-implement-r7rs-hash-table-api`

### 5.1 アーキテクチャおよび設計原則
1. **データ構造の表現 (`define-record-type`)**:
   - `define-record-type` を用いて `<hash-table>` レコードを定義する：
     ```scheme
     (define-record-type <hash-table>
       (%make-raw-hash-table buckets size equal-proc hash-proc min-load max-load)
       hash-table?
       (buckets %ht-buckets %ht-buckets-set!)
       (size %ht-size %ht-size-set!)
       (equal-proc %ht-equal)
       (hash-proc %ht-hash)
       (min-load %ht-min-load)
       (max-load %ht-max-load))
     ```
   - バケット配列には固定長ベクタ `(make-vector capacity '())` を使用し、各スロットは `((key . value) ...)` の連想リスト（チェイニング法）で衝突を解決する。
2. **GC (Garbage Collection) リロケーション耐性の保証**:
   - ULisp の 2-Space コピー GC では、GC 発動時にヒープオブジェクトのアドレスが移動する。
   - そのため、ヒープポインタのアドレスそのものをハッシュ値にしてはならない。
   - `(hash obj)` はオブジェクトの型と不変属性（文字列・シンボルは djb2 文字列ハッシュ、数値は Fixnum 値、ペア・ベクタは先頭要素の再帰ハッシュ）から計算し、GC 移動前後でハッシュ値が不変となる決定論的ハッシュを徹底する。
3. **動的リハッシュ（自動リサイズ）機構**:
   - 負荷率閾値 $\alpha = \text{size} / \text{capacity}$ を管理する。
   - デフォルト最大負荷率 $\alpha_{\text{max}} = 1.5$ を超えた場合、バケット容量を 2 倍（$2N$）に自動拡張し、全エントリを新バケットに再配置（Rehash）する。これにより、エントリ数が増加しても平均計算量 $O(1)$ を維持する。
4. **高階関数・TCO 連携**:
   - `hash-table-fold`, `hash-table-for-each`, `hash-table-keys`, `hash-table-values` 等の反復処理は、バケット配列の各スロットの連想リストを末尾再帰で安全に走査し、スタックオーバーフローを防止する。
5. **モジュール解決とデュアル標準**:
   - `(import (srfi 69))`、`(import (srfi 125))`、および `(import (scheme hash-table))` のいずれでも透過的に利用できるように各 `.sld` を策定し、`include "lib/hashtable.scm"` で共有する。

---

## 6. テスト・検証計画 / Verification Plan

1. **包括的単体テストスイート (`ulisp/tests/test_hashtable.scm`)**:
   - 構築: `make-hash-table`, `alist->hash-table`, 各種初期容量
   - 基本操作: `hash-table-set!`, `hash-table-ref`, `hash-table-ref/default`, `hash-table-delete!`, `hash-table-exists?`
   - 更新: `hash-table-update!`, `hash-table-update!/default`, `hash-table-clear!`, `hash-table-pop!`
   - 高度な走査: `hash-table-keys`, `hash-table-values`, `hash-table-size`, `hash-table->alist`, `hash-table-copy`, `hash-table-merge!`
   - 反復・高階関数: `hash-table-walk` / `for-each`, `hash-table-fold`, `hash-table-map->list`
   - ハッシュ関数: `string-hash`, `symbol-hash`, `number-hash`, `hash` の均一性・有界値テスト
   - 動的リハッシュ: 1000 エントリ以上の大量挿入・検索によるバケット拡張と $O(1)$ 性能維持検証
   - GC 耐性: 大量データ挿入中の GC 発動後もすべてのキー・値が整合性を保っていることの検証
2. **静的構文チェック**:
   - `make -C ulisp lint_sexpr`（括弧深度完全一致）
3. **リグレッションおよびブートストラップ検証**:
   - `make -C ulisp test_all_passes` (全 38 Nanopass 100% PASS)
   - `./ulisp/test.sh` (3-Stage 固定点セルフホスティングブートストラップ 100% PASS)
   - `./ulisp/test_c.sh` (C バックエンド回帰テスト 100% PASS)

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/lib/hashtable.scm` に SRFI 69 / 125 の主要 API（Constructors, Predicates, Accessors/Mutators, Whole-Table, Iteration, Hash Functions）が漏れなく実装されていること。
- [x] 決定論的ハッシュ関数群が実装され、GC によるオブジェクト移動後もハッシュ値の同一性が維持されること。
- [x] 負荷率閾値超過時に自動バケット拡張（動的リハッシュ）が正しく機能し、衝突解決が $O(1)$ 償却時間で動作すること。
- [x] `(srfi 69)`, `(srfi 125)`, `(scheme hash-table)` の各ライブラリ定義 `.sld` が策定され、透過的にインポートできること。
- [x] `ulisp/tests/test_hashtable.scm` の全テストケースがネイティブ AOT で 100% PASS すること。
- [x] `make -C ulisp lint_sexpr`、`make -C ulisp test_all_passes`、`./ulisp/test.sh`、および `./ulisp/test_c.sh` が 100% PASS すること。
- [x] `ulisp/docs/ref_r7rs_compliance.md` の SRFI 69 / 125 準拠ステータスが **◎** に更新されていること。
