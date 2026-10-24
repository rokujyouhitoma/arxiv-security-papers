[ULisp トップ](../README.md) > [ドキュメント一覧](README.md) > **バックエンド & コード生成仕様書**

---

# ULisp バックエンド & コード生成仕様書
## (Backend Architecture & Code Generation Specification)

本ドキュメントは、**ULisp (Underlying LISP)** ネイティブ AOT コンパイラにおけるコード生成バックエンド（x86-64 GNU Assembly、AArch64 GNU Assembly、Portable ANSI C99）のアーキテクチャ、呼出規約（Calling Convention）、レジスタ割り当て規則、末尾呼出最適化（TCO）、およびベアメタルシステムコール規約を定義する。

- **正典アーキテクチャ仕様書**: [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連仕様書**:
  - [パイプライン・Nanopass 詳細仕様書](spec_pipeline.md)
  - [低レベル IR (LIR) 正典仕様書](spec_lir.md)
  - [GC & メモリモデル仕様書](spec_gc_and_memory.md)
  - [クロスプラットフォーム・コンパイル手順書](guide_portable_build.md)
- **関連実装ファイル**:
  - `ulisp/backend/140_backend_x86_64.scm`: Pass 140 x86-64 アセンブリ出力
  - `ulisp/backend/141_backend_x86_gc.scm`: Pass 141 x86-64 GC ルーチン生成
  - `ulisp/backend/142_backend_x86_freestanding.scm`: Pass 142 ベアメタル ELF ランタイム
  - `ulisp/backend/150_backend_aarch64.scm`: Pass 150 AArch64 アセンブリ出力
  - `ulisp/backend/160_backend_c.scm`: Pass 160 Portable ANSI C99 ソース出力

---

## 1. マルチターゲット・バックエンド構成

ULisp は、単一の正典中間表現（Canonical LIR: `spec_lir.md`）から複数のターゲットへ分岐するプラガブルなバックエンド構造を採用している。

```text
               ┌───────────────────────────────┐
               │    Canonical LIR (Pass 130)   │
               └───────────────┬───────────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         ▼                     ▼                     ▼
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│  x86-64 Linux   │   │  AArch64 Linux  │   │  Portable C99   │
│  (Pass 140-142) │   │   (Pass 150)    │   │   (Pass 160)    │
└────────┬────────┘   └────────┬────────┘   └────────┬────────┘
         │                     │                     │
   Direct Asm (GAS)      Direct Asm (GAS)       ANSI C Source
         │                     │                     │
         ▼                     ▼                     ▼
   Standalone ELF        Standalone ELF        Clang / GCC Native
```

---

## 2. x86-64 バックエンド ABI 規約 (System V AMD64 ABI 準拠)

x86-64 バックエンドは、Linux Standard Base / System V AMD64 ABI をベースとしつつ、関数型言語特有の高速アロケーションと TCO に最適化された規約を採用する。

### 2.1 レジスタ割り当て表 (Register Allocation Map)

| レジスタ | 役割 / 規約 | 保存責任 | 備考 |
| :---: | :--- | :---: | :--- |
| `%rax` | **戻り値 (Return Value)** / 汎用一時レジスタ | Caller | 評価結果の Tagged Pointer を格納 |
| `%rdi` | **第 1 引数 (Argument 1)** | Caller | 手続き呼び出し |
| `%rsi` | **第 2 引数 (Argument 2)** | Caller | 手続き呼び出し |
| `%rdx` | **第 3 引数 (Argument 3)** | Caller | 手続き呼び出し |
| `%rcx` | **第 4 引数 (Argument 4)** | Caller | 手続き呼び出し |
| `%r8`  | **第 5 引数 (Argument 5)** | Caller | 手続き呼び出し |
| `%r9`  | **第 6 引数 (Argument 6)** | Caller | 手続き呼び出し |
| `%r10` | 汎用スクラッチ (Scratch) / クロージャポインタ | Caller | 静的スコープ・環境アドレス |
| `%r11` | 汎用スクラッチ (Scratch) | Caller | 一時演算レジスタ |
| `%r12` | **ヒープバンプポインタ (Heap Allocation Ptr)** | **Reserved** | 常時 From-Space の先端アドレスを保持 |
| `%r13` | 多値カウンタ (Values Count) / Callee-saved | Callee | R7RS values 返却値数の保持 |
| `%rbx` | Callee-saved レジスタ | Callee | 継続退避・コンパイラ内部用途 |
| `%rsp` | スタックポインタ (Stack Pointer) | - | 16 バイトアライメント維持 |
| `%rbp` | ベースフレームポインタ (Frame Pointer) | Callee | スタックフレームチェーン |

### 2.2 末尾呼出最適化 (Tail-Call Optimization: TCO)
末尾位置にある手続き呼び出しは、スタックフレームを消費する `call` ではなく、引数レジスタを再配置した後の `jmp` 命令へ直接コンパイルされる。
これにより、再帰深度に依存しない $O(1)$ のスタック消費が数学的に保証される。

```asm
;; 末尾再帰の例: (loop (- n 1) (+ acc n))
movq  -8(%rbp), %rax    ; n
subq  $8,       %rax    ; (- n 1)
movq  %rax,     %rdi    ; Arg 1 再設定
movq  -16(%rbp), %rax   ; acc
addq  -8(%rbp), %rax    ; (+ acc n)
movq  %rax,     %rsi    ; Arg 2 再設定
addq  $32,      %rsp    ; 現在フレームの解放
popq  %rbp              ; フレームポインタ復元
jmp   .Lloop_entry      ; 直接ジャンプ (スタック消費なし)
```

---

## 3. ベアメタル・システムコール (`%syscall`)

ベアメタルモード（libc 非依存）において、入出力およびメモリ確保はカーネルシステムコール命令（`syscall`）を直接インライン展開して発行する：

- `sys_read` (Syscall 0): 標準入力読み取り
- `sys_write` (Syscall 1): 標準出力/エラー出力への直接書き込み
- `sys_exit` (Syscall 60): プロセス終了
- `sys_mmap` (Syscall 9): ページ単位のヒープ領域（128MB〜）の動的獲得

---

## 4. Portable C99 バックエンド (Pass 160)

`backend/160_backend_c.scm` は、Canonical LIR を完全な ANSI C99 規格準拠のコードへ変換する：

1. **Tagged Pointer の C 表現**:
   - `intptr_t` 型（64-bit 整数）を基本型 `ulisp_val` として定義。
2. **スタックマップ & GC 連携**:
   - C レベルでのスタックポインタ退避バッファと、`sigsetjmp` / `siglongjmp` またはトランポリン関数を用いた継続ディスパッチ。
3. **プラットフォーム独立性**:
   - macOS (Apple Silicon ARM64 / Intel x86-64)、FreeBSD、Linux、Windows など、Clang または GCC が動作するあらゆる環境で単一バイナリを生成可能。
