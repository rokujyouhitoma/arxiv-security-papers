# Issue #466: R7RS 構造化エラー例外機構・エラー述語・アクセサの完備 (R7RS 6.11 / Exceptions)

## 1. 概要 (Overview)
R7RS-small 第6.11節「Exceptions」で規定されている構造化エラーオブジェクト型 (`ErrorObject`)、エラー型判定述語 (`error-object?`, `read-error?`, `file-error?`)、エラー情報アクセサ (`error-object-message`, `error-object-irritants`)、および `error` 手続きの構造化連携を ILISP に実装・完備する。
また、Python 由来の I/O エラー (`OSError`, `FileNotFoundError`) や構文エラー (`SyntaxError`, `LispSyntaxError`) が発生した際に自動的に適切なエラーオブジェクトに変換し、Scheme の `guard` や `with-exception-handler` で透過的にキャッチ・分類可能にする。

## 2. 背景・動機 (Background & Motivation)
- **R7RS 6.11 例外機構の完全準拠**: 現在 ILISP は `with-exception-handler`, `raise`, `guard` のコア機構をサポートしているが、`error` 手続きで発生したエラーオブジェクトを検査・分解する述語・アクセサ (`error-object?`, `error-object-message`, `error-object-irritants`, `read-error?`, `file-error?`) が未実装であった。
- **構造化例外処理と安全な障害復旧**: 文字列やシンボルの単純例外だけでなく、メッセージ文字列と irritants リストを保持する正式な `ErrorObject` を導入することで、Scheme プログラムが障害の原因をプログラム的・構造的に分析し、適切にハンドリング・リカバリできるようにする。
- **Python ランタイムエラーとのシームレスな統合**: Python のファイルI/O例外（`FileNotFoundError` 等）やリーダーのパースエラーを Scheme の `file-error?` や `read-error?` で正確に識別可能にし、実用的な耐障害性を高める。

## 3. 要件仕様 (Requirements Specification)
### 3.1 構造化エラーオブジェクト型
- `ErrorObject` クラスを `ilisp/types.py` に新設:
  - 属性: `message: str`, `irritants: Any` (Scheme List), `kind: str` (例: `"generic"`, `"read"`, `"file"`)
  - `SchemeException` と連携し、`error` 手続きまたは Python エラー時に生成
  - 文字列表現: `&error-object(kind=..., message=..., irritants=...)`

### 3.2 エラー述語・アクセサ
- `(error-object? obj)`:
  - `obj` が `ErrorObject` の場合 `#t`、そうでなければ `#f`。
- `(error-object-message error-obj)`:
  - エラーメッセージ文字列を返却。`ErrorObject` でない場合はエラー。
- `(error-object-irritants error-obj)`:
  - 追加引数（irritants）の Scheme リスト（`Cons` または `Nil`）を返却。`ErrorObject` でない場合はエラー。
- `(read-error? obj)`:
  - `obj` が `ErrorObject` であり、構文エラー・リーダーエラーに起因する場合 `#t`。
- `(file-error? obj)`:
  - `obj` が `ErrorObject` であり、ファイルオープン・I/O操作に起因する場合 `#t`。

### 3.3 構造化 `error` 手続きおよび Python 例外変換
- `(error message irritant ...)`:
  - `message` (str) と任意個の `irritants` から `ErrorObject` を生成し、`SchemeException(err_obj)` を送出。
- `with-exception-handler` / `guard`:
  - Python の `FileNotFoundError`, `OSError`, `IOError` が捕捉された場合、`kind="file"` の `ErrorObject` をハンドラに伝播。
  - `LispSyntaxError`, `SyntaxError` が捕捉された場合、`kind="read"` の `ErrorObject` をハンドラに伝播。
  - その他の Python `Exception` が捕捉された場合、`kind="generic"` の `ErrorObject` を生成してハンドラに伝播。

## 4. 影響範囲・対象ファイル (Target Files)
- `ilisp/types.py`: `ErrorObject` クラス新設、述語 `is_error_object`, `is_read_error`, `is_file_error` 実装
- `ilisp/env.py`:
  - `prim_error_object_p`, `prim_error_object_message`, `prim_error_object_irritants`
  - `prim_read_error_p`, `prim_file_error_p`, `prim_read_error`, `prim_file_error`
  - `prim_error` の `ErrorObject` 化
  - `prim_with_exception_handler` の Python 例外変換強化
  - プリミティブ辞書への登録
- `ilisp/stdlib/base.ilisp`: `guard` マクロの節不一致時のフォールバック re-raise 実装
- `ilisp/backend/py_codegen/compiler.py`: `ErrorObject` ランタイムインポート
- `tests/ilisp/test_exceptions.py`: 新規テストスイート (13件)
- `ilisp/docs/SPEC_R7RS.md`: 第6.11節例外機構の準拠状況更新 (100% 達成)
- `docs/issues/closed/466-implement-r7rs-structured-exceptions.md`: クローズされた本 Issue ファイル

## 5. DoD (Definition of Done)
- [x] `ErrorObject` 型が定義され、メッセージと irritants を保持できる。
- [x] `(error "msg" irritant ...)` が `ErrorObject` を送出する。
- [x] `error-object?`, `error-object-message`, `error-object-irritants` が正しく動作する。
- [x] `read-error?` および `file-error?` がそれぞれ該当するエラーオブジェクトを識別する。
- [x] `guard` 構文と組み合わせて、エラーオブジェクトのメッセージや irritants、型判定による安全なフォールバック処理ができる。
- [x] `tests/ilisp/test_exceptions.py` を含む全テストが 100% PASS。
- [x] `flake8` 0 警告、`mypy --strict` 0 エラー。
- [x] `ilisp/docs/SPEC_R7RS.md` の例外機構準拠率が更新される。
