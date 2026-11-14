---
ID: 821
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] SRFI 252 プロパティベーステストライブラリ (srfi 252) と決定論的ジェネレータ群の実装 (ID: 821)

## 1. 概要 / Summary
エッジケースの網羅や数学的性質・コンパイラ不変条件（ラウンドトリップ性・最適化前後の意味保存性など）を自動検証するため、**SRFI 252: Property Testing** を ULisp 標準ライブラリ（`ulisp/lib/property.scm` および `ulisp/lib/srfi/252.sld`）として完全実装する。

SRFI 252 は、個別のテストケースを手動で列挙する代わりに、満たすべき「性質（Property: 述語）」と入力値を供給する「ジェネレータ群（SRFI 158 準拠）」を指定することで、多数のランダム入力（既定 100 回）に対する不変条件の成立を自動検証する手法である。

本 Issue では、[closed/819-implement-srfi-64-test-suites-library-and-custom-test-runners.md](closed/819-implement-srfi-64-test-suites-library-and-custom-test-runners.md) で確立した **SRFI 64 テストランナー (`test-runner`)** への透過的結果集約、[closed/820-implement-srfi-78-lightweight-testing-library.md](closed/820-implement-srfi-78-lightweight-testing-library.md) の軽量テスト連携、ULisp に実装済みの **SRFI 158 (`(scheme generator)`)** 統合、および決定論的擬似乱数生成器（PRNG）による 100% 再現可能な反例（Counterexample）レポーティングを実現する。
さらに、Nanopass コンパイラ検証用の深さ制限付き AST ファジングジェネレータ（`sexpr-generator`）を提供し、Reader/Printer ラウンドトリップ性や CP0 最適化不変条件のプロパティ検証基盤を確立する。

---

