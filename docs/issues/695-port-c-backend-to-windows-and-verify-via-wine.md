---
ID: 695
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] ULisp Portable C99 バックエンドの Windows (MinGW/MSVC) 移植と Wine 実行検証 (ID: 695)

## 1. 概要 / Summary
Pass 160（`ulisp/backend/160_backend_c.scm`）による ANSI C99 出力を Windows プラットフォーム（MinGW-w64 / MSVC）に適合させる。
Windows における I/O 規約（標準入出力のバイナリモード強制 `_setmode`、改行文字 `\r\n` の透過処理、`VirtualAlloc` または `malloc` によるヒープ初期化）を C 出力ランタイムに反映し、MinGW でビルドした `.exe` が Wine 上で Scheme の全基本テストをパスすることを実証する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §2.1 (Tagged Pointer メモリモデル), §3 (言語機能と低レイヤコード生成仕様)
- **関連 Issue**: #504 (Portable C Backend via LIR), #543 (Fix C Backend Syntax Error), #694 (MinGW & Wine Environment)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm): Windows 向けプリプロセッサ分岐およびメモリ確保・I/O 適合
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm): Windows 向け C トランスパイルおよびクロスビルドコマンドの統合
- [ ] [ulisp/tests/test_c_backend_windows.scm](../../ulisp/tests/test_c_backend_windows.scm): Windows (Wine) 向け検証テストスイート

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/695-port-c-backend-to-windows`

1. Windows 環境向け C コード生成ヘッダーの拡充：
   - `#ifdef _WIN32` での `<io.h>`, `<fcntl.h>`, `<windows.h>` のインクルード。
   - `_setmode(_fileno(stdin), _O_BINARY)` による CR/LF 破壊の防止。
   - `VirtualAlloc` またはアライメント確保済み `malloc` による 16MB ヒープ初期化。
2. `ulisp` コンパイラドライバに Windows 向けターゲットオプション（`--target=c-windows` 等）を追加。
3. `x86_64-w64-mingw32-gcc -O2` によるコンパイルと `wine64` での自動テスト実行。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 出力された C コードが MinGW-w64 でコンパイルエラー・警告 0 件でビルドできること。
- [ ] 生成された Windows 向け実行バイナリが Wine 上で Scheme の算術・クロージャ・ペア・I/O を正常に実行できること。

