---
ID: 628
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/DX] S 式括弧整合性 Linter（Parenthesis Depth Linter）の導入およびリーダー EOF 構文診断の強化 (ID: 628)

## 1. 概要 / Summary
Scheme ソースコード編集時における**「括弧の閉じ忘れ（Unclosed Parentheses / S-Expression Depth Mismatch）」**をビルド前および構文解析（Read）時点で即座に検知し、ファイル名および行番号付きで診断メッセージを出力する開発基盤（DX / Linter）を整備する。

現状、ULisp の S 式リーダー（`lib/reader.scm` 等）は、ファイル終端（EOF）に達した際にリストの開き括弧が残っていても構文例外（Syntax Error）を発生させずに終了するか不完全な形式を返す挙動となっている。
さらに、コンパイラビルドパイプライン（`Makefile`）において各パスファイルを `cat $(PASSES) > compiler.scm` で結合しているため、あるファイル末尾で括弧が閉じられていないと、**後続の別ファイルのトップレベル定義全体が先行関数の内部式として静かに飲み込まれてしまう**という深刻な問題がある。

この結果、構文エラーとして検出されず、コード生成や最終静的リンクの段階で `undefined reference to ulisp_fn_...` という全く別のレイヤーの不可解なエラーとして発現し、原因究明に多大な時間を要していた（Issue #624 作業時にも実害が発生）。

本 Issue では以下を実現する：
1. **Per-file S 式括弧整合性 Linter の導入**: `cat` 結合前および `make lint` / `make check` 時に、各 `.scm` ファイルが独立して深度 0 で閉じているかをミリ秒単位で高速検証する Linter を配備。
2. **S 式リーダーの EOF 例外ハンドリング**: リスト・ベクタ・バイトベクタ・文字列読み込み中の予期せぬ EOF 到達時に明示的な構文エラー（Syntax Error: unexpected EOF while reading ...）を報告する。

---

## 2. トレーサビリティ / Traceability
- **関連 Issue**:
  - [624-phase1-direct-known-function-calls.md](624-phase1-direct-known-function-calls.md) (Pass 110 改修時に括弧閉じ忘れによるシンボル脱落・リンク障害が発生)
  - [606-replace-cat-bundle-with-r7rs-include-and-source-tracking.md](606-replace-cat-bundle-with-r7rs-include-and-source-tracking.md) (cat 結合の廃止とモジュール・ソース位置追跡)
  - [604-implement-call-stack-traceback-for-compiler-exceptions.md](604-implement-call-stack-traceback-for-compiler-exceptions.md) (コンパイラ例外診断基盤)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/scripts/lint_sexpr.py](../../ulisp/scripts/lint_sexpr.py) (新規: 高速 S 式括弧整合性・文字列・コメント・文字リテラル Linter スクリプト)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`lint_sexpr` および `test_lint_sexpr` ターゲットの追加、`compiler.scm` / `build/compiler_passes.scm` ビルド前の事前検証フック統合)
- [x] [ulisp/lib/reader.scm](../../ulisp/lib/reader.scm) (S 式リーダーにおける EOF 到達時の未クローズド括弧・未クローズド文字列例外診断)
- [x] [ulisp/tests/test_ports.scm](../../ulisp/tests/test_ports.scm) / [ulisp/tests/test_reader_eof.scm](../../ulisp/tests/test_reader_eof.scm) (リーダー EOF 構文診断のユニットテスト追加)
- [x] [docs/issues/README.md](../README.md) (Issue 台帳の進捗同期: Closed)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/628-implement-sexpr-parenthesis-depth-linter-and-eof-diagnostic`

1. **高速 Linter スクリプトの実装 (`ulisp/scripts/lint_sexpr.py`)**:
   - 引数として受け取った 1 つ以上の `.scm` ファイルを独立に構文走査（Per-file isolated check）。
   - 状態機械（State Machine）による正確なトークン認識：
     - コメント（`; ... \n`）の完全スキップ
     - 複数行文字列リテラル（`"..."`、エスケープ `\"`, `\\`）の完全スキップ
     - 文字リテラル（`#\(`, `#\)`, `#\newline`, `#\space`, `#\xNN` 等）のスキップ（`#\(` や `#\)` を括弧の深さ変動として誤認させない）
     - ブロックコメント（`#| ... |#` ネスト対応）のスキップ
     - 開き括弧 `(` で位置（行番号、列番号）をスタックに push、ネスト深度（depth）を加算
     - 閉じ括弧 `)` で stack から pop、depth を減算。スタックが空（depth <= 0）での `)` は即座に「余剰閉じ括弧エラー」として報告
     - EOF 到達時に `depth != 0` の場合、未閉じの開き括弧のオープン位置（行・列）および該当コード行のスニペットとキャレット（`^`）を出力して終了コード 1 で終了
     - 単一ファイルの検査時間を数ミリ秒以内に抑える高効率ストリーム走査。

