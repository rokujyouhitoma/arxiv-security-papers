---
ID: 204
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] Pure-Python PDF エンジンにおける LZWDecode / CCITTFaxDecode / JBIG2Decode 高度ストリームデコーダ群の統合実装 (ID: 204)

## 1. 概要 / Summary

自作 Pure-Python PDF エンジン（`src/pdf_engine/`）において、ISO 32000-1（PDF 1.7）規格に定められた高度ストリーム圧縮フィルター群：
1. **LZWDecode (Lempel-Ziv-Welch: Clause 7.4.4)**
2. **CCITTFaxDecode (Group 3 / Group 4 2値FAX圧縮: Clause 7.4.5)**
3. **JBIG2Decode (JBIG2 2値画像圧縮: Clause 7.4.7 / ISO 14492)**

の 3 大ストリームデコーダを、**外部 C/Rust バインディング完全ゼロ（Zero External Dependencies / Pure Python）** で統合実装する。

学術論文（arXiv cs.CR）の初期アーカイブ、TIFF 取り込み論文、スキャン図表、および高圧縮ドキュメントに含まれる画像・コンテンツストリームを完全復元可能にする。あわせて、過去に Pegasus（FORCEDENTRY / CVE-2021-30860）等の標的となった JBIG2 セグメント処理に対して、厳格なメモリ境界検証・整数オーバーフロー対策・展開爆弾（Decompression Bomb）防御（SC-1〜SC-7 多層防御）を完備する。

---

