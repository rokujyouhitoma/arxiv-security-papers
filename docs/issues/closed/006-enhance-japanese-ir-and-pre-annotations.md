---
ID: 006
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] 日本語 IR 検索エンジンの高度化 ＆ 自動特徴語抽出・事前注釈 (Pre-Annotation) 機能の導入 (ID: 006)

## 概要
ユーザーからの要請（「日本語検索をよりよくしたい IR よりよくしてください。また、事前に注釈付けをすることによって、検索の質が上がるのであれば、事前に注釈をつけてほしい。自動で、特徴語を抽出するなどが考えられる。」）に基づき、日本語セキュリティ用語のシノニム辞書の飛躍的拡張、自動特徴語抽出（RAKE / セキュリティ概念自動注釈）、日本語 N-gram トークナイズ、および事前注釈（Pre-Annotation）メタデータ付き Vector DB スコアリングエンジンの導入を行う。

## 対象ファイル
- `src/synonym_expander.py`: セキュリティ専門用語ドメインシノニム辞書の拡張 (Web, AI/LLM, System/IoT, Quantum, SOC/Incident)
- `src/vector_engine.py`: 日本語 N-gram トークナイズ、自動特徴語抽出 (`extract_feature_keywords`)、事前注釈 (`annotated_keywords`) 保存および高加重スコアリング (4.0) の実装
- `src/arxiv_okf_fetcher.py`: OKF 変換時の自動メタデータ注釈統合
- `docs/designs/DSN-01-high_level_design.md` & `DSN-02-low_level_design.md`: IR 事前注釈アーキテクチャの文書反映
- `tests/test_vector_engine.py`: 日本語 IR 検索および事前注釈抽出の単体テスト追加

## DoD (Definition of Done)
1. 日本語セキュリティクエリ（「マルウェア解析」「LLM脱獄」「ファジング」「サイドチャネル」等）の適合率・再現率が向上すること。
2. 論文自動変換およびインデックス生成時に特徴語が抽出され、事前注釈メタデータとして `outputs/vector_db/index.json` に保存されること。
3. `make build_js`, `make py_compile`, `make test` が 100% PASS すること。
