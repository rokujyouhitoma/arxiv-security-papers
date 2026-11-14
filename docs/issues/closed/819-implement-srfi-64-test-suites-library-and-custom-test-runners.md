---
ID: 819
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] R7RS-large / SRFI 64 テストスイート標準ライブラリ (srfi 64) と拡張テストランナー・互換ブリッジの実装 (ID: 819)

## 1. 概要 / Summary
Scheme におけるユニットテスト・テストスイートのデファクトスタンダード仕様である **SRFI 64: A Scheme API for test suites** を ULisp 標準ライブラリ（`ulisp/lib/test.scm` および `ulisp/lib/srfi/64.sld`）として完全実装する。
テストのグループ化・階層化（`test-begin` / `test-end` / `test-group` / `test-group-with-cleanup`）、標準アサーションマクロ群（`test-assert`, `test-eq`, `test-eqv`, `test-equal`, `test-approximate`, `test-error`）、条件付きスキップ・期待される失敗（`test-skip`, `test-expect-fail`）、および動的パラメータ駆動のテストランナー機構（`test-runner-current`, `test-runner-factory`, `test-runner-create`, `test-runner-simple`, 各種コールバック）を整備する。
本ライブラリは、ULisp AOT ネイティブバイナリ（x86-64 / AArch64 / C バックエンド）、ULisp ブートストラップ環境、および外部処理系（Gauche `gosh` / Python `ilisp`）の双方で 100% 決定論的かつポータブルに動作するテスト基盤を提供する。

---

