---
ID: 240
種別: Feature
優先度: Medium
ステータス: Open (New)
担当エージェント: Information Security Specialist / Software Development (SWD) / IT Specialist (NLP & Info Retrieval)
---

# [FEAT/CTI] Radix Trie (Prefix Tree) による CTI タクソノミー（CWE / ATT&CK / CVE）高速前方一致検索とオートコンプリート基盤の実装 (ID: 240)

## 1. 概要 / Summary

本リポジトリでは、サイバー脅威インテリジェンス（CTI）および論文オントロジーの構造化データとして、多数の識別子・階層分類体系を管理している：
- **MITRE ATT&CK**: テクニック ID（例: `T1059`, `T1059.001`, `T1059.003`, `TA0002`）
- **MITRE CWE**: 弱点分類 ID（例: `CWE-79`, `CWE-89`, `CWE-20`, `CWE-119`）
- **NVD / CISA KEV**: 脆弱性識別子（例: `CVE-2024-XXXX`, `CVE-2023-XXXX`）
- **セキュリティドメインタグ**: 暗号、Web、ハードウェア等の階層キーワード

現在、`src/domain/security/taxonomy/` やオントロジー検索、Web ゲートウェイのサジェスト処理では、辞書やリストの全件ループ＋`.startswith()` または正規表現による線形走査を行っている。
タクソノミー定義の増加に伴い、以下の課題が生じている：

1. **前方一致検索・サジェストの線形走査オーバーヘッド**:
   入力文字が打鍵されるたびに全エントリを線形走査するため、インタラクティブなオートコンプリートにおいて無駄な CPU サイクルを消費する。
2. **階層的サブテクニック・親弱点の探索コスト**:
   `T1059` 配下のサブテクニック群や `CWE-707` 配下のインジェクション派生群を一括取得するプレフィックス範囲クエリが最適化されていない。

本タスクでは、メモリ効率の高い **Radix Trie（基数木 / パトリシア木）** を Pure-Python ゼロ外部依存で実装し、タクソノミー検索および Web UI / CLI オートコンプリートに統合する。

---

## 2. トレーサビリティ / Traceability

- **設計書**: [`docs/designs/DSN-01-cyber_security_ontology_and_graph_engine.md`](file:///workspace/arxiv-security-papers/docs/designs/DSN-01-cyber_security_ontology_and_graph_engine.md)
- **関連タクソノミー**:
  - `src/domain/security/taxonomy/cwe.py`
  - `src/domain/security/taxonomy/mitre.py`
  - `src/domain/security/taxonomy/stride.py`
- **規約**: ゼロ外部依存（Standard Library Only）、Xenon Grade A (CC <= 5), `mypy --strict`。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/domain/security/taxonomy/radix_trie.py`](file:///workspace/arxiv-security-papers/src/domain/security/taxonomy/radix_trie.py) (新規):
  - Radix Trie (基数木) コアエンジンの実装
  - ノード共有・エッジ圧縮（パス圧縮）
  - API: `insert(key, value)`, `search(key)`, `find_by_prefix(prefix, limit)`, `longest_prefix(key)`
- [ ] [`src/domain/security/taxonomy/mitre.py`](file:///workspace/arxiv-security-papers/src/domain/security/taxonomy/mitre.py):
  - ATT&CK テクニック ID インデックスに Trie をバインド
- [ ] [`src/domain/security/taxonomy/cwe.py`](file:///workspace/arxiv-security-papers/src/domain/security/taxonomy/cwe.py):
  - CWE ID および弱点名称インデックスに Trie をバインド
- [ ] [`tests/domain/security/test_radix_trie.py`](file:///workspace/arxiv-security-papers/tests/domain/security/test_radix_trie.py) (新規):
  - 挿入、完全一致、プレフィックス検索、境界値テスト
  - ATT&CK / CWE 実データを用いた検索速度およびサジェスト精度検証

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/240-implement-radix-trie-for-cti-taxonomy-prefix-search`

1. **Radix Trie アーキテクチャ**:
   - 通常の Trie（1文字1ノード）ではなく、共通接頭辞を 1 本のエッジに圧縮する Radix Tree（基数木）を採用し、メモリフットプリントを最小化。
   - 各ノードに `is_terminal` フラグと関連メタデータ（ペイロード）を保持。
2. **機能仕様**:
   - `find_by_prefix(prefix, limit=10)`: 入力されたプレフィックスに一致するノードまで $O(K)$ で降下し、そこから深さ優先探索（DFS）で上位 $N$ 件のサジェストを高速収集。
   - `longest_prefix(text)`: テキスト先頭に最も長く合致するタクソノミー ID（例: `T1059.001`）をマッチング。
3. **タクソノミー統合**:
   - モジュールロード時に静的インデックスをビルドし、Web API（`/api/taxonomy/suggest` 等）や CLI の高速補完に利用可能とする。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `RadixTrie` が Pure-Python ゼロ外部依存で実装され、単体テストで挿入・検索・プレフィックスサジェストが完全に検証されること。
- [ ] `T1059.` や `CWE-7` などのプレフィックス検索が $O(K)$ で動作し、正しいサブテクニック・派生弱点一覧が即座に返却されること。
- [ ] `mitre.py` / `cwe.py` への統合が完了し、既存のタクソノミー関数との後方互換性が維持されること。
- [ ] Xenon Rank A (CC <= 5) および `mypy --strict` 0 エラーを達成すること。
