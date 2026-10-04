---
ID: 469
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] R7RS システム・プロセスコンテキストおよび高精度タイマーの実装 (ID: 469)

## 1. 概要 / Summary

R7RS-small (Revised^7 Report on the Algorithmic Language Scheme) 仕様準拠を推進するため、以下のシステム・時間・プロセス関連プリミティブ群を ILISP に実装する：
1. **第6.14節 & `(scheme time)` 高精度タイマー (Time)**:
   - `(current-second)`: UTC の現在エポック秒を高精度実数（浮動小数点数）で返却。
   - `(current-jiffy)`: 実装依存の単調増加（monotonic）高精度ティック整数値を返却。
   - `(jiffies-per-second)`: 1 秒あたりの jiffy 数（単調クロック周波数）を整数で返却。
2. **第6.14節 & `(scheme process-context)` プロセスコンテキスト (Process Context)**:
   - `(get-environment-variable name)`: 指定された名前の環境変数文字列を返却。未定義の場合は `#f` を返却。
   - `(get-environment-variables)`: 現在の全環境変数をキーと値のペアからなる連想リスト（Alist: `(("KEY" . "VAL") ...)`）として返却。
   - `(command-line)`: 実行時のコマンドライン引数リスト（プログラム名を含む文字列リスト）を返却。
   - `(emergency-exit [obj])`: クリーンアップハンドラ等をバイパスして即座にプロセスを終了（引数省略時は 0、`#t` は 0、`#f` は 1、整数時はその終了コード）。
   - `(exit [obj])` の R7RS 厳格引数セマンティクス（オプショナル引数、`#t`/`#f` 変換）の完備。

---

## 2. トレーサビリティ / Traceability

- **R7RS 6.14 System interface**:
  - `(current-second)`: "Returns an inexact number representing the current time on the International Atomic Time (TAI) clock or POSIX epoch."
  - `(current-jiffy)`, `(jiffies-per-second)`: "Returns the number of jiffies as an exact integer that have elapsed since an arbitrary epoch in the past."
  - `(get-environment-variable name)`, `(get-environment-variables)`: "Returns string or #f" / "Returns an association list of strings"
  - `(command-line)`: "Returns the command line passed to the process as a list of strings."
  - `(exit [obj])`, `(emergency-exit [obj])`
- **R7RS 7.1.1 Standard Libraries**:
  - `(scheme time)`: `current-jiffy`, `current-second`, `jiffies-per-second`
  - `(scheme process-context)`: `command-line`, `emergency-exit`, `exit`, `get-environment-variable`, `get-environment-variables`
- **ILISP R7RS 仕様準拠マトリクス**:
  - [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ilisp/env.py](../../ilisp/env.py): 時間・環境変数・コマンドライン・エマージェンシー終了プリミティブの追加と `make_initial_env` 辞書登録
- [x] [ilisp/syntax.py](../../ilisp/syntax.py): `core_forms` 予約語セットへの追加（マクロ展開時の変数捕捉防止）
- [x] [tests/ilisp/test_system_and_time.py](../../tests/ilisp/test_system_and_time.py): 新規単体テスト（正常系・単調増加検証・Alist 構造検証・型検査）
- [x] [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md): 実装状況マトリクス (183 -> 189 / 203) および `(scheme time)`, `(scheme process-context)` ライブラリステータスの更新

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/469-implement-r7rs-system-process-context-and-time`

1. **時間プリミティブの実装 (`ilisp/env.py`)**:
   - `prim_current_second() -> float`: `time.time()` を返却。
   - `prim_current_jiffy() -> int`: `time.monotonic_ns()` を返却（ナノ秒精度の正確な整数）。
   - `prim_jiffies_per_second() -> int`: 定数 `1_000_000_000` (10^9) を返却。
2. **プロセス・環境変数プリミティブの実装 (`ilisp/env.py`)**:
   - `prim_get_environment_variable(name: Any) -> Any`:
     - 引数が文字列（`str` または `MutableString`）であることを検証（非文字列は `TypeError`）。
     - `os.environ.get(s)` を取得し、存在すれば `s`、存在しなければ `False` (`#f`) を返却。
   - `prim_get_environment_variables() -> Any`:
     - `os.environ.items()` を走査し、各項目を `Cons(k, v)` のペアとして構築し、全体を Scheme 連想リスト（Alist）として返却。
   - `prim_command_line() -> Any`:
     - `sys.argv` の各要素（文字列）を Scheme リストに変換して返却。
   - `prim_exit(obj: Any = True) -> None`:
     - 引数判定: `obj is True` -> code 0, `obj is False` -> code 1, `isinstance(obj, int)` -> code, 他は 0。`sys.exit(code)`。
   - `prim_emergency_exit(obj: Any = True) -> None`:
     - `sys.exit` または安全な即時終了。
3. **マクロ展開器 `core_forms` 同期 (`ilisp/syntax.py`)**:
   - `current-second`, `current-jiffy`, `jiffies-per-second`, `get-environment-variable`, `get-environment-variables`, `command-line`, `emergency-exit` を登録。
4. **単体テストの実装 (`tests/ilisp/test_system_and_time.py`)**:
   - `current-second`: 浮動小数点数であり、正の数値であることを検証。
   - `current-jiffy`: 整数であり、短時間のインターバル後に単調増加することを検証。
   - `jiffies-per-second`: 1,000,000,000 の正の整数であることを検証。
   - `get-environment-variable`: `PATH` などの既存変数の文字列取得、未定義キーに対する `#f` 返却、型エラー検証。
   - `get-environment-variables`: Alist 形式（各要素が pair で `car`, `cdr` が文字列）の構造検証。
   - `command-line`: 非空の文字列リストであることを検証。
5. **品質ゲートとドキュメント同期**:
   - pytest 全件 PASS (307 -> 320+ 件)。
   - `flake8`, `mypy --strict ilisp` 0 エラー。
   - `SPEC_R7RS.md` の更新。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `current-second`, `current-jiffy`, `jiffies-per-second` が R7RS 6.14 準拠で動作すること
- [x] `get-environment-variable` が文字列および `#f` を適切に返却し、非文字列で型エラーを送出すること
- [x] `get-environment-variables` が環境変数の連想リスト (Alist) を返却すること
- [x] `command-line` が文字列リストを返却すること
- [x] 新規単体テストが全件 PASS すること (13件 100% PASS)
- [x] 既存の 307 件の ILISP テストがすべて PASS すること (全320件 100% PASS)
- [x] `flake8` 0 警告、`mypy --strict ilisp` 0 エラーであること
- [x] `ilisp/docs/SPEC_R7RS.md` が更新され、準拠率が向上していること
