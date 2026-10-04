---
ID: 472
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] R7RS 超越関数・浮動小数点数学関数および (scheme inexact) ライブラリの実装 (ID: 472)

## 1. 概要 / Summary

R7RS-small (Revised^7 Report on the Algorithmic Language Scheme) 第 6.2.6 節 (Numerical operations) および標準ライブラリ `(scheme inexact)` に準拠するため、以下の超越関数・初等数学関数および標準ライブラリを ILISP に実装する：

1. **三角関数・逆三角関数**:
   - `(sin z)`, `(cos z)`, `(tan z)`: 実数および複素数対応（`math` / `cmath` 連動）
   - `(asin z)`, `(acos z)`: 逆正弦・逆余弦（定義域外実数および複素数の複素数分岐切断対応）
   - `(atan z)`: 単項形式（偏角・逆正接）
   - `(atan y x)`: 2引数形式（実数 $y, x$ に対する象限考慮逆正接 `atan2`）
2. **指数・対数・平方根**:
   - `(exp z)`: 自然指数関数 $e^z$（実数・複素数）
   - `(log z)`: 自然対数 $\ln(z)$（実数・負数/複素数の主値枝切断対応）
   - `(log z b)`: 底 $b$ を指定した対数 $\log_b(z) = \frac{\ln(z)}{\ln(b)}$
   - `(sqrt z)`: 平方根（非負整数の完全平方数整数化、負数・複素数の虚数単位対応）
3. **浮動小数点数・複素数状態述語の強化**:
   - `(finite? z)`, `(infinite? z)`, `(nan? z)`: 実数および複素数実部・虚部を考慮した安全判定。
4. **標準ライブラリ `(scheme inexact)` の提供**:
   - `(import (scheme inexact))` による全 12 手続きのエクスポート：
     `acos`, `asin`, `atan`, `cos`, `exp`, `finite?`, `infinite?`, `log`, `nan?`, `sin`, `sqrt`, `tan`。

---

## 2. トレーサビリティ / Traceability

- **R7RS 6.2.6 Numerical operations**:
  - `(exp z)`, `(log z)`, `(log z b)`
  - `(sin z)`, `(cos z)`, `(tan z)`
  - `(asin z)`, `(acos z)`, `(atan z)`, `(atan y x)`
  - `(sqrt z)`
  - `(finite? z)`, `(infinite? z)`, `(nan? z)`
- **R7RS 7.1.1 Standard Libraries**:
  - `(scheme inexact)`
- **ILISP R7RS 仕様準拠マトリクス**:
  - [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ilisp/numbers.py](../../ilisp/numbers.py): `num_sin`, `num_cos`, `num_tan`, `num_asin`, `num_acos`, `num_atan`, `num_exp`, `num_log`, `num_sqrt` の拡張、および `finite_p`/`infinite_p`/`nan_p` の複素数対応
- [x] [ilisp/env.py](../../ilisp/env.py): 数学関数プリミティブの追加および `make_initial_env` 辞書へのバインディング登録
- [x] [ilisp/module.py](../../ilisp/module.py): `(scheme inexact)` ライブラリ定義の登録
- [x] [ilisp/syntax.py](../../ilisp/syntax.py): `core_forms` への数学関数識別子の登録
- [x] [tests/ilisp/test_inexact.py](../../tests/ilisp/test_inexact.py): 単体テスト（三角関数恒等式、2引数atan、2引数log、負数sqrt、import検証）
- [x] [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md): 仕様マトリクスの更新 (`(scheme inexact)` 🟢 100% 準拠化)
- [x] [docs/issues/README.md](README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/472-implement-r7rs-scheme-inexact-transcendental-math`

1. **`ilisp/numbers.py` の数学関数実装**:
   - `num_sin(z: Number) -> Number`: 実数は `math.sin`、複素数は `cmath.sin`。
   - `num_cos(z: Number) -> Number`: 実数は `math.cos`、複素数は `cmath.cos`。
   - `num_tan(z: Number) -> Number`: 実数は `math.tan`、複素数は `cmath.tan`。
   - `num_asin(z: Number) -> Number`: $|z| \le 1$ は `math.asin`、超えるか複素数は `cmath.asin`。
   - `num_acos(z: Number) -> Number`: $|z| \le 1$ は `math.acos`、超えるか複素数は `cmath.acos`。
   - `num_atan(*args: Any) -> Number`:
     - 1引数: 実数は `math.atan`、複素数は `cmath.atan`。
     - 2引数: `(atan y x)` -> `math.atan2(y, x)`。
   - `num_exp(z: Number) -> Number`: 実数は `math.exp`、複素数は `cmath.exp`。
   - `num_log(*args: Any) -> Number`:
     - 1引数: 正実数は `math.log(z)`、非正または複素数は `cmath.log(z)`。
     - 2引数: `(log z b)` -> `log(z) / log(b)`。
   - `num_sqrt(z: Number) -> Number`:
     - 非負実数: 完全平方数の整数化または `math.sqrt`。
     - 負の実数または複素数: `cmath.sqrt`。
   - `finite_p`, `infinite_p`, `nan_p`: 複素数オブジェクトの `.real`, `.imag` 両方へのディスパッチ。
2. **`ilisp/env.py` の同期**:
   - `primitives` 辞書に `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `exp`, `log` を登録。
3. **`ilisp/module.py` の同期**:
   - `(scheme inexact)` ライブラリを登録。
4. **`ilisp/syntax.py` の同期**:
   - `core_forms` に `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `exp`, `log` を追加。
5. **単体テスト (`tests/ilisp/test_inexact.py`)**:
   - オイラーの公式・ピタゴラス恒等式 $\sin^2(x) + \cos^2(x) = 1$。
   - `(atan y x)` 4象限テスト。
   - `(log 8 2)` -> 3.0 等の2引数対数。
   - `(sqrt -4)` -> `0+2i` または虚数判定。
   - `(import (scheme inexact))` によるインポートテスト。
6. **品質ゲートとドキュメント同期**:
   - `pytest`, `flake8`, `mypy --strict ilisp`。
   - `SPEC_R7RS.md` の更新。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] 三角関数・逆三角関数（`sin`, `cos`, `tan`, `asin`, `acos`, `atan`）が実数・複素数で正常動作すること
- [x] 2引数 `atan` (`(atan y x)`) が象限を正しく判定すること
- [x] `exp` および 1引数/2引数 `log` が正しく計算されること
- [x] `sqrt` が負数・複素数で正しく虚部を持つ平方根を返すこと
- [x] `finite?`, `infinite?`, `nan?` が複素数でもエラーにならず正しく判定すること
- [x] `(import (scheme inexact))` で 12 手続きが正常にインポートできること
- [x] 新規単体テストが全件 PASS すること
- [x] 既存の全 338 件のテストが 100% PASS すること
- [x] `flake8` 0 警告、`mypy --strict ilisp` 0 エラーであること
- [x] `ilisp/docs/SPEC_R7RS.md` が更新され、`(scheme inexact)` が Fully Supported になること
