# Issue 157: Implement Rate Limiting & Resource Quotas (DoS Protection)

## 1. 概要 (Overview)
`DSN-07` Rev 2.1 に基づき、外部API（arXiv API / RSS等）への過剰リクエスト（HTTP 429 Rate Limit）の防止、内部リソース消費DoS防御、およびカスケード障害を防ぐサーキットブレーカー機構（`src/security/ratelimit/limiter.py`, `src/security/ratelimit/circuit_breaker.py`）を実装する。

## 2. 目的・背景 (Motivation & Background)
- arXiv APIのレート制限（3秒間隔、急激な連続リクエストの禁止）を順守し、IPバンやHTTP 429エラーを未然に防止する。
- Web GatewayやMCPエンドポイントに対する連続アクセス・ブルートフォース攻撃・DoS試行を、スライディングウィンドウ型レートリミッターで制限する。
- 外部API障害やネットワーク分断発生時に無駄な再試行によるリソース浪費を防ぎ、フェイルファスト（Fail-Fast）と自動回復を実現する3状態（CLOSED / OPEN / HALF_OPEN）サーキットブレーカーを提供する。

## 3. 実装要件 (Requirements)
1. **レートリミッター (`src/security/ratelimit/limiter.py`)**:
   - `TokenBucketRateLimiter`: バースト許容量（Capacity）と継続補充速度（Fill Rate/sec）によるトークンバケットアルゴリズム
   - `SlidingWindowRateLimiter`: キー単位（IP/User/API）のスライディングログ時間枠制限（例: 1分あたり60リクエスト）
   - `RateLimitExceededError` 例外
2. **サーキットブレーカー (`src/security/ratelimit/circuit_breaker.py`)**:
   - `CircuitBreaker`: CLOSED（正常稼働）→ OPEN（障害遮断・即時例外）→ HALF_OPEN（試験的試行）→ CLOSED（自動復帰）の状態遷移
   - コンテキストマネージャー (`with breaker:`) およびデコレータ支援
   - `CircuitBreakerOpenError` 例外
3. **品質・制約要件**:
   - Python標準ライブラリ (`time`, `threading`, `typing`, `enum`, `collections`) のみ使用。
   - Xenon 循環的複雑度 $\le 5$ (Rank A)。
   - Mypy `--strict` 準拠。

## 4. 対象ファイル (Target Files)
- `src/security/ratelimit/__init__.py`: 新規作成
- `src/security/ratelimit/limiter.py`: 新規作成
- `src/security/ratelimit/circuit_breaker.py`: 新規作成
- `src/security/__init__.py`: エクスポート追加
- `tests/security/test_ratelimit_circuit.py`: 単体テスト新規作成

## 5. 完了定義 (Definition of Done)
- [x] `TokenBucketRateLimiter` および `SlidingWindowRateLimiter` が正確に流量制限を行うこと
- [x] `CircuitBreaker` が CLOSED / OPEN / HALF_OPEN を正しく遷移し、フェイルファストと自動復帰を行うこと
- [x] 単体テスト `tests/security/test_ratelimit_circuit.py` が 100% PASS すること
- [x] `make check_format` および `make static_analysis` (xenon, flake8, mypy --strict) が PASS すること

## 6. 実装結果サマリー (Implementation Summary)
- `src/security/ratelimit/limiter.py` を実装し、バースト許容・秒間補充を行うトークンバケットアルゴリズム `TokenBucketRateLimiter`（スレッドセーフ、ブロッキング待機対応）およびキー単位のローリング時間枠制限を行う `SlidingWindowRateLimiter` を提供。
- `src/security/ratelimit/circuit_breaker.py` を実装し、CLOSED / OPEN / HALF_OPEN の3状態遷移によるカスケード障害防止・フェイルファスト・自動復帰サーキットブレーカー `CircuitBreaker`（コンテキストマネージャーおよび `call` ラッパー対応）を提供。
- 全関数で Xenon 循環的複雑度 $\le 5$ (Rank A 100%)、Mypy `--strict` (0エラー)、標準ライブラリのみによる外部依存ゼロを保証。
- 単体テスト `tests/security/test_ratelimit_circuit.py` (全8テストケース) が 100% PASS。
