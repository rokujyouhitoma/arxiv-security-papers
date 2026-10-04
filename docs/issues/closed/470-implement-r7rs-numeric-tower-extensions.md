---
ID: 470
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] R7RS 数値タワー拡張プリミティブおよび複素数算術の実装 (ID: 470)

## 1. 概要 / Summary

R7RS-small (Revised^7 Report on the Algorithmic Language Scheme) 第 6.2 節 (Numbers) および標準ライブラリ `(scheme complex)` に準拠するため、数値タワーを完備し、以下の拡張プリミティブ群を ILISP に実装する：
1. **正確な整数平方根と余り (`exact-integer-sqrt`)**:
   - `(exact-integer-sqrt k)`
   - 非負の正確な整数 $k$ に対し、多値 `(values s r)` を返却（$s^2 \le k < (s+1)^2$, $r = k - s^2$）。
2. **複素数述語・構築・分解 (`(scheme complex)`)**:
   - `(complex? z)`: すべての数値（実数を含む）および複素数型を判定。
   - `(make-rectangular x1 x2)`: 直交座標形式から複素数 $x_1 + x_2 i$ を構築。
   - `(make-polar x3 x4)`: 極座標形式（絶対値 $x_3$、偏角 $x_4$）から複素数を構築。
   - `(real-part z)`: 複素数（または実数）の実部を返却。
   - `(imag-part z)`: 複素数（または実数）の虚部を返却（実数の場合は 0）。
   - `(magnitude z)`: 複素数（または実数）の絶対値（モジュラス）を返却。
   - `(angle z)`: 複素数（または実数）の偏角（ラジアン）を返却。
3. **有理数・実数述語の精緻化**:
   - `(rational? z)`: 有限な実数値（非数・無限大・非ゼロ虚部を除外）を判定。
   - `(real? z)`: 虚部が 0 の数値（`int`, `float`, 虚部ゼロの `complex`）を判定。
4. **コア算術および等価性の複素数透過的サポート**:
   - `+`, `-`, `*`, `/`, `=`, `eqv?`, `equal?` における Python `complex` 型のゼロオーバーヘッド相互運用。

---

## 2. トレーサビリティ / Traceability

- **R7RS 6.2.5 Numerical operations**:
  - `(exact-integer-sqrt k)`: "Returns two non-negative exact integers s and r where k = s^2 + r and k < (s+1)^2."
  - `(complex? z)`, `(real? z)`, `(rational? z)`, `(integer? z)`: "Numerical tower predicates"
  - `(make-rectangular x1 x2)`, `(make-polar x3 x4)`
  - `(real-part z)`, `(imag-part z)`, `(magnitude z)`, `(angle z)`
- **R7RS 7.1.1 Standard Libraries**:
  - `(scheme complex)`: `angle`, `imag-part`, `magnitude`, `make-polar`, `make-rectangular`, `real-part`
- **ILISP R7RS 仕様準拠マトリクス**:
  - [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ilisp/numbers.py](../../ilisp/numbers.py): `exact_integer_sqrt`, `complex_p`, `real_p`, `rational_p`, `make_rectangular`, `make_polar`, `real_part`, `imag_part`, `num_magnitude`, `num_angle` の追加
- [x] [ilisp/env.py](../../ilisp/env.py): コア算術・等価性プリミティブの `complex` 型対応、および `make_initial_env` 辞書へのバインディング登録
- [x] [ilisp/syntax.py](../../ilisp/syntax.py): `core_forms` 予約語セットへの追加
- [x] [tests/ilisp/test_numeric_tower_extensions.py](../../tests/ilisp/test_numeric_tower_extensions.py): 新規単体テスト（平方根多値、複素数算術、極座標、直交座標、等価性）
- [x] [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md): 仕様準拠マトリクスの更新 (189 -> 197 / 203) および `(scheme complex)` 完備ステータス更新

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/470-implement-r7rs-numeric-tower-extensions`

1. **`ilisp/numbers.py` の拡張**:
   - `Number = Union[int, float, complex]`
   - `exact_integer_sqrt(k: Any) -> Values`: `math.isqrt(k)` と差分余りの多値返却。
   - `complex_p(x: Any) -> bool`: `isinstance(x, (int, float, complex)) and not isinstance(x, bool)`。
   - `real_p(x: Any) -> bool`: 実数判定（虚部 0 の複素数も許容）。
   - `rational_p(x: Any) -> bool`: 有限実数判定。
   - `make_rectangular(x1: Any, x2: Any) -> complex`: `complex(x1, x2)`。
   - `make_polar(x3: Any, x4: Any) -> complex`: `cmath.rect(x3, x4)`。
   - `real_part(z: Any) -> Union[int, float]`: `z.real`。
   - `imag_part(z: Any) -> Union[int, float]`: `z.imag`（実数は 0）。
   - `num_magnitude(z: Any) -> Union[int, float]`: `abs(z)`。
   - `num_angle(z: Any) -> float`: `cmath.phase(z)`。
2. **`ilisp/env.py` の算術・等価性更新**:
   - `prim_eqv_p` および `prim_equal_p` に `complex` を型チェック対象に追加。
   - `primitives` 辞書に新設プリミティブを登録。
3. **`ilisp/syntax.py` の同期**:
   - `core_forms` に `exact-integer-sqrt`, `complex?`, `make-rectangular`, `make-polar`, `real-part`, `imag-part`, `magnitude`, `angle` を登録。
4. **単体テスト (`tests/ilisp/test_numeric_tower_extensions.py`)**:
   - `exact-integer-sqrt` の完全平方数・非完全平方数・多値受け取り (`let-values`)。
   - 複素数直交構築・極座標構築・実部虚部分解・絶対値・偏角。
   - 四則演算との連携 (`+`, `-`, `*`, `/`)。
5. **品質ゲートとドキュメント同期**:
   - 全体テスト PASS、`flake8`, `mypy --strict ilisp` 0 エラー。
   - `SPEC_R7RS.md` の更新。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `exact-integer-sqrt` が正確な整数平方根と余りの 2 値を返すこと
- [x] `complex?`, `make-rectangular`, `make-polar`, `real-part`, `imag-part`, `magnitude`, `angle` が R7RS 6.2 準拠で動作すること
- [x] 複素数の四則演算および `eqv?` 等価比較が正常に機能すること
- [x] 新規単体テストが全件 PASS すること
- [x] 既存の全 320 件の ILISP テストがすべて PASS すること
- [x] `flake8` 0 警告、`mypy --strict ilisp` 0 エラーであること
- [x] `ilisp/docs/SPEC_R7RS.md` が更新され、準拠率が向上していること
