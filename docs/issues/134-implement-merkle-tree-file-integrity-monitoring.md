---
ID: 134
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Merkle Tree（暗号論的ハッシュ木）駆動の原本・メタデータ改ざん検知（FIM: File Integrity Monitoring）基盤の実装 (ID: 134)

## 1. 概要 / Summary
ダウンロードした原本 PDF、テキスト中間体、Google OKF 形式の要約ファイル、および STIX 知識グラフ JSON について、外部からの意図せぬ改ざんやストレージ障害によるビット破損を検知するファイル整合性監視（File Integrity Monitoring: FIM）機構を `hashlib` のみで実装する。
全ドキュメントの SHA-256 ダイジェストをリーフノードとし、メモリ上で暗号論的ハッシュ木（Merkle Tree）を構築して Merkle Root ハッシュを日次バッチ（`outputs/raw_data/YYYY-MM-DD/manifest.json`）に記録し、単一ルートハッシュの照合により $O(\log N)$ で全件の完全性を検証可能にする。

---

## 2. トレーサビリティ / Traceability
- [DSN-05: データベースエンジンアーキテクチャ](../../docs/designs/DSN-05-database_engine_architecture.md)
- [src/security/](../../src/security/)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/security/merkle_tree.py`
- [ ] `src/security/fim.py`
- [ ] `src/pipeline/backfill.py`
- [ ] `tests/security/test_merkle_tree.py`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/134-implement-merkle-tree-file-integrity-monitoring`
1. Pure-Python Merkle Tree クラスの実装（リーフ追加、ペアハッシュ計算、ルート算出、Merkle Proof 生成）。
2. `outputs/raw_data/` 配下のファイルスキャンとマニフェスト出力。
3. `verify_integrity()` CLI / API による $O(\log N)$ 改ざん・ビット反転箇所の特定。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 1ファイルでも改ざん・破損された場合に Merkle Proof で即座に特定できること
- [ ] 外部依存なしで高速に Merkle Root が算出されること
- [ ] 全品質ゲート（Xenon Rank A, Flake8, Mypy Strict, pytest）を 100% パスすること
