---
ID: 610
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS (scheme base) 未実装コア手続き群 (string, 多引数 map/for-each, floor/, exact-integer-sqrt) の実装 (ID: 610)

## 1. 概要 / Summary
R7RS-small §6 および `(scheme base)` において未実装または部分サポートとなっている以下の標準手続き群を完全実装し、コアライブラリの適合率を引き上げる。
1. `(string char ...)`: 可変長文字並びからの文字列構築
2. `(map proc list1 list2 ...)` / `(for-each proc list1 list2 ...)`: 複数リスト引数への対応
3. SRFI 141 整数除算ペアおよび床除算剰余修正:
   - `floor/`, `floor-quotient`, `floor-remainder`
   - `truncate/`, `truncate-quotient`, `truncate-remainder`
   - 負数を含む異符号オペランドでの `modulo` を床除算剰余に適合修正
4. `(exact-integer-sqrt k)`: 非負整数の平方根整数部 $s$ と剰余 $r$ （$k = s^2 + r$）の多値返却

---

## 2. トレーサビリティ / Traceability
- R7RS-small:
  - §6.2.6: Numerical operations (`floor/`, `floor-quotient`, `floor-remainder`, `truncate/`, `truncate-quotient`, `truncate-remainder`, `exact-integer-sqrt`, `modulo`)
  - §6.4 / §6.10: Control features (`map`, `for-each`)
  - §6.7: Strings (`string`)
- 関連仕様書:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.2, 6.7, 6.10), §1.4 (`(scheme base)`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/string.scm](../../ulisp/lib/string.scm): `string` コンストラクタの実装
- [ ] [ulisp/lib/list.scm](../../ulisp/lib/list.scm): 多引数版 `map` および `for-each` の実装
- [ ] [ulisp/lib/math.scm](../../ulisp/lib/math.scm): `floor/`, `truncate/`, `exact-integer-sqrt`, `modulo` 修正の実装
- [ ] [ulisp/lib/scheme/base.sld](../../ulisp/lib/scheme/base.sld): 追加手続きのエクスポート宣言
- [ ] [ulisp/tests/test_base_procedures.scm](../../ulisp/tests/test_base_procedures.scm): 各種手続きの単体テスト
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md): 準拠ステータス更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/610-implement-r7rs-base-core-procedures`

1. `string`: 可変長引数リストを受け取り、長さを取得して `make-string` を確保、ループで `string-set!` を行う。
2. `map` / `for-each`: 引数リスト群が空になるまで `car` 群を収集して `apply` し、`cdr` 群を再帰走査する可変長リスト走査ルーチンを実装。
3. `floor/` / `truncate/`: 商と余りを計算し `values` で多値返却する基本演算を定義。異符号オペランド時の商・剰余の丸め方向を数学的に正しく処理。
4. `exact-integer-sqrt`: ニュートン法または二分探索により $s = \lfloor\sqrt{k}\rfloor$ と $r = k - s^2$ を算出し、`(values s r)` を返却。
5. テストスイートを作成し、各種エッジケース（ゼロ除算、空引数、負数、多値受け取り）を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(string #\a #\b #\c)` が `"abc"` を返し、空引数 `(string)` が `""` を返すこと。
- [ ] `(map + '(1 2 3) '(10 20 30))` が `'(11 22 33)` を返すこと。
- [ ] `floor/`, `floor-quotient`, `floor-remainder` および `truncate/` 系が仕様通りの商と剰余を返すこと。
- [ ] `exact-integer-sqrt` が正しく $s$ と $r$ を多値で返すこと。
- [ ] `(scheme base)` からこれらすべての手続きがインポート可能であること。
