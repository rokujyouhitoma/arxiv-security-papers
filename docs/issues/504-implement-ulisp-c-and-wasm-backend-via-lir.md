---
ID: 504
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] Implement Portable C / WebAssembly Backend via Low-Level IR for ULisp (ID: 504)

## 1. 概要 / Summary
Issue #502 で導入される低レベルIR（LIR: Low-level IR）をターゲット機械非依存の C 言語コード（ANSI C99）へトランスパイルする **Portable C / WebAssembly バックエンド** を実装する。
生成された C コードは、GCC / Clang を通じたあらゆる OS・CPU への移植を可能にするほか、Emscripten / clang `--target=wasm32` を経由して WebAssembly（Wasm）バイナリへのビルドを実現する。
また、C トランスパイルパスの単体テストおよび出力 C コードのコンパイル実行テストを網羅的に拡充する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §3 (言語機能と低レイヤコード生成仕様), §4 (フェーズ別コンパイラ設計)
- **DSN-31**: §3.2 (Backend B: ULisp AOT Native Backend)
- **先行 Issue**: #502 (Introduce Low-Level IR and Decouple Backend Codegen)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/07_backend_c.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_c.scm): 新設する LIR $\to$ C言語トランスパイルバックエンド
- [ ] [ulisp/passes/08_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/08_driver.scm): `--target=c` オプションの追加
- [ ] [ulisp/tests/test_backend_c.scm](file:///workspace/arxiv-security-papers/ulisp/tests/test_backend_c.scm): C バックエンド単体テスト
- [ ] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): C トランスパイルおよび Wasm ビルドターゲットの追加
- [ ] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/504-implement-ulisp-c-and-wasm-backend-via-lir`

1. **LIR から C 言語構文へのマッピング**:
   - 各 `%function` を C 言語の `static uint64_t func(uint64_t self, ...)` に変換。
   - 基本ブロックとラベルを C の `goto label;` またはトランポリンループへマッピング。
   - `%mov`, `%add`, `%load`, `%store` を直接的な C 代入文およびポインタ参照に展開。
2. **WebAssembly / Wasm32 互換性**:
   - ポインタサイズを抽象化し、32bit/64bit 双方でビルド可能な C コードを出力。
3. **パス単体テストの拡充**:
   - LIR 命令列から C コード文字列への構文生成テスト。
   - `gcc -O2` での C 出力コンパイル・実行による回帰テスト。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `07_backend_c.scm` が LIR 命令列から完全で警告のない ANSI C コードを出力すること。
- [ ] 出力された C コードが GCC/Clang でコンパイルされ、`test.sh` 相当の機能が 100% 動作すること。
- [ ] C バックエンド向けのパス単体テストが整備され、100% PASS すること。
- [ ] すべての既存品質ゲート（`make check_format`, `make py_compile`）を通過すること。
