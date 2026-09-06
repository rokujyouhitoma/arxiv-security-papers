---
ID: 161
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] 統一セキュリティ WSGI ミドルウェアの実装および Web Gateway パイロット適用 (ID: 161)

## 1. 概要 / Summary
`DSN-07` Rev 2.2 (Section 12) に基づき、Web レイヤーにおける個別コード埋め込みによるセキュリティ適用の散乱・抜け漏れ課題を抜本的に解決するため、PEP 3333 準拠の `SecurityWSGIMiddleware` (`src/security/middleware/wsgi.py`) を実装する。

本ミドルウェアは、任意の WSGI アプリケーションの外側を1行でラップするだけで、全 HTTP 通信に対して透過的かつ漏れなく以下の多層防御を一括提供する：
1. **セキュリティレスポンスヘッダー自動注入**: HSTS, CSP, X-Frame-Options: DENY, X-Content-Type-Options: nosniff
2. **DoS / レート制限自動遮断**: クライアント IP 単位の Token Bucket / Sliding Window 判定（超過時 429 応答）
3. **パス & クエリの危険構文遮断**: パストラバーサル（`../`, `..\`）、Null バイト、制御文字の検知（検知時 400 応答）
4. **全アクセスの構造化監査ログ出力**: `SecurityAuditLogger` への `SecurityAuditEvent` 自動記録

先行パイロットとして `src/web/gateway/app.py` の `WSGIApplication` に本ミドルウェアを接続し、実運用トラフィックへの適用性を検証する。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - `docs/designs/DSN-07-security_guard_and_rbac.md` (Rev 2.2 Section 12)
  - PEP 3333 (Python Web Server Gateway Interface v1.0.1)
  - Issue 154〜159 (System Security Infrastructure Hardening)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/security/middleware/__init__.py`: 新規作成
- [ ] `src/security/middleware/wsgi.py`: 新規作成
- [ ] `src/security/__init__.py`: エクスポート追加
- [ ] `src/web/gateway/app.py`: `SecurityWSGIMiddleware` による透過的ラップ適用
- [ ] `tests/security/test_wsgi_middleware.py`: 単体テスト新規作成
- [ ] `tests/web/gateway/test_gateway.py`: 統合回帰テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/161-security-wsgi-middleware`

1. **`SecurityWSGIMiddleware` の実装 (`src/security/middleware/wsgi.py`)**:
   - `environ` からクライアント IP（`REMOTE_ADDR`, `HTTP_X_FORWARDED_FOR` の最左アドレス検証）を安全に抽出。
   - `PATH_INFO` および `QUERY_STRING` に対するパストラバーサル（`../`, `..\`, `%2e%2e` 等）および危険文字検査。
   - `TokenBucketRateLimiter` または `SlidingWindowRateLimiter` による IP 単位のスロットリング判定。
   - `start_response` をインターセプトし、標準セキュリティヘッダーを透過的付与。
   - レスポンス完了時に `SecurityAuditLogger` へステータスコード・IP・所要時間を記録。
2. **Web Gateway へのパイロット適用 (`src/web/gateway/app.py`)**:
   - `create_app()` または `WSGIApplication` インスタンス化箇所で `SecurityWSGIMiddleware` を適用。
3. **品質・制約要件**:
   - Python 標準ライブラリのみ使用（外部依存ゼロ）。
   - Xenon 循環的複雑度 $\le 5$ (Rank A 必須)。
   - Mypy `--strict` 準拠。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `SecurityWSGIMiddleware` が PEP 3333 準拠の WSGI ミドルウェアとして独立動作すること
- [x] クライアント IP に基づくレート制限超過時に 429 Too Many Requests が返却されること
- [x] パスおよびクエリ内のパストラバーサル（`../`）や Null バイトを検知して 400 Bad Request で遮断すること
- [x] 全レスポンスにセキュリティヘッダー（HSTS, CSP, X-Content-Type-Options, X-Frame-Options）が自動注入されること
- [x] リクエスト処理イベントが `SecurityAuditLogger` に構造化ログとして自動記録されること
- [x] `src/web/gateway/app.py` にミドルウェアが統合され、既存ルートが正常稼働すること
- [x] 単体テスト `tests/security/test_wsgi_middleware.py` が 100% PASS すること
- [x] `make check_format` および `make static_analysis` が 100% PASS すること
