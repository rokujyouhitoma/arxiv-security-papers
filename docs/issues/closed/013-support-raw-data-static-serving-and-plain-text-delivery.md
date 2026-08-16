---
ID: 013
種別: Fix / Enhancement
優先度: High
ステータス: Closed (Completed)
完了日: 2026-08-16
---

# [FIX/ENH] Raw データ（.txt / .pdf / .json）の直接静的配信とプレーンテキスト表示の最適化 (ID: 013)

## 1. 概要 / Summary
`/raw_data/YYYY-MM-DD/<id>.txt` や `.pdf`, `_meta.json` へのアクセス時に、SPA フォールバック（`index.html`）が誤って発動し、CSS が崩壊した HTML が返却される問題を解消しました。

UI/UX デザイナーおよび IT 戦略家（ST）の審議結果に基づき、**`/raw_data/` および `/outputs/` 配下のファイルに対して、適切な MIME タイプ（`.txt` $\to$ `text/plain; charset=utf-8`, `.pdf` $\to$ `application/pdf`, `.json` $\to$ `application/json; charset=utf-8`）での安全な直接静的配信（Raw Data Asset Layer）** を実現しました。

また、SPA フォールバックは拡張子のない URL パス（`/`, `/search`, `/trends` 等）に限定し、存在しない静的アセットファイルに対しては明確に `404 Not Found` を返すようにルーティングを正常化しました。

---

## 2. 実装成果 / Delivered Changes
1. **Web サーバー静的ルーティング拡張 (`src/web_server.py`)**:
   - `/raw_data/` へのアクセスを `outputs/raw_data/` 配下へ安全にマッピング。
   - `/outputs/` へのアクセスを `outputs/` 配下へ安全にマッピング。
   - `os.path.commonpath` によるパストラバーサル（CWE-22）防止（不正パスは `403 Forbidden`）。
   - `.txt` は `Content-Type: text/plain; charset=utf-8`、`.pdf` は `application/pdf`、`.json` は `application/json; charset=utf-8` で正確に配信。
2. **SPA フォールバックの適正化**:
   - 拡張子（`.txt`, `.pdf`, `.json`, `.css`, `.js` 等）を持つ存在しないリソースへのリクエストは、`index.html` にフォールバックせず `404 Not Found` を返却。
3. **テストの追加 (`tests/test_web_server.py`)**:
   - `/raw_data/` 配下のテキスト配信、404 レスポンス、403 トラバーサル遮断のテストを追加。

---

## 3. 完了条件 (DoD) 検証結果
- [x] `GET /raw_data/2026-05-12/2605.11671.txt` で `Content-Type: text/plain; charset=utf-8` として生テキストが返却されること。
- [x] `GET /raw_data/2026-05-12/2605.11671.pdf` で `application/pdf` としてバイナリが返却されること。
- [x] 存在しない `.txt` へのリクエストが `404 Not Found` を返すこと。
- [x] パストラバーサル試行（`/raw_data/../../../etc/passwd`）が `403 Forbidden` で遮断されること。
- [x] Flake8, MyPy, pytest がオールグリーンで通過すること。
