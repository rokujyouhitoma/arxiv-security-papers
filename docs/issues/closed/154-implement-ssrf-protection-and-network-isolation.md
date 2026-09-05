# Issue 154: Implement SSRF Protection & Network Isolation Wrapper

## 1. 概要 (Overview)
`DSN-07` Rev 2.1 に基づき、外部通信（arXiv API / RSS / PDFダウンロード等）における SSRF (Server-Side Request Forgery) 脆弱性、内部ネットワーク偵察、クラウドメタデータエンドポイント (`169.254.169.254` 等) へのアクセス、および DNS リバインディング攻撃を防御するネットワーク検証・分離ラッパーモジュール `src/security/validation/network.py` を実装する。

## 2. 目的・背景 (Motivation & Background)
- 論文フェッチパイプラインやリンク検証機能は外部URLへのHTTPリクエストを伴う。
- 悪意ある入力やリダイレクトによる内部リソース（RFC 1918 プライベートIP、ループバック `127.0.0.1`, `::1`、リンクローカル/メタデータ `169.254.0.0/16`）への不正接続を物理的・プロトコルレベルで防止する必要がある。
- DNSリバインディング攻撃（検証時のIPと実際の接続先IPの差分）を防ぐため、IPピン止めソケット通信機構を標準ライブラリのみで提供する。

## 3. 実装要件 (Requirements)
1. **URL & スキーム検証 (`is_safe_remote_url`)**:
   - 許可されたスキーム (`http`, `https`) のみ許可（`file://`, `gopher://`, `dict://`, `ftp://` 等を拒絶）。
   - クレデンシャル含有URL (`http://user:pass@host`) の拒絶。
2. **IPアドレス検証 (`resolve_and_validate_ip`)**:
   - ホスト名をIPアドレスに解決し、`ipaddress.ip_address()` で検証。
   - `is_loopback`, `is_private`, `is_link_local`, `is_multicast`, `is_reserved`, `is_unspecified` を判定し、全て拒絶。
   - IPv4 / IPv6 両対応。
3. **安全なソケット生成 (`create_safe_socket`)**:
   - ホスト名解決で得た検証済みIPに直接 `socket.connect()` を行い、DNSリバインディングの隙を排除。
   - TLS/SSL ハンドシェイク時の `server_hostname` (SNI) は元のホスト名を保持。
4. **品質・制約要件**:
   - Python標準ライブラリ (`socket`, `urllib.parse`, `ipaddress`, `ssl`) のみ使用。
   - Xenon 循環的複雑度 $\le 5$ (Rank A)。
   - Mypy `--strict` 準拠。

## 4. 対象ファイル (Target Files)
- `src/security/validation/network.py`: 新規作成
- `src/security/validation/__init__.py`: エクスポート追加
- `src/security/__init__.py`: エクスポート追加
- `tests/security/test_network_validation.py`: 単体テスト新規作成

## 5. 完了定義 (Definition of Done)
- [x] `src/security/validation/network.py` に `is_safe_remote_url`, `resolve_and_validate_ip`, `create_safe_socket`, `safe_http_fetch` が実装されていること
- [x] ループバック、プライベートIP、クラウドメタデータ (`169.254.169.254`)、マルチキャスト、不正スキームが正しく遮断されること
- [x] 単体テスト `tests/security/test_network_validation.py` が 100% PASS すること
- [x] `make check_format` および `make static_analysis` (xenon, flake8, mypy --strict) が PASS すること

## 6. 実装結果サマリー (Implementation Summary)
- `src/security/validation/network.py` を実装し、URLスキーム、ユーザー情報混入、プライベートIP / ループバック / リンクローカル / クラウドメタデータ (`169.254.169.254`) / IPv4射影IPv6アドレスを徹底遮断。
- DNSリバインディング攻撃を防止するため、解決済みIPアドレスに直接ソケット接続をピン止めする `create_safe_socket` およびリダイレクト先を都度再検証する `safe_http_fetch` を実装。
- すべての関数で Xenon 循環的複雑度 $\le 5$ (Rank A 100%)、Mypy `--strict` (エラー0件)、外部依存ゼロ (標準ライブラリのみ) を達成。
- 単体テスト `tests/security/test_network_validation.py` (全13テストケース) が 100% PASS。
