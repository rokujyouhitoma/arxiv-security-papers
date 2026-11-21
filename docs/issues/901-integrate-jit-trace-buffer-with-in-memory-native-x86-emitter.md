---
ID: 901
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Integrate JIT Trace Buffer with In-Memory Native x86 Emitter (ID: 901)

## 1. 概要 / Summary
[[DSN-33-05]](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md) 第 6 章に基づき、最適化済み LIR トレースからインメモリ W^X 実行可能バッファ（`mprotect` / Raw Syscall）へのネイティブ機械語直接アセンブルおよび JIT 実行トランポリン配線を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-05] ULisp 内因的メタトレーシング JIT アーキテクチャ包括設計書 (第6章 インメモリ機械語アセンブラと実行バッファ)](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md)
  - [[DSN-33-02] ULisp 多言語フロントエンド ＆ 型付き機械語 LIR 設計書](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md)
  - [[DSN-33-07] ULisp Zero-libc / Freestanding Pure Scheme ベアメタルランタイム包括設計書](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/jit/runtime/jit_buffer.scm](../../ulisp/jit/runtime/jit_buffer.scm)
- [ ] [ulisp/backend/144a_x86_assembler.scm](../../ulisp/backend/144a_x86_assembler.scm)
- [ ] [ulisp/jit/bridge/to_lir.scm](../../ulisp/jit/bridge/to_lir.scm)
- [ ] [ulisp/tests/test_jit_buffer.scm](../../ulisp/tests/test_jit_buffer.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/901-integrate-jit-trace-buffer-with-in-memory-native-x86-emitter`

1. `jit_buffer.scm` において、`mmap` で確保した実行可能メモリ領域への命令バイト書き込みと `mprotect`（W^X 整合）管理を実装。
2. `144a_x86_assembler.scm` を拡張し、LIR トレースからメモリバッファへ直接機械語オペコードを出力するインメモリエンコーダを実装。
3. Scheme 側から JIT 機械語アドレスを関数ポインタとして直接呼び出すインラインアセンブリ・トランポリンを配線。
4. 単体テスト `test_jit_buffer.scm` を作成し、実行時コンパイルされたトレースがネイティブ実行されることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 最適化された LIR トレースがインメモリ実行可能バッファへ直接アセンブルされること。
- [ ] JIT コンパイルされたネイティブコードが安全に実行され、正しい計算結果を返すこと。
- [ ] `make -C ulisp test_jit_buffer` が PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
