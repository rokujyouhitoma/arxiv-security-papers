---
ID: 562
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-10-18
---

# [FEAT] R7RS 標準 16 ライブラリ定義 (*.sld) の物理配置および export/include/import 機構の統合 (ID: 562)

## 1. 概要 / Summary
Issue #561 で策定された「パターンB（ライブラリ宣言 `.sld` によるメタデータ管理）＋セクションコメント（`;; §X.Y.Z`）記法」のハイブリッド標準規約に基づき、R7RS-small 仕様の第5.6.1節および第7章（Standard Libraries）に規定される標準 16 ライブラリ（`(scheme base)`, `(scheme write)`, `(scheme read)`, `(scheme char)`, `(scheme time)`, `(scheme lazy)` 等）の `*.sld`（Scheme Library Definition）ファイルを `ulisp/lib/scheme/` 配下に体系的に配置する。
あわせて、コンパイラパス [Pass 010 (Library Expander)](../../ulisp/passes/010_library.scm) による `define-library` 内の `export`、`import`、`include` 構文の解決機構と結合検証を行い、標準ライブラリのモジュール単位でのインポートおよび依存解決が正常に AOT コンパイル可能であることを保証する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small (Revised^7 Report on the Algorithmic Language Scheme - Small Language)
    - Section 5.6: Libraries (5.6.1 Library Syntax, 5.6.2 Library example)
    - Section 7: Standard Libraries (`(scheme base)`, `(scheme case-lambda)`, `(scheme char)`, `(scheme complex)`, `(scheme cxr)`, `(scheme eval)`, `(scheme file)`, `(scheme inexact)`, `(scheme lazy)`, `(scheme load)`, `(scheme process-context)`, `(scheme read)`, `(scheme repl)`, `(scheme time)`, `(scheme write)`, `(scheme r5rs)`)
  - DSN-33 (ULisp 包括設計仕様書)
  - 関連 Issue:
    - Issue #561: R7RS ライブラリメタデータ管理規約（パターンB＋コメントハイブリッド）の策定と準拠表実装リンクの網羅的整備
    - Issue #548: R7RS ライブラリ構文 (define-library / import) の静的脱糖・フラット名前空間インクルード機構の実装
    - Issue #554: ULisp メタコンパイラの R7RS-small および R7RS-large 仕様準拠状況一覧ドキュメントの策定

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `ulisp/lib/scheme/` ディレクトリ新設
- [x] `ulisp/lib/scheme/base.sld`
- [x] `ulisp/lib/scheme/write.sld`
- [x] `ulisp/lib/scheme/read.sld`
- [x] `ulisp/lib/scheme/char.sld`
- [x] `ulisp/lib/scheme/time.sld`
- [x] `ulisp/lib/scheme/lazy.sld`
- [x] `ulisp/lib/scheme/file.sld`
- [x] `ulisp/lib/scheme/process-context.sld`
- [x] `ulisp/lib/scheme/cxr.sld`
- [x] `ulisp/lib/scheme/r5rs.sld`
- [x] [ulisp/passes/010_library.scm](../../ulisp/passes/010_library.scm) (ライブラリパス検索および sld インクルード処理)
- [x] [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md) (16標準ライブラリの内部実装ファイルリンクを `.sld` に同期)
- [x] [docs/issues/closed/562-implement-r7rs-standard-library-definitions-sld.md](562-implement-r7rs-standard-library-definitions-sld.md) (本 Issue 定義書)
- [x] [docs/issues/README.md](README.md) (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/562-implement-r7rs-standard-library-definitions-sld`

1. **ディレクトリ構造と命名規則の策定**:
   - `ulisp/lib/scheme/` ディレクトリを作成し、`(scheme <name>)` に対応する `<name>.sld` を配置。
   - 例: `(scheme base)` -> `ulisp/lib/scheme/base.sld`。
2. **`.sld` ヘッダおよびエクスポート定義**:
   - Issue #561 で策定したメタデータ規約に準拠。
3. **`010_library.scm` とのインポートパス結合**:
   - 16 標準ライブラリすべての組み込み認識対応。
4. **統合テスト・AOT コンパイル検証**:
   - `test_library` にて全 16 標準ライブラリの判定テスト、x86-64 / C の AOT コンパイル・バイナリ実行が通過。
5. **仕様準拠表の更新**:
   - `ulisp/docs/r7rs_specification_compliance.md` の「1.4 標準 16 ライブラリ」表の内部実装ファイル列を更新された `.sld` パスにリンク。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/lib/scheme/` 配下に R7RS 標準ライブラリ定義 `*.sld` ファイル群が配置されていること。
- [x] 各 `.sld` ファイルが Issue #561 策定のメタデータヘッダおよび `export`, `include` 定義を備えていること。
- [x] コンパイラが `(import (scheme ...))` 宣言を正常にパースし、対応する `.sld` から必要な手続きを読み込んで AOT コンパイルを完了できること。
- [x] `ulisp/docs/r7rs_specification_compliance.md` の第1.4節準拠表が `.sld` への相対リンクに更新されていること。
- [x] `make py_compile && make static_analysis` がエラー 0 件で通過すること。
- [x] `docs/issues/README.md` 台帳に本 Issue 562 が正しく登録・追跡されていること。