## 2. トレーサビリティ / Traceability
- 国際規格: ISO 32000-1:2008 Clause 7.4.4 (LZWDecode Filter)
- 国際規格: ISO 32000-1:2008 Clause 7.4.5 (CCITTFaxDecode Filter / ITU-T Recommendations T.4 and T.6)
- 国際規格: ISO 32000-1:2008 Clause 7.4.7 (JBIG2Decode Filter / ISO/IEC 14492)
- セキュリティ基準: CVE-2021-30860 防御（JBIG2 セグメント境界検証 & 算術バッファ保護）
- 関連 Issue: [Issue 198: Pure-Python PDF エンジンにおける図表・アーキテクチャ図の自動抽出および OKF 埋め込み基盤の実装](closed/198-extract-figures-and-diagrams-in-pure-python-pdf-engine.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

Target Branch: `feat/204-implement-lzw-ccitt-jbig2-stream-decoders`

### 3.1 改修・新規作成ファイル
- [x] [src/pdf_engine/decompress.py](../../src/pdf_engine/decompress.py) (LZWDecode, CCITTFaxDecode, JBIG2Decode のディスパッチおよびデコーダ関数実装)
- [x] [src/pdf_engine/filters/](../../src/pdf_engine/filters/) (新規パッケージ: 各フィルターのアルゴリズム分離)
  - `src/pdf_engine/filters/__init__.py` (公開インターフェース)
  - `src/pdf_engine/filters/lzw.py` (Pure Python LZW デコーダ: 9〜12bit, EarlyChange 0/1, Predictor)
  - `src/pdf_engine/filters/ccitt.py` (Pure Python CCITT Group 3 / Group 4 デコーダ)
  - `src/pdf_engine/filters/jbig2.py` (Pure Python JBIG2 セグメントパーサー & 2値ビットマップ復元)
- [x] [src/pdf_engine/image_extractor.py](../../src/pdf_engine/image_extractor.py) (LZW / CCITT / JBIG2 画像 XObject からの 1bit/8bit PNG 合成)
- [x] [tests/pdf_engine/test_advanced_filters.py](../../tests/pdf_engine/test_advanced_filters.py) (LZW, CCITT, JBIG2 の網羅的単体・結合・セキュリティ防御テスト)

---

## 4. 脅威分析と多層防御設計 (Threat Modeling & SC-1〜SC-7)

1. **LZW 展開爆弾 (Decompression Bomb / DoS)**:
   - わずか数 KB のストリームから数十 GB に爆発するサイクルを防ぐため、`max_bytes`（デフォルト 30MB）での厳格な打ち切り制限。
2. **CCITTFax 不正ランレングス & 2D READ 不正参照**:
   - 参照行の範囲外アクセス（Out-of-bounds Reference）を防ぐため、常に 1 行前のバッファ長を境界クランプ。
   - 不正なパスモード・垂直モード符号を受信した際のフェイルセーフ白画素パディング。
3. **JBIG2 セグメント整数オーバーフロー & メモリ破損 (FORCEDENTRY 防御)**:
   - セグメントヘッダのページ幅・高さ（Page Width / Height）が `MAX_DIMENSION = 4096` および `MAX_TOTAL_PIXELS = 16_000_000` を超える場合は即座に拒否。
   - セグメントデータ長の加算時に 32 ビット整数のラップアラウンドを検証。
   - 算術復号（MQ Decoder）時のバッファ終端検証（Out-of-bounds Read 防止）。

---

## 5. 実装方針と詳細ステップ / Implementation Steps

### Step 1: Pure-Python LZWDecode エンジンの実装 (`src/pdf_engine/filters/lzw.py`)
1. ビットストリームリーダー (`_LzwBitReader`):
   - MSB first で 9〜12 ビットの可変長コードを順次取得。
2. LZW 状態遷移:
   - 初期辞書: 0〜255 を `bytes([i])`、256 (`CLEAR_TABLE`)、257 (`EOD`)。
   - テーブルエントリ数が $2^{\text{code\_len}} - \text{early\_change}$ に達した時点でコード長を 1 拡張（最大 12 ビット）。
   - `CLEAR_TABLE` 受信時にコード長を 9 ビットにリセット、辞書を初期化。
   - 特殊パターン（未定義コード = 直前パターン + 直前パターンの先頭バイト）を正確に処理。
3. `decode_lzw(data: bytes, early_change: int = 1, max_bytes: int = 30_000_000) -> bytes`

### Step 2: Pure-Python CCITTFaxDecode エンジンの実装 (`src/pdf_engine/filters/ccitt.py`)
1. ITU-T T.4 / T.6 ハフマン符号テーブル（Terminating / Make-up Codes: White & Black）の定義。
2. Group 4 (2D T.6, $K < 0$):
   - Pass Mode (`0001`), Horizontal Mode (`001`), Vertical Modes ($V(0), V_R(1..3), V_L(1..3)$) の 2D READ 復元。
3. Group 3 1D ($K = 0$):
   - Modified Huffman ランレングス復号。
4. `BlackIs1` パラメータ対応（反転ビット処理）および行パディング処理。
5. `decode_ccitt_fax(data: bytes, columns: int, rows: int = 0, k: int = -1, black_is_1: bool = False, max_bytes: int = 30_000_000) -> bytes`

### Step 3: Pure-Python JBIG2Decode エンジンの実装 (`src/pdf_engine/filters/jbig2.py`)
1. セグメントヘッダパーサー (ISO/IEC 14492 Clause 7.2):
   - Segment Number (4 bytes), Segment Header Flags, Referred-to Segment Numbers, Segment Page Association, Segment Data Length.
2. セグメントタイプディスパッチ:
   - Type 48 (Page Information): ページ幅・高さ・解像度取得。
   - Type 38 / 39 (Immediate Generic Region): 2値ビットマップ（Generic Region）のデコード。
   - Type 0 (Symbol Dictionary) / Type 6 (Immediate Text Region): テキスト文字形状辞書。
3. MQ 算術デコーダ (MQ Arithmetic Decoder) の基本実装:
   - A / C レジスタ、QE 確率推定テーブルによる算術復号。
4. `decode_jbig2(data: bytes, globals_data: Optional[bytes] = None, max_bytes: int = 30_000_000) -> bytes`

### Step 4: StreamDecompressor & PdfImageExtractor 統合 (`decompress.py`, `image_extractor.py`)
1. `StreamDecompressor._apply_single_filter`:
   - `LZWDecode` / `LZW` -> `decode_lzw()` + Predictor 適用
   - `CCITTFaxDecode` / `CCF` -> `decode_ccitt_fax()`
   - `JBIG2Decode` -> `decode_jbig2()`
2. `PdfImageExtractor`:
   - 1bit 2値画像（CCITT / JBIG2）から 8bit Grayscale PNG（白: 255, 黒: 0）への合成機能を追加。
   - LZW 伸張画像の PNG 合成。

### Step 5: 網羅的テストの整備 (`tests/pdf_engine/test_advanced_filters.py`)
1. LZW: 既知パターン復元、EarlyChange 0/1、Predictor（TIFF/PNG）結合、展開爆弾ガード。
2. CCITT: Group 4 2D 画像、Group 3 1D 画像、BlackIs1 反転、破損ストリーム。
3. JBIG2: Page Information + Generic Region のセグメントパースとビットマップ復元、CVE-2021-30860 防御境界検証。
4. ImageExtractor: LZW/CCITT/JBIG2 経由の PNG 画像抽出 E2E テスト。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] **LZWDecode**: 9〜12bit 可変長コード、EarlyChange (0/1)、PNG/TIFF Predictor が Pure Python で正確に動作すること。
- [ ] **CCITTFaxDecode**: Group 4 (2D) および Group 3 (1D) の 2 値ファックス画像が正しくデコードされ、白黒画素が復元されること。
- [ ] **JBIG2Decode**: セグメント構造（Page Information, Generic Region 等）が正しくパースされ、2値ビットマップが復元されること。
- [ ] **ゼロ外部依存**: すべてのデコーダが C 拡張や外部ライブラリを一切使わず Pure Python で実装されていること。
- [ ] **多層セキュリティ防御 (SC-1〜SC-7)**: メモリ制限（30MB）、整数オーバーフロー、破損データに対するフェイルセーフが機能すること。
- [ ] **テスト網羅性**: 新規ユニットテスト `tests/pdf_engine/test_advanced_filters.py` が 100% PASS すること。
- [ ] **品質ゲート準拠**: `make check_format` および `make static_analysis` (mypy --strict, Xenon Rank A) がエラー 0 件であること。
