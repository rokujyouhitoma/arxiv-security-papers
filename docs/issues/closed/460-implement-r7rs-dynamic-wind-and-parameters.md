# Issue #460: R7RS 動的環境と保護機構の実装 (dynamic-wind, make-parameter, parameterize)

## 1. 概要 (Overview)
ILISP はこれまでに Scheme のレキシカルスコープ、モジュール機構、マクロ展開器、バイトベクタ、バイナリポート、および文字・文字列システムを確立した。
しかし、資源の確実な解放（ファイルのクローズ、一時ファイル・ポートの破棄、排他ロックの解除など）や、動的コンテキスト（カレントポート、探索深度、デバッグトレースレベルなど）のスレッド安全・動的スコープ管理を行うためには、R7RS-small 仕様の第 6.10 節（Control features）に規定されている **`dynamic-wind`** および **パラメータ機構 (`make-parameter`, `parameterize`)** が不可欠である。

本 Issue では、脱出継続 (`call/cc`) や例外送出 (`raise`, `guard`) と完全に協調してスタックのワインディング／アンワインディングを保証する `dynamic-wind` と、スレッド安全な動的スコープ変数を提供する `make-parameter` / `parameterize` を設計・実装する。

---

## 2. 目的とゴール (Goals)
1. **`dynamic-wind` 保護機構の実装 (`ilisp/evaluator.py`, `ilisp/env.py`)**:
   - `(dynamic-wind before-thunk thunk after-thunk)` の実装
   - 正常終了時だけでなく、Python 例外、`raise` による Scheme 例外、および `call/cc` による脱出継続ジャンプ時にも確実に `after-thunk` が実行されることを保証
   - ネストした `dynamic-wind` フレームにおける正しい順序でのクリーンアップ
2. **動的パラメータ機構の実装 (`ilisp/param.py`, `ilisp/types.py`, `ilisp/env.py`)**:
   - `Parameter` クラス（Python `ContextVar` または動的スタックを内部保持する呼び出し可能オブジェクト）
   - `(make-parameter init [converter])`: 初期値および値検証・変換コンバータ付きパラメータ生成
   - ゲッター `(param)` およびセッター `(param new-val)` のサポート
3. **`parameterize` 特殊形式 / 構文マクロの実装 (`ilisp/evaluator.py` または `stdlib/base.ilisp`)**:
   - `(parameterize ((param1 val1) ...) body ...)`
   - `dynamic-wind` を用いて、ブロック突入時に古い値を退避して新値を設定し、脱出時に確実に旧値を復元するセマンティクスの実装
4. **Backend A (Python AST コンパイラ) への統合 (`ilisp/backend/py_codegen/compiler.py`)**:
   - `dynamic-wind` の `try...finally` ブロックへのコード生成
   - `parameterize` のコード生成対応
5. **テストスイートの整備 (`tests/ilisp/test_dynamic_wind_and_parameters.py`)**:
   - 正常系・例外発生時の `before`/`after` 実行順序検証
   - `call/cc` 脱出時の `after` 実行保証検証
   - `parameterize` による動的スコープ一時変更と復元検証
   - コンバータ手続きの動作検証
6. **仕様書・DoD の更新 (`ilisp/docs/SPEC_R7RS.md`)**:
   - 第6.10節の `dynamic-wind` ステータスを ✅ 完全準拠へ更新。

---

## 3. 完了条件 (Definition of Done)
- [x] `dynamic-wind` が正常終了、例外送出、脱出継続 (`call/cc`) のいずれにおいても `before` -> `thunk` -> `after` の規約を守って動作すること。
- [x] `make-parameter` で作成したパラメータが値の取得・更新およびコンバータ変換を正しく行えること。
- [x] `parameterize` が動的スコープ内でパラメータを一時変更し、ブロック脱出時に確実に復元すること。
- [x] Backend A (Python AST トランスパイラ) が `dynamic-wind` およびパラメータ操作を正常にコンパイル・実行できること。
- [x] `tests/ilisp/test_dynamic_wind_and_parameters.py` の全テストが 100% PASS すること。
- [x] 既存の全テスト（162件）がリグレッションなく 100% PASS すること。
- [x] `flake8` および `mypy --strict` をエラー 0 件でパスすること。
- [x] `ilisp/docs/SPEC_R7RS.md` の仕様準拠状況が更新されていること。

---

## 4. 実装結果サマリー (Implementation Results)
- **`dynamic-wind` 保護機構の実装 (`ilisp/env.py`)**:
  - `(dynamic-wind before-thunk thunk after-thunk)` をプリミティブとして実装。
  - `try...finally` ブロックにより、正常終了、Python 例外、Scheme 例外 (`raise`)、および `call/cc`（脱出継続ジャンプ）のいずれの経路であっても `after-thunk` の確実な実行とスタック巻き戻し（unwinding）を保証。
- **動的パラメータ型 `Parameter` (`ilisp/types.py`, `ilisp/env.py`)**:
  - Python `contextvars.ContextVar` を基盤としたスレッド安全・非同期コンテキスト対応の `Parameter` クラスを実装。
  - `(make-parameter init [converter])` による初期値設定およびコンバータ手続き（Scheme `Procedure` 含む）による変換・検証。
  - ゲッター `(param)`、セッター `(param new-val)`、述語 `parameter?` を完備。
  - `ilisp/evaluator.py` の自己評価リテラル型として統合。
- **`parameterize` 構文マクロ (`ilisp/stdlib/base.ilisp`)**:
  - `dynamic-wind` 上で構築された動的スコープパラメータ一時束縛マクロを実装。
  - ブロック突入時に旧値を退避して新値を設定し、ブロック脱出時に確実に旧値を復元。
  - ネストした `parameterize`、ブロック内例外発生時、および `call/cc` 脱出時にも旧値が確実に復元されることを検証。
- **Backend A (Python AST コンパイラ) 統合 (`ilisp/backend/py_codegen/compiler.py`)**:
  - `Parameter` をランタイムインポートに追加し、`dynamic-wind` および `parameterize` を含むコードの正常なトランスパイル・実行を検証。
- **品質・テスト検証**:
  - `tests/ilisp/test_dynamic_wind_and_parameters.py`: 全 14 件 100% PASS。
  - `tests/ilisp/`: 全 176 件 100% PASS。
  - `flake8`: 0 警告、`mypy --strict`: 0 エラー。

