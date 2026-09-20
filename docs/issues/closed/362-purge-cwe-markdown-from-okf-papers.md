---
ID: 362
種別: Refactor
優先度: High
ステータス: Closed
---

# [REFACTOR] `outputs/okf/papers/` 内に混入・残留した CWE-*.md (2,832件) の `outputs/okf/cwes/` への完全移管およびパージ (ID: 362)

## 1. 概要 / Summary

Issue 360 では `outputs/okf/papers/`（旧 `outputs/okf_papers/`）から混入していた脆弱性情報 `CVE-*.md` 1,713件を `outputs/okf/cves/` へ移管・完全削除し、ストレージ階層の再編を実施した。

しかし調査の結果、同様に過去のフェッチやバッチ処理で混入した弱点情報 **`CWE-*.md` が 2,832件も `outputs/okf/papers/` 配下（特に `2026-09-19/` 等）に残存** していることが判明した。
一方で、弱点用の正式な格納ディレクトリ `outputs/okf/cwes/` には 944件が存在しており、論文格納領域が弱点データで汚染され、データ二重管理が生じている。

本 Issue では、`outputs/okf/papers/` 内の `CWE-*.md` を精査し、`outputs/okf/cwes/` に未登録の弱点定義をマージ・保全した上で、`outputs/okf/papers/` から全 `CWE-*.md` を完全に削除・パージする。これにより、学術論文ストレージとしての純度と整合性を完全に回復する。

---

## 2. トレーサビリティ / Traceability

- 関連 Issue: [Issue 360: OKFストレージ階層の再編](360-migrate-okf-storage-to-hierarchical-structure.md)
- 関連 Issue: [Issue 361: レガシー重複台帳 processed_papers.json の完全廃止](361-deprecate-and-purge-legacy-processed-papers-json.md)
- 関連仕様: Google OKF (Open Knowledge Format) v0.2 仕様
- 関連規定: `.agents/AGENTS.md` Section 4 (Google OKF v0.2 Specification Compliance)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### ストレージ・データ
- [x] `outputs/okf/papers/**/CWE-*.md` (2,832件の削除対象)
- [x] `outputs/okf/cwes/` (差分マージ先)

### パイプライン・バックエンド
- [x] `src/pipeline/arxiv_okf_fetcher.py` (CWE混入防止ガード)
- [x] `src/domain/security/pipeline/okf_pipeline.py` (出力パス判定の厳格化)
- [x] `src/settings.py` (`okf_papers`, `okf_cwes` テーブル定義)

### テストスイート
- [x] `tests/domain/security/test_okf_pipeline.py`
- [x] `tests/domain/security/test_okf_pipeline_isolation.py`

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/362-purge-cwe-from-okf-papers`

1. **差分調査とデータの保全 (Audit & Safety Merge)**:
   - `outputs/okf/papers/` 配下の `CWE-*.md` 一覧を抽出し、`outputs/okf/cwes/` と照合。
   - `outputs/okf/cwes/` に未登録の CWE があれば、メタデータを損なわずに `outputs/okf/cwes/` へ安全にコピー・登録。
2. **`outputs/okf/papers/` からの `CWE-*.md` 完全削除**:
   - `outputs/okf/papers/**/CWE-*.md` を一括削除。
   - CWE 削除に伴って空になった日付ディレクトリが存在する場合はクリーンアップ。
3. **混入防止ガードの実装 (Guard Rails)**:
   - `okf_pipeline.py` および `arxiv_okf_fetcher.py` において、`id` が `CWE-` で始まるドキュメントが `outputs/okf/papers` に書き込まれないようアサーション／ルーティング制御を追加。
4. **品質ゲートの検証**:
   - `outputs/okf/papers/` 内に `CWE-*.md` が 0件であることを検証。
   - `make check_format`
   - `make static_analysis`
   - `make test`

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `outputs/okf/papers/` 配下の `CWE-*.md` 件数が 0 件であること。
- [x] `outputs/okf/cwes/` に必要な CWE OKF ファイルが欠落なく保全されていること。
- [x] 論文取得パイプラインで CWE ドキュメントが `papers` 配下に出力されないガードが機能していること。
- [x] 全ユニットテストおよび静的解析（mypy, xenon rank A）が 100% PASS すること。
