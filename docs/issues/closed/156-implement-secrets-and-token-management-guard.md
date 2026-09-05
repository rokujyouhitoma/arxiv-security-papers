# Issue 156: Implement Secrets & Token Management Guard

## 1. 概要 (Overview)
`DSN-07` Rev 2.1 に基づき、APIキー、認証トークン、暗号秘密鍵などの機密情報を安全に管理・ゼロ化（メモリ破棄）・マスクし、ログやWebレスポンスへの漏洩を遮断するシークレット管理基盤（`src/security/secrets/manager.py`, `src/security/secrets/crypto_util.py`）を実装する。

## 2. 目的・背景 (Motivation & Background)
- arXiv APIキー、外部連携トークン、署名鍵などのシークレットがメモリ内に長期間平文で残存することや、例外スタックトレースやログ、UIに平文出力されるセキュリティリスクを排除する。
- トークン比較におけるタイミング攻撃（Timing Attack）を防止するため、全トークン検証に定数時間比較 (`hmac.compare_digest`) を徹底する。
- ログやLLMプロンプト/レスポンス内に混入したシークレット（AWSキー、GitHub PAT、OpenAIキー、秘密鍵ブロック、高エントロピー文字列）を動的検知・マスキングする。

## 3. 実装要件 (Requirements)
1. **シークレットゼロ化ストレージ (`src/security/secrets/manager.py`)**:
   - `EphemeralSecretStore`: `bytearray` によるインメモリ保持と、破棄時のメモリゼロクリア (`zeroize`) 機構
   - プロセス終了時 (`atexit`) の自動ゼロ化
2. **シークレット漏洩検知 & マスキング (`src/security/secrets/manager.py`)**:
   - `mask_secret(secret_value: str, reveal_len: int = 4, mask_char: str = "*") -> str`
   - `detect_exposed_secrets(text: str) -> List[SecretFinding]`
   - AWS (`AKIA...`), GitHub PAT (`ghp_...`), OpenAI (`sk-...`), 秘密鍵 (`-----BEGIN PRIVATE KEY-----`), 高エントロピー文字列の検知
3. **暗号ユーティリティ & タイミング攻撃防御 (`src/security/secrets/crypto_util.py`)**:
   - `constant_time_compare(a: Union[str, bytes], b: Union[str, bytes]) -> bool`
   - 暗号論的擬似乱数 (`secrets.token_urlsafe`, `secrets.token_hex`) による `generate_secure_token`, `generate_csrf_token`, `verify_csrf_token`
4. **品質・制約要件**:
   - Python標準ライブラリ (`secrets`, `hmac`, `hashlib`, `math`, `re`, `atexit`, `typing`) のみ使用。
   - Xenon 循環的複雑度 $\le 5$ (Rank A)。
   - Mypy `--strict` 準拠。

## 4. 対象ファイル (Target Files)
- `src/security/secrets/__init__.py`: 新規作成
- `src/security/secrets/manager.py`: 新規作成
- `src/security/secrets/crypto_util.py`: 新規作成
- `src/security/__init__.py`: エクスポート追加
- `tests/security/test_secrets_guard.py`: 単体テスト新規作成

## 5. 完了定義 (Definition of Done)
- [x] `EphemeralSecretStore` が正常にシークレットを保管し、`zeroize` でメモリ上からクリアされること
- [x] `detect_exposed_secrets` が各種シークレットパターンおよび高エントロピー文字列を正確に検知すること
- [x] `constant_time_compare` および CSRF トークン生成・検証が正常に動作すること
- [x] 単体テスト `tests/security/test_secrets_guard.py` が 100% PASS すること
- [x] `make check_format` および `make static_analysis` (xenon, flake8, mypy --strict) が PASS すること

## 6. 実装結果サマリー (Implementation Summary)
- `src/security/secrets/manager.py` を実装し、ゼロ化可能なオンメモリシークレットストア `EphemeralSecretStore`、安全なマスキングユーティリティ `mask_secret`、既知クレデンシャル（AWS, GitHub PAT, OpenAI, 秘密鍵）および高シャノンエントロピー文字列の漏洩検知 `detect_exposed_secrets` を提供。
- `src/security/secrets/crypto_util.py` を実装し、タイミング攻撃防御のための定数時間比較 `constant_time_compare`、暗号論的擬似乱数を用いた安全なトークン・CSRFトークン生成・検証関数を提供。
- 全関数で Xenon 循環的複雑度 $\le 5$ (Rank A 100%)、Mypy `--strict` (0エラー)、標準ライブラリのみによる外部依存ゼロを保証。
- 単体テスト `tests/security/test_secrets_guard.py` (全9テストケース) が 100% PASS。
