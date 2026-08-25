---
ID: 073
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG] ワーカープロセスおよび Arbiter の RSS メモリ肥大化（各 ~1.37 GB）(ID: 073)

## 1. 概要 / Summary

`make run_supervisor` 起動直後から、Arbiter および全ワーカープロセス（`sync` × 9、`database` × 1）が
それぞれ **約 1,372〜1,382 MB の RSS**（物理メモリ使用量）を消費している。
合計で 15 GB 前後となり、通常の WSGI Web サーバーとして異常なメモリ使用量である。

ログ観測値（起動 0.2〜0.3s 後の状態）:
| プロセス | RSS |
|---|---|
| Arbiter（PID 16352 / 16407） | 1,382.1〜1,382.4 MB |
| `database` ワーカー | 1,372.7〜1,373.1 MB |
| 各 `sync` ワーカー（9本） | 1,372.8〜1,373.2 MB |

Pre-fork モデルでは、fork 前の親プロセス（Arbiter）が大きなオブジェクトを保持していると、
Linux の CoW (Copy-on-Write) が動作していても `top` / `ps` 上の RSS は共有ページ分が各プロセスに
計上されるため、見かけ上の RSS が膨大になる。ただし、fork 直後の IDLE 状態で既に約 1.37 GB を
消費しているのは、起動時に巨大なオブジェクト（ベクトルインデックス等）がメモリに展開されており、
CoW が実際には効いていない（または参照を保持し続けている）可能性が高い。

### 再現手順 / Steps to Reproduce
1. `make run_supervisor` でスーパーバイザーを起動する（9 workers）
2. `PYTHONPATH=src .venv/bin/python -m supervisor.cli top --once` を実行する
3. 全プロセスの `MEM` 列が約 1,372〜1,382 MB であることを確認する

### 再現環境 / Environment
- OS / Env: Linux (WSL2) / Python 3.14.7 / `.venv` 仮想環境、RAM 容量次第でシステム全体に影響
- File: `src/supervisor/arbiter.py`, `src/web/server.py` (アプリケーション本体のロード処理)
- ログ観測日時: 2026-08-23 15:05:55〜15:06:18（起動直後から肥大化を確認）

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/supervisor/arbiter.py`](../../src/supervisor/arbiter.py) — fork 前アプリケーションロード処理
- [ ] [`src/web/server.py`](../../src/web/server.py) — WSGI アプリケーション起動時の初期化処理（インデックスロード等）
- [ ] [`src/search/`](../../src/search/) — ベクトルインデックス (index.json 6.3 GB) のロード処理
- [ ] [`src/supervisor/top.py`](../../src/supervisor/top.py) — RSS 取得・表示ロジック（/proc/<pid>/status 読取）
- [ ] `outputs/vector_db/index.json` — 巨大ベクトルインデックス（肥大化の原因候補）

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

<!-- 調査によって判明した真の根本原因（5つの「なぜ」や仮説など）を詳細に記述します。 -->
**仮説 A（最有力）**: Arbiter の fork 前に `src/web/server.py` の WSGI アプリ初期化が実行され、
`outputs/vector_db/index.json`（6.3 GB）等の大規模インデックスがメモリに完全展開されている。
これにより Arbiter の RSS が約 1.38 GB となり、fork 後の各ワーカーが CoW でこれを共有するが、
Python オブジェクトの参照カウント更新で CoW が実際に発動し、ページが複製されている。

**仮説 B**: インデックスのロードが遅延初期化（lazy load）ではなくモジュール import 時の即時初期化
として実装されており、fork 後も各ワーカーが独立してオブジェクトを保持している。

**仮説 C**: `top.py` の RSS 読取が `/proc/<pid>/status` の `VmRSS` フィールドを使っており、
共有ライブラリ等の共有ページも二重計上している（表示上の問題のみの可能性）。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**: ワーカー数を 2 以下に制限して起動し、合計メモリ使用量を抑制する。
* **恒久対策 (Permanent Fix)**:
  1. WSGI アプリのインデックスロードを遅延初期化（`@functools.lru_cache` + 初回リクエスト時ロード）へ変更し、fork 前のフットプリントを最小化する
  2. Arbiter の fork 前ロードを `preload_app=False` 相当に設定するオプションを追加し、各ワーカーが独立してアプリを初期化できるようにする
  3. `top.py` の RSS 表示に `VmPSS`（共有ページを按分計上）も併記し、実際のメモリ消費を正確に把握できるようにする
  4. `make run_supervisor` のデフォルトワーカー数を CPU コア数ベースの適切な値（`2 × CPU + 1`）に変更する

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/073-worker-rss-memory-bloat`

1. `src/web/server.py`: グローバルスコープのインデックスロード処理を `get_index()` 関数 + `@functools.lru_cache(maxsize=1)` パターンへリファクタリングし、import 時の即時ロードを排除する
2. `src/supervisor/arbiter.py`: `--preload / --no-preload` フラグを追加し、デフォルトを `--no-preload` とする
3. `src/supervisor/top.py`: `/proc/<pid>/status` から `VmPSS` も取得し、`RSS (PSS)` として表示する
4. `tests/supervisor/test_top.py`: PSS 読取テストを追加する

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `make run_supervisor` 起動後の各ワーカー RSS が 200 MB 以下（インデックス非プリロード時）
- [ ] `top --once` の MEM 列に `VmPSS` ベースの値が表示される
- [ ] `make check` (format + static_analysis + test) が 100% PASS
- [ ] `tests/supervisor/` にメモリフットプリントに関するテストが追加・PASS
