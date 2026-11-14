---
ID: 820
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] SRFI 78 軽量テストライブラリ (srfi 78) の実装と SRFI 64 テストランナー・Power Assert 連携 (ID: 820)

## 1. 概要 / Summary
単一ファイルでの手軽な動作確認、スクリプト実行時のインラインアサーション、および Nanopass コンパイラの各パス単体検証（S 式変換前後の AST 構造比較など）を最小限の記述量で直感的に行えるよう、**SRFI 78: Lightweight testing** を ULisp 標準ライブラリ（`ulisp/lib/check.scm` および `ulisp/lib/srfi/78.sld`）として完全実装する。

SRFI 78 は、テスト名文字列の指定を必須とせず、自己文書化された直感的な矢印構文 `(check <expr> => <expected>)` およびカスタム等価述語指定 `(check <expr> (=> <equal-pred>) <expected>)` を提供する。
さらに、実行モード切り替え（`off`, `summary`, `report-failed`, `report`）、結果集計・リセット手続き（`check-report`, `check-reset!`, `check-passed?`）、および [closed/819-implement-srfi-64-test-suites-library-and-custom-test-runners.md](closed/819-implement-srfi-64-test-suites-library-and-custom-test-runners.md) で実装した SRFI 64 `test-runner` との動的相互運用ブリッジを確立する。これにより、スタンドアロンでの軽量テストと、包括的な CI/テストスイートへの自動集約をシームレスに両立させる。

---

