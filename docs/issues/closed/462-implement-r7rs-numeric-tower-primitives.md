# Issue #462: R7RS 数値タワー・算術プリミティブの拡充 (R7RS 6.2 / Numbers)

## 1. 概要 (Overview)
R7RS-small 第6.2節「Numbers」に規定されている標準数値プリミティブ群（数値述語、丸め・切り捨て、最大・最小・絶対値、最大公約数・最小公倍数、整数商・剰余、基数指定対応 `number->string` / `string->number`、正確性判定・変換）を ILISP に実装した。
コードの凝集度と保守性を高めるため、文字・文字列モジュール (`ilisp/char.py`) と同様に対称的な `ilisp/numbers.py` モジュールを新設し、`ilisp/env.py` および `(scheme base)` に登録した。

## 2. 背景・動機 (Background & Motivation)
- **R7RS 準拠性の向上**: 従来の ILISP は基本的な四則演算 (`+`, `-`, `*`) と商余剰のみを提供しており、R7RS 第6.2節の充足率は 31% (11/35) に留まっていた。
- **データ解析・アルゴリズム実装の要求**: 論文メタデータの統計処理、グラフアルゴリズム、ハッシュ計算、暗号学的操作において、`abs`, `min`, `max`, `gcd`, `lcm`, `round`, `floor`, 基数変換 (16進数/2進数等) は必須の基礎手続きである。
- **正確性・浮動小数点の厳密性**: Scheme 仕様に準拠した `exact?`, `inexact?`, `zero?`, `positive?`, `negative?`, `odd?`, `even?`, `nan?`, `infinite?`, `finite?` を提供することで、型安全な分岐制御を実現した。

## 3. 要件仕様 (Requirements Specification)
以下の標準プリミティブ群を `ilisp/numbers.py` に実装し、`ilisp/env.py` に登録した：

### 3.1 数値述語 (Predicates)
- `exact?`, `inexact?`: 正確数（int）/非正確数（float）判定
- `exact-integer?`: 正確な整数判定
- `finite?`, `infinite?`, `nan?`: 浮動小数の有限性・無限大・非数判定
- `zero?`, `positive?`, `negative?`: 符号判定
- `odd?`, `even?`: 偶奇判定

### 3.2 算術操作・統計・公約数 (Arithmetic & Properties)
- `abs`: 絶対値
- `min`, `max`: 任意個の引数の最小値・最大値（正確/非正確型の伝播）
- `gcd`, `lcm`: 任意個の整数の最大公約数および最小公倍数（0個引数時: `gcd` -> 0, `lcm` -> 1）

### 3.3 丸め・切り捨て (Rounding & Truncation)
- `floor`, `ceiling`, `truncate`, `round`: 引数が int の場合は int、float の場合は float（整数値）を返却

### 3.4 整数除算・商と剰余 (Integer Division)
- `floor/`, `floor-quotient`, `floor-remainder`: 床関数に基づく整数除算と多値/単一値返却
- `truncate/`, `truncate-quotient`, `truncate-remainder`: ゼロ方向切り捨てに基づく整数除算

### 3.5 正確性変換 (Exactness Conversion)
- `exact` (`exact->inexact` / `inexact->exact` 互換): int への変換、または exact/inexact 型キャスト
- `inexact`: float への変換

### 3.6 文字列・基数変換 (String & Radix Conversions)
- `number->string(z, [radix])`: 基数 2, 8, 10, 16 に対応した文字列変換（小文字出力）
- `string->number(str, [radix])`: 指定基数（デフォルト 10）による数値パース（失敗時は `#f` 返却）

## 4. 影響範囲・対象ファイル (Target Files)
- `ilisp/numbers.py`: 新規作成。数値タワー・算術プリミティブ群の実装
- `ilisp/env.py`: `ilisp/numbers.py` からのインポートおよびグローバル環境への登録
- `tests/ilisp/test_numeric_tower.py`: 新規作成。網羅的テストスイート
- `ilisp/docs/SPEC_R7RS.md`: 第6.2節のステータス更新
- `docs/issues/closed/462-implement-r7rs-numeric-tower-primitives.md`: 本 Issue ファイル

## 5. DoD (Definition of Done)
- [x] すべての対象数値プリミティブが R7RS 6.2 仕様通りに動作する。
- [x] 基数 (2, 8, 10, 16) 指定の `number->string` および `string->number` が正しく動作する。
- [x] 多引数 `min`, `max`, `gcd`, `lcm` が仕様通り動作する。
- [x] Backend A (Python AST トランスパイラ) での実行と等価性が確認できる。
- [x] `tests/ilisp/test_numeric_tower.py` を含む全テストが 100% PASS (203 passed)。
- [x] `flake8` 0 警告、`mypy --strict` 0 エラー。
- [x] `ilisp/docs/SPEC_R7RS.md` の数値タワー準拠ステータスが更新される (94% 充足)。
