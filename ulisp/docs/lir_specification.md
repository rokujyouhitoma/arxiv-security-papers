# ULisp 低レベル IR (LIR) 命令セット仕様書

本ドキュメントは、ULisp コンパイラにおける中間表現境界である**低レベル IR（LIR: Low-level Intermediate Representation）**の構文、オペコード、意味論、およびマルチバックエンド対応規約を定義する。

正典アーキテクチャ仕様書: [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)  
関連 Issue: #502 (LIR導入), #503 (AArch64), #504 (Portable C/Wasm)

---

## 1. LIR の設計思想と位置付け

LIR は、Scheme 特有の高水準セマンティクス（ラムダ式、クロージャ、レキシカルスコープ、評価順序）が Pass 1〜Pass 5 で完全に平坦化された後に生成される**「機械抽象レベルの中間表現」**である。

- **ホモアイコニック S 式表現**: 特別なコンパイラ内部ポインタ型を使わず、Scheme のリスト構造（S 式）として表現される。
- **ターゲット非依存性**: CPU の物理レジスタ名（`rax`, `r12` 等）を直接含まず、抽象レジスタ／スタックオフセット／ラベルによる 3 番地命令列として定義される。
- **マルチバックエンド拡張性**: x86-64、AArch64、ANSI C、WebAssembly（Wasm）への 1 対 1 マッピングを保証する。

---

## 2. オペコード一覧と構文仕様

### 2.1 制御フロー命令 (Control Flow)

| オペコード | 構文例 | 意味論 (Semantics) | x86-64 対応 | AArch64 対応 | C言語対応 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `%label` | `(%label .L_0)` | 基本ブロックのラベル定義 | `.L_0:` | `.L_0:` | `.L_0:` |
| `%jump` | `(%jump .L_0)` | 無条件ジャンプ | `jmp .L_0` | `b .L_0` | `goto .L_0;` |
| `%jump-if-false` | `(%jump-if-false %v .L_0)` | `%v` が `#f` (0x2F) の場合ジャンプ | `cmp %v, 0x2F; je .L_0` | `cmp %v, #0x2F; b.eq .L_0` | `if (%v == 0x2F) goto .L_0;` |
| `%return` | `(%return %v)` | 手続きからのリターン（戻り値 `%v`） | `mov rax, %v; ret` | `mov x0, %v; ret` | `return %v;` |
| `%tail-call` | `(%tail-call target (args...))` | 末尾呼び出し最適化（フレーム再利用ジャンプ） | 引数上書き後 `jmp target` | 引数上書き後 `br target` | `goto` または 引数更新後末尾呼出 |
| `%call` | `(%call dst target (args...))` | 通常の関数呼び出し | スタック退避後 `call target` | スタック退避後 `bl target` | `dst = target(args...);` |

### 2.2 メモリ・データ転送命令 (Memory & Transfer)

| オペコード | 構文例 | 意味論 (Semantics) | x86-64 対応 | AArch64 対応 | C言語対応 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `%mov` | `(%mov dst src)` | レジスタ/即値間の値転送 | `mov dst, src` | `mov dst, src` | `dst = src;` |
| `%load` | `(%load dst base offset)` | メモリ読み出し: `base + offset` 番地からロード | `mov dst, [base + offset]` | `ldr dst, [base, #offset]` | `dst = *(uint64_t*)(base + offset);` |
| `%store` | `(%store base offset src)` | メモリ書き込み: `base + offset` 番地へストア | `mov [base + offset], src` | `str src, [base, #offset]` | `*(uint64_t*)(base + offset) = src;` |
| `%raw-load` | `(%raw-load base offset)` | 64ビット生メモリロード（`offset` は Fixnum バイト数） | `sar rax, 2; add rdx, rax; mov rax, [rdx]` | `asr x1, x1, 2; add x2, x0, x1; ldr x0, [x2]` | `*(uint64_t*)(base + (offset >> 2))` |
| `%raw-store!` | `(%raw-store! base offset val)` | 64ビット生メモリストア（`offset` は Fixnum バイト数） | `sar rcx, 2; add rdx, rcx; mov [rdx], r10` | `asr x1, x1, 2; add x3, x0, x1; str x2, [x3]` | `*(uint64_t*)(base + (offset >> 2)) = val` |

### 2.3 算術・論理・ポインタタグ演算命令 (Arithmetic, Logic & Pointer Tags)

