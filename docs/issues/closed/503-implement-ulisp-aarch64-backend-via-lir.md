---
ID: 503
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT] Implement AArch64 (ARM64) Backend via Low-Level IR for ULisp (ID: 503)

## 1. 概要 / Summary
Issue #502 で導入された低レベルIR（LIR: Low-level IR）をターゲット機械命令にマッピングし、**AArch64（ARM64 / Apple Silicon / AWS Graviton / Raspberry Pi）向けのネイティブコード生成バックエンド（`passes/07_backend_aarch64.scm`）** を実装する。
Scheme コンパイラ自身がマルチアーキテクチャ対応を果たすことで、x86-64 および Portable C に加えた主要 64bit RISC アーキテクチャでのネイティブ実行・クロスコンパイル・セルフホスティングの基盤を確立する。
本 Issue では、AAPCS64 呼び出し規約、16バイト SP アライメント保証、レジスタマッピング、末尾呼び出し最適化（TCO）、および単体テスト・ドライバ統合を行う。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §3 (言語機能と低レイヤコード生成仕様), §4 (フェーズ別コンパイラ設計), §6.1 (セルフホスティングパイプライン)
- **DSN-31**: §3.2 (Backend B: ULisp AOT Native Backend)
- **正典仕様書**: [ulisp/docs/lir_specification.md](file:///workspace/arxiv-security-papers/ulisp/docs/lir_specification.md)
- **先行 Issue**: #502 (Introduce Low-Level IR and Decouple Backend Codegen), #504 (Portable C / Wasm Backend via LIR)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/07_backend_aarch64.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_aarch64.scm): 新設する AArch64 アセンブリ生成バックエンド（`emit-aarch64`）
- [x] [ulisp/passes/08_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/08_driver.scm): ターゲット切り替えディレクティブ（`(!target aarch64)`）のサポート
- [x] [ulisp/runtime.c](file:///workspace/arxiv-security-papers/ulisp/runtime.c): AArch64 シグナルコンテキスト（`ucontext_t` / `REG_RIP` 対 `pc`）のマルチプラットフォーム対応
- [x] [ulisp/tests/test_passes.scm](file:///workspace/arxiv-security-papers/ulisp/tests/test_passes.scm): AArch64 パス単体テスト（Pass 7c: AArch64 Backend Codegen Tests）の追加
- [x] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): `PASSES_LIB` への `07_backend_aarch64.scm` 組み込みおよびテストターゲット拡充
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

---

## 4. アーキテクチャ設計・脅威モデル / Architecture & Threat Model

### 4.1 レジスタマッピングと AAPCS64 適合性
| LIR 抽象レジスタ | x86-64 物理 | AArch64 物理 | 役割 / ABI 規約 |
| :--- | :--- | :--- | :--- |
| `%rax` | `rax` | `x0` | 式の評価アキュムレータ、関数戻り値、C 呼出第1引数 |
| `%al` | `al` | `w0` | `%rax` / `x0` の下位バイト（文字・ブール値操作用） |
| `%rdx` | `rdx` | `x1` | 一時スクラッチレジスタ、除算剰余格納、C 呼出第2引数 |
| `%rcx` | `rcx` | `x2` | 一時スクラッチレジスタ、除算除数格納 |
| `%rbx` | `rbx` | `x3` | 一時スクラッチレジスタ |
| `%rdi` | `rdi` | `x0` | C ランタイム呼出引数 1 |
| `%rsi` | `rsi` | `x1` | C ランタイム呼出引数 2 |
| `%r10` | `r10` | `x10` | 自己クロージャポインタ（Caller-saved スクラッチ） |
| `%r12` | `r12` | `x19` | ヒープアロケーション基底ポインタ（Callee-saved、C 呼出でも保持） |
| `%rsp` | `rsp` | `sp` | スタックポインタ（16バイトアライメント必須） |
| - | - | `x30` (`lr`) | リンクレジスタ（非末尾呼出時に退避・復元） |
| - | - | `x29` (`fp`) | フレームポインタ（`scheme_entry` エントリポイントで退避） |
| - | - | `wzr` / `xzr` | ゼロレジスタ（0 のストアに活用） |

### 4.2 スタックフレーム管理と 16バイト SP アライメント
- **SP アライメント保証**: ARMv8-A では `sp` をベースとするメモリアクセスにおいて 16 バイトアライメント違反時にハードウェア例外（SP Alignment Fault）が発生する。
  ULisp の `align-frame-shift` は `frame-shift % 16 == 8` を満たすため、呼出時に `total-shift = frame-shift + 8`（必ず 16 の倍数）を引いて `x30` を `[sp]` に保存することで、常に 16 バイト整列を厳格に維持する。
- **引数・ローカルスロット配置**:
  - `[sp + 8]`, `[sp + 16]`, ...: 呼び出し元が退避した関数の引数スロット
  - `[sp - 8]`: 自クロージャポインタ（`x10`）退避スロット
  - `[sp - 16]`, `[sp - 24]`, ...: 局所変数スロット

### 4.3 末尾呼び出し最適化（TCO）とリンクレジスタ
- **非末尾呼び出し (`%call-closure`)**:
  ```armasm
      sub sp, sp, #total_shift
      str x30, [sp]
      ldr x1, [x10, #-1]
      blr x1
      ldr x30, [sp]
      add sp, sp, #total_shift
  ```
- **末尾呼び出し (`%jump`)**:
  引数スロットを上書き後、`br x1` でジャンプ。`x30` は上書きされず呼び出し元のリターンアドレスがそのまま維持されるため、被呼出関数の `ret` で直接元々の呼び出し元へと復帰する。

### 4.4 算術・論理・メモリ命令マッピング
- `%mov`: 即値は `ldr reg, =val`（または小さな即値は `mov reg, #val`）、レジスタ間は `mov dst, src`
- `%load`: `ldr dst, [base, #offset]` またはレジスタオフセット `ldr dst, [base, offset]`
- `%store`: `str src, [base, #offset]`
- `%load-byte-zx`: `ldrb w<dst>, [base, #offset]`（32ビット書き込みにより上位32ビットは自動ゼロ拡張）
- `%store-byte`: `strb w<src>, [base, #offset]`（`0` の場合は `strb wzr, [base, #offset]`）
- `%add` / `%sub`: `add dst, dst, src` / `sub dst, dst, src`
- `%neg`: `neg dst, dst`
- `%imul`: `mul dst, dst, src`
- `%cqo`: AArch64 では 64 ビット符号付き除算が独立命令 `sdiv` で可能なため no-op（省略）
- `%idiv`: 商と剰余を同時に計算し x86-64 `%idiv` の規約に完全適合：
  ```armasm
      sdiv x9, x0, src
      msub x1, x9, src, x0    // x1 (%rdx) = x0 - (x9 * src) [剰余]
      mov x0, x9              // x0 (%rax) = 商
  ```
- `%set-boolean`: 条件コードに応じた `cset x0, cond` 実行後、`lsl x0, x0, 6; add x0, x0, 0x2F`
- `%alloc`: `add dst, x19, #tag; add x19, x19, #bytes`
- `%code-ref` / `%str-ref`: `adrp dst, label; add dst, dst, :lo12:label`

### 4.5 脅威モデル分析とセキュリティ対策 (Threat Model & Mitigations)
- **脅威 1: 不正なメモリアクセス・スタック破壊 (CWE-119 / CWE-787)**:
  - 対策: SP アライメントの厳格な 16 バイト保持、および呼び出し先フレームの事前計算された固定オフセット保護。
- **脅威 2: 未初期化レジスタ情報の漏洩 (CWE-457)**:
  - 対策: `scheme_entry` のエントリ・エグジットでの Callee-saved レジスタ（`x19`, `x29`, `x30`）の完全な退避・復元、およびバイトロード時の自動ゼロ拡張保証。
- **脅威 3: メモリタグ偽装・ポインタインジェクション**:
  - 対策: ULisp のポインタタギング（下位 3 ビット: 0=Fixnum, 1=Pair, 2=Symbol, 3=String）の一貫したビットマスク処理を ARM64 でも不変維持。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/503-implement-ulisp-aarch64-backend-via-lir`

1. **バックエンドモジュールの新設**:
   - `ulisp/passes/07_backend_aarch64.scm` を実装。
   - レジスタ変換（`arm-reg->str`）、メモリオペランド変換（`arm-mem-op->str`）、命令エミッタ（`emit-arm-lir-instruction`）、関数・メインルーチンエミッタ（`emit-aarch64`）を網羅。
2. **コンパイラドライバの統合**:
   - `ulisp/passes/08_driver.scm` を拡張し、`(!target aarch64)` で `emit-aarch64` を呼出可能にする。
3. **ランタイムのマルチアーキテクチャ対応**:
   - `ulisp/runtime.c` のクラッシュハンドラを `#if defined(__aarch64__)` に対応させる。
4. **Makefile とビルドパイプラインの更新**:
   - `ulisp/Makefile` の `PASSES_LIB` に `passes/07_backend_aarch64.scm` を追加。
   - `compiler.scm` を再生成。
5. **テストスイートの拡充**:
   - `ulisp/tests/test_passes.scm` に Pass 7c（AArch64 バックエンド）の単体テストを追加。
   - レジスタフォーマット、メモリオペランド、命令生成、および LIR パイプライン結合を検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/passes/07_backend_aarch64.scm` が新設され、LIR 命令列から有効な GNU AArch64 アセンブリを出力すること。
- [x] 算術、論理、分岐、メモリアクセス、クロージャ生成・呼出、末尾呼び出し（TCO）、ヒープ確保の全オペコードが網羅されていること。
- [x] `ulisp/passes/08_driver.scm` が `(!target aarch64)` ディレクティブを正しく解釈し、AArch64 アセンブリを出力すること。
- [x] `ulisp/runtime.c` が AArch64 環境でもエラーなくコンパイル可能であること。
- [x] `make -C ulisp test_passes` に Pass 7c テストが統合され、100% PASS すること。
- [x] 既存の品質ゲート（Python 構文検査、フォーマット、リンター）に違反がないこと。
- [x] Issue 台帳および closed 移動が完了していること。
