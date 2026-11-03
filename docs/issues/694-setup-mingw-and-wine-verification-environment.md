---
ID: 694
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] MinGW-w64 および Wine を用いた Windows 向けクロスコンパイル・ローカル検証環境の構築 (ID: 694)

## 1. 概要 / Summary
ULisp のマルチ OS サポート（特に Windows / Win32 環境）を Linux ホスト開発環境上で実機レスかつ高速に検証可能とするため、MinGW-w64（`gcc-mingw-w64`）および Wine（`wine64`）を導入し、Windows 向け PE32+ 実行可能ファイルのクロスコンパイルとローカル実行テスト基盤を整備する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §4 (フェーズ別コンパイラ設計), §6 (検証およびテストアーキテクチャ)
- **関連 Issue**: #504 (Portable C Backend via LIR), #695 (Windows C99 Backend), #689 (QEMU Verification)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/Makefile](../../ulisp/Makefile): Windows 向けクロスコンパイル変数および Wine 実行ターゲットの追加
- [ ] [ulisp/test_wine_env.sh](../../ulisp/test_wine_env.sh): MinGW および Wine 疎通確認用テストスクリプト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/694-setup-mingw-wine-verification-environment`

1. ホスト環境への `gcc-mingw-w64-x86-64` および `wine64` パッケージの導入確認。
2. 最小の C プログラム（標準出力および終了ステータス返却）を `x86_64-w64-mingw32-gcc` で `.exe` にクロスコンパイル。
3. `wine64 ./minimal.exe` をヘッドレス（`WINEDEBUG=-all`）で実行し、正常な入出力および終了コード（42 等）が返ることを確認。
4. `Makefile` に `CROSS_CC_WIN64`, `WINE64` 変数を整備。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `x86_64-w64-mingw32-gcc --version` および `wine64 --version` が正常に実行できること。
- [ ] MinGW でビルドした Windows 向け PE/EXE バイナリが Linux ホスト上の Wine 経由でエラーなく実行・検証できること。