## 2. トレーサビリティ / Traceability
- [SRFI 64: A Scheme API for test suites](https://srfi.schemers.org/srfi-64/srfi-64.html)
- [ULisp R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md)
- [ULisp テストおよび検証ガイド](../../ulisp/docs/guide_testing.md)
- [DSN-33 ULisp 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- [Issue #665: R7RS 仕様トレーサビリティとライブラリメタデータ管理規約](../issues/closed/665-enforce-r7rs-specification-traceability-and-diagnostic-tags.md)
- [Issue #818: Makefile テストランナー RUN_SCHEME の Gauche (gosh) 優先化とモジュラー並列ブートストラップ検証の統合](../issues/closed/818-prioritize-gauche-in-test-runner-and-enable-modular-parallel-bootstrap-verify.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成ファイル
- [x] [ulisp/lib/test.scm](../../ulisp/lib/test.scm) (新規作成: SRFI 64 ランナー、レコード型 `<test-runner>`、アサーションマクロ群、集計・スキップ・XFAIL コア実装)
- [x] [ulisp/lib/srfi/64.sld](../../ulisp/lib/srfi/64.sld) (新規作成: R7RS `(srfi 64)` ライブラリ定義・エクスポート節・仕様トレーサビリティヘッダ)
- [x] [ulisp/tests/test_srfi_64.scm](../../ulisp/tests/test_srfi_64.scm) (新規作成: SRFI 64 全仕様・アサーション・カスタムランナー・スキップの総合単体テスト)

### 既存更新ファイル
- [x] [ulisp/stdlib_entry.scm](../../ulisp/stdlib_entry.scm) (モジュラーコンパイル `ulisp_stdlib.o` への `(include "lib/test.scm")` 追加)
- [x] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) (`builtin-library-name?` に `(srfi 64)` を登録、`ulisp-supported-feature?` に `srfi-64` を追加)
- [x] [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm) (`(features)` 出力リストに `srfi-64` を追加)
- [x] [ulisp/tests/passes/common.scm](../../ulisp/tests/passes/common.scm) (既存 Nanopass 単体テスト用ハーネス `assert-true`, `assert-equal` を SRFI 64 互換・委譲対応化)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`ULISP_STD_LIBS` への `lib/test.scm` 追加、`test_srfi_64` ターゲット追加、`lint_sexpr` 対象への登録)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (SRFI 64 準拠状況テーブル更新、§5 原典リンクの追加)
- [x] [ulisp/docs/guide_testing.md](../../ulisp/docs/guide_testing.md) (SRFI 64 テストスイート標準記法およびカスタムランナー利用ガイドの追記)

---

## 4. セキュリティ要件と脅威モデル / Security & Robustness Considerations
1. **メモリ安全性・リソース枯渇保護 (CWE-400 / CWE-770)**:
   - `<test-runner>` のグループスタック（`group-stack`）やスキップ指定リスト（`skip-list`）は、テストケース数が数万件に達した場合でもメモリリークを起こさないよう、テスト終了時（`test-end`）に確実にポップ・破棄されること。
   - `test-error` において例外オブジェクトやトレースバックを保持する際、循環参照を形成しないよう適切なプレーンデータとして捕捉すること。
2. **決定論的実行と例外安全 (CWE-754 / CWE-391)**:
   - `test-group-with-cleanup` において、テスト実行中に予期せぬ例外（`error` や `assert` 違反）が発生した場合でも、`dynamic-wind` の `after-thunk` によりクリーンアップコードが確実に実行され、ランナースタックが不整合な状態に取り残されないこと。
   - ホスト Scheme（Gauche / ILisp）と ULisp AOT バイナリの間で浮動小数点数（`<flonum>`）の `test-approximate` 許容誤差計算（`<= (abs (- actual expected)) error`）が一致し、プラットフォーム依存の偽陽性・偽陰性を排除すること。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/819-implement-srfi-64-test-suites-library-and-custom-test-runners`

### 1. `<test-runner>` レコード型および動的パラメータの実装 (`ulisp/lib/test.scm`)
- `define-record-type` を用い、以下のフィールドを持つ `<test-runner>` を定義する:
  - `pass-count`, `fail-count`, `xpass-count`, `xfail-count`, `skip-count` (各集計カウンタ)
  - `total-count` (実行総テスト数)
  - `group-stack` (現在のネストしたテストスイート名リスト)
  - `skip-list` (現在のスキップ述語・カウンタリスト)
  - `fail-list` (現在の期待される失敗述語・カウンタリスト)
  - `on-test-begin`, `on-test-end`, `on-group-begin`, `on-group-end`, `on-final`, `on-bad-count` (コールバックハンドラ)
  - `aux-value` (ユーザー定義カスタムデータ保持用)
- R7RS `make-parameter` を用いて動的パラメータを定義:
  - `test-runner-current`: 現在アクティブな `<test-runner>` インスタンスを保持
  - `test-runner-factory`: 新規ランナー生成関数を保持（デフォルトは `test-runner-simple` を生成）
- 基本操作関数:
  - `test-runner-create`, `test-runner-simple`, `test-runner-null`
  - `test-runner-reset!`
  - 各種ゲッター・セッター（`test-runner-pass-count`, `test-runner-fail-count`, `test-runner-on-test-end!`, 等）

### 2. グループ化・階層化構文の実装
- `test-begin [suite-name [count]]`:
  - 現在のランナーが存在しない場合は `(test-runner-create)` で自動生成・設定。
  - スイート名を `group-stack` にプッシュし、`on-group-begin` を呼び出す。
- `test-end [suite-name]`:
  - `group-stack` をポップし、`on-group-end` を呼び出す。
  - 最上位グループ（スタックが空）に達した場合は `on-final` を呼び出し、結果サマリーを出力する。
- `test-group suite-name body ...`:
  - `(test-begin suite-name)` と `(test-end suite-name)` で `body ...` を囲む構文マクロ。
- `test-group-with-cleanup suite-name form ... cleanup-form`:
  - `dynamic-wind` を用いて、テスト中の例外発生時にも `cleanup-form` が確実に実行されるセーフティ構文マクロ。

### 3. アサーションマクロ群の実装 (`syntax-rules`)
- `test-assert [name] expr`:
  - `expr` の真偽値を評価し、真なら Pass、偽なら Fail を記録。
- `test-eq [name] expected expr`:
  - `(eq? expected expr)` による評価。
- `test-eqv [name] expected expr`:
  - `(eqv? expected expr)` による評価。
- `test-equal [name] expected expr`:
  - `(equal? expected expr)` による評価。
- `test-approximate [name] expected expr error`:
  - 数値塔（Fixnum / `<ratnum>` / `<flonum>`）対応の許容誤差比較:
    `(<= (abs (- actual expected)) error)` を判定。
- `test-error [name] [error-type] expr`:
  - `guard` 構文で例外を捕捉し、指定された `error-type`（指定なしの場合は任意の例外）が発生したかを検証。

### 4. スキップ制御と期待される失敗 (Skip & Expect-Fail)
- `test-skip specifier ...`:
  - 指定されたテスト名文字列またはカウント・述語に一致するテストをスキップ対象として登録。
- `test-expect-fail specifier ...`:
  - 指定されたテストが失敗することを期待（XFAIL）として登録。成功した場合は XPASS として警告集計。
- `test-match-name name`: テスト名完全一致または正規表現/プレフィックス一致判定述語。
- `test-match-nth n [count]`: 実行順序インデックスによるスキップ判定述語。

### 5. ライブラリ定義とコンパイラ統合 (`ulisp/lib/srfi/64.sld`, etc.)
- `ulisp/lib/srfi/64.sld`:
  - R7RS `define-library` で全 SRFI 64 識別子をエクスポート。
  - `Traceability: ulisp/docs/ref_r7rs_compliance.md` ヘッダを付与。
- `ulisp/stdlib_entry.scm`:
  - `(include "lib/test.scm")` を追加し、`ulisp_stdlib.o` に事前コンパイル登録。
- `ulisp/compiler/helpers.scm`:
  - `builtin-library-name?` に `(srfi 64)` を登録。
- `ulisp/lib/posix.scm`:
  - `(features)` リストに `srfi-64` を追加。
- `ulisp/tests/passes/common.scm`:
  - `assert-true`, `assert-equal` を SRFI 64 `test-assert`, `test-equal` にマッピングし、既存テストとの二重定義・衝突を防止。

### 6. 単体テストスイートの作成とビルド統合
- `ulisp/tests/test_srfi_64.scm`:
  - 基本アサーション（`test-assert`, `test-eq`, `test-eqv`, `test-equal`, `test-approximate`, `test-error`）の正常系・異常系検証。
  - グループ階層ネスト（`test-group`, `test-group-with-cleanup`）の検証。
  - スキップ（`test-skip`）および期待される失敗（`test-expect-fail`）の動作検証。
  - カスタムテストランナーによる TAP / JSON 風集計コールバックの検証。
- `ulisp/Makefile`:
  - `test_srfi_64` ターゲットを新設。
  - `lint_sexpr` および `test_r7rs_traceability` 対象に `lib/test.scm`, `lib/srfi/64.sld`, `tests/test_srfi_64.scm` を登録。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/lib/test.scm` および `ulisp/lib/srfi/64.sld` が作成され、全 SRFI 64 標準マクロ・手続きが提供されていること。
- [x] `(import (srfi 64))` により、`test-begin`, `test-end`, `test-group`, `test-group-with-cleanup`, `test-assert`, `test-eq`, `test-eqv`, `test-equal`, `test-approximate`, `test-error`, `test-skip`, `test-expect-fail`, `test-runner-*` が利用可能であること。
- [x] `ulisp/tests/test_srfi_64.scm` が AOT ネイティブコンパイルおよびホスト Scheme（Gauche `gosh` / Python `ilisp`）の双方で 100% PASS すること。
- [x] `make -C ulisp test_srfi_64` が Makefile から正常に実行でき、0 エラーで終了すること。
- [x] `make -C ulisp lint_sexpr` および `make -C ulisp test_r7rs_traceability` が 100% PASS すること。
- [x] ドキュメント（`ulisp/docs/ref_r7rs_compliance.md` および `ulisp/docs/guide_testing.md`）が更新され、仕様トレーサビリティが確立されていること。
- [x] ドキュメント内のすべての内部リンクが相対パス（`file://` や絶対パスを含まない）で記述されていること。
