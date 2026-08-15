---
name: okf-converter
description: 原本データ (JSON/TXT/PDF) から Google OKF (Open Knowledge Format) v0.2 仕様準拠の YAML フロントマター付き Markdown ドキュメントを生成・更新する標準スキル。
---

# okf-converter

本スキルは、**「保存された原本データ（Raw Data）から Google Open Knowledge Format (OKF) v0.2 仕様に完全準拠した構造化 Markdown ドキュメント（`outputs/okf_papers/YYYY-MM-DD/<clean_id>.md`）を生成・検証する」** ための標準プロシージャスキルです。

システムアーキテクト（SA）、セキュリティ（SC）、情報検索（IR）、および監査人（AU）の連携により、スキーマ整合性とトレーサビリティを完全アサートします。

---

## 📄 Google OKF v0.2 スキーマ構造

生成されるすべての Markdown ドキュメントは、以下の厳格な YAML フロントマター構造を備えている必要があります：

```yaml
---
type: "security-paper"
title: "Paper Title in Original English"
description: "構造化エグゼクティブサマリーの1文日本語要約"
resource: "https://arxiv.org/abs/XXXX.XXXXX"
tags:
  - "cs.CR"
  - "cryptography" # ドメインタグ
  - "zero-trust"   # セキュリティ種別タグ
timestamp: "2026-08-15T20:00:00Z"
provenance:
  origin: "arxiv.org"
  raw_json_path: "../../raw_data/YYYY-MM-DD/<clean_id>_meta.json"
  published: "YYYY-MM-DD"
  authors:
    - "Author 1"
    - "Author 2"
trust:
  signature: "sha256-hash-value"
  attestation: "Google OKF v0.2 Verified"
---

# [論文タイトル]

## 1. 概要 (Executive Summary)
[日本語1文要約および主要ハイライト]

## 2. 原本アブストラクト (Original Abstract)
[英文アブストラクト全文]

## 3. 全文テキスト抽出情報 (Extracted Text Metadata)
- **PDFリンク**: [原論文PDF](../../raw_data/YYYY-MM-DD/<clean_id>.pdf)
- **抽出TXT**: [全文テキスト](../../raw_data/YYYY-MM-DD/<clean_id>.txt)
```

---

## 📋 実行手順 (Instructions)

### Step 1: 原本データの存在アサーション
1. `outputs/raw_data/YYYY-MM-DD/<clean_id>_meta.json` および `<clean_id>_raw_abstract.txt` が存在することを確認。

### Step 2: OKF 変換処理の実行
1. `arxiv_okf_fetcher.py` の OKF 変換モジュールが動作し、`outputs/okf_papers/YYYY-MM-DD/<clean_id>.md` が生成されたことをアサート。

### Step 3: OKF スキーマ・相関検証 (Quality Gate 2)
1. **YAML フロントマターアサーション**:
   - `type` が `"security-paper"` であること。
   - `description` が完全に日本語化された1文要約であること。
   - `provenance.raw_json_path` が実在する相対パスであること。
2. **相対パスアサーション**:
   - ドキュメント内の Raw データへの全リンクが相対パス (`../../raw_data/...`) で書かれていること。

### Step 4: ルートインデックス (`outputs/index.md`) 更新
1. 変換完了後、`outputs/index.md` の OKF カタログ表に論文エントリを追加・更新する。
