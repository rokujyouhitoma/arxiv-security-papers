# Issue #455: R7RS モジュール機構 (define-library, import, export) の実装

## 1. 概要 (Overview)
R7RS-small (Section 5.6 "Libraries" & Section 7 "Libraries") では、独立した名前空間のカプセル化と安全な再利用を目的としてライブラリ機構（`define-library`）が規定されている。
これまでの ILISP は、単一のグローバル環境と `load` によるスクリプト読込のみをサポートしていた。

本 Issue では、R7RS-small 規格に準拠したモジュール機構（`define-library`, `export`, `import`）およびインポート修飾子（`only`, `except`, `prefix`, `rename`）を実装し、組み込み標準ライブラリ（`(scheme base)`, `(scheme write)`, `(ilisp python)` 等）とユーザー定義ライブラリの厳格な分離とカプセル化を実現する。

---

## 2. 目的とゴール (Goals)
1. **`define-library` 構文のサポート**:
   - `(define-library (name ...) decl ...)` のパースと登録
   - ライブラリ内での独立したレキシカル環境の構築（非エクスポート識別子の完全な隠蔽）
   - 宣言節のサポート: `(export ...)`, `(import ...)`, `(begin ...)`
2. **`export` 構文のサポート**:
   - 識別子の公開: `(export id ...)`
   - エクスポート時リネーム: `(export (rename id1 id2) ...)`
3. **`import` 構文およびインポート修飾子のサポート**:
   - ライブラリ参照: `(import (scheme base))`
   - フィルタリングと名前空間修飾:
     - `(only import-set id ...)`: 指定した識別子のみインポート
     - `(except import-set id ...)`: 指定した識別子を除外してインポート
     - `(prefix import-set prefix-id)`: インポートする識別子に接頭辞を付与
     - `(rename import-set (orig-id new-id) ...)`: インポート時に識別子を改名
4. **ライブラリレジストリと組込ライブラリの提供**:
   - `LibraryRegistry` によるライブラリキャッシュ
   - 組込標準ライブラリの整備:
     - `(scheme base)`
     - `(scheme write)`
     - `(scheme load)`
     - `(ilisp python)`
5. **Tree-walk 評価器および Backend A コンパイラへの統合**:
   - `evaluator.py`: トップレベル `define-library`, `import` の評価
   - `compiler.py`: コンパイル時ライブラリ解決およびエクスポートシンボルの名前空間マッピング

---

## 3. 完了条件 (Definition of Done)
- [x] `ilisp/module.py` に `Library`, `LibraryRegistry`, `import_set` 解決ロジックが実装されている。
- [x] `define-library` により非公開シンボルが外部に漏洩せず、`export` されたシンボルのみが公開されることが保証されている。
- [x] `import` における `only`, `except`, `prefix`, `rename` 修飾子が正確に動作する。
- [x] 組込ライブラリ `(scheme base)`, `(scheme write)`, `(ilisp python)` が `(import ...)` 経由で利用可能である。
- [x] Tree-walk 評価器と Backend A (Python AST コンパイラ) の双方でモジュール機構が動作する。
- [x] `tests/ilisp/test_modules.py` に単体テストが追加され、全テストが 100% PASS すること（全 96 件完全通過）。
- [x] 静的解析（flake8, mypy --strict）をパスし、Issue 台帳を更新すること。

---

## 4. 実装結果サマリー (Implementation Summary)
- **R7RS ライブラリ基盤の実装 (`ilisp/module.py`)**:
  - `Library` クラス、`parse_library_name`、および大域 `LibraryRegistry`（組込ライブラリキャッシュ付）を構築。
  - 組込ライブラリ `(scheme base)`, `(scheme write)`, `(scheme load)`, `(ilisp python)` を標準初期化。
- **インポート修飾子エンジンの構築**:
  - `only`: 指定シンボルのみを透過抽出。
  - `except`: 指定シンボルを厳格に遮断。
  - `prefix`: 識別子群に接頭辞（例: `my:`）を付与して名前衝突を防止。
  - `rename`: `(orig new)` ペアによる明示的改名。
- **2 パス宣言処理によるカプセル化**:
  - `(import ...)` と `(begin ...)` を先に評価して独立環境 `lib_env` を満たしたのち、後続または先行する `(export ...)` を評価することで、宣言順序に依存しない安定したエクスポートと非公開シンボルの完全な隠蔽を達成。
- **評価器 & コンパイラへの統合**:
  - `evaluator.py`: `define-library` によるライブラリ登録と `import` によるターゲット環境への束縛注入。
  - `compiler.py` (Backend A): コンパイル時マクロ展開フェーズにおける `define-library` と `import` の先行評価および実行時 AST 透過パス。
- **品質・テスト検証**:
  - `tests/ilisp/test_modules.py`: 9 件の単体テストを追加。
  - ILISP 全 96 件のテストが 100% PASS、`flake8` / `mypy --strict` エラー 0 件を達成。
