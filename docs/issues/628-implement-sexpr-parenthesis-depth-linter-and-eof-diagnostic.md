---
ID: 628
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/DX] S 式括弧整合性 Linter（Parenthesis Depth Linter）の導入およびリーダー EOF 構文診断の強化 (ID: 628)

## 1. 概要 / Summary
Scheme ソースコード編集時における**「括弧の閉じ忘れ（Unclosed Parentheses / S-Expression Depth Mismatch）」**をビルド前および構文解析（Read）時点で即座に検知し、ファイル名および行番号付きで診断メッセージを出力する開発基盤（DX / Linter）を整備する。

現状、ULisp の S 式リーダー（`lib/reader.scm` 等）は、ファイル終端（EOF）に達した際にリストの開き括弧が残っていても構文例外（Syntax Error）を発生させずに終了するか不完全な形式を返す挙動となっている。
さらに、コンパイラビルドパイプライン（`Makefile`）において各パスファイルを `cat $(PASSES) > compiler.scm` で結合しているため、あるファイル末尾で括弧が閉じられていないと、**後続の別ファイルのトップレベル定義全体が先行関数の内部式として静かに飲み込まれてしまう**という深刻な問題がある。

この結果、構文エラーとして検出されず、コード生成や最終静的リンクの段階で `undefined reference to ulisp_fn_...` という全く別のレイヤーの不可解なエラーとして発現し、原因究明に多大な時間を要していた（Issue #624 作業時にも実害が発生）。

本 Issue では以下を実現する：
1. **Per-file S 式括弧整合性 Linter の導入**: `cat` 結合前および `make lint` / `make check` 時に、各 `.scm` ファイルが独立して深度 0 で閉じているかをミリ秒単位で高速検証する Linter を配備。
2. **S 式リーダーの EOF 例外ハンドリング**: リスト読み込み中の予期せぬ EOF 到達時に `Syntax Error: unexpected EOF while reading list started at line X` を強制通知する。

---

## 2. トレーサビリティ / Traceability
- **関連 Issue**:
  - [624-phase1-direct-known-function-calls.md](624-phase1-direct-known-function-calls.md) (Pass 110 改修時に括弧閉じ忘れによるシンボル脱落・リンク障害が発生)
  - [606-replace-cat-bundle-with-r7rs-include-and-source-tracking.md](closed/606-replace-cat-bundle-with-r7rs-include-and-source-tracking.md) (cat 結合の廃止とモジュール・ソース位置追跡)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/scripts/lint_sexpr.py](../../ulisp/scripts/lint_sexpr.py) (新規: 高速 S 式括弧整合性・文字列・コメント Linter スクリプト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`make lint_sexpr` ターゲットの追加、および `compiler.scm` / `build/compiler_passes.scm` ビルド前の事前検証フック)
- [ ] [ulisp/lib/reader.scm](../../ulisp/lib/reader.scm) (S 式リーダーにおける EOF 到達時の未クローズド括弧例外診断)
- [ ] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) (コンパイラ内蔵リーダーの構文検証堅牢化)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳の進捗同期)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/628-implement-sexpr-parenthesis-depth-linter-and-eof-diagnostic`

1. **高速 Linter スクリプトの実装 (`ulisp/scripts/lint_sexpr.py`)**:
   - コメント（`;`）および文字列リテラル（`"..."`、エスケープ `\"`）を正確にスキップしながら、開き括弧 `(` と閉じ括弧 `)` のネスト深度（depth）および括弧オープン箇所のスタック（行番号・列番号）を追跡。
   - EOF 到達時に `depth != 0` の場合、非ゼロ終了ステータスと共に `Error: unclosed '(' opened at line X, col Y (unclosed count: Z)` を出力。
2. **`Makefile` への品質ゲート統合**:
   - `compiler.scm` 生成ルールおよび `test` 前段に `python3 scripts/lint_sexpr.py $(PASSES)` を実行するゲートを追加。
   - 括弧の閉じ忘れが存在する場合は `cat` によるファイル結合自体を中止し、即座にビルドを Fail させる。
3. **リーダーの例外化**:
   - `read` 手続きにおいて、リスト蓄積中に EOF オブジェクトを受け取った場合は即座にエラーを報告する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 意図的に括弧を閉じ忘れた `.scm` ファイルに対して Linter が 1ms 以内に開始行番号付きでエラーを報告すること。
- [ ] `make compiler` 実行時に各入力ファイルが自動検証され、括弧不整合がある場合に結合前に停止すること。
- [ ] リポジトリ内のすべての既存 `.scm` ファイルに対して Linter が 100% PASS すること。
