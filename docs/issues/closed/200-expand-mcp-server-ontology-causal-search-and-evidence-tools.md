---
ID: 200
種別: Feature
優先度: Medium
ステータス: Closed
Created At: 2026-09-06T21:56:15+09:00
Polished At: 2026-09-06T22:01:00+09:00
Closed At: 2026-09-06T22:06:00+09:00
---

# [FEAT/ENH] AI エージェント向け MCP サーバーにおけるオントロジー因果探索・エビデンス推論ツールの拡充 (ID: 200)

## 1. 概要 / Summary

Claude Desktop、Cursor、Antigravity IDE 等の AI コーディングエージェントから利用される Model Context Protocol (MCP) サーバー群（`src/mcp/`）を拡張し、Full-Spectrum SKO (W3C OWL / DSN-22) に蓄積された因果連鎖や実証エビデンスを直接問い合わせ・推論できる高次ツール群を追加する。

具体的には以下の 2 つの高次ツールを新設する：
1. `search_defense_causal_chains`: 攻撃手法（MITRE ATT&CK ID / 脅威キーワード）から、前提条件、無力化メカニズム、緩和策、推奨防御コードまでの因果パスをワンステップで探索・返却。
2. `query_ontology_evidence`: 論文 ID または主張（Claim ID）から、紐付けられた実証エビデンス（ベンチマーク数値、データセット、PoC アーティファクト、信頼度スコア）を構造化返却。

これにより、AI エージェントがセキュアコーディングや脅威モデリングを行う際、単なる文献テキスト検索にとどまらず、**「学術的に検証された攻撃因果連鎖と実証エビデンス」** に基づく極めて高精度な意思決定・パッチ生成を自律実行可能にする。

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-10 Model Context Protocol (MCP) サーバー群包括的仕様書](../designs/DSN-10-mcp_servers_architecture.md)
- 設計書: [DSN-22 セキュリティおよび脅威インテリジェンス知識オントロジー W3C 仕様書](../designs/DSN-22-security_and_threat_ontology_w3c_specification.md)
- 設計書: [DSN-04 検索エンジンおよび検索プラットフォーム包括的アーキテクチャ設計仕様書](../designs/DSN-04-search_engine_and_platform.md)
- 仕様書: [MCP-01 MCP サーバ ＆ ベクトル DB 仕様書](../mcp/MCP-01-mcp_server_specification.md)
- 関連過去Issue:
  - [Issue 179: 全領域統合セキュリティ知識オントロジーの実装](closed/179-implement-full-spectrum-security-knowledge-ontology.md)
  - [Issue 185: 脅威モデル因果連鎖および前提条件無力化モデルの実装](closed/185-implement-threat-model-causality-impact-and-precondition-neutralization.md)
  - [Issue 186: 主張と実証の分離・エッジ属性具現化の実装](closed/186-implement-claim-evidence-reification-and-regex-data-constraints.md)
  - [Issue 188: 実論文データABoxへの新実体統合と因果・エビデンス探索の実装](closed/188-integrate-causal-reified-entities-into-paper-abox-graph.md)

---

## 3. セキュリティ要件と脅威モデリング (Security & Threat Analysis)

MCP サーバーは外部プロセス（AI エージェントや IDE）からの JSON-RPC 入力を処理するため、以下の脅威に対処する：

1. **入力インジェクション / 汚染 (Input Injection & Taint Analysis)**:
   - クライアントからの `technique_id`, `paper_id`, `claim_id` に特殊文字やエスケープシーケンス、改行等が含まれる可能性。
   - 対策: `mcp.security.TaintGuard` および `sanitize_payload` による厳格な入力サニタイズと正規化（英数字、ハイフン、ドット、コロンのみ許容）。
2. **グラフ走査による DoS / メモリ枯渇 (Algorithmic Complexity Attack)**:
   - 循環グラフや大規模隣接ノードの探索による無限ループ・スタックオーバーフロー・高負荷。
   - 対策: 探索深度（`max_depth`）のデフォルト制限（最大 3〜4 ホップ）、訪問済みノード（`visited_set`）によるループ検出、最大返却件数（`limit`）の上限設定。
3. **パストラバーサル / 機密情報漏洩**:
   - 内部ストレージパスへの不正アクセス防止のため、`is_safe_workspace_path` による厳格なパス検証を徹底。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/mcp/tools/ontology_tools.py](../../src/mcp/tools/ontology_tools.py) (新規: 因果連鎖探索 `CausalChainFinder` およびエビデンス抽出 `EvidenceInspector` の実装)
