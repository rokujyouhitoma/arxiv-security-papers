---
ID: 398
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/SEC] VectorEngine のインデックスパス参照不整合の是正およびセマンティック RAG 検索の復旧 (ID: 398)

## 1. 概要 / Summary

Web UI の「🔍 セマンティック RAG 論文検索 & 脅威インテリジェンス」画面において、初期クエリ（「ペンテスト」）やキーワード検索のいずれを実行しても、常時「検索結果 (0件)」のまま表示され、学術論文の検索・探索が行えない不具合が発生している。

### 再現手順 / Steps to Reproduce

1. Web コンソール（`http://localhost:8000/`）を開く。
2. 「🔍 セマンティック RAG 論文検索」画面において、検索ボックスに「ペンテスト」や「security」と入力して検索を実行する。
3. `searchTime` のプロファイル表示に `total_documents: 0`、`candidates_evaluated: 0` と表示され、検索結果一覧が常に「該当する論文は見つかりませんでした。(0件)」となる。
4. `curl -s "http://localhost:8000/api/search?q=security&top_k=5"` を実行しても、`total_documents: 0, results: []` が返却される。

### 再現環境 / Environment

- OS / Env: Linux (Antigravity IDE 2.0 / Python 3.14.7)
- File: [src/search/vector_engine.py](../../src/search/vector_engine.py)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [src/search/vector_engine.py](../../src/search/vector_engine.py)
- [ ] [src/search/server/service.py](../../src/search/server/service.py)
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py)
- [ ] [tests/search/test_vector_engine.py](../../tests/search/test_vector_engine.py)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

Issue 360 および Issue 364 において、OKF およびデータベースストレージのディレクトリ階層再編が行われ、過渡期のシンボリックリンク `outputs/vector_db` は撤去された。
これに伴い、本番の検索インデックス（14,000件超の論文メタデータ、約51MB）の実体は `outputs/database/search_vector/index.json` および `vectors.vdb`, `hnsw_index.json` に配置された。

しかし、検索エンジン本体である `VectorEngine`（`src/search/vector_engine.py` L115-L117）において、以下のように旧パス `outputs/vector_db` がハードコードされたまま残存していた：
```python
self.vector_db_dir = os.path.join(self.workspace_dir, "outputs", "vector_db")
self.index_file = os.path.join(self.vector_db_dir, "index.json")
```

`outputs/vector_db/` は空ディレクトリとして存在するため、`load_index()` 実行時に `index.json` が見つからず、`VectorEngine` はドキュメント数 0 件の空インデックス状態で起動・常駐していた。
このため、Supervisor の `search` ワーカープロセスおよび `web` ワーカーのフォールバック検索がすべて 0 件の結果を返し続けていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**:
  `outputs/vector_db` から `outputs/database/search_vector` へのシンボリックリンクを一時的に設置するか、`outputs/database/search_vector/` のインデックスファイルを `outputs/vector_db/` へコピーする。
* **恒久対策 (Permanent Fix)**:
  `VectorEngine` のインデックスディレクトリ解決ロジックを改修し、正規パス `outputs/database/search_vector` を最優先でロードする。後方互換性およびテスト容易性のため、旧パス `outputs/vector_db` が存在する場合のフォールバックも維持する。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/398-vector-engine-index-path`

1. **`src/search/vector_engine.py` のパス解決の是正**:
   - `self.vector_db_dir` を `outputs/database/search_vector` を優先するように変更。
   - `index.json` が存在するか判定し、`outputs/database/search_vector` -> `outputs/vector_db` の優先順で自動解決。
   - `build_index()` 時の保存先も正規ディレクトリ `outputs/database/search_vector` とする。
2. **テストコード・CLIの検証**:
   - `VectorEngine` の初期化テストおよび `tests/search/` のテストスイートを実行し、インデックスが正常にロードされることを検証。
3. **Supervisor ワーカーへの反映**:
   - 変更後、Supervisor の `search` ワーカーおよび `web` ワーカーを再起動し、`/api/search` で正しく論文が検索されることを確認。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `VectorEngine` が `outputs/database/search_vector/index.json` を自動検出し、14,000件超の論文インデックスを正常にロードすること。
- [ ] `/api/search?q=ペンテスト` および `/api/search?q=security` のクエリ実行で、該当する学術論文がヒットして返却されること。
- [ ] Web UI 上の「🔍 セマンティック RAG 論文検索 & 脅威インテリジェンス」画面で、検索結果カードが正常に描画されること。
- [ ] `make test` および `make static_analysis` が 100% PASS すること。
