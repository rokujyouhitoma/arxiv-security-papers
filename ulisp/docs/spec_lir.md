[ULisp トップ](../README.md) > [ドキュメント一覧](README.md) > **低レベル IR (LIR) 正典仕様書**

---

# ULisp Canonical 低レベル IR (LIR) 正典仕様書

本ドキュメントは、ULisp コンパイラにおけるメタコンパイラ（フロントエンド／ミドルエンド）と低水準コードジェネレータ（バックエンド: x86-64 / AArch64 / C99 / Wasm）の接合境界である**正典低レベル中間表現（Canonical LIR: Low-level Intermediate Representation）**の完全な構文、BNF文法、オペコード辞書、不変条件規則、および境界バリデータ仕様を定義する。

- **アーキテクチャ親仕様書**: [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連仕様書**:
  - [パイプライン・Nanopass 詳細仕様書](spec_pipeline.md)
  - [バックエンド & コード生成仕様書](spec_backend.md)
  - [GC & メモリモデル仕様書](spec_gc_and_memory.md)
  - [テスト実行ガイド](guide_testing.md)
- **関連 Issue**: #589 (Canonical LIR 仕様厳格化と境界バリデータ), #583 (LIR Nanopass 分割), #576 (IR Verifier), #590 (物理層分離), #591 (ドライバ・テスト階層化)

---

## 1. Canonical LIR の設計思想と境界契約 (Boundary Contract)

LIR は、高水準 Scheme の意味論（ラムダ式、レキシカルスコープ、マクロ、CPS/継続、多値、脱糖）が Pass 010〜120 で完全に平坦化された後に生成される**「機械抽象レベルの中間表現」**である。

1. **ホモアイコニック S 式表現**:
   - 独自のバイナリ AST ではなく、純粋な Scheme の S 式（リスト・シンボル・整数）として表現され、メタプログラミング、直列化（`write` / `read`）、パイプライン差分検証が極めて容易である。
2. **ターゲット非依存性とバックエンド中立性**:
   - 抽象レジスタセット、スタックスロット、ラベル、3番地命令列で構成され、特定 CPU アーキテクチャのマイクロアーキテクチャ依存を排除する。
3. **厳格な境界契約 (Contract) と多層検証 (Two-Tier Verification)**:
   - メタコンパイラ層（Scheme フロントエンドの `Pass 130` → `Pass 131 (lower-managed-dialect)` 経由、および C99 フロントエンドの `lower_to_lir` 経由）は、`L_lir_core` / `define-language L_lir_canonical`（`ulisp/lir/lir_lang.scm`）および本仕様で定義された BNF 文法・不変条件を満たす `%lir-program` を出力する契約となっている（現役 Pass Manager の遷移契約は `L_lir_managed` → `L_lir_core`、`L_lir_raw` / `L_lir_canonical` は汎用スキーマ検証・内部 `define-pass` 用レガシー階層）。
   - バックエンド層（`140_backend_x86_64.scm`, `150_backend_aarch64.scm`, `160_backend_c.scm`）は、本仕様を満たす LIR 入力に対してのみ正当なマシン語／ソースコードを生成する責務を負う。
   - 両層の物理的分離点において、独立バリデータ `validate-lir` / `validate-core-lir` / `verify-lir`（`ulisp/lir/lir_verifier.scm`）が常時境界検証を行い、Tier 1 構文スキーマ検査（`L_lir_core?` / `L_lir_canonical?`）と Tier 2 意味論的 CFG/アライメント検査の多層防護を提供する。

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
 
バリデータは `ulisp/lir/lir_verifier.scm` に実装され、`ulisp/lir/lir_lang.scm`（`L_lir_core` / `L_lir_managed` および汎用スキーマ `define-language L_lir_canonical`）と宣言的に統合された以下の多層防護（Two-Tier Verification）API を提供する：

- `(validate-core-lir prog)` / `(validate-lir prog ['core])` / `(verify-lir prog)`:
  - **Tier 1 (構文スキーマ検証)**: `(L_lir_core? prog)`（Core LIR 純粋性検査）および `(L_lir_canonical? prog)` による形式文法適合性・未定義オペコード排除・オペランド型整合性検証。
  - **Tier 2 (コンテキスト意味論検証)**: CFG ラベル重複排除・未定義ラベルジャンプ検査・SSA ブロック引数 arity 整合・スタックフレーム 8 バイトアライメント・セーフポイントスタックマップ正当性検査。
  - 不変条件違反を検出した場合、詳細な診断メッセージ（関数名、命令、違反理由）を出力し、非 strict モードでは `#f` を返却、strict モードでは例外を raise する。
- 統合コンパイラドライバ（`compiler/driver.scm`）において、Pass 130 完了直後かつバックエンド呼出直前に自動実行される。

---

## 6. インライン・アセンブリ (`%inline-asm`) 仕様

レジスタ制約付きインライン・アセンブリ命令 `%inline-asm` は、`L_lir_core` / `L_lir_raw` / `L_lir_canonical` のファーストクラス命令として定義される（Issue #838 / DSN-33-02 §4.4 準拠）。

### 6.1 S 式構文

```scheme
(%inline-asm <template-string>
  (:outputs (<out-spec> ...))      ; 任意 (省略可)
  (:inputs (<in-spec> ...))        ; 任意 (省略可)
  (:clobbers (<clobber> ...))      ; 任意 (省略可)
  (:volatile? <boolean>))          ; 任意 (デフォルト #t)
```

各 `<out-spec>` / `<in-spec>` は無名 2 要素形式または名前付き 3 要素形式をとる：

- **無名形式**: `(<operand> "<constraint>")` — 例: `((%reg %rax) "=a")`, `((%stack -8) "=r")`, `(42 "r")`
- **名前付き形式**: `(<name> "<constraint>" <operand>)` — 例: `(res "=r" (%reg %rax))`, `(x "r" (%stack -16))`

### 6.2 制約文字列 (Register & Memory Constraints)

- **出力制約 (`:outputs`)**:
  - `"=r"`, `"+r"`, `"=q"`, `"+q"`, `"=&r"`: 任意汎用レジスタ（`+` は読み書き両用）
  - `"=a"`, `"=b"`, `"=c"`, `"=d"`, `"=S"`, `"=D"`, `"+a"` 等: 固定 GPR (`%rax`, `%rbx`, `%rcx`, `%rdx`, `%rsi`, `%rdi`)
  - `"={rax}"` .. `"={r15}"` / `"+{reg}"`: 任意明示レジスタ名
  - `"=m"`, `"+m"`: メモリオペランド
- **入力制約 (`:inputs`)**:
  - `"r"`, `"q"`, `"ri"`, `"ir"`: 汎用レジスタ
  - `"a"`, `"b"`, `"c"`, `"d"`, `"S"`, `"D"`, `"{reg}"`: 固定 GPR
  - `"i"`, `"n"`, `"I"`, `"J"`, `"K"`: 整数即値
  - `"m"`: メモリオペランド
  - `"0"`, `"1"`, ...: 出力インデックスに結び付けられる (tied) 入力
- **破壊指定 (`:clobbers`)**:
  - レジスタシンボル/文字列（`"%rcx"`, `"%r11"` 等、ただし `"%rsp"` は静的拒否）
  - `"cc"` / `"flags"`（ステータスフラグ破壊）
  - `"memory"`（メモリバリア・エイリアス最適化抑止）

### 6.3 テンプレート展開規則とプレースホルダ

- `%0`, `%1`, ...: 対応する出力・入力オペランド（出力先頭から 0 始まり通番）
- `%bN`, `%wN`, `%kN`, `%qN`, `%hN`: 8/16/32/64-bit サブレジスタ修飾子（例: `%b0` → `al`, `%k0` → `eax`, `%q0` → `rax`）
- `%[name]`, `%b[name]` 等: 名前付き 3 要素エントリ参照
- `%%reg` / `%%`: 明示レジスタ参照（例: `%%rax` → `rax`）およびリテラル `%` エスケープ

### 6.4 安全性・最適化・バックエンド保証 (`THREAT-838-1..4`)

1. **静的検証 (`lir_verifier.scm`)**: `%rsp` 破壊、重複固定出力レジスタ、不正な制約文字列、範囲外 `%N` および未定義 `%[name]`、書込不能出力（即値への `=r`/`=m` 等）をコンパイル時に拒否する。
2. **レジスタ保存と並列入力ステージング**: Pass 140（`140_backend_x86_64.scm`）は非出力キャリアおよび `:clobbers` レジスタをフレーム下部のスクラッチ領域に退避・復元し（`%rsp` を変化させずに `"m"` スタックオフセットを保持）、複数入力のサイクル（スワップ等）を 2 段階スナップショットによりサイクルフリーかつ `mov mem, mem` なしでステージングする。
3. **最適化バリア (`133_lir_peephole.scm`)**: `:volatile? #t` の `%inline-asm` は DCE で除去されず、`"memory"` 指定時は Store-Load Forwarding や DAG キャッシュを完全に遮断する。
4. **マルチバックエンド等価性**: x86-64 直接アセンブリ（`140_backend_x86_64.scm` + `144a_x86_assembler.scm`）、ANSI C バックエンド（`160_backend_c.scm` による `__asm__ volatile`）、および参照 VM（`vm/lir_interpreter.scm` + `register-inline-asm-handler!`）間で意味論的等価性を維持する。
