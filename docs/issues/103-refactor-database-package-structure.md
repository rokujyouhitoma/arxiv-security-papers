---
ID: 103
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Refactor and Reorganize src/database Package Structure (ID: 103)

## 1. 概要 / Summary
`src/database/` 直下に 22 個の Python モジュール（`pager.py`, `slotted_page.py`, `buffer_pool.py`, `wal.py`, `mvcc.py`, `lock_manager.py`, `recovery.py`, `vdbe.py`, `client.py`, `service.py`, `driver.py` 等）がフラットに配置されており、モジュール強度の向上と責務の明確化（高凝集・低結合）のためにサブパッケージへ体系的に再配置・整理します。

### 整理・分類方針（案）
1. **`src/database/storage/`** (物理ストレージ・ページ・バッファ管理)
   - `pager.py`, `slotted_page.py`, `buffer_pool.py`, `vfs.py`, `storage.py`
2. **`src/database/transaction/`** (トランザクション・ロック・WAL・リカバリ)
   - `mvcc.py`, `lock_manager.py`, `wal.py`, `recovery.py`
3. **`src/database/ipc/`** または **`src/database/client/`** (IPCプロトコル・クライアント・サービス・ドライバ)
   - `client.py`, `service.py`, `driver.py`, `protocol.py`
4. **`src/database/vdbe/`** または **`src/database/execution/`** (VDBE 仮想マシン・バイトコード生成・コンパイラ)
   - `vdbe.py`, `compiler.py`, `codegen.py`
5. **`src/database/index/`** (インデックス構造・埋め込みベクトル)
   - `index.py`, `embedding.py`
6. **`src/database/compat/`** (SQLite 互換レイヤー・ブリッジ・プロファイラ)
   - `sqlite_bridge.py`, `sqlite_engine.py`, `profiler.py`
7. **後方互換性ファサード (`src/database/__init__.py`)**:
   - 既存のすべてのインポートパス（`from database.pager import Pager`, `from database.client import DatabaseClient` 等）を透過的にサポートするエイリアス・エクスポートを維持し、外部破壊を防止。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/database/*.py` (22ファイル)
- [ ] `src/database/__init__.py`
- [ ] `src/database/storage/` (新規)
- [ ] `src/database/transaction/` (新規)
- [ ] `src/database/ipc/` (新規)
- [ ] `src/database/vdbe/` (新規)
- [ ] `src/database/index/` (新規)
- [ ] `src/database/compat/` (新規)
- [ ] `tests/database/` 配下の全テスト
- [ ] `src/web/`, `src/supervisor/`, `src/graph/`, `src/analytics/` などの依存元

---

## 3. 実装方針 / Implementation Plan
※ `/polish-issue` 実行時に詳細なマッピング表と DoD を策定します。

---

## 4. 完了条件 / Success Criteria (DoD)
- [ ] `src/database/` 直下のフラットなモジュールが適切にサブパッケージへ分類・配置されていること
- [ ] `src/database/__init__.py` により既存のインポート互換性が 100% 維持されていること
- [ ] `tests/database/` を含む全テストが 100% PASS すること
- [ ] `make check` (flake8, isort, black, xenon) がエラー 0 件で通過すること
