---
ID: 125
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Late-Interaction（MaxSim）演算機構およびセキュリティ専門語彙拡張（SPLADE風疎表現）リランカーの実装 (ID: 125)

## 1. 概要 / Summary
セキュリティ文献における専門用語や頭字語（例: PQC, PEP/PDP, ATT&CK T1059）の表記揺らぎを吸収するため、ColBERT 型の Late-Interaction 演算（MaxSim）と疎表現拡張（SPLADE 風アプローチ）を実装する。
クエリトークンとドキュメントトークン間の最大コサイン類似度総和を標準 `math` 内積ループのみで算出し、ドメイン辞書による仮想的重み付きエントリ拡張と組み合わせて高精度なリランキングを実現する。

---

## 2. トレーサビリティ / Traceability
- [DSN-04: 検索エンジン・プラットフォーム](../../docs/designs/DSN-04-search_engine_and_platform.md)
- [src/search/ranking/](../../src/search/ranking/)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/search/ranking/late_interaction.py`
- [ ] `src/search/ranking/splade_expansion.py`
- [ ] `src/search/vector_engine.py`
- [ ] `tests/search/test_late_interaction.py`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/125-implement-late-interaction-maxsim-and-splade-term-expansion`
1. クエリ/ドキュメントのマルチトークン埋め込み生成と MaxSim 行列演算の実装。
2. セキュリティシノニム辞書に基づく疎表現重み付き拡張転置リストの構築。
3. 2段階リランキングパイプラインの統合。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] MaxSim 演算が外部依存なしにサブミリ秒で完了すること
- [ ] 専門用語・頭字語の表記揺らぎに対する検索再現率が向上すること
- [ ] 全品質ゲート（Xenon Rank A, Flake8, Mypy Strict, pytest）を 100% パスすること
