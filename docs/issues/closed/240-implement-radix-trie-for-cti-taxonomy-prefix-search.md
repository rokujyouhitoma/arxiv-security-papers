---
ID: 240
種別: Feature
優先度: High
ステータス: Closed (2026-09-11)
担当エージェント: Information Security Specialist / Software Development (SWD) / IT Specialist (NLP & Info Retrieval)
---

# [FEAT/CORE] Radix Trie (Prefix Tree) の共通コア実装と CTI タクソノミー（CWE / ATT&CK / CVE）高速前方一致検索・オートコンプリート基盤の確立 (ID: 240)

## 1. 概要 / Summary

本リポジトリでは、サイバー脅威インテリジェンス（CTI）および論文オントロジーの構造化データとして、多数の識別子・階層分類体系を管理している：
- **MITRE ATT&CK**: テクニック ID（例: `T1059`, `T1059.001`, `T1059.003`, `TA0002`）
- **MITRE CWE**: 弱点分類 ID（例: `CWE-79`, `CWE-89`, `CWE-20`, `CWE-119`）
- **NVD / CISA KEV**: 脆弱性識別子（例: `CVE-2024-XXXX`, `CVE-2023-XXXX`）
- **セキュリティドメインタグ**: 暗号、Web、ハードウェア等の階層キーワード

現在、`src/domain/security/taxonomy/` やオントロジー検索、Web ゲートウェイのサジェスト処理では、辞書やリストの全件走査＋`.startswith()` または正規表現による線形走査を行っている。
タクソノミー定義の増加に伴い、以下の課題が生じている：

1. **前方一致検索・サジェストの線形走査オーバーヘッド**:
   入力文字が打鍵されるたびに全エントリを線形走査するため、インタラクティブなオートコンプリートにおいて無駄な CPU サイクルを消費する。
2. **階層的サブテクニック・親弱点の探索コスト**:
   `T1059` 配下のサブテクニック群や `CWE-707` 配下のインジェクション派生群を一括取得するプレフィックス範囲クエリが最適化されていない。

本タスクでは、Roaring Bitmap や Bloom Filter と同様に、メモリ効率の高い **Radix Trie（基数木 / パトリシア木）** を共通コア基盤 [`src/core/structures/radix_trie.py`](../../src/core/structures/radix_trie.py) にゼロ外部依存で実装し、CTI タクソノミー検索および Web UI / CLI オートコンプリートに統合する。

---

## 2. トレーサビリティ / Traceability

- **設計書**:
  - [`docs/designs/DSN-01-cyber_security_ontology_and_graph_engine.md`](../designs/DSN-01-cyber_security_ontology_and_graph_engine.md) (CTI Taxonomy & Prefix Index)
  - [`docs/designs/DSN-04-search_engine_architecture.md`](../designs/DSN-04-search_engine_architecture.md) (Query Autocomplete & Suggest)
- **関連タクソノミー**:
  - `src/domain/security/taxonomy/cwe.py`
  - `src/domain/security/taxonomy/mitre.py`
  - `src/domain/security/taxonomy/stride.py`
- **学術・技術参照**:
  - Morrison, D. R. (1968). "PATRICIA—Practical Algorithm To Retrieve Information Coded in Alphanumeric", *Journal of the ACM*.
  - Knuth, D. E. (1998). *The Art of Computer Programming, Volume 3: Sorting and Searching* (Sec. 6.3).
- **規約**:
  - ゼロ外部依存（Standard Library Only）
  - Xenon Rank A (CC <= 4), `mypy --strict` 準拠

---

## 3. 脅威モデルとセキュリティ分析 (STRIDE / Threat Model)

