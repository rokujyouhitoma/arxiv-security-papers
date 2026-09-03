---
ID: 136
種別: Improvement
優先度: High
ステータス: Closed (Completed)
完了日: 2026-09-03
---

# [IMPR] Context Meshにおけるエンティティ名寄せ（Entity Resolution）・重複排除（Deduplication）と論文横断グラフ結合の実装 (ID: 136)

## 1. 概要 / Summary
`/dashboard` の Context Mesh（4層パイプライン概念モデル: SOURCE $\rightarrow$ ENTITY $\rightarrow$ CLAIM $\rightarrow$ DECISION）において、各論文ごとに `src_0, ent_0, clm_0, dec_0` という独立したノードIDが毎回新規生成され、共通のセキュリティ概念（例: `Zero Trust`, `Cryptography`, `Prompt Injection` 等）が存在しても論文間でエッジが結合されず、1:1:1:1 の孤立した4ノードの組が分散配置される構造的問題を解決した。
エンティティ名寄せ（Entity Resolution）・重複排除（Deduplication）エンジンを導入し、複数論文から同一の ENTITY や DECISION へ多対多接続される相互結合メッシュネットワークへ高度化した。

---

## 2. トレーサビリティ / Traceability
- [DSN-14: Graph Engineering Dashboard (Section 11)](../../designs/DSN-14-graph_engineering_dashboard.md)
- [DSN-09: Web Gateway & Presentation (Section 7)](../../designs/DSN-09-web_gateway_and_presentation.md)
- [Issue 135: arXivセキュリティ論文・MITRE ATT&CK・CWEナレッジグラフデータ基盤および /dashboard インタラクティブグラフ可視化の実装](135-implement-paper-attck-cwe-knowledge-graph-and-dashboard-visualization.md)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Modeling & Mitigations)
- **T-136-01: 名寄せキー生成時のインジェクション・キー衝突 (CWE-20)**
  - *対策*: 英数字およびハイフン・アンダースコアのみに正規化するスラッグ関数および定義済みドメインスペック（`MESH_DOMAIN_DEFINITIONS`）により、厳格に型安全なノードID生成を保証。
- **T-136-02: 密結合グラフによる Canvas 物理演算負荷増大 (DoS)**
  - *対策*: 上位 12 件の代表論文にクリッピングし、エッジ重みの正規化を行うことで Canvas 描画の 60 FPS を維持。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/web/gateway/handlers.py` (`_build_dynamic_paper_mesh` の名寄せ・重複排除・多対多エッジ生成の実装、`_scan_real_okf_papers` の日付逆順ソート最適化)
- [x] `tests/web/test_dashboard_html.py` (`test_context_mesh_entity_resolution_and_deduplication` および `test_gateway_graph_mesh_with_vector_engine` の更新)

---

## 5. 実装内容 / Implementation Details
1. **正規化名寄せスペック（`MESH_DOMAIN_DEFINITIONS`）の導入**:
   - `ent_llm_aiml` (AI & Neural Subsystems)
   - `ent_crypto_protocols` (Cryptographic Protocols & PKI)
   - `ent_zero_trust_iam` (Zero-Trust Identity & Access)
   - `ent_os_hardware` (OS Kernel & Memory Subsystems)
   - `ent_software_pipeline` (Software Supply Chain & Registries)
   - `ent_network_protocol` (Network & Protocol Infrastructure)
2. **多対多ノード辞書と重み動的インクリメント**:
   - `_upsert_domain_node`: 同一エンティティや共通ポリシーノードへの複数論文からの参照時に、重み（weight）を動的に加算しハブノードとして可視化。
3. **論文横断エッジの結合**:
   - `SOURCE` $\rightarrow$ 共通 `ENTITY`（`targets`）
   - `SOURCE` $\rightarrow$ 共通 `CLAIM`（`asserts`）
   - `CLAIM` $\rightarrow$ 共通 `DECISION`（`requires`）
   - `DECISION` $\rightarrow$ 共通 `ENTITY`（`protects`）
4. **ディレクトリ走査の超高速化**:
   - `_scan_real_okf_papers`: `os.walk` を `sorted(os.listdir, reverse=True)` による日付別直近走査に改善（0.0005秒で最新論文を即時ロード）。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `/api/graph/mesh` において同一タグ・概念を持つノードが重複排除（Deduplication）され、共有ノードとして返却されること
- [x] 複数の論文（SOURCE）が同一の ENTITY / CLAIM / DECISION に接続され、孤立した 4 ノードの組が解消されること
- [x] 全品質ゲート（Xenon Rank A, Flake8 0 errors, Mypy Strict 0 errors, pytest 100% PASS）を充足すること
