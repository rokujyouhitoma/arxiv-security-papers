---
ID: 324
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-09-18
---

# [FEAT/ENH] Django互換のTIME_ZONE/USE_TZ設定およびDSN構成の追加 (ID: 324)

## 1. 概要 / Summary
Djangoのタイムゾーン設計理念と同様に、システム全体の一元設定（Single Source of Truth: SSOT）である `src/settings.py` に以下のタイムゾーン設定を導入する。

```python
TIME_ZONE = "Asia/Tokyo"
USE_TZ = True
```

- **表示・テンプレート層 (`TIME_ZONE = 'Asia/Tokyo'`)**:
  テンプレートレンダリング、Webゲートウェイレスポンス、コンソール画面表示において、設定されたタイムゾーン（デフォルト: 日本標準時 JST / Asia/Tokyo）を使用する。
- **データベース層 (`USE_TZ = True`)**:
  データベース内部（自作 MultiTable VDB, SQLite, JSON, WAL, OTLP等）には協定世界時（UTC）のISO 8601形式でタイムスタンプを厳格に永続化し、取得・出力・表示時に設定された `TIME_ZONE`（日本時間）へ自動変換を行う。
- **DSN定義への記載**:
  `src/settings.py` の `DATABASES` 辞書内の各データベースDSN定義（`arxiv_security_db`, `cti_catalog_db`, `graph_db`, `analytics_db`, `spider_execution_db`, `default`）に、タイムゾーン仕様およびストレージ時刻基準（`TIME_ZONE = 'UTC'`, `USE_TZ = True`, `DISPLAY_TIMEZONE = 'Asia/Tokyo'`）を明記し、DSN経由での接続・イントロスペクション時にも参照可能とする。

---

## 2. 背景と設計原則 / Background & Design Principles
1. **Django互換のタイムゾーン・モデル思想 (Django-compatible Model)**:
   - Djangoの `TIME_ZONE = 'Asia/Tokyo'` / `USE_TZ = True` に則り、ストレージ内部は常に timezone-aware な UTC として保持し、ユーザーやクライアントへの提供・描画時にのみ指定されたタイムゾーンへプロジェクション（射影）する。
2. **単一の真実源 (Single Source of Truth: SSOT)**:
   - タイムゾーン情報やストレージ時間基準を各サブシステム（API, DB, Spider, CLI）でハードコードせず、すべて `src/settings.py` から読み取る。
3. **ゼロ外部依存 (Zero External Dependencies)**:
   - `pytz` や `django` などの重量級サードパーティパッケージを導入せず、Python 3.9+ 標準ライブラリの `zoneinfo` および `datetime` のみで自己完結する。
4. **耐障害性とポータビリティ (Portability & Fallback Resilience)**:
   - システム環境に IANA tzdata が存在しない最小コンテナ環境でも、JST（+09:00）および UTC への固定オフセットフォールバックを備え、例外クラッシュを100%防止する。

---

## 3. 脅威モデリングとセキュリティ要件 / Threat Modeling & Security Considerations
| 脅威 / リスク (STRIDE) | 脆弱性・影響 (CWE) | 対策・緩和策 (Mitigation) |
| :--- | :--- | :--- |
| **不正入力・改ざん (Tampering)** | CWE-20 (不適切な入力検証): 悪意のある文字列や極端な数値による例外クラッシュ | 入力値の型（`datetime`, `str`, `int`, `float`）を厳格に検査。文字列は長さ制限（最大64文字）を設け、`datetime.fromisoformat` による標準パースを実施。不正な形式は `ValueError` を送出。 |
| **パス走査・名前空間汚染 (Elevation of Privilege)** | CWE-22 (パストラバーサル): `zoneinfo.ZoneInfo("../etc/passwd")` 等の悪意あるタイムゾーン指定 | タイムゾーン名に英数字、スラッシュ、アンダースコア、ハイフン、プラス・マイナス以外が含まれる場合は即座に拒否し、フォールバックまたは安全な例外処理を行う。 |
| **境界値オーバーフロー (DoS)** | CWE-190 (整数オーバーフロー): 1e15 を超える巨大エポック秒による `OverflowError` | エポック秒の許容範囲（例: -62135596800 〜 253402300799、西暦0001〜9999年）を検証し、範囲外は安全に拒絶。 |
| **ネイティブ混在不整合 (Information Disclosure)** | タイムゾーン未設定 (Naive datetime) と Aware datetime の不用意な比較・減算エラー | Naive datetime を受領した際は、`USE_TZ` 設定に基づいて決定論的に UTC またはローカルゾーンを補完（`replace(tzinfo=...)`）し、一貫した timezone-aware オブジェクトとして扱う。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/settings.py](../../src/settings.py) (設定定数、DSN辞書、core パッケージ関数再エクスポート、Xenon CC <= 5)
- [x] [src/core/timezone/](../../src/core/timezone/) (新規パッケージ: タイムゾーン解決・変換・正規化エンジン、ゼロ外部依存)
- [x] [src/core/settings/](../../src/core/settings/) (新規パッケージ: データベーススコープ・メタデータイントロスペクションユーティリティ)
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (データベースイントロスペクションメタデータへのタイムゾーン反映)
- [x] [tests/test_settings_timezone.py](../../tests/test_settings_timezone.py) (新規ユニットテスト: TIME_ZONE/USE_TZの動作・変換・DSN適合性・異常系・境界値・パッケージ直接インポート検証)
- [x] [docs/issues/README.md](README.md) (Issue台帳のステータス確認・更新)

---

## 5. 詳細設計・実装方針 / Detailed Implementation Plan
Target Branch: `feat/324-add-timezone-and-use-tz-settings`

