# [DSN-07] 共通セキュリティ基盤・ASTガード＆RBACエンジン設計書 (Repository Security, AST Guard & Threat Defense) — arxiv-security-papers

- **文書番号**: `DSN-07`
- **文書ステータス**: `APPROVED`
- **対象サブシステム**: `src/security/` (RBAC, AST Guard, Path Validation, Taxonomy)
- **関連パッケージ**: システム全体 (`src/`)
- **作成日**: 2026-08-22
- **最終更新日**: 2026-08-22
- **主幹エージェント**: Information Security Specialist & Systems Auditor

---

## 1. アーキテクチャ概要・設計思想・スコープ

### 1.1 セキュリティサブシステムのミッション
`src/security/` は、AI コーディングエージェントや外部 MCP クライアントからの動的コード実行、ファイルアクセス、権限昇格、および悪意あるペイロードインジェクションをゼロトラスト原則に基づき完全に防御・検知・遮断する共通多層セキュリティ基盤である。

```
+---------------------------------------------------------------------------------------------------+
|                                  src/security/ Subsystem Architecture                             |
+---------------------------------------------------------------------------------------------------+
|  1. AST Guard & Code Sandbox (src/security/sandbox/)                                              |
|   - AST Static Analysis | Prohibited Modules/Builtins Blacklist | Recursive Call Depth Guard      |
+---------------------------------------------------------------------------------------------------+
|  2. Path Traversal & File System Shield (src/security/validation/)                               |
|   - Path Normalization | Symlink Resolution | Workspace Confinement (jail)                        |
+---------------------------------------------------------------------------------------------------+
|  3. Multi-Tenant Role-Based Access Control (src/security/rbac/)                                   |
|   - Roles: admin, analyst, guest | Permission Matrix | Permission Enforcement Decorator           |
+---------------------------------------------------------------------------------------------------+
|  4. Cybersecurity Taxonomy & Threat Mapping (src/security/taxonomy/)                              |
|   - MITRE ATT&CK Enterprise Matrix | Common Weakness Enumeration (CWE) | STRIDE Threat Model      |
+---------------------------------------------------------------------------------------------------+
```

---

## 2. 全13大専門エージェント多角的多面協議議事録

```mermaid
mindmap
  root((セキュリティ基盤合意))
    PM["1. PM: ゼロトラスト防御・セキュリティインシデントゼロ目標"]
    Sec["2. InfoSec: ASTガード・プロヒビテッドモジュール遮断・CWEマッピング"]
    Arch["3. Architect: 全レイヤー横断インターセプター・最小権限の原則"]
    QA["4. SQA: 悪意あるコード・PoCインジェクションによるファジング検証"]
    DB["5. DB: SQLインジェクション防止・パラメータバインディング必須化"]
    Net["6. Network: SSRF防御・許可ドメインホワイトリスト"]
    IR["7. IR: 脅威タクソノミー抽出・MITRE ATT&CK自動付与"]
    Strat["8. Strategist: NIST SP 800-53 / ISO 27001 コンプライアンス"]
    Ops["9. Service: 監査ログ改竄防止・セキュリティアラート即時通知"]
    IoT["10. Embedded: メモリ破壊・バッファオーバーフロー検知"]
    Audit["11. Auditor: 操作ログ不変性・ハッシュ署名検証"]
    UI["12. UI: XSSサニタイズ・Content-Security-Policy (CSP)"]
    Edu["13. Education: セキュアコーディングガイドライン・用語定義"]
```

---

## 3. パッケージ構造 & 防御フロー

```mermaid
graph TD
    subgraph Client["外部入力 / エージェントリクエスト"]
        Req["コード実行 / パスアクセス / API呼び出し"]
    end

    subgraph SecurityGuard["src/security/ 多層防御シールド"]
        PathVal["Path Validator<br/>(is_safe_workspace_path)"]
        ASTGuard["AST Guard<br/>(validate_python_ast)"]
        RBAC["RBAC Engine<br/>(enforce_permission)"]
        Taxonomy["Threat Taxonomy<br/>(MITRE / CWE / STRIDE)"]
    end

    subgraph Target["保護対象リソース"]
        FS["Workspace Filesystem"]
        Exec["Python Execution Context"]
        Data["Database & Search Engine"]
    end

    Req --> PathVal & ASTGuard & RBAC
    PathVal -- "安全な相対パス" --> FS
    ASTGuard -- "許可されたASTノード" --> Exec
    RBAC -- "認可されたロール" --> Data
    Data --> Taxonomy
```

---

## 4. コアアルゴリズム & AST セキュリティ検証仕様

### 4.1 AST ノード走査と禁止要素ブラックリスト
Python 抽象構文木 (`ast.parse`) に対する深さ優先探索（DFS）走査：

$$\forall \text{node} \in \text{AST}(code): \text{node} \notin \mathcal{B}_{\text{prohibited}} \land \text{Depth}(\text{node}) \le D_{\max}$$

禁止モジュール集合 $\mathcal{B}_{\text{prohibited}}$：
- `os`, `subprocess`, `socket`, `pty`, `sys`, `shutil`, `importlib`, `ctypes`
- 禁止組み込み関数: `eval`, `exec`, `__import__`, `open` (書き込みモード), `compile`

---

## 5. 公開インターフェース & クラス定義

```python
class ASTGuard:
    def validate_code(self, source_code: str) -> None:
        """Raises SecurityException if forbidden nodes or modules are detected."""
        ...

class RBACEngine:
    def check_permission(self, context: SecurityContext, required_perm: Permission) -> bool: ...
    def enforce(self, context: SecurityContext, required_perm: Permission) -> None: ...

def is_safe_workspace_path(path: str, workspace_root: str) -> bool: ...
```

---

## 6. シーケンス図: 動的コード実行と権限制御フロー

```mermaid
sequenceDiagram
    autonumber
    actor User as クライアント / MCP
    participant RBAC as RBAC Engine
    participant AST as AST Guard
    participant Val as Path Validator
    participant Target as 内部実行エンジン

    User->>RBAC: リクエスト実行 (Token / Role)
    alt 権限不足 (Guest -> Admin Tool)
        RBAC-->>User: 403 Forbidden (PermissionDeniedError)
    else 認可成功
        RBAC->>AST: コード検証 (source_code)
        alt 危険なインポート検知 (import os)
            AST-->>User: 400 Bad Request (SecurityASTException)
        else 安全確認
            AST->>Val: パス検証 (file_path)
            alt パストラバーサル検知 (../../etc/passwd)
                Val-->>User: 400 Bad Request (PathTraversalError)
            else パス安全
                Val->>Target: 安全に実行
                Target-->>User: 実行結果返却
            end
        end
    end
```

---

## 7. 包括的テスト戦略

- **`tests/security/test_ast_sandbox.py`**: 禁止モジュール、悪意ある式、無限再帰のブロックテスト
- **`tests/security/test_path_validation.py`**: シンボリックリンク攻撃、絶対パス、`..` トラバーサル検証
- **`tests/security/test_rbac_engine.py`**: admin / analyst / guest の権限マトリクステスト
- **`tests/security/test_taxonomy.py`**: MITRE ATT&CK / CWE / STRIDE タグ抽出テスト

---

## 8. 完了定義 (DoD)

- [x] AST サンドボックス・パストラバーサルシールドの完全実装
- [x] マルチテナント RBAC デコレータとコンテキスト伝播
- [x] 100% カバレッジ・型検査通過