## 2. トレーサビリティ / Traceability
- [SRFI 252: Property Testing](https://srfi.schemers.org/srfi-252/srfi-252.html)
- [Issue #819 R7RS-large / SRFI 64 テストスイート標準ライブラリの実装](closed/819-implement-srfi-64-test-suites-library-and-custom-test-runners.md)
- [Issue #820 R7RS-large / SRFI 78 軽量テストライブラリの実装](closed/820-implement-srfi-78-lightweight-testing-library.md)
- [Issue #701 R7RS-large / SRFI 128 (scheme comparator) 第一級比較器ライブラリの実装](closed/701-implement-srfi-128-comparators.md)
- [Issue #704 R7RS-large / SRFI 158 (scheme generator) 汎用ジェネレータ・アキュムレータライブラリの実装](closed/704-implement-srfi-158-generators-and-accumulators.md)
- [ULisp R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md)
- [ULisp テストおよび検証ガイド](../../ulisp/docs/guide_testing.md)
- [DSN-33 ULisp 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- [Issue #665 R7RS 仕様トレーサビリティとライブラリメタデータ管理規約](closed/665-enforce-r7rs-specification-traceability-and-diagnostic-tags.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成ファイル
- [x] [ulisp/lib/property.scm](../../ulisp/lib/property.scm) (新規作成: SRFI 252 コアエンジン、決定論的 PRNG、R7RS-small 型ジェネレータ群、AST 生成器、反例レポーティング)
- [x] [ulisp/lib/srfi/252.sld](../../ulisp/lib/srfi/252.sld) (新規作成: R7RS `(srfi 252)` ライブラリ定義・エクスポート節・仕様トレーサビリティヘッダ)
- [x] [ulisp/tests/test_srfi_252.scm](../../ulisp/tests/test_srfi_252.scm) (新規作成: SRFI 252 総合プロパティテストスイート: 数学的不変条件、リスト/ベクタ性質、反例再現性、S式ASTファジング)

### 既存更新ファイル
- [x] [ulisp/stdlib_entry.scm](../../ulisp/stdlib_entry.scm) (モジュラーコンパイル `ulisp_stdlib.o` への `(include "lib/property.scm")` 追加)
- [x] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) (`builtin-library-name?` に `(srfi 252)` を登録、`ulisp-supported-feature?` に `srfi-252` を追加)
- [x] [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm) (`(features)` 出力リストに `srfi-252` を追加)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`ULISP_STD_LIBS` への `lib/property.scm` 追加、`test_srfi_252` ターゲット新設、`lint_sexpr` 対象への登録)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (SRFI 252 準拠状況テーブル更新、§5 原典リンクの追加)
- [x] [ulisp/docs/guide_testing.md](../../ulisp/docs/guide_testing.md) (Layer 10: SRFI 252 プロパティベーステスト利用ガイドの追記)
- [x] [docs/issues/README.md](README.md) (Issue 台帳のステータス同期)

---

## 4. セキュリティ要件と脅威モデル / Security & Robustness Considerations

1. **無限再帰・メモリ枯渇 DoS 防止 (CWE-400 / CWE-770)**:
   - 複合型（リスト、ベクタ、文字列、および S 式木）をランダム生成する際、サイズ制限が未指定または不十分な場合にヒープアロケーションが急激に増大し OOM やスタックオーバーフローを引き起こすリスクがある。
   - *対策*: リスト・ベクタ・文字列の要素数上限（既定最大長 32）、および S 式木の再帰深さ（既定最大深度 5）を厳密に制限し、反復ごとにアロケーション総量をバウンドする。
2. **被テスト述語の例外安全と隔離性 (CWE-754 / CWE-391)**:
   - ランダム生成された値（例: 0、負数、NaN、空リスト）により、被テスト手続きがゼロ除算や未定義動作の例外を送出する場合がある。
   - *対策*: プロパティ実行を `guard` 構文で完全に保護し、未捕捉の例外発生時にもテストスイート全体を中断せず、明示的な例外反例（`property-exception`）として捕捉・記録する。また `test-property-error` 構文により、例外発生自体を期待するプロパティも安全に検証可能とする。
3. **決定論的 PRNG と 100% 反例再現性 (CWE-330 / Flaky Test 防御)**:
   - ランダムテスト特有の「CI 上で稀に失敗するがローカルで再現しない（Flaky Test）」問題を根絶する。
   - *対策*: 内部擬似乱数生成器に Xorshift32/64 を採用し、明示的なシード管理（`property-random-seed-set!`, `property-random-seed-get`）を提供する。テスト失敗時には、失敗した引数列（Counterexample）とともに **実行シード番号** をコンソールおよび `test-runner` ログに明示出力し、シード指定により 1 回で同一反例を再現可能とする。
4. **Fixnum 境界値とオーバーフロー防御**:
   - 62-bit Fixnum の境界値（$-2^{61}, 2^{61}-1, 0, 1, -1$ 等）において符号やビット反転のコーナーケースが潜在しやすい。
   - *対策*: 数値ジェネレータにおいて、ランダム値だけでなく代表的なエッジケース（0, 1, -1, 境界値）を一定確率で意図的に注入（Edge-case bias）する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/821-implement-srfi-252-property-based-testing-library`

### 1. 決定論的 PRNG 基盤とシード管理 (`ulisp/lib/property.scm`)
- Xorshift32/64 アルゴリズムに基づく高速・自己完結型の決定論的 PRNG を実装:
  - `*property-random-seed*`: 現在の乱数シードを保持する `box` セル（初期値 `123456789`）。
  - `(%property-next-random!)`: 0 以上 $2^{31}-1$ 以下の擬似乱数整数を生成・返却し、シードを更新。
  - `(%property-random-range low high)`: `[low, high]` の整数を一様分布から生成。
  - `(property-random-seed-set! seed)`: シードを手動更新。
  - `(property-random-seed-get)`: 現在のシードを取得。

### 2. R7RS-small 標準型ジェネレータ群の実装 (SRFI 252 & SRFI 158 準拠)
SRFI 158 の引数なし手続き（呼び出しごとに値を返し、終了時は `eof-object` を返却）として各種ジェネレータを定義:
- **基本型**:
  - `(boolean-generator)`: `#t` / `#f` を 50% 確率で生成。
  - `(char-generator)`: 印字可能 ASCII 文字（32〜126）および制御文字を生成。
  - `(string-generator [char-gen] [max-len])`: 指定文字ジェネレータから長さ 0〜max-len（既定 16）の文字列を生成。
  - `(symbol-generator [char-gen] [max-len])`: 有効な識別子シンボルを生成。
  - `(bytevector-generator [max-len])`: 0〜255 のランダムバイト列を生成。
- **数値型**:
  - `(exact-integer-generator [low high])`: 指定範囲（既定 -1000〜1000）の正確な整数を生成（0, 1, -1 のエッジケース注入あり）。
  - `(exact-rational-generator)`: 分子・分母（非ゼロ）からなる既約分数を生成。
  - `(exact-complex-generator)`: 実部・虚部の正確な数からなる複素数を生成。
  - `(exact-real-generator)`, `(exact-number-generator)`: 正確な実数・数を生成。
  - `(inexact-real-generator)`: 実数浮動小数点数を生成。
  - `(inexact-integer-generator)`, `(inexact-rational-generator)`, `(inexact-complex-generator)`, `(inexact-number-generator)`: 各種非正確数。
- **複合型・高階ジェネレータ**:
  - `(pair-generator car-gen cdr-gen)`: ペアを生成。
  - `(list-generator elem-gen [max-len])`: 指定要素のリストを生成。
  - `(vector-generator elem-gen [max-len])`: 指定要素のベクタを生成。
  - `(sexpr-generator [max-depth])`: ULisp コンパイラ AST テスト用。アトム（シンボル、数値、真偽値、文字列）およびネストしたリストを深さ制限（既定 4）内でランダム生成。

### 3. プロパティ検証コア API と SRFI 64 統合 (`ulisp/lib/property.scm`)
- `(test-property property generator-list [runs])`:
  - `runs`: テスト実行回数（省略時 100 回）。
  - 各反復において、`generator-list` の各ジェネレータから引数を採取: `(map (lambda (g) (g)) generator-list)`。
  - プロパティを `(guard (ex (else (cons 'property-exception ex))) (apply property args))` で実行。
  - **検証判定**:
    - 返却値が真: 続行。
    - 返却値が偽または例外捕捉: テスト失敗。即時反復を打ち切り、反例（`counterexample: args`）および `seed` を標準エラー/出力に記録。
  - **SRFI 64 テストランナー (`test-runner-current`) への記録**:
    - ランナーがアクティブな場合、`test-result-alist` に `(test-name)`, `(result-kind 'pass / 'fail)`, `(counterexample args)`, `(random-seed seed)` を設定し、`pass-count` / `fail-count` を加算。
- `(test-property-expect-fail property generator-list [runs])`:
  - 期待される失敗（XFAIL）として記録。全回数成功した場合は XPASS として報告。
- `(test-property-skip property generator-list [runs])`:
  - 実行をスキップし、`skip-count` を加算。
- `(test-property-error property generator-list [runs])`:
  - プロパティ実行中に例外が送出されることを検証（例外送出で PASS、正常復帰で FAIL）。
- `(test-property-error-type error-type property generator-list [runs])`:
  - 特定のコンディション型/エラータグの例外送出を検証。
- `(property-test-runner)`:
  - 反例情報（引数一覧、シード番号、反例発生ステップ数）をリッチに整形表示する SRFI 64 準拠カスタムテストランナー。

### 4. R7RS ライブラリ定義 (`ulisp/lib/srfi/252.sld`)
- ライブラリ名: `(srfi 252)`
- エクスポート:
  - プロパティ検証構文・手続き: `test-property`, `test-property-expect-fail`, `test-property-skip`, `test-property-error`, `test-property-error-type`, `property-test-runner`
  - シード制御: `property-random-seed-set!`, `property-random-seed-get`
  - ジェネレータ群: `boolean-generator`, `bytevector-generator`, `char-generator`, `string-generator`, `symbol-generator`, `exact-complex-generator`, `exact-integer-generator`, `exact-number-generator`, `exact-rational-generator`, `exact-real-generator`, `inexact-complex-generator`, `inexact-integer-generator`, `inexact-number-generator`, `inexact-rational-generator`, `inexact-real-generator`, `pair-generator`, `list-generator`, `vector-generator`, `sexpr-generator`
- 仕様トレーサビリティヘッダ `Traceability: ulisp/docs/ref_r7rs_compliance.md` を付与。

### 5. コンパイラ・ビルド設定およびテストスイート (`ulisp/tests/test_srfi_252.scm`)
- `ulisp/tests/test_srfi_252.scm` のテスト構成:
  - **Group 1: ジェネレータ単体基本検査**: 各型ジェネレータが生成する値の型述語（`boolean?`, `integer?`, `string?`, `vector?` 等）の整合性。
  - **Group 2: 数学的不変条件の検証**:
    - 加算・乗算の交換法則: `(= (+ a b) (+ b a))`, `(= (* a b) (* b a))`
    - 結合法則: `(= (+ (+ a b) c) (+ a (+ b c)))`
    - 分配法則: `(= (* a (+ b c)) (+ (* a b) (* a c)))`
    - 0 および 1 の単位元性質
  - **Group 3: コレクション構造の不変条件**:
    - リスト二重反転: `(equal? (reverse (reverse lst)) lst)`
    - リスト結合長さ保存: `(= (length (append a b)) (+ (length a) (length b)))`
    - ベクタ $\to$ リスト $\to$ ベクタのラウンドトリップ性: `(equal? (list->vector (vector->list v)) v)`
  - **Group 4: エラー・スキップ・期待される失敗**:
    - `test-property-skip`, `test-property-expect-fail`, `test-property-error` (ゼロ除算検知など)
  - **Group 5: 反例検出と決定論的再現性**:
    - 意図的に失敗するプロパティを検証し、特定シードにおいて同一の反例が 100% 決定論的に再現されることを確認。
  - **Group 6: AST ファジングと Reader/Printer ラウンドトリップ**:
    - `sexpr-generator` で生成した S 式に対し、`read(write(S)) == S`（`equal?`）が成立することを検証。
  - **Group 7: SRFI 64 テストランナー統合集計**:
    - `test-begin` / `test-end` 内で `test-property` を実行し、`test-runner-pass-count` が正しく集約されることを確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/lib/property.scm` および `ulisp/lib/srfi/252.sld` が作成され、全 SRFI 252 標準手続きおよびジェネレータ群が利用可能であること。
- [x] `(import (srfi 252))` により、`test-property`, `property-test-runner` および各種ジェネレータが正しくロードできること。
- [x] 決定論的 PRNG シード制御（`property-random-seed-set!`, `property-random-seed-get`）が提供され、同一シードで同一の乱数列・反例が 100% 再現可能であること。
- [x] 反例検出時に失敗した引数列とシード番号がレポートされ、SRFI 64 の `test-runner` に正しく集約されること。
- [x] `make -C ulisp test_srfi_252` が Makefile から正常に実行でき、ネイティブ x86-64 ELF バイナリとして 0 エラーで終了すること。
- [x] ホスト Scheme（Gauche `gosh` / Python `ilisp`）環境でも `ulisp/tests/test_srfi_252.scm` が 100% PASS すること。
- [x] `make -C ulisp lint_sexpr` および `python3 scripts/verify_r7rs_traceability.py` が 100% PASS すること。
- [x] ドキュメント（`ulisp/docs/ref_r7rs_compliance.md` および `ulisp/docs/guide_testing.md`）が更新され、仕様トレーサビリティが確立されていること。
- [x] ドキュメント内のすべての内部リンクが相対パス（絶対パスや `file://` を含まない）で記述されていること。
