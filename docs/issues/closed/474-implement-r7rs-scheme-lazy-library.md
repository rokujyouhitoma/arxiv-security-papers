---
ID: 474
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS (scheme lazy) 遅延評価ライブラリの独立モジュール化と完全準拠 (ID: 474)

## 1. 概要 / Summary
R7RS-small (Revised^7 Report on the Algorithmic Language Scheme) 4.2.5 および 7.1.1 で規定される `(scheme lazy)` 標準ライブラリを独立モジュールとして完全サポートする。
すでに実装済みの遅延評価構文・プリミティブ（`delay`, `delay-force`, `force`, `make-promise`, `promise?`）について、マクロ衛生性（`core_forms` への登録）、`ilisp/module.py` への `(scheme lazy)` 登録・エクスポート、個別インポート `(import (scheme lazy))` の検証、包括的テストスイートの作成、および `ilisp/docs/SPEC_R7RS.md` の準拠マトリクス更新を実施する。

---

## 2. トレーサビリティ / Traceability
- R7RS-small Section 4.2.5 (Delayed evaluation): `delay`, `delay-force`, `make-promise`, `promise?`, `force`
- R7RS-small Section 7.1.1 (Standard Libraries): `(scheme lazy)`
- [SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md): 遅延評価および `(scheme lazy)` ライブラリ仕様マトリクス

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ilisp/syntax.py](../../ilisp/syntax.py): `core_forms` への遅延評価識別子登録
- [x] [ilisp/module.py](../../ilisp/module.py): `LibraryRegistry` に `(scheme lazy)` の定義・エクスポート追加
- [x] [tests/ilisp/test_scheme_lazy.py](../../tests/ilisp/test_scheme_lazy.py): 新規テストスイート
- [x] [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md): 準拠状況の更新
- [x] [docs/issues/README.md](README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/474-implement-scheme-lazy`

1. **マクロ衛生性と識別子保護**:
   - `ilisp/syntax.py` の `core_forms` に `delay`, `delay-force`, `force`, `make-promise`, `promise?` を追加。
2. **ライブラリ登録**:
   - `ilisp/module.py` の `_register_builtin_libraries` に `(scheme lazy)` を追加。
   - `delay`, `delay-force`, `force`, `make-promise`, `promise?` を `base_env` からエクスポート。
3. **テストスイート実装**:
   - `tests/ilisp/test_scheme_lazy.py` を作成し、以下を検証:
     - `(import (scheme lazy))` 経由でのインポート
     - `delay` と `force` の基本メモ化（副作用が1度だけ評価されること）
     - `delay-force` による反復的末尾再帰遅延ストリーム（スタックオーバーフローなしのテスト）
     - `make-promise` による即時 Promise 化（Promise を渡したときの二重ラッピング防止）
     - `promise?` による型述語テスト
4. **仕様マトリクス更新**:
   - `ilisp/docs/SPEC_R7RS.md` の `(scheme lazy)` を Fully Supported (🟢 100%) に更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ilisp/syntax.py` に `(scheme lazy)` の識別子が登録されていること
- [x] `(import (scheme lazy))` が正常に動作し、`delay`, `force`, `delay-force`, `make-promise`, `promise?` が利用可能であること
- [x] `tests/ilisp/test_scheme_lazy.py` のテストがすべて PASS すること
- [x] 全テスト（354件以上）が PASS し、`flake8`、`mypy --strict ilisp` が 0 エラーであること
- [x] `ilisp/docs/SPEC_R7RS.md` の準拠ステータスが更新されていること

