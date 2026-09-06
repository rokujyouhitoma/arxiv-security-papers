---
ID: 198
種別: Feature
優先度: High
ステータス: Closed
Created At: 2026-09-06T21:56:02+09:00
Polished At: 2026-09-06T22:20:00+09:00
Closed At: 2026-09-06T22:22:00+09:00
---

# [FEAT/ENH] Pure-Python PDF エンジンにおける図表・アーキテクチャ図の自動抽出および OKF 埋め込み基盤の実装 (ID: 198)

## 1. 概要 / Summary

ISO 32000 準拠の内製 Pure-Python PDF エンジン (`src/pdf_engine/`) を拡張し、セキュリティ論文内の攻撃シーケンス図、システム構成図（アーキテクチャ図）、ネットワークトポロジー図、評価結果グラフ等の画像・図表ブロックを自動検出・抽出する機能を実装する。

外部バイナリ（Poppler / `pdfimages` / ImageMagick）やサードパーティ C 拡張ライブラリ（Pillow / OpenCV 等）に一切依存せず、**Python 3.14+ 標準ライブラリ（`struct`, `zlib`, `io`, `os`, `re`）のみを用いた Pure-Python XObject Image パーサーおよび PNG/JPEG シリアライザー** を構築する。

抽出された図表ファイルは `outputs/raw_data/YYYY-MM-DD/<paper_id>/figures/` 配下に構造化保存され、Google OKF v0.2 Markdown および Web 統合コンソール上の論文プレビューモーダルへ自動埋め込みを行い、視覚的アーキテクチャ知見の利便性を飛躍的に高める。

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-13 ISO 32000 準拠 Pure-Python PDF テキスト抽出エンジン包括的アーキテクチャ設計仕様書](../designs/DSN-13-pure_python_pdf_text_extractor.md) (Clause 7.8.2, 8.9 XObjects & Images)
- 設計書: [DSN-03 パイプライン・アーキテクチャ包括的設計仕様書](../designs/DSN-03-pipeline_architecture.md)
- 設計書: [DSN-21 エンタープライズ統合デザインシステム ＆ クラウドコンソール UI 包括設計書](../designs/DSN-21-enterprise_design_system_and_cloud_console_ui.md)
- 国際規格: ISO 32000-1:2008 Clause 8.9 (Images) & Clause 7.4.4 (FlateDecode)
- 画像標準: RFC 2083 (Portable Network Graphics Specification v1.0) / ITU-T T.81 (JPEG)

---

## 3. 外部データ入力に対する脅威モデリングと複数のSC（Security Controls）多層防御体系

外部ソース（arXiv 等）から取得される PDF ファイルおよび画像ストリームは、**完全に信用できない任意の外部データ（Untrusted Input）** である。
悪意を持って細工された PDF による DoS、メモリ破壊、パストラバーサル、スクリプト実行（XSS/Polyglot）等の攻撃ベクトルを遮断するため、**複数の SC (Security Controls: 情報セキュリティスペシャリスト視点)** による包括的な多層防御体系を構築する。

### 複数のSC多層防御マトリクス (Defense-in-Depth Matrix)

