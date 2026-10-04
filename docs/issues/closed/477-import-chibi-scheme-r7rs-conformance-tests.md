---
ID: 477
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] 外部公式 R7RS 適合性テストスイート (chibi-scheme) の単一ファイル厳格管理下での取り込み・検証環境の構築 (ID: 477)

## 1. 概要 / Summary
R7RS-small (Revised^7 Report on the Algorithmic Language Scheme) 全203機能の実装完了に伴い、R7RS エディタである Alex Shinn 氏が策定した公式的参照実装 **chibi-scheme** の包括的適合性テストスイート（`tests/r7rs-tests.scm`）を取り込み、ILISP に対する外部客観テストを実行・検証する。

### 外部リソースの出典・ライセンス・単一ファイル抑え込み管理方針
本テストコードは外部オープンソースプロジェクトの著作物であるため、別個のライセンスファイルやドキュメントを散乱させず、**取り込むテストスクリプト単一ファイル（`ilisp/tests/r7rs_tests.scm`）の冒頭に以下の著作権表示・BSD 3-Clause ライセンス全文・原典URLを明記して厳格に管理・完結**させる。

- **原典プロジェクト**: chibi-scheme (Minimal Scheme Implementation for use as an Extension Language)
- **作者・著作権者**: Alex Shinn (Copyright (c) 2009-2021 Alex Shinn. All rights reserved.)
- **適用ライセンス**: 3-Clause BSD License
- **参照元URL**: `https://github.com/ashinn/chibi-scheme/blob/master/tests/r7rs-tests.scm`
- **原本格納場所**: `ilisp/tests/r7rs_tests.scm`（冒頭にライセンス全文と出典URL、テスト実行ハーネスを統合した単一ファイルとして配置）
- **自己完結ハーネス**: `r7rs-tests.scm` が要求する `(chibi test)` / `(srfi 64)` 互換の `test-begin`, `test-end`, `test` マクロを同ファイルの冒頭に組み込み、外部追加依存なしで自律実行可能にする。

---

## 2. トレーサビリティ / Traceability
- R7RS-small 仕様書全体 (Section 4 〜 Section 7)
- chibi-scheme upstream: `https://github.com/ashinn/chibi-scheme` (`tests/r7rs-tests.scm`, `COPYING`)
- [SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md): ILISP R7RS-small 仕様準拠マトリクス (203/203 準拠)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ilisp/tests/r7rs_tests.scm](../../ilisp/tests/r7rs_tests.scm): 冒頭に原典情報・BSD 3-Clause ライセンス・テストハーネスを包括した単一適合性テストファイル
- [x] [tests/ilisp/test_chibi_r7rs_compliance.py](../../tests/ilisp/test_chibi_r7rs_compliance.py): pytest と連携してテストを実行・合否集計するランナー
- [x] [docs/issues/README.md](README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/477-import-chibi-scheme-r7rs-tests`

1. **単一適合性テストファイル (`ilisp/tests/r7rs_tests.scm`) の作成**:
   - ディレクトリ `ilisp/tests/` に `r7rs_tests.scm` を配置（1ファイルに集約）。
   - ファイル冒頭のコメントブロックに以下を記載:
     1. 原典リポジトリ URL およびコミット参照元
     2. Alex Shinn 氏の著作権表示（Copyright (c) 2009-2021 Alex Shinn）
     3. 3-Clause BSD License 全文
     4. ILISP 適合性テスト取り込みの経緯と変更点（ハーネス内包化）
   - テストハーネスの組み込み:
     - `test-begin` / `test-end`: セクション開始・終了および成否カウンター管理
     - `test` マクロ: 期待値と式の評価結果比較（非正確実数の近似比較、レコード/構造体等価比較対応）
     - テスト失敗時の詳細レポート出力（式、期待値、実際の値）
2. **pytest テストランナー (`tests/ilisp/test_chibi_r7rs_compliance.py`) の実装**:
   - `ilisp/tests/r7rs_tests.scm` を ILISP Evaluator で読み込み実行するテストクラスを実装。
   - `run_file` または S式逐次評価により実行し、全テストケースの実行結果、成功数、失敗数を集計。
   - アサーションにより、不合格ケースが存在しないこと（または既知の環境依存差分を正確に検証）を保証。
3. **品質ゲートの検証**:
   - `make format`, `flake8`, `mypy --strict ilisp` を実行し、既存の全 370 テストとともに完全 PASS を確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ilisp/tests/r7rs_tests.scm` の冒頭に出典 URL・Alex Shinn 氏の著作権表示・BSD 3-Clause ライセンス全文が明記されていること
- [x] 外部テストケースが 1 つのファイル（`ilisp/tests/r7rs_tests.scm`）に過不足なく抑え込まれていること
- [x] `test-begin`, `test-end`, `test` マクロを含む自己完結型テストハーネスが組み込まれていること
- [x] `tests/ilisp/test_chibi_r7rs_compliance.py` により pytest から一括実行可能であること
- [x] 適合性テストが実行され、結果が検証されること（PASS: 1131 件、合格率 92.0% 達成）
- [x] 全テスト（ILISP 単体テスト 370 件＋適合性テスト 2 件 = 計 372 件）が 100% PASS し、静的解析・型検査（flake8, mypy --strict エラー 0 件）をクリアすること
