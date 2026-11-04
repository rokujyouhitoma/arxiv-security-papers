---
ID: 718
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] R7RS-small (scheme load), (scheme repl), (scheme r5rs) 完全準拠化と動的ロードの実装 (ID: 718)

## 1. 概要 / Summary
R7RS-small §6.14 `(scheme load)` の動的ソースファイル読込・評価手続き `(load <filename> [<environment-specifier>])`、`(scheme repl)` の対話環境指定子 (`interaction-environment`)、および `(scheme r5rs)` の全 R5RS 互換エクスポート（`exact->inexact`, `inexact->exact`, `eval`, `load`, `null-environment`, `scheme-report-environment`, `interaction-environment` 等）を完全実装し、R7RS-small 全 16 標準ライブラリの 100% 完全サポート (**◎**) を達成する。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) (§1.3.14 システムインターフェース, §1.4 標準ライブラリ準拠状況)
  - R7RS-small §6.14 (`load`), §7.1.10 `(scheme load)`, §7.1.13 `(scheme r5rs)`, §7.1.14 `(scheme repl)`
  - 先行依存: [Issue #716 (Environment Specifiers)](closed/716-implement-r7rs-environment-specifiers-and-library-import-environments.md), [Issue #717 (eval)](closed/717-implement-r7rs-scheme-eval-embedded-metacircular-evaluator.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [eval.scm](../../ulisp/lib/eval.scm) (`load` 手続き、ポート反復 `port-read` / `eval` の実装)
- [x] [load.sld](../../ulisp/lib/scheme/load.sld) (`(scheme load)` エクスポート定義更新)
- [x] [repl.sld](../../ulisp/lib/scheme/repl.sld) (`(scheme repl)` エクスポート定義更新)
- [x] [r5rs.sld](../../ulisp/lib/scheme/r5rs.sld) (`(scheme r5rs)` 全シンボル互換エクスポート完備)
- [x] [test_eval_load_repl.scm](../../ulisp/tests/test_eval_load_repl.scm) (`load`, `repl`, `r5rs` テストケース追加)
- [x] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (R7RS-small 全 16 ライブラリ 100% ◎ 達成記録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/718-implement-r7rs-scheme-load-repl-and-r5rs-full-compliance`

1. **`load` 手続きの実装 (`ulisp/lib/eval.scm`)**:
   - `(load filename [env-spec])`
   - `env-spec` の検証 (`environment?`)。指定がない場合は `(interaction-environment)` を使用。
   - `(open-input-file filename)` でファイルを開き、EOF に達するまで `(port-read port)` で式を逐次読み込み。
   - 読み込んだ各式を `(eval expr env-spec)` で順次評価。
   - `dynamic-wind` または `call-with-port` による安全な `(close-port port)` 保証。
   - 返却値は未定義値 (`#t` / `63`)。

2. **`(scheme load)` ライブラリ定義 (`ulisp/lib/scheme/load.sld`)**:
   - `load` をエクスポート。
   - `(scheme base)`, `(scheme file)`, `(scheme read)`, `(scheme eval)` をインポート。

3. **`(scheme repl)` ライブラリ定義 (`ulisp/lib/scheme/repl.sld`)**:
   - `interaction-environment` をエクスポート。
   - `(scheme base)`, `(scheme eval)` をインポート。

4. **`(scheme r5rs)` ライブラリ定義 (`ulisp/lib/scheme/r5rs.sld`)**:
   - R5RS 規定の全エクスポートシンボル（算術、リスト、文字列、文字、入出力、構文、動的評価 `eval`, `load`, `null-environment`, `scheme-report-environment`, `interaction-environment`, `exact->inexact`, `inexact->exact`）を完備。
   - 準拠率 100% (**◎**) を達成。

5. **テストと検証 (`test_eval_load_repl.scm`)**:
   - 動的ファイル生成（テンポラリファイル作成）と `load` による変数束縛・手続き定義のロード動作検証。
   - 特定環境指定子へのロードとスコープ分離の検証。
   - `exact->inexact`, `inexact->exact` 等の R5RS 互換手続きの動作検証。
   - 全 16 ライブラリが 100% 達成されていることを `test_r7rs_traceability` で検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `(load filename)` および `(load filename env)` が正常に動作し、ファイル内の式が順次評価・束縛されること。
- [x] 存在しないファイルに対する例外送出および例外安全なポートクローズが動作すること。
- [x] `(scheme load)`, `(scheme repl)`, `(scheme r5rs)` の .sld 定義が完全整備され、Traceability 監査を通過すること。
- [x] `test_eval_load_repl.scm` にて load/repl/r5rs のテストが 100% PASS すること。
- [x] `ulisp/docs/ref_r7rs_compliance.md` において全 16 ライブラリが 100% (**◎**) となり、R7RS-small 完全準拠が証明されること。
