# Issue #465: R7RS リスト拡張操作の網羅 (R7RS 6.4 / Pairs and lists)

## 1. 概要 (Overview)
R7RS-small 第6.4節「Pairs and lists」に規定されているリスト拡張操作・要素アクセス・破壊的変更・多引数走査プリミティブ群を ILISP に実装・完備する。
具体的には、インデックス指定参照 `list-ref`、部分リスト抽出 `list-tail`、インプレース更新 `list-set!`、リスト動的確保 `make-list`、背骨浅い複製 `list-copy`、フロイドの循環検出による真正リスト判定 `list?`、ペア更新 `set-car!` / `set-cdr!`、ならびに多引数版 `map` および `for-each`（最短長同期）を実装する。

## 2. 背景・動機 (Background & Motivation)
- **R7RS 6.4 リスト仕様の完全準拠**: ILISP は基本リスト操作 (`cons`, `car`, `cdr`, `null?`, `pair?`, `append`, `reverse`, `member`, `assoc` 等) をサポートしているが、インデックス操作 (`list-ref`, `list-tail`, `list-set!`) や動的確保 (`make-list`)、背骨複製 (`list-copy`) は未実装であり、`list?` や `map`/`for-each` も単一リスト版や基本判定にとどまっていた。
- **配列風インデックス操作とデータ構造**: リスト上の任意位置アクセス (`list-ref`) や先頭スキップ (`list-tail`)、インプレース要素置換 (`list-set!`) を提供することで、アルゴリズムの実装が容易になる。
- **循環リストに対する安全な型判定**: 不正な循環ペア（Cyclic pairs）が渡された場合でも無限ループに陥らないフロイドの循環検出アルゴリズム（Tortoise and Hare）による `list?` を確立する。
- **多変量関数型マッピング**: 複数のリストを同時に走査する多引数 `map` および `for-each` を提供し、関数型プログラミング表現力を最大化する。

## 3. 要件仕様 (Requirements Specification)
### 3.1 インデックス・生成・複製操作
- `(make-list k [fill])`:
  - 長さ `k` のリストを動的生成。要素は `fill`（デフォルトは空リスト `'()`）。`k` が負ならエラー。
- `(list-tail list k)`:
  - 先頭から `k` 回 `cdr` を適用したサブリスト/末尾オブジェクトを返却。`k=0` のときは `list` そのもの。`k` がリスト長を超える場合はエラー。不完全リスト（dotted list）でも末尾までアクセス可能。
- `(list-ref list k)`:
  - `(car (list-tail list k))` と同等。`k` 番目（0-indexed）の要素を返却。インデックス超過時はエラー。
- `(list-set! list k obj)`:
  - `k` 番目のペアの `car` を `obj` で破壊的更新（未定義値を返却）。
- `(list-copy obj)`:
  - `obj` がペアの場合は背骨（spine）を新設して浅いコピーを生成。不完全リストの場合は最後のペアの `cdr` をそのまま共有。非ペアならそのまま返却。

### 3.2 述語・破壊的変更
- `(list? obj)`:
  - 循環のない有限の真正リスト（Proper list: 空リスト `'()` で終端するペア列）の場合のみ `#t`、循環リストや不完全リスト、非ペアは `#f`。
- `(set-car! pair obj)`, `(set-cdr! pair obj)`:
  - ペアの `car` / `cdr` をインプレースに書き換え。

### 3.3 多引数リスト走査
- `(map proc list1 list2 ...)`:
  - 1個以上のリストを受け取り、対応する要素を引数として `proc` を適用した結果からなる新しいリストを返却。リスト長が異なる場合は最短長で停止。
- `(for-each proc list1 list2 ...)`:
  - 1個以上のリストを受け取り、対応する要素を引数として `proc` を適用し副作用を実行（未定義値を返却）。最短長で停止。

## 4. 影響範囲・対象ファイル (Target Files)
- `ilisp/types.py`: `Cons` の `set_car`, `set_cdr` 破壊的更新の明確化
- `ilisp/env.py`:
  - `prim_list_p` (フロイド循環検出)
  - `prim_make_list`, `prim_list_tail`, `prim_list_ref`, `prim_list_set_bang`, `prim_list_copy`
  - `prim_set_car_bang`, `prim_set_cdr_bang`
  - プリミティブ辞書への登録
- `ilisp/stdlib/base.ilisp`: 多引数対応版 `map` および `for-each`（Scheme マクロまたは関数として高速実装）
- `tests/ilisp/test_list_extensions.py`: 新規テストスイート
- `ilisp/docs/SPEC_R7RS.md`: 第6.4節リストカテゴリの更新
- `docs/issues/closed/465-implement-r7rs-list-extension-operations.md`: クローズされた本 Issue ファイル

## 5. DoD (Definition of Done)
- [x] `make-list`, `list-tail`, `list-ref`, `list-set!`, `list-copy` が R7RS 6.4 に準拠して動作する。
- [x] `list?` が循環リストでも停止し、有限真正リストのみ `#t` を返却する。
- [x] `set-car!`, `set-cdr!` によるインプレース変更が正しく機能する。
- [x] `map` および `for-each` が任意個の多引数リストで最短長同期動作する。
- [x] Backend A (トランスパイラ) での実行と等価性が確認できる。
- [x] `tests/ilisp/test_list_extensions.py` を含む全テストが 100% PASS。
- [x] `flake8` 0 警告、`mypy --strict` 0 エラー。
- [x] `ilisp/docs/SPEC_R7RS.md` のリストカテゴリ準拠率が 100% に更新される。