| SC 番号 | 防御ドメイン | 脅威・CWE | 防御仕様・実装対策 (Defense Implementation) | 実装コンポーネント |
|---|---|---|---|---|
| **SC-1** | **メモリ・解凍 DoS 防御** | CWE-409 (Decompression Bomb), CWE-400 (Uncontrolled Resource Consumption) | 1. `MAX_DECOMPRESSED_BYTES = 30MB` の解凍後サイズ上限制限。<br>2. **解凍前ピクセル試算チェック**: `width * height * bpp > MAX_DECOMPRESSED_BYTES` の場合、解凍を試行せず事前遮断。<br>3. **累積容量ガード**: 論文あたりの総抽出容量上限 (`MAX_CUMULATIVE_FIGURE_BYTES = 50MB`) 到達時の抽出即時終了。 | `src/pdf_engine/image_extractor.py`<br>(`_extract_flate_image`, `extract_and_save`) |
| **SC-2** | **画像寸法・ピクセルフラッド防御** | CWE-190 (Integer Overflow), CWE-789 (Memory Allocation with Excessive Size) | 1. **最小境界値チェック**: `width >= 150`, `height >= 100` (数式記号・微小アイコン除外)。<br>2. **最大境界値チェック**: `width <= 4096`, `height <= 4096`。 <br>3. **総ピクセル数上限**: `width * height <= 16,000,000` (16メガピクセル上限)。<br>4. **型・符号検証**: 負数・ゼロ・非整数値の完全除外 (`isinstance(int) and x > 0`)。 | `src/pdf_engine/image_extractor.py`<br>(`_is_valid_figure_dimension`, `_is_valid_dimension_bounds`) |
| **SC-3** | **パストラバーサル・ファイル破壊防御** | CWE-22 (Path Traversal), CWE-73 (External Control of File Name or Path) | 1. **XObject 名のサニタイズ**: `re.sub(r"[^a-zA-Z0-9_-]+", "_", clean).strip("_")` により `..` や `/` や `\x00` を完全無効化。<br>2. **キャノニカルパス検証**: `os.path.realpath(file_path).startswith(os.path.realpath(output_dir))` による出力先ディレクトリ逸脱の事前遮断。<br>3. **拡張子のホワイトリスト強制**: `.jpg`, `.png` 以外は一切保存不可。 | `src/pdf_engine/image_extractor.py`<br>(`_sanitize_xobject_name`, `_save_figure`) |
| **SC-4** | **実行可能コード・Polyglot / MIME スニッフィング防御** | CWE-434 (Unrestricted Dangerous Type), CWE-79 (Cross-Site Scripting) | 1. **Pure-Python 無害化 PNG 再構成**: 外部の危険な ancillary チャンク（`iTXt`, `tEXt` 等の悪意の埋め込み）を完全排除し、`IHDR`, `IDAT`, `IEND` のみで無害化生成。<br>2. **JPEG Polyglot ペイロード検知**: JPEG ストリーム先頭 2KB 内の HTML/JS/PHP タグ（`<script`, `<svg`, `javascript:`, `<?php`, `onload=` 等）をスキャン・検知時に即時破棄。<br>3. **Web Gateway 配信隔離**: `Content-Type: image/jpeg` または `image/png`、`X-Content-Type-Options: nosniff`、`Content-Security-Policy: default-src 'none'`、`Cache-Control: public, max-age=86400` を強制付与。 | `src/pdf_engine/image_extractor.py`<br>(`_has_malicious_script_tags`, `_build_png_bytes`)<br>`src/web/gateway/handlers.py`<br>(`handle_paper_figure`) |
| **SC-5** | **計算量爆弾・リソース枯渇防御** | CWE-400 (Resource Exhaustion / ReDoS) | 1. **ページあたり抽出上限**: `max_per_page = 5`。<br>2. **論文全体抽出上限**: `max_total_figures = 10`。<br>3. **XObject 走査上限**: 1ページあたり最大 50 オブジェクト (`MAX_PAGE_XOBJECT_SCAN = 50`) で走査を打ち切り、CPU 枯渇を防止。 | `src/pdf_engine/image_extractor.py`<br>(`extract_figures_from_page`, `extract_and_save`) |
| **SC-6** | **不正データ構造・循環参照防御** | CWE-674 (Uncontrolled Recursion) | 1. **間接参照ループ検出**: `_visited_refs: Set[Tuple[int, int]]` により、PDF 内の循環 IndirectRef (`10 0 R -> 10 0 R`) による無限再帰・スタックオーバーフローを確実に防止。 | `src/pdf_engine/image_extractor.py`<br>(`_resolve_xobject_dict`, `_resolve_stream`) |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/pdf_engine/image_extractor.py](../../src/pdf_engine/image_extractor.py) (Pure-Python XObject Image 抽出 & SC-1〜SC-6 多層防御機構)
- [x] [src/pdf_engine/extractor.py](../../src/pdf_engine/extractor.py) (高水準 API `PurePdfTextExtractor.extract_figures()` および `extract_text_and_figures()`)
- [x] [src/pipeline/transformer/okf_serializer.py](../../src/pipeline/transformer/okf_serializer.py) (OKF Markdown への図表画像相対リンク動的埋め込み)
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (`/api/paper/<clean_id>/figures/<fig_id>` 画像配信 & CSP/nosniff 配信隔離)
- [x] [tests/pdf_engine/test_image_extractor.py](../../tests/pdf_engine/test_image_extractor.py) (SC-1〜SC-6 セキュリティ防御検証ユニットテスト)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳ステータス更新)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/198-extract-figures-and-diagrams-in-pure-python-pdf-engine`

### Step 1: `src/pdf_engine/image_extractor.py` の実装と SC 多層防御
- `PdfImageExtractor` クラス:
  - `XRefResolver` 間接参照の解決時に SC-6 (循環参照ガード) を適用。
  - SC-2: `_is_valid_figure_dimension` による寸法・総画素数上限検証。
  - SC-1: `_extract_flate_image` による解凍前ピクセル試算および解凍後 30MB 上限チェック。
  - SC-4: `_build_png_bytes` による Pure-Python 最小チャンク構成（IHDR, IDAT, IEND）無害化 PNG 生成。
  - SC-4: `_extract_dct_image` による JPEG SOI 検証および HTML/JS Polyglot タグ遮断。
  - SC-3: `_sanitize_xobject_name` および `_save_figure` での realpath 境界検証。
  - SC-5: ページ走査上限 (50) および抽出上限 (5/ページ, 10/論文, 50MB/論文)。

### Step 2: `PurePdfTextExtractor` への統合
- `src/pdf_engine/extractor.py` に `extract_figures()` および `extract_text_and_figures()` を追加。
- 外部入力 PDF を安全にパースし、テキスト抽出と図表抽出を単一パスまたは個別パスで実行可能化。

### Step 3: `okf_serializer.py` への OKF Markdown 相対リンク埋め込み
- `build_okf_from_raw()` において抽出図表が存在する場合、末尾に「主要アーキテクチャ図・システム構成図 (Key Figures & Architecture Diagrams)」セクションを自動生成。

### Step 4: Web API Gateway 画像配信 & セキュリティ隔離
- `src/web/gateway/handlers.py`:
  - `GET /api/paper/<clean_id>/figures/<fig_id>` エンドポイント。
  - `is_safe_workspace_path` によるワークスペース外読み出し防止。
  - レスポンスヘッダーに `Content-Type`, `X-Content-Type-Options: nosniff`, `Content-Security-Policy: default-src 'none'` を付与。

### Step 5: セキュリティ検証テストスイートの実装
- `tests/pdf_engine/test_image_extractor.py`:
  - SC-1: Decompression Bomb 遮断テスト。
  - SC-2: 不正型・極大ピクセルフラッド遮断テスト。
  - SC-3: パストラバーサル無害化テスト。
  - SC-4: JPEG Polyglot スクリプトタグ検知・遮断テスト、PNG チャンク整合性テスト。
  - SC-6: 循環参照 IndirectRef 無限ループ防止テスト。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 外部バイナリ（Poppler/pdfimages等）および外部 C 拡張に依存せず、Pure-Python 標準ライブラリのみで JPEG および PNG 画像が抽出できること。
- [x] 外部データ（Untrusted Input）に対する複数のSC多層防御（SC-1〜SC-6）が設計・実装・単体テストで検証されていること。
- [x] 抽出された図表が `outputs/raw_data/YYYY-MM-DD/<paper_id>/figures/` 配下に保存され、メタデータ JSON が生成されること。
- [x] OKF v0.2 Markdown に図表の相対リンクが正しく埋め込まれ、リンク切れが 0 件であること。
- [x] Web Gateway API `/api/paper/<clean_id>/figures/<fig_id>` から画像が安全に取得でき、CSP/nosniff 隔離ヘッダーが付与されていること。
- [x] 単体テスト（`tests/pdf_engine/test_image_extractor.py`）が全件 PASS すること。
- [x] `make check_format` および `make static_analysis` (mypy strict, Xenon Grade A $\le 5$) がエラー 0 件であること。
