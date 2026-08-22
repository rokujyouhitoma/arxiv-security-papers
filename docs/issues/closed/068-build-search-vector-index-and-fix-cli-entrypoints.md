# Issue 068: 検索インデックス生成 (14,349件) および VectorEngine CLI・ハンドラ自動ロード改修

## 1. 概要 (Overview)
Web UI / API (`http://localhost:8000/?q=pentest` / `/api/search?q=pentest`) で検索結果が0件 (`(0件評価 / 全0件)`) となる事象が発生していた。
原因調査の結果、`outputs/okf_papers/` には 14,349 件の OKF 論文データが存在していたものの、ベクトル検索エンジン `VectorEngine` が読み込む `outputs/vector_db/index.json` が未構築（0件）状態であったことが判明した。
また、`Makefile` の `build_vector_db` および `rag_query` ターゲットが旧パス (`src/vector_engine.py`) を参照していたため、モジュール実行形式への是正と、CLI エントリポイントおよび Web ゲートウェイハンドラの自動リロード機構を追加した。

---

## 2. 原因分析 (Root Cause Analysis)
1. **未構築インデックス (`index.json` 欠落)**:
   - `VectorEngine` は `outputs/vector_db/index.json` をロードして BM25 / ベクトル / PageRank グラフ / Knowledge Graph を構築するが、新規環境または移行直後でインデックスファイルが存在していなかったため、検索対象ドキュメント数が 0 件として評価されていた。
2. **`Makefile` ターゲットパスの不整合**:
   - `Makefile` 内の `build_vector_db` および `rag_query` が `src/vector_engine.py` を呼び出していたが、パッケージリファクタリング後の実体は `src/search/vector_engine.py` であり、`-m search.vector_engine` 形式で実行する必要があった。
3. **CLI エントリポイント (`main()`) の欠落**:
   - `src/search/vector_engine.py` に `__name__ == "__main__"` CLI ハンドラが存在せず、コマンドラインからの `--build` や `--query` 実行ができなかった。
4. **Web ゲートウェイハンドラの耐障害性 (再読み込み)**:
   - サーバー起動後にインデックスが生成された場合、`GatewayHandlers` が空の `VectorEngine` インスタンスを保持し続ける状態となっていた。

---

## 3. 実施した変更内容 (Changes Made)

1. **インデックス一括構築 (`outputs/vector_db/index.json`)**:
   - 全 14,349 件の OKF 論文 (`outputs/okf_papers/YYYY-MM-DD/*.md`) をスキャンし、トークナイズ、BM25 IDF、PageRank、RAPTOR ツリー、近接グラフを生成して `outputs/vector_db/index.json` を出力。
2. **`VectorEngine` CLI ハンドラ追加 (`src/search/vector_engine.py`)**:
   - `main()` 関数および `argparse` による `--build` / `--query` / `--top-k` CLI インターフェースを実装。
3. **`Makefile` 修正 (`Makefile`)**:
   - `build_vector_db`: `PYTHONPATH=src ${VENV_PYTHON} -m search.vector_engine --build`
   - `rag_query`: `PYTHONPATH=src ${VENV_PYTHON} -m search.vector_engine --query "$(Q)"`
4. **Web ゲートウェイハンドラ自動ロード (`src/web/gateway/handlers.py`)**:
   - `GatewayHandlers.vector_engine` プロパティにて、ドキュメントが空の場合に動的 `load_index()` を行う安全フォールバックを追加。

---

## 4. 検証結果 (Verification Results)
- **検索 API 疎通確認**:
  - `curl -s "http://localhost:8000/api/search?q=pentest&top_k=3"`:
    - `total_documents`: 14,349 件
    - 取得結果:
      1. `From Controlled to the Wild: Evaluation of Pentesting Agents for the Real-World` (スコア: 226.2)
      2. `Pen-Strategist: A Reasoning Framework for Penetration Testing Strategy Formation and Analysis` (スコア: 210.8)
      3. `Qualcomm Trusted Application Emulation for Fuzzing Testing` (スコア: 190.0)
- **品質ゲート**:
  - `make check`: `check_format`, `static_analysis`, `test` (397 passed, 0 failures, 81.11% coverage) 全て PASS。
