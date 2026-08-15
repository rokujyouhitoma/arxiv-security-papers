# [MNG-01] 文書管理・ドキュメント台帳 (Document Management & Ledger) - arxiv-security-papers

本ドキュメントは、「`arxiv-security-papers`」プロジェクトにおいて作成・維持されるすべてのドキュメントの台帳であり、ドキュメントごとの目的、担当領域、および設計ドキュメントのオーバーラップ時におけるすみ分け方針を定義します。

---

## 1. 文書管理方針 (Document Management Policy)

本プロジェクトにおける文書管理の基本理念は、全13専門エージェントガバナンスに基づく「**ドキュメント・スキル・コードの三位一体（連携）モデル**」に基づいています。

ドキュメント（Single Source of Truth / SOT）は、プロジェクトにおける唯一の「正」であり、コードと同等以上の価値を持つ重要成果物です。暗黙知や場当たり的な開発を徹底排除し、機能追加・仕様変更・モデル更新時には、必ず要件定義書（REQ-01）、基本設計書（DSN-01）、詳細設計書（DSN-02）、および Issue 台帳（issues/README.md）を先行して更新し、設計変更履歴を常に追跡可能（トレーサブル）な状態に維持することで、ドキュメントの腐敗（死文化）を恒久的に防止します。

### 1.1 文書管理番号の設計方針と管理策 (Numbering Policy & Controls)

変更影響を最小化し、トレーサビリティを担保するため、以下の分類プレフィックス＋2桁連番の管理体系を導入します。

- **`MNG` (Management)**: プロセス定義、文書管理台帳等のプロジェクト運用管理文書。
- **`REQ` (Requirements)**: システム要件定義書、機能一覧等の要求・要件文書。
- **`DSN` (Design)**: アーキテクチャ基本設計書(HLD)、コンポーネント詳細設計書(LLD)等の技術設計文書。
- **`MCP` (Model Context Protocol)**: AI エージェント連携用 MCP サーバおよびベクトル DB 仕様文書。
- **`ISS` (Issues)**: 開発タスク・障害追跡用の Issue 台帳および個別 Issue アーカイブ。

#### 文書管理策 (Document Controls)
1. **事前登録管理**: 新規ドキュメントの作成・改廃時は、本台帳（`MNG-01`）へ登録し一意の管理番号を採番します。
2. **完全相対パス管理**: 環境独立性を担保するため、ドキュメント間リンクには厳格に相対パスのみを使用します。
3. **品質ゲート連携**: `make py_compile` および `verify-quality-gates` スキルにより、ドキュメント内相対パスの有効性と整合性を自動検証します。

---

## 2. ドキュメント台帳 (Document Ledger)

| 管理番号 / ドキュメント名 | 相対ファイルパス | 目的・概要 | 主な参照者 | 承認・責任者 | 更新タイミング |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **[MNG-01] 文書管理台帳** | [processes/MNG-01-document_ledger.md](MNG-01-document_ledger.md) | 全ドキュメントの一覧管理、命名・採番規則、分掌方針を定義する台帳。 | PM, SA, 全エージェント | PM | ドキュメントの追加・削除・構成変更時 |
| **[REQ-01] 要件定義書** | [requirements/REQ-01-system_requirements.md](../requirements/REQ-01-system_requirements.md) | arXiv cs.CR フェッチ、OKF v0.2 変換、5階層日本語サマリー、MCP/ベクトルDBの機能・非機能要件を定義。 | PM, SA, QA, SC, 開発者 | PM | 新機能追加、パイプライン仕様変更時 |
| **[DSN-01] 基本設計書 (HLD)** | [designs/DSN-01-high_level_design.md](../designs/DSN-01-high_level_design.md) | システム全体の論理アーキテクチャ、データフロー、5階層サマリー構造、MCP 統合設計を定義。 | SA, PM, 開発エージェント | SA | アーキテクチャ変更、データ構造刷新時 |
| **[DSN-02] 詳細設計書 (LLD)** | [designs/DSN-02-low_level_design.md](../designs/DSN-02-low_level_design.md) | スクリプト (`src/arxiv_okf_fetcher.py`, `src/vector_engine.py`, `src/mcp_server.py`) の関数仕様、正規表現、JSONスキーマ等の物理設計。 | 実装担当エージェント, SQA | SA | モジュールインターフェース、アルゴリズム変更時 |
| **[MCP-01] MCP & Vector DB 仕様書** | [mcp/MCP-01-mcp_server_specification.md](../mcp/MCP-01-mcp_server_specification.md) | MCP JSON-RPC サーバ (4大ツール) およびセマンティックベクトル DB (Chroma/TF-IDF) の詳細仕様。 | AI エージェント, IR, SC, 開発者 | SA, IR | MCP ツール拡張、検索アルゴリズム改訂時 |
| **[ISS-00] Issue 台帳** | [issues/README.md](../issues/README.md) | プロジェクトの全 Issue (起票・進行中・完了) を一括追跡・管理する中央台帳。 | PM, 開発チーム | PM | Issue の新規作成・ステータス変更時 |

---

## 3. 設計ドキュメント間のすみ分けと分掌 (Demarcation & Overlap Rules)

### 3.1 HLD（基本設計）と LLD（詳細設計）の分掌
- **HLD (基本設計)**: **「何が（What）」定義されているか（論理・概念）** に特化。論理アーキテクチャ、データフロー図（Mermaid）、ディレクトリ構造、エグゼクティブサマリーの 5 階層概念を規定。
- **LLD (詳細設計)**: **「どのように（How）実装するか（物理・具象）」** を詳細規定。各 Python スクリプトの関数名・引数・戻り値・YAMLフロントマタースキーマ・パス解決アルゴリズムを明記。

### 3.2 要件定義 (REQ) と設計 (DSN) の競合解決規則
- 実装や検証の過程で要件定義（REQ-01）と設計（DSN-01/DSN-02）に不一致が生じた場合、**「要件定義（REQ-01）が上位」** となります。要件変更時はまず REQ-01 を更新後、設計・コードに反映します。
