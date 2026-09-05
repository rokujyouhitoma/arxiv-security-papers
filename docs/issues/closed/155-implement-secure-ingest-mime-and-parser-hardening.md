# Issue 155: Implement Secure Ingestion, MIME Validation & Parser Hardening

## 1. 概要 (Overview)
`DSN-07` Rev 2.1 に基づき、外部から取得される非信頼データ（PDF論文原本、RSS XMLフィード、圧縮アーカイブ、画像、JSONメタデータ等）に対するマジックバイト検証（MIME偽装検知）、展開ボム（Decompression Bomb / Zip Bomb / XML Entity Expansion Attack）の防御、およびセキュアなパーサー硬化モジュール（`src/security/validation/mime.py`, `src/security/validation/file_scanner.py`）を実装する。

## 2. 目的・背景 (Motivation & Background)
- arXivの論文PDFダウンロードや外部RSSフィード取得時、拡張子偽装や細工されたバイナリ、巨大展開ボムによるDoS攻撃・メモリ枯渇リスクが存在する。
- 拡張子だけでなくバイナリのマジックバイト（先頭シグネチャ）による厳格な実態検証が必要。
- 標準の `xml.etree.ElementTree` は XML外部実体参照 (XXE) や Billion Laughs 攻撃（実体展開指数関数的増殖）に対して脆弱であるため、外部エンティティや DTD の展開を無効化した Defused XML パーサーを標準ライブラリのみで提供する。
- アーカイブやテキスト展開時の最大サイズ制限（Quota）、最大展開倍率（Expansion Ratio Cap）を適用する。

## 3. 実装要件 (Requirements)
1. **マジックバイト検証 (`src/security/validation/mime.py`)**:
   - `detect_mime_type_from_bytes(data: bytes) -> Optional[str]`
   - `verify_magic_bytes(data: bytes, expected_type: str) -> bool`
   - 対応形式: PDF (`application/pdf`), PNG (`image/png`), JPEG (`image/jpeg`), GZIP (`application/gzip`), ZIP (`application/zip`), TAR (`application/x-tar`), JSON/Text (`text/plain`, `application/json`)
   - 制御文字・ヌルバイト不正混入の検知
2. **展開ボム防御 & XMLパーサー硬化 (`src/security/validation/file_scanner.py`)**:
   - `DefusedXMLParser`: DTD宣言、外部エンティティ (`SYSTEM`, `PUBLIC`)、再帰エンティティ展開を無効化・拒絶
   - `parse_safe_xml(xml_content: Union[bytes, str]) -> xml.etree.ElementTree.Element`
   - `DecompressionBombGuard`: 展開前後のサイズ比較（最大展開倍率50倍、最大展開サイズ50MB制限）
   - `validate_safe_decompression(compressed_size: int, uncompressed_size: int, max_ratio: float = 50.0, max_size_bytes: int = 52428800) -> bool`
   - `validate_pdf_safety_metadata(pdf_bytes: bytes, max_pages: int = 200, max_file_size: int = 52428800) -> Tuple[bool, Optional[str]]`
3. **品質・制約要件**:
   - Python標準ライブラリ (`xml.etree.ElementTree`, `xml.parsers.expat`, `typing`, `io`) のみ使用（外部依存ゼロ）。
   - Xenon 循環的複雑度 $\le 5$ (Rank A)。
   - Mypy `--strict` 準拠。

## 4. 対象ファイル (Target Files)
- `src/security/validation/mime.py`: 新規作成
- `src/security/validation/file_scanner.py`: 新規作成
- `src/security/validation/__init__.py`: エクスポート追加
- `src/security/__init__.py`: エクスポート追加
- `tests/security/test_secure_ingest.py`: 単体テスト新規作成

## 5. 完了定義 (Definition of Done)
- [x] `mime.py` に各ファイル形式のマジックバイト判定と検証ロジックが実装されていること
- [x] `file_scanner.py` に XXE / Billion Laughs 攻撃を遮断する `parse_safe_xml` が実装されていること
- [x] 展開ボム判定および PDF 制限検証が正常に動作すること
- [x] 単体テスト `tests/security/test_secure_ingest.py` が 100% PASS すること
- [x] `make check_format` および `make static_analysis` (xenon, flake8, mypy --strict) が PASS すること

## 6. 実装結果サマリー (Implementation Summary)
- `src/security/validation/mime.py` を実装し、PDF, PNG, JPEG, GIF, GZIP, ZIP, TAR, XML, JSON, Text のバイナリマジックバイト実体検証・拡張子偽装防止・ヌルバイト排除を提供。
- `src/security/validation/file_scanner.py` を実装し、DTDおよび外部エンティティを完全遮断した安全な XML パーサー `parse_safe_xml`、展開倍率50倍/最大50MBの展開ボム防止 `validate_safe_decompression`、および PDF ページ数・サイズ・悪意ある JavaScript/Launch アクションの静的検知 `validate_pdf_safety_metadata` を実装。
- 全関数で Xenon 循環的複雑度 $\le 5$ (Rank A 100%)、Mypy `--strict` (0エラー)、標準ライブラリのみによる外部依存ゼロを保証。
- 単体テスト `tests/security/test_secure_ingest.py` (全10テストケース) が 100% PASS。
