---
ID: 699
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG] GitHub Actions CI 新規チェックアウト時における VDB 欠落エラーおよび Bare-Metal テスト遅延の根本改修 (ID: 699)

## 1. 概要 / Summary

GitHub Actions CI（Run ID: 41615092064）において、Quality Gate 3（`make test`）が 28 分以上要した末に失敗（Process completed with exit code 2）する事象が発生した。

### 根本原因の特定 / Root Cause Analysis:

1. **クリーンチェックアウト環境における Gitignored VDB ファイルの欠落 (`tests/test_vdb_migration_full.py`)**:
   - `.gitignore` にて `outputs/database/` が除外指定されているため、GitHub Actions ランナー等の新規チェックアウト環境には `outputs/database/catalog/cti_catalog.vdb` および `outputs/database/analytics/analytics.vdb` が存在しない。
   - `tests/test_vdb_migration_full.py` 内の `test_migrated_cti_catalog_vdb_integrity` および `test_migrated_analytics_vdb_integrity` が `assert os.path.exists(vdb_path)` を無条件で検証しており、新規クローン環境で `AssertionError` となる。
   - `tests/security/test_mitigation_defense_integration.py` と同様に、実体ファイルが存在しない場合は `pytest.skip()` で安全にスキップする必要がある。

2. **ネイティブブートストラップバイナリ非存在時の純粋 Python コンパイル過負荷 (`tests/test_bare_metal_ulisp.py`)**:
   - `ulisp/bin/ulisp-boot` は `.gitignore` に指定されており新規チェックアウト環境には存在しない。
   - `test_bare_metal_ulisp.py` では `get_compiler_cmd()` が純粋 Python の AST インタプリタ（`python3 -m ilisp ulisp/compiler.scm`）にフォールバックし、10 件のベアメタル ELF 生成テストでそれぞれ約 22,000 行の Scheme コンパイラを Python 上で実行していた。
   - これにより、1 テストあたり 1〜2 分、全体で 20 分以上を費やし CI 実行時間の大部分を占有していた。
   - `shutil.which("gosh")` の優先検出を追加し、さらに高速コンパイラホスト（`ulisp-boot` または `gosh`）が存在しない場合は重厚なコンパイルテストをスキップ（または `@pytest.mark.slow` 指定）とすることで、CI の高速性を維持する。

3. **MultiTableVectorStorage におけるアトミック置換時の一時ファイル競合**:
   - `src/database/storage/multi_storage.py`、`src/database/storage/storage.py`、`src/database/storage/fts5_storage.py` で固定名 `.tmp` を用いていたため、並行テスト実行時に一時ファイルが衝突・消失し `FileNotFoundError` が発生するリスクがあった。
   - `csv_storage.py` や `json_storage.py` と同様に `f"{dest}.tmp.{os.getpid()}.{uuid.uuid4().hex[:8]}"` 形式を適用し、完全なプロセス・スレッド分離を担保する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- `tests/test_vdb_migration_full.py`: クリーンチェックアウト環境における `pytest.skip()` 安全ガードの追加
- `tests/test_bare_metal_ulisp.py`: `gosh` 優先検出およびネイティブホスト非存在時の安全スキップ
- `src/database/storage/multi_storage.py`: 一時ファイル名への PID + UUID 付与による競合解消
- `src/database/storage/storage.py`: 一時ファイル名への PID + UUID 付与による競合解消
- `src/database/storage/fts5_storage.py`: 一時ファイル名への PID + UUID 付与による競合解消

---

## 3. 実装計画 / Implementation Plan

1. `multi_storage.py`, `storage.py`, `fts5_storage.py` の一時ファイル生成を PID + UUID 化。
2. `tests/test_vdb_migration_full.py` にファイル存在チェックと `pytest.skip` を適用。
3. `tests/test_bare_metal_ulisp.py` に `gosh` 検出と、ホスト実行系非存在時の `pytest.skip` を適用。
4. クリーンな git worktree 環境にて全テストが即座に PASS/SKIP することを確認。
5. 品質ゲート（`check_format`, `static_analysis`, `test`）を通過させコミット・プッシュ。