## 2. トレーサビリティ / Traceability
- [SRFI 78: Lightweight testing](https://srfi.schemers.org/srfi-78/srfi-78.html)
- [Issue #819 R7RS-large / SRFI 64 テストスイート標準ライブラリの実装](closed/819-implement-srfi-64-test-suites-library-and-custom-test-runners.md)
- [ULisp R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md)
- [ULisp テストおよび検証ガイド](../../ulisp/docs/guide_testing.md)
- [DSN-33 ULisp 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- [Issue #665 R7RS 仕様トレーサビリティとライブラリメタデータ管理規約](closed/665-enforce-r7rs-specification-traceability-and-diagnostic-tags.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成ファイル
- [ ] [ulisp/lib/check.scm](../../ulisp/lib/check.scm) (新規作成: SRFI 78 コアランタイム、`check`, `check-ec`, `check-report`, `check-set-mode!`, `check-reset!`, `check-passed?` 実装)
- [ ] [ulisp/lib/srfi/78.sld](../../ulisp/lib/srfi/78.sld) (新規作成: R7RS `(srfi 78)` ライブラリ定義・エクスポート節・仕様トレーサビリティヘッダ)
- [ ] [ulisp/tests/test_srfi_78.scm](../../ulisp/tests/test_srfi_78.scm) (新規作成: SRFI 78 全モード・アサーション・SRFI 64 連携の総合単体テスト)

### 既存更新ファイル
- [ ] [ulisp/stdlib_entry.scm](../../ulisp/stdlib_entry.scm) (モジュラーコンパイル `ulisp_stdlib.o` への `(include "lib/check.scm")` 追加)
- [ ] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) (`builtin-library-name?` に `(srfi 78)` を登録、`ulisp-supported-feature?` に `srfi-78` を追加)
- [ ] [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm) (`(features)` 出力リストに `srfi-78` を追加)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`ULISP_STD_LIBS` への `lib/check.scm` 追加、`test_srfi_78` ターゲット追加、`lint_sexpr` 対象への登録)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (SRFI 78 準拠状況テーブル更新、§5 原典リンクの追加)
- [ ] [ulisp/docs/guide_testing.md](../../ulisp/docs/guide_testing.md) (Layer 9: SRFI 78 軽量テストフレームワーク利用ガイドの追記)

---

## 4. セキュリティ要件と脅威モデル / Security & Robustness Considerations
1. **被テスト式の例外安全と隔離性 (CWE-754 / CWE-391)**:
   - `check` に渡された被テスト式 `<expr>` および期待値式 `<expected>` の評価において未処理の例外（`error`, `raise`, アロケーション失敗等）が発生した場合でも、テストドライバがクラッシュせず、適切に `guard` 構文で例外を捕捉してチェック失敗（Failed with exception）として記録すること。
2. **状態汚染防止とメモリバウンディング (CWE-400 / CWE-770)**:
   - 長時間のループテストや大量の式検証時において、失敗履歴リストが無制限に肥大化してヒープを浪費しないよう、集計カウンタおよび直近の失敗情報のみを適切に管理・解放すること。
   - `check-set-mode!` によるモード変更が、意図しないグローバル状態破壊を招かないよう、妥当なシンボル（`'off`, `'summary`, `'report-failed`, `'report`）のみを受け入れ、不正な値に対しては明確な契約違反エラーを送出すること。
3. **決定論的マルチプラットフォーム出力**:
   - ULisp AOT ネイティブバイナリ、Gauche（`gosh`）、および Python（`ilisp`）のいずれの実行環境においても、同一のテストケースに対して同一の判定結果・終了コードが返却されること。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/820-implement-srfi-78-lightweight-testing-library`

### 1. 状態管理カプセル化と基本操作手続き (`ulisp/lib/check.scm`)
- ULisp の AOT コンパイル特性と `set-box!` パターンに適合した内部状態セルを定義:
  - `*check-mode*`: 現在の出力モード（初期値 `'report-failed`）
  - `*check-passed-count*`: 合格テスト数
  - `*check-failed-count*`: 失敗テスト数
  - `*check-total-count*`: 総実行テスト数
- API 手続きの実装:
  - `(check-set-mode! mode)`:
    - `mode` が `'off`, `'summary`, `'report-failed`, `'report` のいずれかであることを検証し、設定を更新。
  - `(check-reset!)`:
    - 各カウンタを `0` にリセット。
  - `(check-passed? expected-total-passed)`:
    - 失敗数 `0` かつ 合格数 `= expected-total-passed` の場合に `#t`、それ以外は `#f` を返却。
  - `(check-report)`:
    - 現在のモードが `'off` でない場合、サマリー（`All X correct` または `X of Y correct, Z failed`）を出力し、失敗があればフラグを立てる。

### 2. コアアサーションマクロ群の実装 (`check`, `check-ec`)
- `(check <expr> => <expected>)`:
  - 既定の等価述語 `equal?` を用いて式を比較。
- `(check <expr> (=> <equal-pred>) <expected>)`:
  - ユーザー指定の等価述語 `<equal-pred>` を用いて比較。
- 内部展開マクロ `%check`:
  - `*check-mode*` が `'off` の場合は評価・検証をスキップ。
  - `<expected>` を事前評価し、`<expr>` を `(guard (ex (else (cons 'check-exception ex))) <expr>)` で保護評価。
  - 比較結果が真の場合:
    - 合格カウンタを加算。
    - モードが `'report` の場合、合格ログ `(check <expr> => <actual>) ; correct` を出力。
    - SRFI 64 の `(test-runner-current)` が非 `#f` の場合、SRFI 64 ランナーへ Pass を通知。
  - 比較結果が偽または例外捕捉の場合:
    - 失敗カウンタを加算。
    - モードが `'report` または `'report-failed` の場合、失敗ログ:
      `*** Check failed: <expr>`
      `  Expected: <expected>`
      `  Actual:   <actual>` を出力。
    - SRFI 64 の `(test-runner-current)` が非 `#f` の場合、SRFI 64 ランナーへ Fail を通知。
- `(check-ec <qualifier>* <expr> => <expected>)`:
  - 反復内包表記形式のチェック構文。単一変数バインドおよび複数修飾子のループ展開に対応。

### 3. R7RS ライブラリ定義およびコンパイラ統合
- `ulisp/lib/srfi/78.sld`:
  - R7RS `define-library` で `(srfi 78)` を定義。
  - エクスポート: `check`, `check-ec`, `check-report`, `check-set-mode!`, `check-reset!`, `check-passed?`。
  - `Traceability: ulisp/docs/ref_r7rs_compliance.md` ヘッダを付与。
- `ulisp/stdlib_entry.scm`:
  - `(include "lib/check.scm")` を追加。
- `ulisp/compiler/helpers.scm`:
  - `builtin-library-name?` に `78` を追加。
  - `ulisp-supported-feature?` に `srfi-78` を追加。
- `ulisp/lib/posix.scm`:
  - `(features)` リストに `srfi-78` を追加。
- `ulisp/Makefile`:
  - `ULISP_STD_LIBS` に `lib/check.scm` を登録。
  - `test_srfi_78` ターゲット新設（`$(ULISP_STD_LIBS) tests/test_srfi_78.scm` を AOT ネイティブコンパイル・実行）。
  - `lint_sexpr` の対象に `lib/srfi/78.sld`, `lib/check.scm`, `tests/test_srfi_78.scm` を追加。

### 4. 単体テストスイート (`ulisp/tests/test_srfi_78.scm`)
以下のシナリオ群を網羅するテストスイートを作成:
1. **基本等価アサーション**: 数値、シンボル、文字列、リスト、ベクタの `=>` 比較。
2. **カスタム等価述語**: 近似浮動小数点比較、大文字小文字無視文字列比較（`string-ci=?`）。
3. **モード制御**: `'off`, `'summary`, `'report-failed`, `'report` の各モードにおける出力抑制・詳細出力の動作確認。
4. **例外捕捉保護**: ゼロ除算や未定義変数参照など例外を送出する式が正しく Fail として補足され、後続テストが継続すること。
5. **SRFI 64 動的連携**: `test-with-runner` スコープ下で `check` を実行し、SRFI 64 ランナーの `test-runner-pass-count` / `fail-count` に正しく集約されることの検証。
6. **`check-passed?` および `check-reset!` 整合性**: 判定フラグおよびカウンタリセットの厳密な動作確認。

### 5. ドキュメント更新
- `ulisp/docs/ref_r7rs_compliance.md`:
  - SRFI 78 項目を **◎** (完全準拠) に更新し、Issue #820 へのリンクを記載。
- `ulisp/docs/guide_testing.md`:
  - Layer 9 として SRFI 78 軽量テスト API の利用方法、記法例、および SRFI 64 との使い分け指針を追記。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/lib/check.scm` および `ulisp/lib/srfi/78.sld` が作成され、全 SRFI 78 標準構文・手続きが利用可能であること。
- [x] `(import (srfi 78))` により、`check`, `check-ec`, `check-report`, `check-set-mode!`, `check-reset!`, `check-passed?` が正しくロードできること。
- [x] `make -C ulisp test_srfi_78` が Makefile から正常に実行でき、ネイティブ x86-64 ELF バイナリとして 0 エラーで終了すること。
- [x] ホスト Scheme（Gauche `gosh` / Python `ilisp`）環境でも `ulisp/tests/test_srfi_78.scm` が 100% PASS すること。
- [x] `make -C ulisp lint_sexpr` および `python3 scripts/verify_r7rs_traceability.py` が 100% PASS すること。
- [x] 全品質ゲート（`make format`, `make static_analysis`, `make test`）が完全パスすること。
- [x] ドキュメント（`ulisp/docs/ref_r7rs_compliance.md` および `ulisp/docs/guide_testing.md`）が更新され、仕様トレーサビリティが確立されていること。
- [x] ドキュメント内のすべての内部リンクが相対パス（絶対パスや `file://` を含まない）で記述されていること。