| オペコード | 構文例 | 意味論 (Semantics) |
| :--- | :--- | :--- |
| `%add` | `(%add dst s1 s2)` | 64ビット加算: `dst = s1 + s2` |
| `%sub` | `(%sub dst s1 s2)` | 64ビット減算: `dst = s1 - s2` |
| `%mul` | `(%mul dst s1 s2)` | 64ビット乗算: `dst = s1 * s2` |
| `%div` | `(%div dst s1 s2)` | 符号付き除算商: `dst = s1 / s2` |
| `%mod` | `(%mod dst s1 s2)` | 剰余算: `dst = s1 % s2` |
| `%bit-and` | `(%bit-and dst s1 s2)` | ビット単位論理積: `dst = s1 & s2`（タグ判定用） |
| `%bit-or` | `(%bit-or dst s1 s2)` | ビット単位論理和: `dst = s1 \| s2`（タグ付与用） |
| `%shl` | `(%shl dst s1 n)` | 左シフト: `dst = s1 << n`（Fixnum 化: `n=2`） |
| `%sar` | `(%sar dst s1 n)` | 算術右シフト: `dst = s1 >> n`（Fixnum 復元: `n=2`） |
| `%ptr-tag` | `(%ptr-tag val)` | 下位 2 ビットを抽出し Fixnum（0, 1, 2, 3）として返却: `(val & 3) << 2` |
| `%ptr-untag` | `(%ptr-untag val)` | 下位 3 ビットをクリアし、生のアドレス（aligned pointer）を返却: `val & ~7` |
| `%ptr-add` | `(%ptr-add ptr bytes)` | 生アドレスに Fixnum バイト数を加算: `ptr + (bytes >> 2)` |
| `%ptr-tag-add` | `(%ptr-tag-add ptr tag)` | 生アドレスにタグ（1〜3）を合成: `ptr + (tag >> 2)` |

### 2.4 ランタイム・GC制御・ヒープアロケーション命令 (Runtime & GC Control)

| オペコード | 構文例 | 意味論 (Semantics) | x86-64 対応 |
| :--- | :--- | :--- | :--- |
| `%get-rsp` | `(%get-rsp)` | 現在のマシンスタックポインタを取得 | `mov rax, rsp` |
| `%get-heap-ptr`| `(%get-heap-ptr)` | 現在のヒープアロケーションポインタを取得 | `mov rax, r12` |
| `%set-heap-ptr!`| `(%set-heap-ptr! new_ptr)` | ヒープアロケーションポインタを更新 | `mov r12, rax` |
| `%get-gc-state-ptr` | `(%get-gc-state-ptr)` | 静的GC状態バッファのアドレスを取得 | `lea rax, [rip + ulisp_gc_state]` |
| `%alloc` | `(%alloc dst bytes tag)` | ヒープから `bytes` バイトを確保し、下位ビットに `tag` を付与して `dst` に格納 | `lea dst, [r12 + tag]; add r12, bytes` |

- **Prefix Header 付与規約**:
  ヒープオブジェクト生成時、直前 8 バイトに Fixnum タグ付きメタデータヘッダをストアする：
  ```nasm
  # cons (Pair: 24B = 8B Header + 16B payload)
  mov rdx, 4196356       # ((16 << 16) | (2 << 8) | 1) * 4
  mov [r12 + 0], rdx     # 8B 接頭辞ヘッダ
  mov [r12 + 8], rax     # car
  mov [r12 + 16], rbx    # cdr
  lea rax, [r12 + 9]     # tag 0x01 (ヘッダスキップ +8 + tag 1)
  add r12, 24
  ```

---

## 3. LIR プログラム全体の構文木構造

Pass 6（`06_lir.scm`）が出力する LIR プログラムは、以下の形式を持つ：

```scheme
(%lir-program
  (%lir-functions
    (%lir-function .L_lambda_0
      (params %self x)
      (frame-size 24)
      (body
        (%load %t0 %self 8)
        (%add  rax %t0 x)
        (%return rax)))
    ...)
  (%lir-main
    (frame-size 16)
    (body
      (%mov rax 42)
      (%return rax))))
```

---

## 4. バックエンド実装ガイドライン

1. **レジスタ割り当ての局所性**:
   - ANF を通過しているため、各大項の生存期間は極めて短く、スクラッチレジスタおよびスタックオフセットへのマッピングが容易。
2. **呼び出し規約と ABI**:
   - 内部関数呼び出しは Scheme 固有の軽量規約（コンテキストポインタを第 1 レジスタ、引数を後続レジスタに格納）を用い、C ランタイム関数呼び出し（`ulisp_read_char` 等）のみプラットフォーム標準 ABI（System V AMD64 / ARM AAPCS）に適合させる。
