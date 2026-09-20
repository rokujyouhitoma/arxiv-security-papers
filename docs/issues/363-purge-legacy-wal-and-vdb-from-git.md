---
ID: 363
種別: Refactor
優先度: High
ステータス: Open (In Progress)
---

# [REFACTOR] .gitignore 対象でありながら Git 追跡され続けているレガシー WAL / VDB ファイルの Git インデックスからの完全除外・パージ (ID: 363)

## 1. 概要 / Summary

リポジトリの `.gitignore` では、ランタイム一時データやローカルデータベースとして `outputs/wal/` および `outputs/database/*.vdb` が無視対象として明記されている。

しかし `git ls-files` を調査したところ、過去（2026年8月）のコミットにより以下の WAL チェックポイントおよび VDB ファイルが Git インデックスで追跡され続けていることが判明した：
- `outputs/wal/cycle_20260827_143822.checkpoint.json` / `*.wal.jsonl`
- `outputs/wal/cycle_20260827_143945.checkpoint.json` / `*.wal.jsonl`
- `outputs/wal/cycle_20260827_144629.checkpoint.json` / `*.wal.jsonl`
- `outputs/wal/cycle_20260828_001101.checkpoint.json` / `*.wal.jsonl`
- `outputs/database/metrics.vdb`

最新の運用サイクル（`cycle_20260911_*` 等）は `.gitignore` に従いローカル管理されているのに対し、上記 8 件の過去 WAL 残骸と VDB 1 件が Git リポジトリ内に不整合に残留している。
本 Issue では、これらを `git rm --cached` により Git インデックスから安全に除外・パージし、Git 管理対象データの純度とルール適合性を回復する。

---

## 2. トレーサビリティ / Traceability

- 関連 Issue: [Issue 361: レガシー重複台帳 processed_papers.json の完全廃止](closed/361-deprecate-and-purge-legacy-processed-papers-json.md)
- 関連規定: `.gitignore`（outputs/wal/, *.vdb）
- 関連規定: `.agents/AGENTS.md` Section 6 (Raw Data Preservation & Idempotency Rules)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### Git インデックス・管理対象
- [ ] `outputs/wal/cycle_20260827_143822.checkpoint.json`
- [ ] `outputs/wal/cycle_20260827_143822.wal.jsonl`
- [ ] `outputs/wal/cycle_20260827_143945.checkpoint.json`
- [ ] `outputs/wal/cycle_20260827_143945.wal.jsonl`
- [ ] `outputs/wal/cycle_20260827_144629.checkpoint.json`
- [ ] `outputs/wal/cycle_20260827_144629.wal.jsonl`
- [ ] `outputs/wal/cycle_20260828_001101.checkpoint.json`
- [ ] `outputs/wal/cycle_20260828_001101.wal.jsonl`
- [ ] `outputs/database/metrics.vdb`

### テストスイート（固定ファイル依存の有無の検証）
- [ ] `tests/database/` 配下の WAL 関連テスト

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/363-purge-legacy-wal-vdb`

1. **テストスイートの依存性監査**:
   - `tests/` 内で特定のコミット済み WAL ファイル名（`cycle_20260827_*.wal.jsonl` 等）に依存しているテストが存在しないか grep 検索。
   - 存在する場合は、一時ディレクトリ（`tmp_path`）上に動的生成するフィクスチャ方式へ修正。
2. **Git インデックスからの安全なパージ**:
   - `git rm --cached outputs/wal/cycle_20260827_*.json outputs/wal/cycle_20260827_*.jsonl outputs/wal/cycle_20260828_*.json outputs/wal/cycle_20260828_*.jsonl outputs/database/metrics.vdb` を実行。
3. **`.gitignore` 整合性検証**:
   - `git status` を実行し、上記ファイルが Untracked として再出現せず、正常に無視されていることを確認。
4. **品質ゲートの検証**:
   - `make static_analysis`
   - `make test`

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `git ls-files outputs/wal/` が 0 件であること。
- [ ] `git ls-files outputs/database/metrics.vdb` が 0 件であること。
- [ ] リポジトリの `.gitignore` 設定に従い、ローカルでの WAL / VDB 生成時に Git 差分が発生しないこと。
- [ ] 全テストスイートが 100% PASS すること。
