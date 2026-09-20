---
ID: 364
種別: Refactor
優先度: Medium
ステータス: Open (In Progress)
---

# [REFACTOR] Issue 360 移行用シンボリックリンク (`okf_papers`, `okf_vulnerabilities`, `okf_weaknesses`, `vector_db`) の撤去と新ストレージ階層への完全一本化 (ID: 364)

## 1. 概要 / Summary

Issue 360 において、OKFストレージ階層を `outputs/okf/{papers,cves,cwes}` へ移行した際の後方互換性措置として、`outputs/` 直下に以下の 4 つのシンボリックリンクが設置された：
- `outputs/okf_papers -> okf/papers`
- `outputs/okf_vulnerabilities -> okf/cves`
- `outputs/okf_weaknesses -> okf/cwes`
- `outputs/vector_db -> database/search_vector`

現在、主要コード（`src/`）や Web Gateway、フロントエンドにおける新階層へのパス切り替えは完了している。
本 Issue では、リポジトリ内の全スクリプト、Makefile、ドキュメント、テストスイートにおける旧パスへの残存参照を完全に払拭し、上記 4 つの過渡期シンボリックリンクを安全に撤去・完全一本化する。

---

## 2. トレーサビリティ / Traceability

- 関連 Issue: [Issue 360: OKFストレージ階層の再編](closed/360-migrate-okf-storage-to-hierarchical-structure.md)
- 関連規定: `.agents/AGENTS.md` Section 4 & Section 7 (Relative Link & Documentation Rules)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### シンボリックリンク（撤去対象）
- [ ] `outputs/okf_papers`
- [ ] `outputs/okf_vulnerabilities`
- [ ] `outputs/okf_weaknesses`
- [ ] `outputs/vector_db`

### 参照監査対象ファイル
- [ ] `Makefile`
- [ ] `scripts/`
- [ ] `tools/`
- [ ] `docs/`
- [ ] `.agents/AGENTS.md`
- [ ] `.agents/skills/`

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/364-remove-legacy-okf-symlinks`

1. **旧パス参照の全走査と是正**:
   - `outputs/okf_papers`, `outputs/okf_vulnerabilities`, `outputs/okf_weaknesses`, `outputs/vector_db` の文字列をプロジェクト全体で grep 検索。
   - 残存している参照箇所をすべて新正規パス（`outputs/okf/papers/`, `outputs/okf/cves/`, `outputs/okf/cwes/`, `outputs/database/search_vector/`）へ置換。
2. **シンボリックリンクの安全な撤去**:
   - `git rm outputs/okf_papers outputs/okf_vulnerabilities outputs/okf_weaknesses outputs/vector_db` を実行。
3. **リンク不在環境でのテスト検証**:
   - リンクが存在しない状態で `make test` およびパイプライン実行を行い、Broken Link やパス解決エラーが発生しないことを確認。
4. **品質ゲートの検証**:
   - `make verify_quality` または `make test` & `make static_analysis`。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `outputs/` 直下の 4 つの後方互換シンボリックリンクがリポジトリから完全に削除されていること。
- [ ] プロジェクト全コード・設定・ドキュメントにおいて旧パスへの直接参照が 0 件であること。
- [ ] シンボリックリンクが存在しない状態で全テストスイートが 100% PASS すること。
