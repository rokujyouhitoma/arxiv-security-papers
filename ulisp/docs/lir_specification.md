# ULisp Canonical 低レベル IR (LIR) 正典仕様書

本ドキュメントは、ULisp コンパイラにおけるメタコンパイラ（フロントエンド／ミドルエンド）と低水準コードジェネレータ（バックエンド: x86-64 / AArch64 / C99 / Wasm）の接合境界である**正典低レベル中間表現（Canonical LIR: Low-level Intermediate Representation）**の完全な構文、BNF文法、オペコード辞書、不変条件規則、および境界バリデータ仕様を定義する。

- **アーキテクチャ親仕様書**: [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連 Issue**: #589 (Canonical LIR 仕様厳格化と境界バリデータ), #583 (LIR Nanopass 分割), #576 (IR Verifier), #590 (物理層分離), #591 (ドライバ・テスト階層化)

---

## 1. Canonical LIR の設計思想と境界契約 (Boundary Contract)

LIR は、高水準 Scheme の意味論（ラムダ式、レキシカルスコープ、マクロ、CPS/継続、多値、脱糖）が Pass 010〜120 で完全に平坦化された後に生成される**「機械抽象レベルの中間表現」**である。

1. **ホモアイコニック S 式表現**:
   - 独自のバイナリ AST ではなく、純粋な Scheme の S 式（リスト・シンボル・整数）として表現され、メタプログラミング、直列化（`write` / `read`）、パイプライン差分検証が極めて容易である。
2. **ターゲット非依存性とバックエンド中立性**:
   - 抽象レジスタセット、スタックスロット、ラベル、3番地命令列で構成され、特定 CPU アーキテクチャのマイクロアーキテクチャ依存を排除する。
3. **厳格な境界契約 (Contract)**:
   - メタコンパイラ層は、本仕様で定義された BNF 文法および不変条件を 100% 満たす `%lir-program` を出力することを保証する。
   - バックエンド層（`140_backend_x86_64.scm`, `150_backend_aarch64.scm`, `160_backend_c.scm`）は、本仕様を満たす LIR 入力に対してのみ正当なマシン語／ソースコードを生成する責務を負う。
   - 両層の物理的分離点において、独立バリデータ `validate-lir` / `verify-lir` が常時境界検証を行う。

---

## 2. Canonical LIR の形式 BNF 文法 (Formal BNF Grammar)

```ebnf
(* ================= LIR プログラム構造 ================= *)
<lir-program>     ::= "(%lir-program" <strings-decl> <stackmaps-decl> <functions-decl> <main-decl> ")"

<strings-decl>    ::= "(strings (" <string-entry>* "))"
<string-entry>    ::= "(" <label-symbol> <string-literal> ")"

<stackmaps-decl>  ::= "(stackmaps (" <safepoint-entry>* "))"
<safepoint-entry> ::= "(" <label-symbol> <frame-size-int> <bitmap-int> ")"

<functions-decl>  ::= "(%lir-functions" <lir-function>* ")"
<lir-function>    ::= "(%lir-function" <label-symbol> <params-clause> <frame-clause> <body-clause> ")"

<main-decl>       ::= "(%lir-main" <frame-clause> <body-clause> ")"

<params-clause>   ::= "(params (" <param-symbol>* "))"
<frame-clause>    ::= "(frame-size" <frame-size-int> ")"
<body-clause>     ::= "(body" <instruction>* ")"

(* ================= オペランド定義 ================= *)
<operand>         ::= <register> | <immediate> | <stack-slot> | <mem-ref> | <label-symbol>
<register>        ::= "%rax" | "%rbx" | "%rcx" | "%rdx" | "%rsi" | "%rdi"
                    | "%rbp" | "%rsp" | "%r8"  | "%r9"  | "%r10" | "%r11"
                    | "%r12" | "%r13" | "%r14" | "%r15" | "%al"
                    | "(%reg" <register-name> ")"
<immediate>       ::= <integer>
<stack-slot>      ::= "(%stack" <integer> ")"
<mem-ref>         ::= "(%mem" <register> <offset> ")"
<offset>          ::= <integer> | <register>
<frame-size-int>  ::= <non-negative-integer-multiple-of-8>
<bitmap-int>      ::= <non-negative-integer>

(* ================= 命令定義 ================= *)
<instruction>     ::= <control-flow-inst>
                    | <call-abi-inst>
                    | <memory-transfer-inst>
                    | <arithmetic-logic-inst>
                    | <runtime-gc-inst>
                    | <exception-values-inst>
```

---

## 3. 全 Canonical オペコード辞書 (Opcode Dictionary)

### 3.1 制御フロー命令 (Control Flow)

| オペコード | 構文形式 | オペランド制約 | 意味論 (Semantics) |
| :--- | :--- | :--- | :--- |
| `%label` | `(%label <lbl>)` | `<lbl>`: シンボル | 基本ブロックのラベル定義 |
| `%block` | `(%block <lbl> (<p1> ...) <inst> ...)` | `<lbl>`: シンボル, `<p>`: 仮引数シンボル列 | 仮引数付き SSA 基本ブロック |
| `%jump` | `(%jump <lbl> (<a1> ...))` | `<lbl>`: シンボル, `<a>`: 実引数オペランド列 | 無条件ジャンプ（ブロック引数渡し付き） |
| `%jump-if-false` | `(%jump-if-false <reg> <lbl> (<a1> ...))` | `<reg>`: レジスタ, `<lbl>`: シンボル | `<reg>` が `#f` (0x2F) の場合ジャンプ |
| `%jump-if` | `(%jump-if <reg> <t_lbl> (<ta> ...) <e_lbl> (<ea> ...))` | `<reg>`: レジスタ, 各 `<lbl>`: シンボル | 真偽値条件分岐（then/else 実引数渡し付き） |
| `%jump-cond` | `(%jump-cond <cond-op> <lbl>)` | `<cond-op>`: シンボル (e.g. `je`, `jne`, `jl`, `jle`, `jg`, `jge`) | CPU フラグに応じた条件ジャンプ |
| `%jump-if-zero` | `(%jump-if-zero <lbl>)` | `<lbl>`: シンボル | 直前のゼロフラグ (ZF=1) によるジャンプ |
| `%direct-jump` | `(%direct-jump <lbl>)` | `<lbl>`: シンボル | 直接関数ジャンプ（末尾呼出 TCO 用） |
| `%return` | `(%return)` または `(%return <val>)` | 任意 (戻り値は通常 `%rax`) | 関数からの復帰 |

### 3.2 手続き呼出・ABI 命令 (Procedure Calls & ABI)

| オペコード | 構文形式 | オペランド制約 | 意味論 (Semantics) |
| :--- | :--- | :--- | :--- |
| `%c-call` | `(%c-call <fn-name> <shift>)` | `<fn-name>`: シンボル/文字列, `<shift>`: 8倍数整数 | C ランタイム ABI 呼出（スタックシフト保護） |
| `%call-closure` | `(%call-closure <shift> [<safepoint>])` | `<shift>`: 整数, `<safepoint>`: 任意シンボル | クロージャ間接呼出（`%r10` 経由） |
| `%direct-call` | `(%direct-call <lbl> <shift> [<safepoint>])` | `<lbl>`: シンボル, `<shift>`: 整数 | 既知関数ラベルへの直接呼出 |
| `%dispatch-consumer` | `(%dispatch-consumer <c-si> <a-si> <shift>)` | 各引数: 整数スタックインデックス | 多値コンシューマ呼び出しディスパッチ |

### 3.3 データ転送・メモリ・定数命令 (Data Transfer & Memory)

| オペコード | 構文形式 | オペランド制約 | 意味論 (Semantics) |
| :--- | :--- | :--- | :--- |
| `%mov` | `(%mov <dst> <src>)` | `<dst>`: レジスタ/スタック, `<src>`: オペランド | レジスタ・即値・スタック間の転送 |
| `%load` | `(%load <dst> <base> <offset>)` | `<dst>`, `<base>`: レジスタ, `<offset>`: 整数/レジスタ | メモリ 8 バイト読出: `*(uint64_t*)(base + offset)` |
| `%store` | `(%store <base> <offset> <src>)` | `<base>`: レジスタ, `<offset>`: 整数/レジスタ, `<src>`: オペランド | メモリ 8 バイト書込: `*(uint64_t*)(base + offset) = src` |
| `%load-byte-zx`| `(%load-byte-zx <dst> <base> <offset>)` | `<dst>`, `<base>`: レジスタ, `<offset>`: 整数 | 1 バイトゼロ拡張読出 |
| `%store-byte` | `(%store-byte <base> <offset> <src>)` | `<base>`: レジスタ, `<offset>`: 整数, `<src>`: レジスタ/整数 | 1 バイト書込 |
| `%push` | `(%push <src>)` | `<src>`: レジスタ | スタックへの push |
| `%pop` | `(%pop <dst>)` | `<dst>`: レジスタ | スタックからの pop |
| `%code-ref` | `(%code-ref <dst> <lbl>)` | `<dst>`: レジスタ, `<lbl>`: シンボル | コードシンボルアドレスの RIP 相対取得 |
| `%str-ref` | `(%str-ref <dst> <lbl>)` | `<dst>`: レジスタ, `<lbl>`: シンボル | 文字列リテラルポインタ取得（ヘッダ＋タグ付与） |
| `%global-ref` | `(%global-ref <reg> <var>)` | `<reg>`: レジスタ, `<var>`: シンボル | グローバル変数領域からのロード |
| `%global-set!` | `(%global-set! <var> <reg>)` | `<var>`: シンボル, `<reg>`: レジスタ | グローバル変数領域へのストア |

### 3.4 算術・論理・ビット演算命令 (Arithmetic & Logic)

| オペコード | 構文形式 | 意味論 (Semantics) |
| :--- | :--- | :--- |
| `%add` | `(%add <dst> <src>)` | 64ビット加算 |
| `%raw-add` | `(%raw-add <dst> <src>)` | アンボックス生整数加算 |
| `%sub` | `(%sub <dst> <src>)` | 64ビット減算 |
| `%raw-sub` | `(%raw-sub <dst> <src>)` | アンボックス生整数減算 |
| `%imul` | `(%imul <dst> <src>)` | 符号付き 64 ビット乗算 |
| `%raw-mul` | `(%raw-mul <dst> <src>)` | アンボックス生整数乗算 |
| `%neg` | `(%neg <dst>)` | 符号反転 (`dst = -dst`) |
| `%inc` | `(%inc <dst>)` | インクリメント (`dst = dst + 1`) |
| `%cqo` | `(%cqo)` | 除算用符号拡張 (`rdx:rax = rax`) |
| `%idiv` | `(%idiv <src>)` | 符号付き除算 (`rax = rax / src, rdx = rax % src`) |
| `%shl` | `(%shl <dst> <count>)` | 左ビットシフト |
| `%shr` | `(%shr <dst> <count>)` | 論理右ビットシフト |
| `%sar` | `(%sar <dst> <count>)` | 算術右ビットシフト |
| `%bit-and` | `(%bit-and <dst> <src>)` | ビット論理積 |
| `%bit-or` | `(%bit-or <dst> <src>)` | ビット論理和 |
| `%bit-xor` | `(%bit-xor <dst> <src>)` | ビット排他的論理和 |
| `%cmp` | `(%cmp <s1> <s2>)` | 64ビット比較（フラグセット） |
| `%raw-cmp` | `(%raw-cmp <s1> <s2>)` | アンボックス生整数比較 |
| `%set-boolean`| `(%set-boolean <dst> <cond>)` | 条件フラグに基づく Scheme 真偽値生成 |
| `%box-fixnum` | `(%box-fixnum <dst> <src>)` | Fixnum タグ付与 (`dst = src << 2`) |
| `%unbox-fixnum`| `(%unbox-fixnum <dst> <src>)`| Fixnum タグ除去 (`dst = src >> 2`) |
| `%syscall` | `(%syscall)` | OS システムコール呼び出し |

### 3.5 アロケーション・ランタイム・継続・多値・例外制御 (Runtime, GC, CC & Values)

| オペコード | 構文形式 | 意味論 (Semantics) |
| :--- | :--- | :--- |
| `%alloc` | `(%alloc <dst> <bytes> <tag> [<si>])` | ヒープ領域確保（GCトリガー検査付き） |
| `%alloc-stack` | `(%alloc-stack <dst> <offset> <tag>)` | 非エスケープオブジェクトのスタック領域割当 |
| `%capture-cc` | `(%capture-cc <ret-lbl> <k-si>)` | 現在スタックをヒープへ退避し一級継続オブジェクト生成 |
| `%push-handler`| `(%push-handler <catch-lbl> <f-si> <h-si>)` | 例外ハンドラチェーンへの登録 |
| `%pop-handler` | `(%pop-handler <f-si>)` | 例外ハンドラチェーンからの解除 |
| `%raise` | `(%raise)` | 登録された最も内側のハンドラへ大域脱出 |
| `%set-values-count` | `(%set-values-count <cnt>)` | 多値返却カウントのセット |
| `%store-values-buf` | `(%store-values-buf <base-si> <cnt>)` | 多値返却バッファへのストア |

---

## 4. Canonical LIR の不変条件規則 (LIR Invariant Rules)

独立バリデータ `validate-lir` は、以下の不変条件を機械的に検査する：

1. **ルート構造不変条件 (Program Structure)**:
   - ルートは `(%lir-program ...)` であり、必須節 `strings`, `stackmaps`, `%lir-functions`, `%lir-main` を含むこと。
2. **スタックフレーム・アライメント不変条件 (Stack Frame Alignment)**:
   - 各関数の `frame-size` は 0 以上の整数であり、かつ 8 の倍数（偶数アライメント）であること。
3. **オペコード正当性不変条件 (Opcode Validity)**:
   - すべての命令ノードの先頭オペコードは、セクション 3 で定義された Canonical オペコード集合に厳密に含まれること。
4. **レジスタ集合不変条件 (Register Set)**:
   - すべてのレジスタ指定は `%rax`〜`%r15`, `%al` のいずれかであること。
5. **CFG ラベル一意性不変条件 (Label Uniqueness)**:
   - 同一関数／メインブロック内において、`%label` および `%block` で定義されるラベル名は重複してはならない。
6. **CFG ジャンプ先閉包不変条件 (CFG Closure & Reachability)**:
   - すべての `%jump`, `%jump-if-false`, `%jump-if`, `%jump-cond`, `%jump-if-zero` の遷移先ラベルは、その関数内部で定義されたラベルに解決されなければならない。
7. **SSA 基本ブロック引数不変条件 (Block Arguments Arity Matching)**:
   - `%block <lbl> (<p1> ...)` に対するすべての `%jump <lbl> (<a1> ...)` は、定義された仮引数リストの長さと実引数リストの長さが完全に一致しなければならない。
8. **セーフポイント・スタックマップ不変条件 (Safepoints & Stackmaps)**:
   - 各セーフポイントエントリは `(<label> <frame-size> <bitmap>)` の 3 要素タプルであり、`frame-size` は 8 の倍数、`bitmap` は非負整数であること。

---

## 5. 境界バリデータ (`validate-lir` / `verify-lir`) 仕様

バリデータは `ulisp/compiler/lir_verifier.scm` に実装され、以下の公開 API を提供する：

- `(validate-lir prog)` / `(verify-lir prog)`:
  - 引数 `prog` が Canonical LIR 不変条件をすべて満たせば `#t` を返却する。
  - 不変条件違反を検出した場合、詳細な診断メッセージ（関数名、命令、違反理由）を出力し、非 strict モードでは `#f` を返却、strict モードでは例外を raise する。
- 統合コンパイラドライバ（`compiler/driver.scm`）において、Pass 130 完了直後かつバックエンド呼出直前に自動実行される。
