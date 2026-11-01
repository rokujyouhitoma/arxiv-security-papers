---
ID: 649
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large (SRFI 69 / 125) 汎用ハッシュテーブル API の実装 (ID: 649)

## 1. 概要 / Summary
R7RS-large (SRFI 69 / SRFI 125) に準拠した汎用ハッシュテーブルデータ型および基本手続き群（`make-hash-table`, `hash-table?`, `hash-table-ref`, `hash-table-ref/default`, `hash-table-set!`, `hash-table-delete!`, `hash-table-keys`, `hash-table-values`, `hash-table-size` 等）を実装する。
ULisp 内部では現在シンボルテーブル用の特殊ハッシュが存在するが、これを一般ユーザーおよびコンパイラ最適化パス（LVN、デッドコード削除、シンボル環境検索）で利用可能なファーストクラスデータ型として昇華させる。

---

## 2. トレーサビリティ / Traceability
- R7RS-large: Red Edition / SRFI 125 (Intermediate Hash Tables) および SRFI 69 (Basic Hash Tables)
- 仕様リファレンス: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1, §2.3

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/hashtable.scm](../../ulisp/lib/hashtable.scm) (新規モジュール)
- [ ] [ulisp/lib/srfi/69.sld](../../ulisp/lib/srfi/69.sld) (新規ライブラリ定義)
- [ ] [ulisp/lib/srfi/125.sld](../../ulisp/lib/srfi/125.sld) (新規ライブラリ定義)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)
- [ ] [ulisp/tests/test_hashtable.scm](../../ulisp/tests/test_hashtable.scm) (新規テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/649-implement-r7rs-hash-table-api`

1. バケット配列（固定長ベクタ）とチェイニング法（連想リスト）をベースとしたハッシュテーブル型を `define-record-type` またはベクタラップ構造で定義。
2. デフォルトのハッシュ関数 (`equal-hash`, `string-hash`, `symbol-hash`) および等価性述語をサポート。
3. 動的リハッシュ（負荷率閾値超過時の自動拡張）機構を組み込み、O(1) 償却アクセスを保証。
4. `(srfi 69)` および `(srfi 125)` モジュールを策定する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `make-hash-table`, `hash-table-ref`, `hash-table-set!`, `hash-table-delete!` 等の基本操作がすべてパスすること。
- [ ] 動的リサイズおよび衝突解決が正常に機能すること。
- [ ] 2-Space コピー GC 下でキー・値オブジェクトが正しく追跡・移動されること。
- [ ] `ref_r7rs_compliance.md` の SRFI 69 / 125 ステータスを更新すること。