### 5.1. `src/settings.py` の定数直接定義
各データベース内部で重複定義するのではなく、`src/settings.py` のトップレベルに直接定数として定義:
```python
TIME_ZONE: str = "Asia/Tokyo"
USE_TZ: bool = True
DATABASE_TIME_ZONE: str = "UTC"
DISPLAY_TIME_ZONE: str = TIME_ZONE
DB_TIME_ZONE: str = DATABASE_TIME_ZONE
```

### 5.2. `src/core/` へのパッケージ分離と実装配置
`settings.py` を純粋な宣言的設定ファイル（SSOT）として保つため、関数実装を `src/core/` 以下の専門パッケージへ配置:

1. **`src/core/timezone/` (タイムゾーン変換エンジン)**:
   - `converter.py`:
     - `get_zoneinfo(tz_name: Optional[str] = None) -> Any`
     - `to_storage_utc(dt_or_val: Union[datetime, str, int, float]) -> datetime`
     - `to_display_timezone(dt_or_val: Union[datetime, str, int, float], tz_name: Optional[str] = None) -> datetime`
     - `format_display_datetime(dt_or_val: Union[datetime, str, int, float], fmt: str = "...", tz_name: Optional[str] = None) -> str`
     - `get_timezone() -> str`, `is_use_tz() -> bool`, `get_database_timezone() -> str`, `get_display_timezone() -> str`
   - `__init__.py`: 上記関数群を公開。

2. **`src/core/settings/` (設定・メタデータユーティリティ)**:
   - `metadata.py`:
     - `resolve_database_scopes(databases)`
     - `resolve_all_configured_databases(databases)`
     - `resolve_database_metadata(scope_name, databases, default_tz, ...)`
     - `resolve_table_scope(tname, databases)`
     - `resolve_table_type(tname, databases)`
   - `__init__.py`: 上記関数群を公開。

3. **`src/settings.py` からの再エクスポート廃止と直接呼び出し**:
   - `settings.py` ではタイムゾーン関数の再エクスポートを行わず、タイムゾーン変換・取得処理はすべて `core.timezone` パッケージから直接インポートして呼び出すアーキテクチャに統一。

### 5.3. `src/web/gateway/handlers.py` イントロスペクション連携
- `_introspect_database_metrics` 内の `arxiv_db_info` および `_introspect_generic_database` の返却オブジェクトに、設定されたタイムゾーンメタデータを統合。

---

## 6. テスト設計と検証手順 / Test Plan & Verification Procedures
新規テストファイル [tests/test_settings_timezone.py](../../tests/test_settings_timezone.py) を作成し、以下を網羅:
1. **設定値・定数テスト**:
   - `TIME_ZONE == "Asia/Tokyo"`, `USE_TZ is True`, `DATABASE_TIME_ZONE == "UTC"`, `DISPLAY_TIME_ZONE == "Asia/Tokyo"` の検証。
   - `DATABASES` の全エントリ（`default` 含む全6スコープ）に対するメタデータ取得検証。
2. **変換機能テスト (`to_display_timezone` & `to_storage_utc`)**:
   - UTC aware datetime から JST への +9時間変換。
   - Naive datetime に対する UTC 仮定および変換。
   - ISO 8601 文字列（`"2026-09-18T00:00:00Z"`, `"2026-09-18T09:00:00+09:00"` 等）の正確な相互変換。
   - UNIX エポック秒（整数および浮動小数点数）からの変換。
3. **フォーマット出力テスト (`format_display_datetime`)**:
   - JST/UTC フォーマット文字列出力の整合性検証。
4. **異常系・セキュリティ境界値テスト**:
   - 不正な日付文字列（`"invalid-date"`）に対する `ValueError` 送出。
   - 巨大エポック値（オーバーフロー）に対する適切な例外送出。
   - 未知のタイムゾーン名に対するフォールバック動作。
5. **Gateway イントロスペクション検証**:
   - `get_database_metadata()` が `time_zone`, `use_tz`, `display_time_zone` を正しく返却すること。
6. **パッケージ直接インポート検証**:
   - `core.timezone` および `core.settings` からの直接インポート動作検証（`settings.py` からの再エクスポートに依存しないことの検証）。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `src/settings.py` に `TIME_ZONE = "Asia/Tokyo"`, `USE_TZ = True`, `DATABASE_TIME_ZONE = "UTC"`, `DISPLAY_TIME_ZONE = "Asia/Tokyo"` が直接定数として定義されていること
- [x] `src/settings.py` の `DATABASES` 辞書から重複したタイムゾーン記述が排除され、`get_database_metadata()` 経由で一元的にメタデータが付与されること
- [x] `src/core/timezone/` パッケージが新設され、タイムゾーン変換関数群（`to_display_timezone`, `to_storage_utc`, `format_display_datetime`, `get_zoneinfo`, `get_timezone`, `is_use_tz` 等）が実装されていること
- [x] `src/settings.py` からのタイムゾーン関数再エクスポートを廃止し、`core.timezone` パッケージからの直接呼び出しに統一されていること
- [x] `src/core/settings/` パッケージが新設され、設定・DBイントロスペクションユーティリティが実装されていること
- [x] 各種入力形式（UTC aware datetime, naive datetime, ISO 8601 文字列, UNIX epoch秒）に対応していること
- [x] 外部依存ゼロ（Python 3.9+ 標準ライブラリのみ）で動作すること
- [x] `tests/test_settings_timezone.py` の全27テストが 100% パスすること (`pytest tests/test_settings_timezone.py`)
- [x] `make py_compile`, `isort`, `black`, `flake8`, `xenon` (CC <= 5, Grade A), `mypy --strict` を 100% パスすること
- [x] すべての社内ドキュメント・リンクが相対パス（`../../`）で記述され、絶対パス参照が 0 件であること


