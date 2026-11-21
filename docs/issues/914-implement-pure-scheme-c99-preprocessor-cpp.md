---
ID: 914
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 純粋 Scheme 製 C99 プリプロセッサ (CPP: #include / #define / ## / #if CTFE) の実装 (ID: 914)

## 1. 概要 / Summary
外部 `cc -E` に依存せず、純粋 Scheme で C99 プリプロセッサ（`ulisp/frontend_c/preprocessor.scm`）を実装する（Step S2 / T2）。Lua 5.x の `luaconf.h` や `lobject.h` で多用されるネストした関数形式マクロ、可変長マクロ（`__VA_ARGS__`）、トークン連結（`##`）、文字列化（`#`）、および `#if` 定数整数式評価（CTFE #825 連携）を正確に処理する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §3.1, §5.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §3.3, §4.1](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
- 前提基盤 Issue: #824 (Source Span), #825 (CTFE), #832 (Bignum), #913 (C99 Lexer)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/preprocessor.scm` (新規: CPP マクロ展開エンジン & `#include` リゾルバ)
- [ ] `ulisp/tests/test_c99_preprocessor.scm` (新規: プリプロセッサ単体テスト & `cc -E` オラクル突合テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/914-implement-pure-scheme-c99-preprocessor`

1. `-I` / `-D` / `-U` 設定と `#include "..."` / `#include <...>` のファイル探索・インクルードガード高速バイパス機構を実装する。
2. Dave Prosser の Blue-painted（`hide-set`）アルゴリズムに基づき、オブジェクトマクロ・関数マクロ・可変長引数（`...` / `__VA_ARGS__`）・`#` 文字列化・`##` トークン連結（自己再帰抑止付き）を実装する。
3. `#if` / `#elif` / `defined(...)` の定数整数式パーサ＆評価器を `eval_in_language.scm`（#825）および 64bit 整数演算（#832）を用いて実装し、`__LINE__`, `__FILE__`, `__STDC_VERSION__` 等の定義済みマクロを提供する。
4. ホストの `cc -E` をテストオラクルとして Lua ヘッダ群に対する出力一致検証を行う。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `#include`, `#define`, `#undef`, `#if`/`#ifdef`/`#ifndef`/`#else`/`#elif`/`#endif`, `#error`, `#pragma` が仕様通り動作すること。
- [ ] `#` 文字列化、`##` トークン連結、`__VA_ARGS__` および Blue-painted 自己参照抑止が正しく動作すること。
- [ ] Lua 5.x ヘッダのプリプロセス結果が `cc -E` のトークン列と意味的に一致すること。