- [ ] [src/mcp/threat_defense_server.py](../../src/mcp/threat_defense_server.py) (`TOOLS_MANIFEST` に `search_defense_causal_chains` 追加、ハンドラー実装およびディスパッチ登録)
- [ ] [src/mcp/papers_server.py](../../src/mcp/papers_server.py) (`TOOLS_MANIFEST` に `query_ontology_evidence` 追加、ハンドラー実装およびディスパッチ登録)
- [ ] [docs/mcp/MCP-01-mcp_server_specification.md](../mcp/MCP-01-mcp_server_specification.md) (新 MCP ツールのスキーマ、パラメータ、使用プロンプト例の追記)
- [ ] [tests/mcp/test_ontology_mcp_tools.py](../../tests/mcp/test_ontology_mcp_tools.py) (新規ユニットテスト: 正常系・異常系・サニタイズ・ループ防止検証)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳ステータス更新)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/200-expand-mcp-server-ontology-causal-search-and-evidence-tools`

### Step 1: `src/mcp/tools/ontology_tools.py` の新規実装
1. **`CausalChainFinder` クラス**:
   - `GraphEngine.load_from_storage(workspace_dir)` を利用し、インメモリ CSR グラフを走査。
   - メソッド `find_defense_chains(tech_or_threat_id: str, max_depth: int = 3, min_confidence: float = 0.5) -> Dict[str, Any]`:
     - 指定された脅威エンティティ（例: `AttackTechnique:T1059` やキーワード一致ノード）を基点とする。
     - 出力因果エッジ `HAS_IMPACT` (Impact), `REQUIRES_PRECONDITION` (Precondition), `TARGETS` (TargetAsset) を探索。
     - Precondition から逆引きで `NEUTRALIZES_PRECONDITION` (DefenseMechanism) を取得。
     - DefenseMechanism から `MITIGATES` (AttackTechnique), `PATCHES` (Vulnerability), `GENERATES_RULE` (DetectionRule) を取得。
     - 各パスの推論確信度（`confidence`）および推論ルール ID（`inference_rule`）を収集し、推奨緩和チェーンとしてランキング整形。
2. **`EvidenceInspector` クラス**:
   - メソッド `get_evidence_for_entity(entity_id: str) -> Dict[str, Any]`:
     - 論文ノード（`Paper:...`）または主張ノード（`Claim:...`）を基点とする。
     - エッジ `ASSERTS_CLAIM`, `YIELDS_EVALUATION`, `EVALUATES_CLAIM`, `EVALUATES_TECHNIQUE`, `HAS_POC` を走査。
     - 実証エビデンス（`EvaluationResult` のメトリクス・数値、`PoCArtifact` のリポジトリリンク・再現環境、`BenchmarkMetric` のベンチマーク名）を抽出。
     - 論文の主張とそれを支える定量的・定性的エビデンスをペアリングして返却。

### Step 2: `threat_defense_server.py` へのツール統合
- `TOOLS_MANIFEST` に `search_defense_causal_chains` の JSON スキーマを登録：
  - `threat_id`: 必須文字列 (例: `"T1059"`, `"Command Injection"`, `"CWE-89"`)
  - `max_depth`: 任意整数 (デフォルト: 3, 範囲: 1〜5)
  - `min_confidence`: 任意浮動小数点数 (デフォルト: 0.0, 範囲: 0.0〜1.0)
- `handle_search_defense_causal_chains(params: Dict[str, Any]) -> Dict[str, Any]` を実装。
- `TOOL_HANDLERS` 辞書に登録。

### Step 3: `papers_server.py` へのツール統合
- `TOOLS_MANIFEST` に `query_ontology_evidence` の JSON スキーマを登録：
  - `entity_id`: 必須文字列 (arXiv 論文 ID 例: `"2403.12345"` または Claim/Paper URI)
  - `include_pocs`: 任意真偽値 (デフォルト: true, PoC アーティファクト情報を含めるか)
- `handle_query_ontology_evidence(params: Dict[str, Any]) -> Dict[str, Any]` を実装。
- `dispatch_tool` および `tool_map` に登録。

### Step 4: ドキュメントおよびテストの拡充
- `docs/mcp/MCP-01-mcp_server_specification.md` に Section 2.5 および 2.6 を追加。
- `tests/mcp/test_ontology_mcp_tools.py` を作成し、以下を検証：
  1. `CausalChainFinder` による因果パス走査（正常系および存在しない ID のハンドリング）。
  2. `EvidenceInspector` によるエビデンス取得（正常系および空データ時のハンドリング）。
  3. `threat_defense_server.py` および `papers_server.py` を通じた JSON-RPC stdio 呼び出しテスト。
  4. 不正な文字列・深度上限超過時のバリデーションガード検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `src/mcp/tools/ontology_tools.py` が新規作成され、`CausalChainFinder` と `EvidenceInspector` が実装されていること。
- [x] `threat_defense_server.py` の `tools/list` に `search_defense_causal_chains` が現れ、`tools/call` で正常に因果連鎖が取得できること。
- [x] `papers_server.py` の `tools/list` に `query_ontology_evidence` が現れ、`tools/call` で正常にエビデンスが取得できること。
- [x] 外部プロセスからの入力に対するサニタイズおよび探索上限（深度・件数）ガードが機能していること。
- [x] [docs/mcp/MCP-01-mcp_server_specification.md](../mcp/MCP-01-mcp_server_specification.md) に新仕様が追記されていること。
- [x] 新規単体テスト（`tests/mcp/test_ontology_mcp_tools.py`）を含む全 MCP テストが PASS すること。
- [x] `make check_format` および `make static_analysis` (mypy strict, Xenon Grade A $\le 5$) がエラー 0 件であること。
