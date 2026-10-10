---
ID: 504
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] Implement Portable C / WebAssembly Backend via Low-Level IR for ULisp (ID: 504)

## 1. 概要 / Summary
Issue #502 で導入された低レベルIR（LIR: Low-level IR, `ulisp/passes/06_lir.scm`）を入力とし、ターゲット機械非依存の C 言語コード（ANSI C99）へトランスパイルする **Portable C / WebAssembly バックエンド (`ulisp/passes/07_backend_c.scm`)** を実装した。

生成された C コードは GCC / Clang を通じたあらゆる OS・CPU への移植（x86-64, AArch64, RISC-V 等）を可能にし、さらに Emscripten や `clang --target=wasm32` を経由した WebAssembly（Wasm）バイナリへのビルドを実現する。
また、C トランスパイルパスの単体テスト（Pass 7b）および出力 C コードの GCC/Clang コンパイル・実行回帰テストスイート（`ulisp/test_c.sh`）を網羅的に整備した。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §3 (言語機能と低レイヤコード生成仕様), §4 (フェーズ別コンパイラ設計), §6 (マルチターゲットバックエンド)
- **DSN-31**: §3.2 (Backend B: ULisp AOT Native Backend & Portable Codegen)
- **先行 Issue**: #502 (Introduce Low-Level IR and Decouple Backend Codegen), #500 (Metacircular Macro Expander)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [docs/issues/closed/504-implement-ulisp-c-and-wasm-backend-via-lir.md](504-implement-ulisp-c-and-wasm-backend-via-lir.md): 本 Issue 仕様書
- [x] [ulisp/passes/07_backend_c.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_c.scm): 新設された LIR $\to$ ANSI C99 トランスパイルバックエンド
- [x] [ulisp/passes/08_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/08_driver.scm): ターゲット切り替えディレクティブ（`!target c` / `x86_64`）およびバックエンド呼び出し
- [x] [ulisp/tests/test_passes.scm](file:///workspace/arxiv-security-papers/ulisp/tests/test_passes.scm): Pass 7b (C Backend) 単体テスト群の追加 (全 64 テスト PASS)
- [x] [ulisp/test_c.sh](file:///workspace/arxiv-security-papers/ulisp/test_c.sh): C 出力 E2E 回帰テストスイート (`gcc -Wall -Wextra -Werror -O2`, 全 42 テスト PASS)
- [x] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): `PASSES_LIB` への `07_backend_c.scm` 追加および `test_c`, `run_c_42` ターゲット新設
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳のステータス更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/504-implement-ulisp-c-and-wasm-backend-via-lir`

1. **LIR から ANSI C99 構文へのマッピング設計 (`ulisp/passes/07_backend_c.scm`)**:
   - **仮想レジスタとスタック**:
     - 64bit レジスタ: `static uint64_t reg_rax, reg_rdx, reg_rcx, reg_r10, reg_rdi;` (`ULISP_UNUSED` アノテーション付き)
     - ヒープポインタ (`%r12`): `static char *reg_r12;`
     - スタックポインタ (`%rsp`): `static char *reg_rsp;`
     - スキームスタック領域: `static char stack_mem[64 * 1024 * 1024];`
     - 比較レジスタ: `static uint64_t cmp_s1, cmp_s2;`
   - **LIR 全 29 命令のマッピング**:
     - `%label lbl`: `lbl:;`
     - `%jump lbl`: ラベルシンボルの場合は `goto lbl;`、レジスタ（`%rdx`）の場合は `((void (*)(void))(uintptr_t)reg_rdx)(); return;`（末尾呼び出し最適化 TCO）
     - `%jump-if-false reg lbl`: `if (reg == 0x2F) goto lbl;`
     - `%jump-if-zero lbl`: `if (cmp_s1 == cmp_s2) goto lbl;`
     - `%return`: `return;`
     - `%mov dst src`: `dst = src;`（ポインタ/整数変換の型キャストケア）
     - `%load dst base offset`: `dst = *(uint64_t *)((char *)(uintptr_t)base + offset);`
     - `%store base offset src`: `*(uint64_t *)((char *)(uintptr_t)base + offset) = (uint64_t)src;`
     - `%store-byte base offset src`: `*(uint8_t *)((char *)(uintptr_t)base + offset) = (uint8_t)src;`
     - `%load-byte-zx dst base offset`: `dst = (uint64_t)(*(uint8_t *)((char *)(uintptr_t)base + offset));`
     - `%add`, `%sub`: `dst += src;`, `dst -= src;`
     - `%neg`: `dst = (uint64_t)(-(int64_t)dst);`
     - `%imul`: `dst = (uint64_t)((int64_t)dst * (int64_t)src);`
     - `%cqo`: `/* no-op in C */`
     - `%idiv`: `reg_rax = (uint64_t)((int64_t)reg_rax / (int64_t)reg_rcx);`
     - `%inc`: `dst++;`
     - `%shl`, `%shr`, `%sar`: ビットシフト代入
     - `%bit-and`, `%bit-or`, `%bit-xor`: ビット論理演算代入
     - `%cmp s1 s2`: `cmp_s1 = s1; cmp_s2 = s2;`
     - `%set-boolean reg cc`: 条件判定に基づき `0x6F` (`#t`) または `0x2F` (`#f`) を代入
     - `%alloc dst bytes tag`: `dst = ((uint64_t)(uintptr_t)reg_r12) + tag; reg_r12 += bytes;`
     - `%code-ref dst lbl`: `dst = (uint64_t)(uintptr_t)lbl;`
     - `%str-ref dst lbl`: `dst = ((uint64_t)(uintptr_t)lbl) + 3;`
     - `%c-call func shift`: ランタイム関数（`ulisp_read_char`, `ulisp_peek_char`, `ulisp_write_char`）の呼び出しとフレームシフト
     - `%call-closure shift`: クロージャ呼び出し間接関数ポインタ実行 (`reg_rsp -= (shift + 8); call; reg_rsp += (shift + 8);`)
   - **関数プロローグ / エピローグ**:
     - リフトされた各 `%lir-function` を `static void func_label(void)` として出力。
     - エントリポイント `uint64_t scheme_entry(char *heap_base)` を定義し、`reg_r12 = heap_base; reg_rsp = stack_mem + sizeof(stack_mem) - 1024;` で初期化後、メイン処理を実行して `return reg_rax;`。
   - **静的データセクション**:
     - 文字列リテラルを `static const char str_X[] = "...";` として定義。

2. **コンパイラパイプラインとの統合 (`08_driver.scm`, `Makefile`)**:
   - `08_driver.scm` で `(!target c)` ディレクティブによる C バックエンド自動選択をサポート。
   - `ulisp/Makefile` の `PASSES_LIB` に `passes/07_backend_c.scm` を追加。

3. **単体テストおよび回帰テストの拡充**:
   - `ulisp/tests/test_passes.scm`: Pass 7b 単体テストを追加（全 64 テスト PASS）。
   - `ulisp/test_c.sh`: C 出力コードを `gcc -O2 -Wall -Wextra -Werror` でビルドし、算術・論理・条件分岐・ペア・クロージャ・再帰・マクロ展開済みコードが 100% 正しく動作することを検証（全 42 テスト PASS）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/passes/07_backend_c.scm` が LIR から警告のない規格準拠 ANSI C コードを正しく出力すること。
- [x] `make -C ulisp test_passes` に Pass 7b テストが追加され、全テストが 100% PASS すること。
- [x] C バックエンドで出力された C ソースコードが `gcc -O2 -Wall -Wextra -Werror` でビルド可能であり、正常動作すること (`test_c.sh` 全 42 テスト PASS)。
- [x] 既存の全テスト（`test_passes`, `test.sh`, `bootstrap.sh`）および品質ゲート（`make check_format`, `make py_compile`）を 100% パスすること。
- [x] Issue 台帳およびドキュメントが整合していること。
