---
ID: 198
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Pure-Python PDF エンジンにおける図表・アーキテクチャ図の自動抽出および OKF 埋め込み基盤の実装 (ID: 198)

## 1. 概要 / Summary

ISO 32000 準拠の内製 Pure-Python PDF エンジン (`src/extractor/pdf/`) を拡張し、セキュリティ論文内の攻撃シーケンス図、システム構成図（アーキテクチャ図）、評価グラフ等の画像・図表ブロックを自動検出・抽出する機能を実装する。
抽出された図表ファイル（PNG/JPEG）を `outputs/raw_data/` 配下に構造化保存し、Google OKF v0.2 Markdown および Web コンソール上のプレビューモーダルへ自動埋め込みを行い、視覚的知見の利便性を飛躍的に高める。

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-13 ISO 32000 準拠 Pure-Python PDF テキスト抽出エンジン包括的アーキテクチャ設計仕様書](../designs/DSN-13-pure_python_pdf_text_extractor.md)
- 設計書: [DSN-03 パイプライン・アーキテクチャ包括的設計仕様書](../designs/DSN-03-pipeline_architecture.md)
- 設計書: [DSN-21 エンタープライズ統合デザインシステム ＆ クラウドコンソール UI 包括設計書](../designs/DSN-21-enterprise_design_system_and_cloud_console_ui.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/extractor/pdf/image_extractor.py](../../src/extractor/pdf/image_extractor.py) (新規: XObject / Inline Image ストリーム解析と画像抽出)
- [ ] [src/extractor/pdf/pipeline.py](../../src/extractor/pdf/pipeline.py) (PDF 抽出パイプラインへの画像抽出統合)
- [ ] [src/pipeline/converter/okf_converter.py](../../src/pipeline/converter/okf_converter.py) (OKF Markdown への図表画像相対リンク埋め込み)
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (静的画像配信エンドポイント `/api/papers/{id}/figures/{fig_id}`)
- [ ] [site/index.html](../../site/index.html) (論文モーダルプレビューにおける図表カルーセル・サムネイル表示)
- [ ] [tests/extractor/test_pdf_image_extractor.py](../../tests/extractor/test_pdf_image_extractor.py) (新規ユニットテスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/198-extract-figures-and-diagrams-in-pure-python-pdf-engine`

1. **Pure-Python XObject 画像パーサーの実装**:
   - `src/extractor/pdf/image_extractor.py` を実装し、Poppler / pdftotext 等の外部バイナリに依存せず、PDF ストリーム内の `/Subtype /Image` オブジェクト（DCTDecode / FlateDecode / CCITTFaxDecode）をピュア Python でパース・抽出。
   - 小さな装飾アイコンや数式記号を除外する最小解像度・アスペクト比フィルタリングロジックを実装。
2. **Raw データ永続化と OKF 連携**:
   - 抽出した画像を `outputs/raw_data/YYYY-MM-DD/<paper_id>/figures/fig_XX.png` に保存。
   - `okf_converter.py` において、OKF ドキュメント本文末尾に `## 主要アーキテクチャ図・システム構成図` セクションを追加し、相対パスで画像を配置。
3. **Web コンソール連携**:
   - Web コンソール（`site/index.html`）の論文詳細モーダルに、抽出された図表をスライド・プレビューできるギャラリーコンポーネントを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 外部バイナリ（Poppler/pdfimages等）に一切依存せず、Pure-Python のみで PDF 内の主要図表（PNG/JPEG）が抽出できること。
- [ ] 抽出された図表が `outputs/raw_data/YYYY-MM-DD/<paper_id>/figures/` 配下に整理して保存されること。
- [ ] OKF v0.2 Markdown に図表の相対リンクが明記され、マークダウンプレビューで正しく表示されること。
- [ ] Web コンソールの論文プレビューモーダルで図表画像が閲覧可能であること。
- [ ] 単体テストおよび品質ゲート（`mypy --strict`, Xenon Grade A）が 100% PASS すること。