2. **`Makefile` への品質ゲート統合**:
   - `compiler.scm` 生成ルールおよび `build/compiler_passes.scm` 生成ルールの直前に `@$(PYTHON) scripts/lint_sexpr.py $(PASSES)` を実行する事前検証ゲートを追加。
   - 括弧の不整合（閉じ忘れ・閉じすぎ）が存在する場合は `cat` 結合前に即座にビルドを Fail させ、後続ファイルの巻き込みを物理的に遮断。
   - `make lint_sexpr` および `make test_lint_sexpr` を追加し、Linter 自体のテストスイート（正常系・未閉じ括弧・余剰閉じ括弧・文字リテラル `#\(` 混入・文字列内括弧混入）を自動検証。

3. **リーダー EOF 構文診断の強化 (`ulisp/lib/reader.scm`)**:
   - `port-read` におけるリスト読み込みループ (`read-list`)、ベクタ読み込み (`read-vec-list`)、バイトベクタ読み込み (`read-bv-list`)、および文字列読み込み (`read-str`) において、予期せぬ EOF 到達時に `c` を暗黙終了値として返却するのではなく、`(error "read: unexpected EOF while reading list" ...)` を送出して構文例外として通知。
   - トップレベルでの通常 EOF（正常なファイル末尾到達）との明確な区別を保証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 意図的に括弧を閉じ忘れた `.scm` ファイルに対して Linter がミリ秒単位で開始行番号・列番号・スニペット付きでエラーを報告し非ゼロ終了すること。
- [x] 文字リテラル `#\(` や `#\)`、文字列リテラル内の `"()"`、コメント行内の `()` を含む正常な Scheme ファイルを誤検知（False Positive）なく PASS すること。
- [x] `make compiler` 実行時に各入力ファイルが自動検証され、括弧不整合がある場合に結合前に停止すること。
- [x] リポジトリ内のすべての既存 `.scm` ファイルに対して Linter が 100% PASS すること（全 234 ファイル検査合格）。
- [x] `lib/reader.scm` においてリスト読み込み中の予期せぬ EOF 到達時に適切な例外が発生すること（リスト、ベクタ、バイトベクタ、文字列、クォート構文すべてで PASS）。
- [x] `make -C ulisp test` が 100% PASS すること（38 パス Nanopass テスト、ランタイムテスト、3段階セルフホスティングブートストラップ固定小数点完全一致、モジュラー分割コンパイルすべて PASS）。

---

## 6. 検証結果 / Verification Results
- `make -C ulisp lint_sexpr`: 69 ファイルを検査し全件 PASS (所要時間 ~0.04s)。
- `make -C ulisp test_lint_sexpr`: 17 単体テスト全件 PASS。
- `make -C ulisp test_reader_eof`: 5 グループ全 14 項目 PASS。
- `make -C ulisp test_ports`: Test 8 含む全 8 グループ PASS。
- `make -C ulisp test`: 全 38 パス、ブートストラップ Stage 1〜3 固定小数点一致、増分ビルド含め 100% PASS (Exit Code 0)。
