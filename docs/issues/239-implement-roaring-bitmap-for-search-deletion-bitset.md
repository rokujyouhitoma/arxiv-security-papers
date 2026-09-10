---
ID: 239
種別: Feature
優先度: High
ステータス: Open (New)
担当エージェント: Software Development (SWD) / Systems Architect / Software Quality Assurance Specialist
---

# [FEAT/SEARCH] Roaring Bitmap データ構造の Pure-Python 実装と DeletedDocsBitset 削除フラグ管理の省メモリ・高速化 (ID: 239)

## 1. 概要 / Summary

本リポジトリの分散検索エンジン `src/search/` では、検索クエリ実行時に削除済み・論理無効化された論文文書を除外するため、削除ビットセット（`DeletedDocsBitset` または `Set[int]`）を使用している。

現在、この削除フラグ追跡は標準の Python `set[int]` で実装されている。しかしながら、論文データが 1 万〜数万件規模に拡大するにつれ、以下の技術的課題が生じる：

1. **メモリオーバーヘッドの増大**:
   Python の `set` はハッシュテーブル構造（エントリあたり数十バイト）であるため、万単位の doc_id を保持する際に大きなメモリを浪費する。
2. **集合演算（AND/OR/ANDNOT）の計算コスト**:
   転置インデックス（Postings List）との交差判定（削除ドキュメントのフィルタリング）において、Python オブジェクトのイテレーションとハッシュ参照が発生し、検索レイテンシのボトルネックとなり得る。

本タスクでは、Apache Lucene や ClickHouse 等で業界標準として採用されている **Roaring Bitmap（32-bit Pure-Python ゼロ外部依存）** を独自実装し、`src/search/core/index/` の削除ドキュメント管理および転置インデックス演算に統合する。

---

## 2. トレーサビリティ / Traceability

- **設計書**: [`docs/designs/DSN-04-search_engine_architecture.md`](file:///workspace/arxiv-security-papers/docs/designs/DSN-04-search_engine_architecture.md)
- **論文 / アルゴリズム参照**:
  - Lemire et al., "Consistently faster and smaller compressed bitmaps with Roaring", Software: Practice and Experience (2016).
  - 16-bit チャンク分割、基数に応じた動的コンテナ選択（ArrayContainer / BitmapContainer / RunContainer）。
- **規約**: ゼロ外部依存（Pure-Python 3.14）、Xenon Grade A (CC <= 5), `mypy --strict`。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/search/core/index/roaring_bitmap.py`](file:///workspace/arxiv-security-papers/src/search/core/index/roaring_bitmap.py) (新規):
  - 32-bit Roaring Bitmap のコア実装
  - `ArrayContainer`（カーディナリティ < 4096）
  - `BitmapContainer`（カーディナリティ >= 4096、65536 bit = 8 KB 固定長バイト列）
  - `RunContainer`（連続区間ランレングス圧縮）
  - ビット論理演算: `&` (AND), `|` (OR), `-` (ANDNOT), `^` (XOR) の高速インプレースおよび新規生成
- [ ] [`src/search/core/index/postings.py`](file:///workspace/arxiv-security-papers/src/search/core/index/postings.py) (または削除管理モジュール):
  - `DeletedDocsBitset` のストレージバックエンドを Roaring Bitmap へ移行
- [ ] [`tests/search/test_roaring_bitmap.py`](file:///workspace/arxiv-security-papers/tests/search/test_roaring_bitmap.py) (新規):
  - 疎データ、密データ、連続区間データにおけるコンテナ自動昇格・降格検証
  - Python `set` との完全な結果一致性テスト
  - メモリ使用量とビット演算速度のベンチマーク

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/239-implement-roaring-bitmap-for-search-deletion-bitset`

1. **32-bit Roaring Bitmap アーキテクチャ**:
   - 32-bit 整数 $x$ を上位 16-bit（チャンクキー）と下位 16-bit（値 $0 \le v < 65536$）に分割。
   - 上位 16-bit をキーとするチャンクマップを保持。
   - 下位 16-bit を格納するコンテナは要素数に応じて動的に昇格：
     - **ArrayContainer**: 要素数 4,096 未満（ソート済み `array('H')`）。
     - **BitmapContainer**: 要素数 4,096 以上（`bytearray(8192)` によるビットマスク）。
     - **RunContainer**: 連続した整数区間が多数存在する場合（`[(start, length), ...]`）。
2. **高速集合演算**:
   - ビット単位の論理演算（C拡張に頼らず Python のビット演算 `int.from_bytes` やスライスを活用）を最適化。
3. **検索コアへの結合**:
   - 転置インデックス検索時のフィルタリング処理を `postings_list.and_not(deleted_bitmap)` として適用。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `RoaringBitmap` が Pure-Python かつゼロ外部依存で実装され、基本操作（`add`, `remove`, `contains`, `len`）および集合演算（`&`, `|`, `-`）が正しく動作すること。
- [ ] Python 標準の `set` と比較してメモリ使用量が大幅に削減（密データで 1/10 以下）されること。
- [ ] 検索エンジンの削除ドキュメント除外処理が Roaring Bitmap 経由で正常に機能すること。
- [ ] 全テストが PASS し、Xenon Rank A (CC <= 5) および `mypy --strict` 0 エラーであること。
