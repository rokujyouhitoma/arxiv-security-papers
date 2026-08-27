# [FEAT] 内製 Pure-Python PDF エンジンにおける 2 カラム多段組レイアウト自動認識と暗号・数式記号正規化の実装 (ID: 081)

| 項目 | 内容 |
| :--- | :--- |
| **ID** | 081 |
| **種別** | Feature |
| **優先度** | High |
| **ステータス** | Open (In Progress) |
| **起票日** | 2026-08-27 |
| **担当ロール** | NLP & IR Specialist (IR) / Systems Architect (SA) |
| **対象ブランチ** | `feat/081-pure-python-pdf-multicol-and-math-symbols` |

---

## 1. 概要 / Summary
arXiv の学術セキュリティ論文に特有の「2 カラム（多段組）レイアウト」および「暗号理論・数式記号（LaTeX / Type1 フォントマッピング）」を、外部 C ライブラリ不要の内製 Pure-Python PDF エンジン（`src/pdf_engine/`）において高精度に自動認識・テキスト順序復元する。これにより、左カラムと右カラムのテキスト混同を根絶し、抽出される全文テキスト（`<clean_id>.txt`）の品質と下流のベクトル検索精度を向上させる。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- `src/pdf_engine/layout.py` (多段組・カラムクラスタリング・バウンディングボックス解析)
- `src/pdf_engine/font.py` (特殊暗号数学記号 / CMap / Type1 フォントデコーダ)
- `src/pdf_engine/interpreter.py` (PDF コンテンツストリーム命令解釈)
- `src/pdf_engine/extractor.py` (抽出エントリーポイント)
- `tests/pdf_engine/` (PDF エンジン単体テスト & ベンチマーク)

---

## 3. 要件定義と脅威モデル / Requirements & Threat Model
- **機能要件**:
  - `src/pdf_engine/layout.py` に X 座標ヒストグラムに基づく 2 カラム境界検出アルゴリズムを実装し、左カラム上 $\rightarrow$ 下 $\rightarrow$ 右カラム上 $\rightarrow$ 下の自然な学術論文読解順序でテキストブロックをソート。
  - LaTeX の数式記号（$\oplus, \otimes, \mathbb{F}_q, \mathcal{O}, \leftarrow, \mathbb{Z}_p$ 等）を標準 UTF-8 ユニコード文字列へ正規化。
- **非機能・セキュリティ要件**:
  - `zlib.decompress` 実行時の Zip Bomb 対策（最大解凍サイズ制限 20MB）。
  - ゼロ外部依存（標準ライブラリのみ）を厳格に維持。

---

## 4. 実装方針 / Implementation Plan
1. **`src/pdf_engine/layout.py`**:
   - `ColumnAwareLayoutEngine` を実装し、ページ内のテキスト要素を X 軸射影で左右カラムに分離。
2. **`src/pdf_engine/font.py`**:
   - 暗号論文で頻出する Type1 / TrueType 数学記号グリフマッピング辞書 `CRYPTO_MATH_CMAP` を拡張。
3. **`tests/pdf_engine/`**:
   - 多段組 PDF テストフィクスチャに対する抽出順序アサーションを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 2 カラム論文のテキスト抽出において、段組み混同（横跨ぎ読み）が発生せず、正しくカラム順でテキストが出力されること。
- [ ] 暗号記号が文字化けせず UTF-8 で正規化されること。
- [ ] `tests/pdf_engine/` の全単体テストが 100% PASS すること。
- [ ] `make check` をパスすること。
