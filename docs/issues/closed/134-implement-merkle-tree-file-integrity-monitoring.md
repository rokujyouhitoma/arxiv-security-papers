---
ID: 134
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] Merkle Tree（暗号論的ハッシュ木）駆動の原本・メタデータ改ざん検知（FIM: File Integrity Monitoring）基盤の実装 (ID: 134)

## 1. 概要 / Summary
arXiv からダウンロードされた生 PDF、テキスト中間体（pdftotext 抽出物）、Google OKF v0.2 形式の要約ファイル、および STIX 知識グラフ JSON について、外部からの意図せぬ改ざん、ストレージ障害によるビット反転（Silent Data Corruption / Bit Rot）、あるいは不正なファイル置換を検知するファイル整合性監視（File Integrity Monitoring: FIM）基盤を Pure Python（ゼロ外部依存: `hashlib` のみ）で実装する。

全ドキュメントの SHA-256 ダイジェストをリーフノードとし、RFC 6962 に準拠したドメイン分離（Leaf プレフィックス `0x00`、Internal プレフィックス `0x01`）を施した暗号論的ハッシュ木（Merkle Tree）をメモリ上で構築する。日次バッチ完了時に単一の Merkle Root ハッシュをマニフェスト（`manifest.json`）に記録することで、監査時には $O(\log N)$ の監査パス（Merkle Proof）を用いて特定ファイルの真正性をサブミリ秒で数学的に証明可能にする。

---

## 2. トレーサビリティ / Traceability
- [DSN-05: データベースエンジンアーキテクチャ](../../docs/designs/DSN-05-database_engine_architecture.md)
- [DSN-07: セキュリティガード & RBAC](../../docs/designs/DSN-07-security_guard_and_rbac.md)
- [REQ-03: プロジェクトユースケース台帳 (UC-OPS-01, UC-OPS-02)](../requirements/REQ-03-use_case_ledger.md)
- [Issue 048: バージョンベクトル・CRDT・Merkle ツリーアンチエントロピー基盤の実装](closed/048-implement-version-vectors-crdt-and-merkle-anti-entropy.md)
- [src/security/](../../src/security/)
- [outputs/raw_data/](../../outputs/raw_data/)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Modeling & Mitigations)
- **T-134-01: セカンドプレイメージ攻撃および内部ノード衝突 (Second Preimage Attack)**
  - *脅威*: 異なるツリー構造や異なるメッセージ長で同一のハッシュ値が算出され、悪意ある中間ノードがリーフとして偽装される。
  - *対策*: RFC 6962 形式のドメイン分離バイトを導入。リーフノード計算時は `SHA256(0x00 || data)`、内部ノード計算時は `SHA256(0x01 || left || right)` を強制し、階層間の衝突を数学的に排除。
- **T-134-02: パストラバーサルおよびシンボリックリンク誘導 (Path Traversal / Symlink Attack)**
  - *脅威*: 悪意あるシンボリックリンクが `outputs/raw_data/` 配下に配置され、リポジトリ外部の機密ファイル（`/etc/passwd` 等）がツリーに巻き込まれてハッシュが漏洩する。
  - *対策*: ディレクトリ走査時にシンボリックリンクを追跡せずスキップし、正規化された相対パス（`os.path.relpath`）のみをキーとして採用。
- **T-134-03: マニフェストファイル改ざん・事後すり替え (Manifest Tampering)**
  - *脅威*: 攻撃者がファイルを改ざんした後、`manifest.json` の Merkle Root 自体も再計算して上書きする。
  - *対策*: マニフェストに生成時刻、ファイル総数、Git コミットハッシュを記録し、改ざん検知 CLI（`python -m security.fim --verify`）で履歴照合を可能にする。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/security/merkle_tree.py` (Pure Python Merkle Tree、ドメイン分離、Proof 生成・検証エンジン)
- [x] `src/security/fim.py` (FIM ディレクトリ走査、マニフェスト出力、改ざん特定 CLI)
- [x] `src/security/__init__.py` (FIM および MerkleTree のエクスポート)
- [x] `tests/security/test_merkle_tree.py` (ハッシュツリー、Merkle Proof、ビット反転検出、シンボリックリンク除外テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/134-implement-merkle-tree-file-integrity-monitoring`

1. **ステップ 1: 暗号論的 Merkle Tree の実装 (`src/security/merkle_tree.py`)**:
   - `MerkleNode` および `MerkleTree` クラスを実装。
   - リーフハッシュ: `hashlib.sha256(b"\x00" + data).hexdigest()`.
   - 内部ノードハッシュ: `hashlib.sha256(b"\x01" + left_bytes + right_bytes).hexdigest()`.
   - 奇数個ノード時のハンドリング: 末尾ノードの複製（Duplicate）による完全二分木化。
   - `get_proof(index: int) -> List[Tuple[str, str]]`: 指定リーフの監査パス（隣接ハッシュと "left"/"right" 方向）を生成。
   - `verify_proof(leaf_hash: str, proof: List[Tuple[str, str]], root_hash: str) -> bool`: 監査パスを再計算してルートと照合。
2. **ステップ 2: FIM ディレクトリ監視エンジンの実装 (`src/security/fim.py`)**:
   - `FileIntegrityMonitor` クラスを実装。
   - `build_manifest(target_dir: str) -> Dict[str, Any]`:
     - ディレクトリ配下の全ファイルを再帰走査し、相対パスで昇順ソート。
     - 各ファイルの SHA-256 を計算してリーフとし、Merkle Tree を構築。
     - `manifest.json`（`merkle_root`, `leaf_count`, `timestamp`, `files`）をディレクトリ直下に出力。
    - `verify_manifest(target_dir: str) -> Tuple[bool, List[str]]`:
      - 現在のファイル群から Merkle Root を再計算し、マニフェストと照合。不一致の場合、変更・追加・削除・破損したファイル名を特定して返却。
3. **ステップ 3: CLI インターフェースの追加**:
   - `python -m security.fim --scan <dir>`: マニフェストの生成・更新。
   - `python -m security.fim --verify <dir>`: 完全性検証の実行（破損箇所の即時表示、exit code 0/1）。
4. **ステップ 4: テストスイートと品質検証**:
   - `tests/security/test_merkle_tree.py` で、1 バイトのファイル改ざん、ファイルの不正追加・削除に対する検知、および Proof の正当性をテスト。
   - `make format`, `make static_analysis` (Xenon Rank A, Mypy Strict), `pytest` 100% PASS を達成。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 外部依存なし（`hashlib` のみ）で RFC 6962 準拠のドメイン分離 Merkle Tree が正常に構築されること
- [x] ディレクトリ内のファイルが 1 バイトでも改ざん・破損された場合、`verify_manifest()` が即座に検知し、該当ファイルを特定できること
- [x] 任意ファイルの監査パス（Merkle Proof）が $O(\log N)$ ステップでルートハッシュと一致検証できること
- [x] シンボリックリンクやトラバーサルパスが安全にスキップされ、セキュリティ境界が維持されること
- [x] 全品質ゲート（Xenon Rank A, Flake8 0 errors, Mypy Strict 0 errors, pytest 100% PASS）を満たすこと
