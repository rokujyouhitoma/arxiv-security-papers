---
ID: 367
種別: Refactor
優先度: Medium
ステータス: Closed
---

# [REFACTOR] `src/settings.py` の後方互換レイヤー (`__getattr__`) の撤去と `core.settings` への参照一本化 (ID: 367)

## 1. 概要 / Summary

`src/settings.py` の末尾には、設定モジュールを `src/core/settings/` へ分割した際に過渡期措置として設置された動的フォールバック `__getattr__` が残存していた：
```python
def __getattr__(name: str) -> Any:
    """Backward compatibility fallback for functions migrated to core.settings."""
    if name in (
        "get_database_scopes",
        "get_all_configured_databases",
        "get_database_metadata",
        "get_table_scope_from_settings",
        "get_table_type_from_settings",
    ):
        import core.settings as _core_settings
        return getattr(_core_settings, name)
    raise AttributeError(...)
```

この動的委譲ハックは、静的型チェッカー（mypy）や IDE による補完・検証の精度を低下させ、コードの追跡性を損ねていた。
本 Issue では、プロジェクト全体で `src.settings` 経由でこれらの関数を呼び出している箇所を正規の `src.core.settings` 直接インポートに置き換え、`__getattr__` を撤去して設定アーキテクチャの多重構造を一本化した。

---

## 2. トレーサビリティ / Traceability

- 関連 Issue: [Issue 361: レガシー重複台帳 processed_papers.json の完全廃止](361-deprecate-and-purge-legacy-processed-papers-json.md)
- 関連コード: [src/settings.py](../../src/settings.py), [src/core/settings/](../../src/core/settings/)
- 関連品質ゲート: `make static_analysis` (mypy strict compliance), `make verify_quality`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 設定モジュール
- [x] `src/settings.py` (`__getattr__` 削除)
- [x] `src/core/settings/`

### 呼び出し元モジュール
- [x] `src/web/gateway/`
- [x] `src/cli/commands/`
- [x] `src/database/`

### テストスイート
- [x] `tests/test_settings_timezone.py`

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/367-deprecate-settings-getattr`

1. **呼び出し元の調査**:
   - `get_database_scopes`, `get_all_configured_databases`, `get_database_metadata`, `get_table_scope_from_settings`, `get_table_type_from_settings` が `src.settings` 経由で import されている全箇所を grep で特定。
2. **正規インポートへの置換**:
   - すべて `from src.core.settings import ...` または `import src.core.settings as ...` に書き換え。
3. **`__getattr__` の撤去**:
   - `src/settings.py` から `__getattr__` 関数を完全に削除。
4. **型検査とテスト検証**:
   - `make static_analysis` を実行し、mypy が型エラーなく通過することを確認。
   - `make test` を実行。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `src/settings.py` から `__getattr__` フォールバックが完全に削除されていること。
- [x] プロジェクト全体で設定関数のインポートが正規の `core.settings` に統一されていること。
- [x] 静的型検査（mypy）およびテストスイートが 100% PASS すること。
