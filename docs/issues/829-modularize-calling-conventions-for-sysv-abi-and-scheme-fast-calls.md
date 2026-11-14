---
ID: 829
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] 呼出規約 (Calling Convention) の多重化・モジュール分離とゼロオーバーヘッド C-FFI の実現 (ID: 829)

## 1. 概要 / Summary
LIR およびバックエンドにおいて、Scheme 内部の高速関数呼出規約（全レジスタ引数渡し、継続渡し、スタック割り当て等）と、System V AMD64 ABI 規約（整数レジスタ `rdi..r9`、浮動小数点レジスタ `xmm0..xmm7`、スタック渡し、可変長引数の `al` 設定、callee-saved 退避、16 バイトスタックアライメント）を独立したモジュールとして抽象化・分離する。
これにより、Scheme から外部 C 関数や musl/libc を直接呼び出すゼロオーバーヘッド FFI（Foreign Function Interface）を実現するとともに、C 言語フロントエンドからネイティブ関数を相互運用するための確固たる基盤を築く。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §2 (C2: SysV ABI, E5: SysV 準拠呼出/入口/出口, E6: 関数ポインタ間接呼出)
- **関連 Issue**: #810 (Safepoint Exclusion), #826 (Typed LIR)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/calling_convention.scm](../../ulisp/compiler/calling_convention.scm): 呼出規約の抽象データ型および ABIInfo 分配器
- [ ] [ulisp/backend/140_backend_x86.scm](../../ulisp/backend/140_backend_x86.scm): SysV ABI 準拠プロローグ/エピローグ生成
- [ ] [ulisp/compiler/120_ast_to_lir.scm](../../ulisp/compiler/120_ast_to_lir.scm): 外部関数呼出ノードへの ABI 属性付与
- [ ] [ulisp/tests/test_sysv_abi_calls.scm](../../ulisp/tests/test_sysv_abi_calls.scm): SysV 相互呼出（整数/浮動小数点/可変長）テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/829-modular-calling-conventions-sysv-abi`

1. LIR 関数ノードへの属性拡張：
   - `(:calling-convention <'sysv | 'scheme-internal>)`
   - `(:varargs #t/#f)`
2. SysV ABIInfo ディスパッチャの設計：
   - 引数型のリスト（`i64`, `f64`, `struct` 等）を受け取り、各引数の格納先（`reg:rdi`, `reg:xmm0`, `stack:offset`）を算出する純粋関数の提供。
   - 戻り値の格納先（`rax`, `rdx`, `xmm0`, 隠蔽ポインタ戻し）の計算。
3. 可変長引数およびスタック整列の保証：
   - `call` 発行直前における 16 バイトアライメント調整命令（`and rsp, -16` またはスタックオフセット計算）の自動挿入。
   - 浮動小数点引数個数を `al` レジスタへセットするロジックの実装。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Scheme から `printf` 等の SysV 可変長 C 関数を直接呼び出し、浮動小数点数および文字列が正しく渡せること。
- [ ] C 言語互換の入口・出口を持つ関数が生成され、ホストの `gcc`/`clang` でコンパイルされたコードから正しく呼び出せること。
- [ ] 単体テスト `test_sysv_abi_calls.scm` がパスすること。