| 脅威カテゴリ (STRIDE) | 潜在リスク | 緩和策・セキュリティ要件 |
| :--- | :--- | :--- |
| **Denial of Service (DoS)** | 悪意ある長大キー（数万文字）の挿入や深いプレフィックス走査によるスタックオーバーフロー・CPU 枯渇攻撃 | キー長の上限ガード（最大 4096 文字）、探索時の深さ上限制限、および DFS 走査時の反復スタック（非再帰）実装によりスタック枯渇を根本防止。サジェスト件数に上限（`limit` デフォルト 20、最大 1000）を強制。 |
| **Tampering** | Trie ノードの参照改竄や分割エッジの不正なポインタ書き換え | ノードカプセル化を徹底し、エッジ分割・マージロジックを単体テストで厳密にアサーション。 |
| **Information Disclosure** | サジェスト結果における非公開タクソノミーや内部ポインタの漏洩 | サジェスト返却時にキー文字列と指定ペイロードのみをコピー返却し、内部ノード構造への直接アクセスを遮断。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/core/structures/radix_trie.py`](../../src/core/structures/radix_trie.py) (新規):
  - `RadixNode[T]`: 圧縮エッジ文字列、1文字分岐辞書、終端フラグ、ペイロード値
  - `RadixTrie[T]`: `insert(key, value)`, `get(key, default)`, `contains(key)`, `find_by_prefix(prefix, limit)`, `longest_prefix(text)`, `delete(key)`, `__len__()`, `clear()`
- [x] [`src/core/structures/__init__.py`](../../src/core/structures/__init__.py):
  - `RadixTrie`, `RadixNode` のエクスポート
- [x] [`src/domain/security/taxonomy/mitre.py`](../../src/domain/security/taxonomy/mitre.py):
  - ATT&CK テクニック ID インデックスに Radix Trie を統合（`search_techniques_by_prefix()`）
- [x] [`src/domain/security/taxonomy/cwe.py`](../../src/domain/security/taxonomy/cwe.py):
  - CWE ID および弱点名称インデックスに Radix Trie を統合（`search_cwe_by_prefix()`）
- [x] [`tests/core/test_radix_trie.py`](../../tests/core/test_radix_trie.py) (新規):
  - 基数木の基本操作、エッジ分割（Branch Split）、ノードマージ（Deletion Merge）、共通接頭辞探索、長大プレフィックス境界値テスト
- [x] [`tests/domain/security/test_cve_kev_spiders.py`](../../tests/domain/security/test_cve_kev_spiders.py):
  - タクソノミー検索の回帰テスト（100% PASS）

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/240-implement-radix-trie-for-cti-taxonomy-prefix-search`

### Step 1: 共通コア `src/core/structures/radix_trie.py` の実装
- **エッジ圧縮アルゴリズム**:
  - キー挿入時、既存エッジとの最長共通接頭辞（Longest Common Prefix: LCP）を計算。
  - 完全一致なら終端フラグを立て値を更新。
  - エッジの途中までしか一致しない場合、共通接頭辞ノードを新設して元ノードと新ノードに 2 分割（Edge Splitting）。
- **プレフィックス探索 (`find_by_prefix`)**:
  - プレフィックスに一致するノードまで $O(K)$ で降下。
  - 発見したサブツリーから非再帰 DFS（スタック）を用いて辞書順または挿入順に上位 `limit` 件を高速収集。
- **最長前方一致 (`longest_prefix`)**:
  - 入力テキスト（例: `T1059.001 (Command and Scripting Interpreter)`）の先頭から最も長くマッチするタクソノミー ID（`T1059.001`）を $O(K)$ で抽出。

### Step 2: CTI タクソノミーへのバインド
- `src/domain/security/taxonomy/mitre.py`:
  - `MitreTaxonomy` またはモジュールロード時に全 ATT&CK テクニック・サブテクニックを `RadixTrie` にインデックス化。
  - `find_by_prefix("T1059")` で全サブテクニック（`T1059.001`, `T1059.003` 等）を即時返却。
- `src/domain/security/taxonomy/cwe.py`:
  - 全 CWE ID（`CWE-79`, `CWE-798` 等）をインデックス化。

### Step 3: 単体テストと品質検証
- `tests/core/test_radix_trie.py` を作成し、基本CRUD、エッジ分割、最長前方一致、大量キー（1万件）性能を検証。
- `make check_format`、Xenon Rank A (CC <= 4)、`mypy --strict src` 0 エラーの完全遵守。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `src/core/structures/radix_trie.py` にゼロ外部依存で `RadixTrie` が実装されていること。
- [x] エッジ圧縮（パトリシア木構造）およびノード分割が正しく機能し、メモリ使用量が素の Trie に比べ半減していること。
- [x] `find_by_prefix` による前方一致サジェストと `longest_prefix` による最長一致トークン抽出が $O(K)$ で動作すること。
- [x] MITRE ATT&CK および CWE タクソノミーからプレフィックス検索が利用可能であること。
- [x] `tests/core/test_radix_trie.py` が新規作成され、100% PASS すること。
- [x] Xenon Rank A (CC <= 4)、`mypy --strict` 0 エラー、フォーマッタ 100% 合格であること。
