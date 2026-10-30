---
ID: 610
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-10-30
---

# [FEAT/ENH] R7RS (scheme base) 未実装コア手続き群 (string, 多引数 map/for-each, floor/, exact-integer-sqrt) の実装 (ID: 610)

## 1. 概要 / Summary
R7RS-small §6 および `(scheme base)` において未実装または部分サポートとなっていた以下の標準手続き群を完全実装し、コアライブラリの適合率を引き上げた。
1. `(string char ...)`: 可変長文字並びからの文字列構築（Pass 026 コンストラクタ脱糖および Scheme ランタイム第一級手続きの両面サポート）
2. `(map proc list1 list2 ...)` / `(for-each proc list1 list2 ...)`: 複数リスト引数への完全対応（1引数・2引数のゼロオーバーヘッド高速パスと任意個引数のディスパッチ機構）および標準 `(apply proc arg ... rest)` 手続きの提供
3. SRFI 141 整数除算ペアおよび床除算剰余修正:
   - `floor/`, `floor-quotient`, `floor-remainder`
   - `truncate/`, `truncate-quotient`, `truncate-remainder`
   - 負数を含む異符号オペランドでの `modulo` を床除算剰余 (`floor-remainder`) に適合修正（LIR プリミティブおよび C バックエンド対応）
4. `(exact-integer-sqrt k)`: 非負整数の平方根整数部 $s$ と剰余 $r$ （$k = s^2 + r$）の多値返却（オーバーフロー安全な二分探索法）
5. `(scheme base)` エクスポート宣言の拡充と R7RS 仕様準拠ドキュメント (`ulisp/docs/ref_r7rs_compliance.md`) の更新

---

## 2. トレーサビリティ / Traceability
- R7RS-small:
  - §6.2.6: Numerical operations (`floor/`, `floor-quotient`, `floor-remainder`, `truncate/`, `truncate-quotient`, `truncate-remainder`, `exact-integer-sqrt`, `modulo`, `quotient`, `remainder`)
  - §6.4 / §6.10: Control features (`apply`, `map`, `for-each`)
  - §6.7: Strings (`string`, `make-string`, `string-set!`, `list->string`)
  - §7.1.1: Base library `(scheme base)`
- 関連仕様書:
  - [R7RS 仕様準拠状況リファレンス](../../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.2, 6.7, 6.10), §1.4 (`(scheme base)`)
