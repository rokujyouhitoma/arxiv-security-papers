# Issue #463: R7RS ベクタ拡張プリミティブの網羅 (R7RS 6.8 / Vectors)

## 1. 概要 (Overview)
R7RS-small 第6.8節「Vectors」に規定されているベクタ拡張プリミティブ群（部分コピー `vector-copy`、ブロックインプレース代入 `vector-copy!`、一括塗りつぶし `vector-fill!`、複数ベクタ連結 `vector-append`、高階関数 `vector-map` および `vector-for-each`）を ILISP に実装する。
これにより、ベクタデータ構造に対する部分抽出、高速ブロック転送、インプレース変更、関数型走査の全仕様を 100% 網羅する。

## 2. 背景・動機 (Background & Motivation)
- **R7RS 準拠性の向上**: 現行の ILISP は基本ベクタ操作 (`vector?`, `make-vector`, `vector`, `vector-ref`, `vector-set!`, `vector-length`, `vector->list`, `list->vector`) を提供しているが、R7RS 6.8 の拡張機能（`vector-copy`, `vector-copy!`, `vector-fill!`, `vector-append`, `vector-map`, `vector-for-each`）は未実装（計画中）となっていた。
- **データ処理の高速化と配列アルゴリズム**: バイトベクタ (`bytevector-copy!`) や文字列 (`string-copy!`) で培ったブロック転送アルゴリズムを汎用ベクタへ適用することで、配列ソート、スライシング、バッファリング等のアルゴリズムが効率的に記述可能となる。
- **重複範囲安全なインプレース転送**: `vector-copy!` において転送元と転送先が同一ベクタかつ重複範囲を含む場合でも、メモリ破壊や値の意図せぬ上書きを起こさない安全なコピー順序（memmove 互換）を保証する。

## 3. 要件仕様 (Requirements Specification)
### 3.1 範囲操作・コピー
- `(vector-copy vec [start [end]])`:
  - `start`（デフォルト 0）から `end`（デフォルト `vector-length`）までの要素からなる新しいベクタを返却。
- `(vector-copy! to at from [start [end]])`:
  - `from` の `start` から `end` までの要素を、`to` のインデックス `at` 以降へ破壊的インプレースコピー。
  - `to` と `from` が同一インスタンスかつ `at > start` の場合は後方からコピーし、値破壊を防止。
- `(vector-fill! vec fill [start [end]])`:
  - `vec` の `start` から `end` までの要素を `fill` で一括上書き。

### 3.2 連結・高階関数
- `(vector-append vec ...)`:
  - 任意個のベクタを連結した新しいベクタを返却。引数 0 個の場合は空ベクタ `#()` を返却。
- `(vector-map proc vec1 vec2 ...)`:
  - 各ベクタの対応要素に `proc` を適用した結果からなる新しいベクタを返却。
- `(vector-for-each proc vec1 vec2 ...)`:
  - 各ベクタの対応要素に `proc` を適用して副作用走査（未定義値を返却）。

## 4. 影響範囲・対象ファイル (Target Files)
- `ilisp/env.py`: ベクタ拡張プリミティブの実装および環境登録
- `tests/ilisp/test_vector_extensions.py`: 新規作成。ベクタ拡張テストスイート
- `ilisp/docs/SPEC_R7RS.md`: 第6.8節ベクタ準拠ステータスの更新
- `docs/issues/closed/463-implement-r7rs-vector-extension-primitives.md`: 本 Issue ファイル

## 5. DoD (Definition of Done)
- [x] `vector-copy`, `vector-copy!`, `vector-fill!`, `vector-append`, `vector-map`, `vector-for-each` が R7RS 6.8 仕様に準拠して動作する。
- [x] `vector-copy!` において同一ベクタ内の前方/後方重複コピーが安全に動作する。
- [x] 多引数 `vector-map` および `vector-for-each` が正しく動作する。
- [x] Backend A (Python AST トランスパイラ) での実行と等価性が確認できる。
- [x] `tests/ilisp/test_vector_extensions.py` を含む全テストが 100% PASS。
- [x] `flake8` 0 警告、`mypy --strict` 0 エラー。
- [x] `ilisp/docs/SPEC_R7RS.md` のベクタ準拠ステータスが 100% 達成に更新される。

## 6. 実装成果と品質検証 (Verification & Results)
- `ilisp/env.py`:
  - `prim_vector_copy`: 範囲指定・デフォルト全域対応のスライス生成。
  - `prim_vector_copy_bang`: 一時バッファを経由した重複領域安全なインプレース転送（`memmove` 互換動作）。
  - `prim_vector_fill_bang`: インデックス範囲指定可能な要素一括上書き。
  - `prim_vector_append`: 任意個（0個含む）のベクタ連結。
  - `prim_vector_map`, `prim_vector_for_each`: 多引数対応・最短長同期のイテレーションと高階手続き適用。
- `tests/ilisp/test_vector_extensions.py`:
  - 18 件の単体・統合テストを新規作成、全 221 件の ilisp テストとともに 100% PASS。
- 静的解析・型検査:
  - `flake8` 0 警告、`mypy --strict ilisp` 0 エラー。
- 規格準拠ドキュメント:
  - `ilisp/docs/SPEC_R7RS.md` のベクタカテゴリ準拠率を 100% (14/14) に更新。
