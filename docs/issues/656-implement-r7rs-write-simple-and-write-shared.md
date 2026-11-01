---
ID: 656
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] R7RS §6.13.3 循環参照・共有構造表記対応ライター (write-simple, write-shared) の実装 (ID: 656)

## 1. 概要 / Summary
R7RS-small §6.13.3 および SRFI 38 で規定されている `(write-simple <obj> [<port>])` および `(write-shared <obj> [<port>])` 手続きを ULisp に実装し、ライブラリ `(scheme write)` の準拠度を 100% に引き上げる。
循環リストや循環ベクタなどの自己参照・共有構造を含むデータ構造を出力する際、無限ループでクラッシュすることなく `#1=(a . #1#)` 形式の datum label 記法で安全に出力可能にする。

---

## 2. トレーサビリティ / Traceability
- R7RS-small: Section 6.13.3 (Output procedures - write-shared, write-simple)
- 仕様リファレンス: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.13.3), §1.4 (`(scheme write)`)
- 関連モジュール: [ulisp/lib/printer.scm](../../ulisp/lib/printer.scm), [ulisp/lib/scheme/write.sld](../../ulisp/lib/scheme/write.sld)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/printer.scm](../../ulisp/lib/printer.scm)
- [ ] [ulisp/lib/scheme/write.sld](../../ulisp/lib/scheme/write.sld)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)
- [ ] [ulisp/tests/test_printer.scm](../../ulisp/tests/test_printer.scm) (追加テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/656-implement-r7rs-write-simple-and-write-shared`

1. `write-simple`: 循環参照や共有構造を追跡せず、単に木構造として S 式を出力する高速ライター（現状の `write` の挙動に相当）。
2. `write-shared`:
   - 第 1 パス: 対象オブジェクトを深さ優先探索し、訪問回数をハッシュテーブルまたは連想リストで記録して共有・循環ノードを検出。
   - 第 2 パス: 複数回参照されるノードに `#1=`, `#2=` 等のラベルを付与しながら出力し、2回目以降の出現時は `#1#`, `#2#` として出力。
3. `(scheme write)` から `write`, `display`, `write-simple`, `write-shared` の全 4 手続きをエクスポート。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 循環リスト `(let ((x (list 1 2))) (set-cdr! (cdr x) x) x)` を `write-shared` してもハングせず、`#1=(1 2 . #1#)` 形式で正しく出力されること。
- [ ] `write-simple` が循環構造に対して木展開を試みる仕様通り動作すること。
- [ ] `(scheme write)` の準拠率が 100% となること。
- [ ] `ref_r7rs_compliance.md` の §6.13.3 および §1.4 を更新すること。