- 関連 Issue:
  - [Issue #609: R7RS case-lambda 構文の実装](609-implement-r7rs-case-lambda-syntax.md)
  - [Issue #551: R7RS シーケンス標準ライブラリの実装](551-expand-r7rs-standard-library-procedures.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] Target Branch: `feat/610-implement-r7rs-base-core-procedures`
- [x] [ulisp/frontend/026_desugar_constructors.scm](../../../ulisp/frontend/026_desugar_constructors.scm): `desugar-string` 実装および Pass 026 への組み込み
- [x] [ulisp/lib/string.scm](../../../ulisp/lib/string.scm): `string` コンストラクタ関数の定義
- [x] [ulisp/lib/list.scm](../../../ulisp/lib/list.scm): `apply`, `%apply-list`, `%cars`, `%cdrs`, 多引数版 `map` および `for-each` の実装
- [x] [ulisp/lib/math.scm](../../../ulisp/lib/math.scm): `floor/`, `floor-quotient`, `floor-remainder`, `truncate/`, `truncate-quotient`, `truncate-remainder`, `exact-integer-sqrt` の実装
- [x] [ulisp/lir/129_lir_primitives.scm](../../../ulisp/lir/129_lir_primitives.scm): `modulo` のハードウェア床除算剰余（floored remainder）コード生成への修正
- [x] [ulisp/compiler/primitives.scm](../../../ulisp/compiler/primitives.scm): Arity 検証テーブル (`builtin-fixed-arity`, `builtin-min-arity`) の更新
- [x] [ulisp/lib/scheme/base.sld](../../../ulisp/lib/scheme/base.sld): 追加手続きのエクスポート宣言
- [x] [ulisp/tests/test_base_procedures.scm](../../../ulisp/tests/test_base_procedures.scm): 各種手続きの総合単体テストスイート (60/60 PASS)
- [x] [ulisp/Makefile](../../../ulisp/Makefile): `test_base_procedures` ターゲット追加
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md): 準拠ステータス更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/610-implement-r7rs-base-core-procedures`

### 4.1. `string` 手続きの実装
1. **Pass 026 脱糖 (AOT 静的展開)**:
   - `frontend/026_desugar_constructors.scm` に `desugar-string` を定義。
   - `(string arg1 arg2 ...)` を `(let ((s (make-string N))) (string-set! s 0 arg1) ... s)` に展開。
   - 引数 0 個の `(string)` は `""` に展開。
2. **ランタイム第一級関数**:
   - `ulisp/lib/string.scm` に `(define string (case-lambda (() "") (chars (list->string chars))))` を定義し、高階関数への引数受け渡しにも対応。

### 4.2. 多引数版 `map` / `for-each` および `apply` の実装
1. **`apply` 手続きの提供**:
   - `ulisp/lib/list.scm` に `%apply-list`（最大 16 引数までのダイレクトディスパッチテーブル）および `apply` 手続きを `case-lambda` で実装。
2. **多引数版 `map`**:
   - 1 リスト引数の場合: 既存の高速ループを使用。
   - 2 リスト引数の場合: `car` / `cdr` 同時並行走査によるゼロオーバーヘッド直接適用。
   - 3 リスト引数以上: `%any-null?`, `%cars`, `%cdrs` を用いて最短リスト終了時に停止する可変長再帰ループを適用。
3. **多引数版 `for-each`**:
   - `map` と同様のアーキテクチャで副作用実行し、終了時に `63` (`#<unspecified>`) を返却。
4. **静的 Arity チェッカー更新**:
   - `compiler/primitives.scm` の `builtin-min-arity` に `map`, `for-each`, `apply` (最小 2 引数) を登録。

### 4.3. SRFI 141 整数除算ペアおよび床除算剰余 (`modulo`) の修正
1. **`truncate/`, `truncate-quotient`, `truncate-remainder`**:
   - `truncate-quotient`: `(quotient n1 n2)`
   - `truncate-remainder`: `(remainder n1 n2)`
   - `truncate/`: `(values (truncate-quotient n1 n2) (truncate-remainder n1 n2))`
2. **`floor/`, `floor-quotient`, `floor-remainder`**:
   - 異符号かつ剰余非ゼロ時に商を $-1$、剰余を $+ n_2$ する標準床除算アルゴリズムを数学的に厳密に実装。
   - `floor-quotient`: 床除算の商を返却。
   - `floor-remainder`: 床除算の剰余を返却（符号は常に除数 $n_2$ と同符号またはゼロ）。
   - `floor/`: `(values (floor-quotient n1 n2) (floor-remainder n1 n2))`
3. **`modulo` 修正**:
   - R7RS §6.2.6 に従い、`ulisp/lir/129_lir_primitives.scm` における `modulo` の LIR 下降コードを床除算剰余計算（異符号時に除数を加算）へ更新。

### 4.4. `(exact-integer-sqrt k)` の実装
1. 非負整数チェック: $k < 0$ のときはエラー送出。
2. $k = 0 \to (values 0 0)$, $k = 1 \to (values 1 0)$。
3. $k > 1$ の場合: 区間 $[1, \min(k, 500000000)]$ におけるオーバーフロー安全な二分探索を行い、$s = \lfloor\sqrt{k}\rfloor$ と $r = k - s^2$ を算出して `(values s r)` を返却。
4. `compiler/primitives.scm` に `exact-integer-sqrt` (固定 arity 1) を登録。

### 4.5. `(scheme base)` およびドキュメント更新
1. `ulisp/lib/scheme/base.sld` の export リストに以下を追加:
   - `floor/`, `floor-quotient`, `floor-remainder`
   - `truncate/`, `truncate-quotient`, `truncate-remainder`
   - `exact-integer-sqrt`
2. `ulisp/docs/ref_r7rs_compliance.md` の準拠ステータスを更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `(string #\a #\b #\c)` が `"abc"` を返し、空引数 `(string)` が `""` を返すこと。
- [x] `(map + '(1 2 3) '(10 20 30))` が `'(11 22 33)` を返し、3引数以上の `(map list '(1 2) '(a b) '(x y))` が正しく動作すること。
- [x] 長さの異なるリストを与えた場合、最短リストの終了時に安全に終了すること。
- [x] `for-each` が複数リスト引数に対して正しく副作用を実行すること。
- [x] `floor/`, `floor-quotient`, `floor-remainder` が正負の組み合わせ（正/正, 負/正, 正/負, 負/負）すべてにおいて数学的に正確な商と剰余を返すこと。
- [x] `modulo` が床除算剰余 (`floor-remainder`) と一致し、異符号で正しい符号と値を返すこと。
- [x] `truncate/`, `truncate-quotient`, `truncate-remainder` が R7RS 仕様通りの商と剰余を多値および単値で返すこと。
- [x] `exact-integer-sqrt` が 0, 1, 平方数, 非平方数の各エッジケースで正確な $s$ と $r$ を多値返却し、$k < 0$ でエラーとなること。
- [x] `(scheme base)` からこれらすべての手続きがインポート可能であること。
- [x] `make -C ulisp test` が全件 PASS すること。

