---
ID: 123
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] mmap・struct駆動 Pure-Python IVF-PQ（転置インデックス積量子化）高密度ベクトルANN探索エンジンの実装 (ID: 123)

## 1. 概要 / Summary
外部のベクトル検索ライブラリや重量級 C-lib（Faiss, Annoy, ScaNN 等）に一切依存せず、Python 標準ライブラリの `struct` モジュールによる固定長バイナリパッキングと `mmap` によるゼロコピーメモリマッピングを組み合わせた、Pure-Python による転置インデックス付き積量子化（Inverted File with Product Quantization: IVF-PQ）近似最近傍探索（ANN）エンジンを実装する。
128次元の論文埋め込みベクトルを 8〜16 個のサブスペース（各 8〜16次元）に分割し、各サブスペースを 256 重心（1バイトコード）で量子化することで、ベクトルあたりわずか 8〜16 バイト（圧縮率 96.8%）に圧縮しながら、非対称距離計算（Asymmetric Distance Computation: ADC）のルックアップテーブル（LUT）参照によりサブミリ秒の Top-K 探索を実現する。

---

## 2. トレーサビリティ / Traceability
- [DSN-04: 検索エンジン・プラットフォーム (Section 4.6)](../../docs/designs/DSN-04-search_engine_and_platform.md)
- [DSN-05: データベースエンジンアーキテクチャ](../../docs/designs/DSN-05-database_engine_architecture.md)
- [src/search/vector/](../../src/search/vector/)
- [src/database/index/embedding.py](../../src/database/index/embedding.py)

---

## 3. 脅威モデリングとセキュリティ要件 / Threat Modeling & Security
1. **境界外メモリアクセス・バッファオーバーフロー**:
   - `struct.unpack` およびバイナリ展開時、ヘッダーの次元数 $D$、サブスペース数 $M$、クラスタ数 $K$ の整合性を検証し、不正なインデックス境界値によるクラッシュを防止する。
2. **ゼロ除算・浮動小数点例外**:
   - K-Means 重心更新時に要素数 0 の空クラスタが発生した場合のフォールバック重心再初期化を実装し、NaN / Inf の混入を防止する。
3. **パス・トラバーサル**:
   - インデックスファイル保存・読み込み時のパス境界検証を徹底する。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/search/vector/quantization.py` (新設: Product Quantizer & ADC LUT)
- [x] `src/search/vector/ivf_pq.py` (新設: IVFPQIndex & Inverted File Posting Lists)
- [x] `src/search/vector/__init__.py` (公開インターフェース追加)
- [x] `tests/search/test_ivf_pq.py` (新設: 単体・性能・再現性テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/123-implement-pure-python-ivf-pq-dense-vector-ann-engine`

1. **`ProductQuantizer` の実装 (`src/search/vector/quantization.py`)**:
   - パラメータ: `dim=128`, `M=8` (各 $d^*=16$ 次元), `num_centroids=256` (各 1 バイトコード)。
   - 純粋 Python K-Means（K-Means++ 初期化、コサイン/ユークリッド距離）によるコードブック学習。
   - `encode(vector: Sequence[float]) -> bytes`: ベクトルを $M$ バイトのコード列に量子化。
   - `decode(codes: bytes) -> List[float]`: コード列から近似ベクトルを復元。
   - `compute_lut(query: Sequence[float]) -> List[List[float]]`: クエリサブベクトルと全重心間の $M \times 256$ 距離テーブル（LUT）を事前計算。
   - `compute_adc(lut: List[List[float]], codes: bytes) -> float`: LUT 参照による $O(M)$ 超高速非対称距離計算。
   - `save(path)` / `load(path)` によるバイナリ/JSON 永続化。

2. **`IVFPQIndex` の実装 (`src/search/vector/ivf_pq.py`)**:
   - Inverted File (IVF) 空間粗探索部: $nlist$ 個（例: 16〜32セル）の粗重心（Coarse Centroids）。
   - 転置リスト（Posting Lists）: 各セル ID に `List[Tuple[int, bytes]]`（`doc_id`, `pq_codes`）を保持。
   - `train(vectors)`: 粗重心 K-Means 学習および PQ コードブック学習。
   - `add(doc_id, vector)`: 最も近い粗重心に所属させ、PQ コードを転置リストに追加。
   - `search(query, top_k=10, nprobe=4)`:
     1. クエリに最も近い `nprobe` 個の粗重心セルを選択。
     2. クエリに対する ADC LUT を一括事前計算。
     3. 選択されたセルの転置リストのみを走査し、LUT 参照加算で高速距離算出。
     4. `heapq.nsmallest` により Top-K 近傍を返却。

3. **公開モジュール統合 (`src/search/vector/__init__.py`)**:
   - `ProductQuantizer`, `IVFPQIndex` をエクスポート。

4. **テストスイートの構築 (`tests/search/test_ivf_pq.py`)**:
   - 量子化エンコード/デコードの精度検証、LUT・ADC 距離の正確性。
   - IVF-PQ 探索精度（ブルートフォース探索との Top-K リコール検証）。
   - 保存/復元の完全性。
   - 10,000 件規模ベクトルに対するサブミリ秒（$ < 1\text{ms}$）レイテンシベンチマーク。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 外部依存ゼロ（標準ライブラリのみ）で `ProductQuantizer` および `IVFPQIndex` が動作すること
- [x] 128次元ベクトルが 8 バイト（1/16 のフットプリント）に圧縮されること
- [x] 10,000 件規模のベクトルに対して 1ms 未満で Top-K 探索が完了すること
- [x] 探索精度においてブルートフォース探索に対して高い順位相関が得られること
- [x] 全品質ゲート（Xenon Rank A, Flake8, Mypy Strict, pytest）を 100% パスすること

