---
ID: 471
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] R7RS 深層リストアクセサおよび (scheme cxr) ライブラリの実装 (ID: 471)

## 1. 概要 / Summary

R7RS-small (Revised^7 Report on the Algorithmic Language Scheme) 第 7.1.1 節および第 6.4 節に準拠し、3段および4段の合成リストアクセサ計 24 手続き、ならびに標準ライブラリ `(scheme cxr)` を ILISP に実装する：

1. **3段合成アクセサ (8手続き)**:
   - `caaar`, `caadr`, `cadar`, `caddr`, `cdaar`, `cdadr`, `cddar`, `cdddr`
2. **4段合成アクセサ (16手続き)**:
   - `caaaar`, `caaadr`, `caadar`, `caaddr`, `cadaar`, `cadadr`, `caddar`, `cadddr`,
   - `cdaaar`, `cdaadr`, `cdadar`, `cdaddr`, `cddaar`, `cddadr`, `cdddar`, `cddddr`
3. **標準ライブラリ `(scheme cxr)` の登録**:
   - `(import (scheme cxr))` による 24 手続きのモジュールインポート対応。
   - `(scheme base)`, `(scheme time)`, `(scheme process-context)`, `(scheme complex)` に続く R7RS 標準ライブラリの完備。
4. **高速プリミティブ実装と型安全保護**:
   - `ilisp/env.py` で Python レベルの直接属性アクセス (`.car`, `.cdr`) による最適化プリミティブとして定義。
   - ペア以外の不正なオブジェクトに対する型エラー検証。
   - `ilisp/syntax.py` の `core_forms` への登録によるマクロ衛生性の保護。

---

## 2. トレーサビリティ / Traceability

- **R7RS 6.4 Pairs and lists**:
  - 2段アクセサ (`caar`, `cadr`, `cdar`, `cddr`) は `(scheme base)` に所属。
  - 3段および4段の全 24 アクセサは `(scheme cxr)` に所属。
- **R7RS 7.1.1 Standard Libraries**:
  - `(scheme cxr)`: 全 24 アクセサ (`c[ad]{3,4}r`) をエクスポート。
- **ILISP 仕様マトリクス**:
  - [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ilisp/env.py](../../ilisp/env.py): 24 個の cxr プリミティブ関数の定義および `make_initial_env` 辞書へのバインディング登録
- [x] [ilisp/module.py](../../ilisp/module.py): `(scheme cxr)`、`(scheme complex)`、`(scheme time)`、`(scheme process-context)` ライブラリ定義の登録
- [x] [ilisp/syntax.py](../../ilisp/syntax.py): `core_forms` への 24 識別子の登録
- [x] [ilisp/stdlib/base.ilisp](../../ilisp/stdlib/base.ilisp): 必要に応じた同期
- [x] [tests/ilisp/test_cxr.py](../../tests/ilisp/test_cxr.py): 全 24 アクセサの正常系・多段木構造抽出・異常系・ライブラリ import テスト
- [x] [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md): 準拠マトリクス更新 (`(scheme cxr)` 🟢 100% 準拠化、機能数更新)
- [x] [docs/issues/README.md](README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/471-implement-r7rs-scheme-cxr-accessors`

1. **`ilisp/env.py` における cxr プリミティブ群の実装**:
   - `_cxr(p: Any, pattern: str) -> Any` ヘルパー関数の作成。
   - 各アクセサをクロージャまたは専用関数として高効率に定義。
   - `caaar` 〜 `cddddr` の 24 関数を生成し、`env.bindings` に登録。
2. **`ilisp/module.py` におけるライブラリ登録**:
   - `(scheme cxr)` を `LibraryRegistry._init_standard_libraries` に登録。
   - あわせて `(scheme complex)`, `(scheme time)`, `(scheme process-context)` の登録も完備。
3. **`ilisp/syntax.py` における予約語・コア形式登録**:
   - 24 個の cxr 手続き名を `core_forms` に登録。
4. **単体テスト (`tests/ilisp/test_cxr.py`)**:
   - 3段アクセサ 8 個のテスト（四分木・二分木データ）。
   - 4段アクセサ 16 個のテスト。
   - `(import (scheme cxr))` によるインポートテスト。
   - 非ペアに対する型エラー発生テスト。
5. **品質ゲートとドキュメント同期**:
   - `pytest`, `flake8`, `mypy --strict ilisp`。
   - `SPEC_R7RS.md` の更新。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] 3段合成アクセサ 8 個 (`caaar` 〜 `cdddr`) が正しく機能すること
- [x] 4段合成アクセサ 16 個 (`caaaar` 〜 `cddddr`) が正しく機能すること
- [x] `(import (scheme cxr))` で 24 個のアクセサが正しくインポートできること
- [x] 新規単体テストが全件 PASS すること
- [x] 既存の全 331 件のテストが 100% PASS すること
- [x] `flake8` 0 警告、`mypy --strict ilisp` 0 エラーであること
- [x] `ilisp/docs/SPEC_R7RS.md` が更新され、`(scheme cxr)` が Fully Supported になること
