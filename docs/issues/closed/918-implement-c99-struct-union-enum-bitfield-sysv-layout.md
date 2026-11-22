---
ID: 918
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-22
---

# [FEAT/ENH] C99 構造体・共用体・列挙型・ビットフィールドの SysV AMD64 メモリレイアウト計算の実装 (ID: 918)

## 1. 概要 / Summary
Lua 5.x の中核データ構造（`TValue`, `Value` union, `Table`, `Node`, `GCObject`, `lua_State`, `CallInfo`, `Proto`）を正確に扱うため、SysV AMD64 ABI 準拠の `struct` / `union` / `enum` / 無名複合体 / 柔軟配列メンバ / ビットフィールドのメモリレイアウト計算 ＆ ABI クラス分類エンジン（`ulisp/frontend_c/type_layout.scm`）、ブロック語彙スコープ対応タグ・不完全型解決、`_Alignof` / `offsetof` / `__builtin_offsetof` / `sizeof` CTFE 評価、Designated Initializer ＆ `.data`/`.bss` 多バイト静的領域、メンバアクセス（`.` / `->`）＆ ビットフィールド R/W Lowering、ならびに SysV AMD64 構造体値渡し・戻り値（`<= 8B`, `9..16B`, `> 16B sret`）を Reference VM (#834)・Pass 140/144a ネイティブ ELF・Pass 160 Portable C の 3 ターゲット横断で実装する（Phase S3 / Task T6）。

### `#919` との責務境界
- **本 Issue (`#918`) の責務**: 複合型（`struct`/`union`/`enum`/無名複合体/柔軟配列メンバ/ビットフィールド）の型表現・SysV AMD64 レイアウト＆ABI 分類、スコープ付きタグ・不完全型解決、`.` / `->` メンバアクセスおよびビットフィールド読み書き、Designated Initializer（静的 `.data`/`.bss` およびローカル初期化）、構造体コピー、SysV AMD64 構造体値渡し/戻り値。
- **後続 Issue ([[#919]](919-implement-c99-pointer-scaling-array-decay-and-escape-analysis.md)) の責務**: 一般ポインタ算術スケーリング（`p + n`, `p1 - p2`）、多次元配列の一般退化規則、および単項 `&var` エスケープ変数に対する Pass 132 Braun SSA（[132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm)）選択的 mem2reg 保護。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §2.1, §3.2](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §3.3, §4.2](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-13 §3.2, §5.2](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤（実装済・先行）:
  - `#825`: CTFE 定数式評価（[ulisp/compiler/eval_in_language.scm](../../ulisp/compiler/eval_in_language.scm)）
  - `#829`: SysV ABI 呼出規約（[ulisp/compiler/calling_convention.scm](../../ulisp/compiler/calling_convention.scm)）
  - `#830`: ELF `.data`/`.rodata`/`.bss` セクション（[ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm), [ulisp/backend/144a_x86_assembler.scm](../../ulisp/backend/144a_x86_assembler.scm)）
  - `#833`: 診断レポータ（[ulisp/compiler/diagnostic.scm](../../ulisp/compiler/diagnostic.scm)）
  - `#834`: Reference LIR VM（[ulisp/vm/lir_interpreter.scm](../../ulisp/vm/lir_interpreter.scm)）
  - `#915`: C99 Parser ＆ `L_c_ast`（[[#915]](closed/915-implement-c99-parser-and-nanopass-c-ast-definitions.md)）
  - `#916`: C99 Sema Core ＆ 整数 Lowering（[[#916]](closed/916-implement-c99-sema-core-and-integer-subset-lir-lowering.md)）
  - `#917`: C コンパイラドライバ ＆ ホストリンカ連携（[[#917]](closed/917-implement-c-compiler-driver-and-host-ld-integration.md)）
- 後続連携 Issue:
  - [[#919]](919-implement-c99-pointer-scaling-array-decay-and-escape-analysis.md), [[#921]](921-implement-sysv-amd64-stdarg-va-list-lowering.md), [[#925]](925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `ulisp/frontend_c/type_layout.scm` (新規: `<c-struct-layout>` / `<c-field-layout>`・SysV AMD64 パディング/ビットフィールド配置・8バイト ABI 分類・静的初期化バイト列シリアライザ)
- [x] [tools/grammars/c99.peg](../../tools/grammars/c99.peg) / [ulisp/frontend_c/lexer.scm](../../ulisp/frontend_c/lexer.scm) / [ulisp/frontend_c/parser.scm](../../ulisp/frontend_c/parser.scm) (`_Alignof` / `__alignof__` / `__builtin_offsetof` 追加、前方宣言 `(c-struct tag #f)` と定義 `(c-struct tag fields)` の曖昧性解消)
- [x] [ulisp/frontend_c/c_lang.scm](../../ulisp/frontend_c/c_lang.scm) (`L_c_ast` / `L_c_typed` 拡張: `c-alignof-type`, `c-alignof-expr`, `c-offsetof`, `c-init-list`, タグ参照型とレイアウト連携)
- [x] [ulisp/frontend_c/sema.scm](../../ulisp/frontend_c/sema.scm) (ブロック語彙スコープ対応 `struct-tags`/`enum-tags`・不完全型/環状定義検査・`.`/`->` メンバ解決・Designated Initializer 正規化・`sizeof`/`_Alignof`/`offsetof` 定数評価・診断 `C99-LAY-001..004`)
- [x] [ulisp/lir/lir_lang.scm](../../ulisp/lir/lir_lang.scm) / [ulisp/lir/lir_verifier.scm](../../ulisp/lir/lir_verifier.scm) (Core Machine LIR 後方互換拡張: オプション `(data ...)` 静的データ定義および `(%global-addr reg var)` による多バイト静的オブジェクトアドレス取得)
- [x] [ulisp/frontend_c/lower_to_lir.scm](../../ulisp/frontend_c/lower_to_lir.scm) (`%c99-lower-alloc-bytes!` 整列スタック割当、`(%mov %rax %rsp)` + `(%add %rax off)` アドレス算出、`.`/`->`・ビットフィールド抽出/挿入・定数長 `memcpy`・Designated Initializer・`.data`/`.bss` 出力・SysV 構造体値渡し/戻り値 `<=8B` / `9..16B` / `>16B sret`)
- [x] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) / [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm) / [ulisp/vm/lir_interpreter.scm](../../ulisp/vm/lir_interpreter.scm) / [ulisp/driver/c_driver.scm](../../ulisp/driver/c_driver.scm) (`(data ...)` セクションと `%global-addr` の 3 ターゲット対応およびマルチ TU マージ対応)
- [x] `ulisp/tests/test_c99_struct_union_layout.scm` (新規: 単体レイアウト・ABI 分類・診断 `C99-LAY-001..004`・Reference VM 実行検証)
- [x] `ulisp/tests/test_c99_struct_union_layout.sh` (新規: ホスト GCC `sizeof`/`_Alignof`/`offsetof` オラクル突合・ELF/C/GCC 構造体値渡し・戻り値 ABI 互換 E2E 検証)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`C99_FRONTEND_SOURCES` へ `frontend_c/type_layout.scm` を追加、`test_c99_struct_union_layout` ターゲットおよび `test` 集約への登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/918-implement-c99-struct-union-sysv-layout`

### 4.1 文法・AST 補強 (`c99.peg`, `lexer.scm`, `parser.scm`, `c_lang.scm`)
1. **前方宣言と定義の明確分離 (`struct_or_union_specifier`)**:
   - 現状の [parser.scm](../../ulisp/frontend_c/parser.scm) では `struct Foo;` や `struct Foo *p;` の参照形式と `struct Foo {};` の空定義がともに `(c-struct Foo '())` となるため、`{ ... }` の有無で前方宣言・タグ参照を `(c-struct tag #f)`（または `(c-union tag #f)`）、波括弧付き定義を `(c-struct tag fields)` として明確に区別する。
2. **`_Alignof` / `__alignof__` ＆ `__builtin_offsetof` 対応**:
   - [tools/grammars/c99.peg](../../tools/grammars/c99.peg)（`ulisp/peg/` と `src/core/peg/` 双方で PEP-617 互換性を維持）、[lexer.scm](../../ulisp/frontend_c/lexer.scm)、[parser.scm](../../ulisp/frontend_c/parser.scm)、および [c_lang.scm](../../ulisp/frontend_c/c_lang.scm) の `L_c_ast` / `L_c_typed` に `_Alignof` / `__alignof__`（`c-alignof-type`, `c-alignof-expr`）および `__builtin_offsetof(type_name, designator)`（`c-offsetof`、ネスト `.a.b[k]` 指定子対応）を追加する。
   - 標準 `<stddef.h>` マクロ慣用句 `((size_t)&(((T *)0)->m))` / `((uintptr_t)&((T *)0)->m)` についても、`c99-eval-const-int-expr` で定数オフセットへ畳み込めるよう対応する。
3. **無名パディングビットフィールド ＆ 無名複合メンバの AST 保存確認**:
   - `int : 0;`, `int : 3;` 等の declarator 省略ビットフィールド（`c-struct-decl #f width-expr`）および `struct { short lo; short hi; };` 等の declarator 省略メンバ宣言（`c-field-decl specs '()`）が `parser.scm` で欠落せず `L_c_ast` に保持されることを検証・補完する。

### 4.2 SysV AMD64 レイアウト ＆ ABI 分類エンジン (`ulisp/frontend_c/type_layout.scm`)
1. **データ構造 `<c-field-layout>` と `<c-struct-layout>`**:
   - `<c-field-layout>`: `name`（シンボルまたは無名なら `#f`）, `type`, `offset`（構造体先頭からのバイトオフセット）, `bit-offset`（格納単位内 LSB 基準ビット位置、`#f` なら非ビットフィールド）, `bit-width`（ビット幅、`#f` なら非ビットフィールド）, `storage-unit-offset`, `storage-unit-type`, `signed?`, `anon-path`（無名複合体経由アクセス経路）。
   - `<c-struct-layout>`: `kind`（`'struct` | `'union`）, `tag`, `complete?`, `size`, `align`, `fields`（無名メンバを展開したアクセス用リスト）, `raw-fields`（位置指定初期化子 `[i]` 用の直接宣言リスト）, `has-fam?`（末尾柔軟配列メンバの有無）, `abi-classes`（8バイトごとの SysV ABI クラス列）。
2. **SysV AMD64 psABI §3.1.2 準拠レイアウト規則**:
   - **`struct` 配置 ＆ パディング**: 各メンバを自身の型アライメント（`c-type-align`）へ切り上げた位置へ配置し、全体サイズを `max(align)`（最低 1 バイト、空構造体は GCC C 互換 `size=0, align=1`）の倍数へ末尾パディングする。
   - **`union` 配置**: 全メンバをオフセット `0` へ重ね、サイズ `max(member-sizes)` を `max(member-aligns)` の倍数へ切り上げる。
   - **無名 `struct`/`union` のフラット化**: 名前なし複合メンバは親の `raw-fields` には 1 要素の無名サブレイアウトとして残し、メンバ名探索用 `fields` へは累積オフセットを加算して再帰昇格（フラット化）する（例: `struct AnonSU { int tag; union { int64_t iv; struct { short lo; short hi; }; }; };` は `sz=16, al=8, off(iv)=8, off(lo)=8, off(hi)=10`）。メンバ名衝突時は診断エラーを送出する。
   - **柔軟配列メンバ (FAM: `T data[];`)**: 非柔軟メンバが 1 つ以上先行する `struct` の最終要素にのみ許可し、`alignof(T)` は構造体アライメントに寄与させ、`sizeof` への寄与は `0` とする（例: `struct FAM { int len; int data[]; };` は `sz=4, al=4, off(data)=4`）。
   - **ビットフィールド配置規則 (LSB-first)**:
     - 宣言基底型のサイズ・アライメント（格納単位 `unit-bits` = 8 / 16 / 32 / 64）内で LSB 側から順にパックする。
     - 現在のビット位置が格納単位境界を超える（`bit-cur + w > unit-bits`）場合は次の格納単位境界（`align(base)`）へ繰り上げる。
     - **ゼロ幅 / 無名ビットフィールド規則**: `: 0` は現在のビットパック単位を強制終了し次の格納単位境界へ進める。特に SysV AMD64 GCC 仕様に従い、**無名ビットフィールドは構造体全体の `align` には寄与しない**（例: `struct ZeroBF { char a; int : 0; char b; };` は `off(a)=0, off(b)=4, align=1, sz=5`、対して名前付き `struct NamedBF { unsigned a:4; int b:5; unsigned c:24; };` は `sz=8, align=4`）。
3. **SysV AMD64 §3.2.3 8バイト ABI クラス分類 `(c99-classify-sysv-aggregate layout)`**:
   - `size > 16` または非整列メンバを含む場合、あるいは柔軟配列メンバを含む場合は `'(memory)`。
   - `size <= 16` の場合は 8 バイトチャンク（最大 2 個）に分割し、各基本型（`'integer`, `'sse` = `f32`/`f64`, `'no-class`）を階層合流規則（`memory > integer > sse > no-class`）でマージする（例: Lua 5.4 `TValue` 16B `{ Value (union ptr/i64/f64); lu_byte tt_; }` → `'(integer integer)`）。
   - `union { double n; int64_t i; }` は `'integer` が `'sse` に勝つため第 1 チャンク `'integer`。`struct { double x; double y; }` は `'(sse sse)`。
4. **定数初期化バイト列シリアライザ `(c99-flatten-static-initializer type norm-init layout-env)`**:
   - `.data` 用リトルエンディアン生バイト列（パディングは 0 埋め、ビットフィールドはビット論理和パック済み）および外部シンボル・文字列リテラルへの再配置エントリ（オフセット ＋ ターゲットラベル）を生成する。すべてゼロ初期化の場合は `.bss`（サイズ指定ゼロ領域）へ自動分類する。

### 4.3 スコープ付きタグ解決・意味解析・Designated Initializer (`ulisp/frontend_c/sema.scm`)
1. **語彙ブロック単位のタグテーブル ＆ 非循環タグ参照型**:
   - `<c99-sema-env>` の `struct-tags` / `enum-tags` を `scopes` と同様のネストフレームスタックへ変更し、内側ブロックでの `struct Foo { ... };` シャドウイングおよび C99 前方宣言 `struct Foo;` に対応する。
   - 各タグには一意 ID（`tag-id`）を割り当て、型表現には `(struct-ref tag-id tag-name)` / `(union-ref tag-id tag-name)`（`type_layout.scm` の環境から `<c-struct-layout>` を参照）を保持する。これにより自己参照ポインタ `struct lua_State { struct lua_State *next; };` を循環 S 式なしで安全に表現する。
   - 従来の `c-parse-decl-specs`（`c_lang.scm`）を拡張または `sema-resolve-type-specs` と統合し、宣言指定子中の `c-struct` / `c-union` / `c-enum` 定義・参照を語彙スコープへ即座に登録・完了させて `<c-struct-layout>` を生成する。
2. **メンバアクセス (`.` / `->`)・`sizeof` / `_Alignof` / `offsetof`・複合リテラル**:
   - `c-member`（`.` と `->`）の解析: 左辺型を解決し（`->` 時はポインタ非配列・完全型確認後にデリファレンス）、`<c-struct-layout>` から対象 `<c-field-layout>`（無名メンバ経由を含む）を引いて `L_c_typed` ノード `(c-typed field-ty (c-member lhs field-sym arrow? layout-info))` を生成。左辺値の判定（`c99-lvalue-expr?`）では `.` は左辺が lvalue かつ非配列・非ビットフィールドアドレス制限付きで lvalue、`->` は常に lvalue とする。
   - `c-sizeof-type` / `c-sizeof-expr` / `c-alignof-type` / `c-alignof-expr` / `c-offsetof`: `sema-env` から完全レイアウトを取得して定数サイズ・アライメント・累積バイトオフセットを `c99-eval-const-int-expr` および `c99-analyze-expr` 双方で CTFE 評価する（メンバ `c-offsetof` ではビットフィールド指定不可、複数段 `.a.b[i].c` オフセット合算対応）。
   - `c-compound-lit`: `(struct Point){ .x = 1, .y = 2 }` を匿名ローカル／静的オブジェクト＋初期化子リストとして型検査する。
3. **Designated Initializer 正規化 (`{ .field = v, [idx] = v, .a[1].b = v }`)**:
   - C99 §6.7.8 に従い、現在カーソル位置（位置要素インデックスまたは構造体フィールド番号）を追跡しながらネストした `.field` / `[idx]` 指定子を解決する。
   - `union` の初期化は明示指定されたメンバまたは先頭メンバのみを有効化し、後続指定子は直近上書きを採用。
   - `struct P pts[] = { [2] = { .x = 10 }, [0].y = 20 };` のようにサイズ未指定配列に対して最大到達インデックス＋1 から配列長を自動確定し、未指定要素はゼロ初期化子へ正規化する。
   - グローバル変数・`static` 変数に対しては定数式評価可能性を検査し、`const-bytes`/`.bss` へ降格できるよう `typed-init` を構築する。
4. **診断コード (`diagnostic.scm` #833)**:
   - `"C99-LAY-001"`: 不完全型に対する `sizeof` / `_Alignof` / 実体宣言 / 値渡し / メンバ参照 / 構造体値メンバへの包含、または不正な柔軟配列メンバ配置。
   - `"C99-LAY-002"`: 非複合型に対する `.`/`->`/`offsetof`/`.field` 指定子適用、または存在しないメンバ名参照・無名複合体メンバ名衝突。
   - `"C99-LAY-003"`: 無効なビットフィールド型、幅が負・基底型ビット幅超過・名前付きで幅 `0`、またはビットフィールドに対する `&` / `sizeof` / `offsetof` 適用。
   - `"C99-LAY-004"`: 構造体・共用体の直接・間接の環状値包含定義（visiting 集合ガードによる検出）。

### 4.4 Core Machine LIR 拡張・Lowering・3ターゲット配線
1. **Core Machine LIR 拡張 (`lir_lang.scm`, `lir_verifier.scm`)**:
   - `%lir-program` に既存の `(strings ...)` 等との後方互換性を保つ**オプション** `(data (de ...))` 条項を追加する（各エントリは `(data-entry lbl align total-bytes init-spec)` 形式: ゼロ埋めの場合は `(bss lbl align total-bytes)`、定数データ/ポインタ再配置混在時は `(bytes lbl align chunk-list ...)`）。
   - 多バイト静的オブジェクトのベースアドレスをレジスタへ読み込む `(%global-addr reg var)` 命令を `L_lir_core` / `L_lir_raw` および `lir_verifier.scm` へ追加する（既存 8 バイトスカラー用の `%global-ref` / `%global-set!` は完全維持）。
2. **ローカル複合体割当・`.` / `->`・ビットフィールド Lowering (`lower_to_lir.scm`)**:
   - **整列スタック割当 `%c99-lower-alloc-bytes!`**: 型サイズ `sz`・アライメント `align` に基づきフレーム上に十分な連続領域を確保し（`lower-ctx-next-si` を `align` 境界へ切り下げ）、ベースアドレスを `(%mov dst %rsp)` ＋ `(%add dst slot-offset)` として算出する（Pass 132 Braun SSA および Core LIR 規約準拠。`c99-lower-function` でスカラー変数に割り当て済みアドレスと非干渉、またアドレスエスケープ対象の正式管理は `#919` へ接続）。
   - **通常メンバ R/W**: 親ベースアドレス ＋ 定数 `field.offset`（連続の `.` はオフセット畳み込み）に対し、スカラーなら `%load-typed` / `%store-typed`、構造体/配列メンバなら部分オフセット付きアドレスを返却・コピーする。
   - **ビットフィールド R/W**:
     - **読出し**: 格納単位（`storage-unit-offset`, `storage-unit-type`）を `%load-typed` で読込み、符号なしは `(%shr %rax bit-off)` ＋ `(%bit-and %rax ((1 << w) - 1))`、符号付きは左シフト `(- 64 (+ bit-off w))` 後に算術右シフト `(- 64 w)` で符号拡張する。
     - **書込み（Read-Modify-Write）**: RHS 値を幅 `w` にマスク後、対象格納単位を読み出して隣接ビットをマスク保存 `(old & ~(mask << bit-off)) | ((val & mask) << bit-off)` して `%store-typed` で書き戻し、さらに代入式の値として切り詰め済み値（符号拡張またはゼロ拡張）を `%rax` へ残す（連鎖代入 `a = s.bf = v` 対応）。
   - **構造体コピー ＆ ローカル初期化子**: 定数長代入 `s1 = s2` / `{ ... }` 初期化はサイズに応じて 8/4/2/1 バイトの展開コピー列（> 64B の場合は外部 `'sysv` `memcpy` 呼出しまたはループ）へ降格する。初期化リストがある場合はまず領域全体をゼロクリア（または未指定部クリア）した上で指定フィールド/要素のみ格納する。
3. **SysV AMD64 構造体値渡し・戻り値 Lowering**:
   - `c99-classify-sysv-aggregate` の結果に基づき呼出し側・定義側双方を展開する:
     - `<= 8B`（`'(integer)` / `'(sse)`）: 単一 GPR（`%rdi`..`%r9` / 戻り値 `%rax`）または XMM（`%xmm0`..`%xmm7` / 戻り値 `%xmm0`）へ 8 バイトパック（部分サイズはロード幅保護）。
     - `9..16B`（`'(integer integer)` 等）: 引数は連続する **2 レジスタ**（空き GPR < 2 の場合は SysV 規則に従い全体をスタック引数領域へスピル）へ展開、戻り値は `%rax`（下位 8B）＋ `%rdx`（上位 8B）へ格納・復元（混合 `integer`+`sse` は GPR+XMM ペア）。
     - `> 16B`（`'(memory)`）:
       - **戻り値**: 呼び出し側で一時返却バッファを確保し、第 1 隠れ引数（`%rdi`）として `sret` ポインタを渡す（通常引数は `%rsi`..`%r9` へ 1 つ繰り下げ）。被呼出側は `sret` 先へ結果をコピーして `sret` ポインタ自体を `%rax` で返す。
       - **引数**: 呼出しスタックフレーム（`[rsp - shift + stack_off]`、8B 整列）へコピーし、レジスタ消費なしで被呼出側の `[rsp + 8 + caller_off]` から参照する。
4. **3 バックエンド ＆ マージ対応 (`140_backend_x86_64.scm`, `160_backend_c.scm`, `vm/lir_interpreter.scm`, `c_driver.scm`)**:
   - **Pass 140 x86-64**: `(data ...)` を `.section .data`（`.byte` / `.quad` / 再配置シンボル `.quad sym + off`）および `.section .bss`（`.zero N`）へ出力（[144a_x86_assembler.scm](../../ulisp/backend/144a_x86_assembler.scm) 既存の `.data`/`.bss`/`.byte`/`.quad`/`.zero` を再利用）。`(%global-addr reg var)` は `lea <reg>, [rip + <mangled_var>]` へ降格する。
   - **Pass 160 Portable C**: `'c-tu` モード時に `(data ...)` をアライン済み静的バイト配列 `static uint8_t ... __attribute__((aligned(A))) = { ... };`（再配置を含む場合は構造体配列または初期代入文）へ変換し、`(%global-addr reg var)` は `(uint64_t)(uintptr_t)&...` を出力する。
   - **Reference VM (#834)**: `vm-strings-table` に準じて `vm-data-table` に連続リニアメモリブロックを確保し、`(%global-addr reg var)` でその仮想ベースアドレスを返す（既存の `vm-mem-read-*` / `vm-mem-write-*` と透過連携）。
   - **C Driver (`c_driver.scm`)**: `c99-merge-lir-programs` で複数翻訳単位の `(data ...)` エントリも衝突なく統合する。

### 4.5 セキュリティ ＆ 堅牢性設計 (Threat Model & Mitigations)
1. **無限再帰 / スタック枯渇 DoS 防止 (CWE-674)**:
   - タグレイアウト解決時に明示的な `visiting` 集合で直接・間接の自己値包含を検出して即座に `C99-LAY-004` を報告する。さらにネストした無名構造体/共用体および初期化子リストの最大深度上限（例: depth `<= 256`）を設け、細工された巨大ネスト C ヘッダによるパーサ/Sema のスタック枯渇を防ぐ。
2. **整数オーバーフロー防止 (CWE-190)**:
   - 構造体サイズ累計 `offset + field_size`、アライメント切上げ、配列要素総サイズ `elem_size * count` 計算時に上限検査を実施し、安全なオブジェクト上限（例: `> #x7fffffff`）を超過した場合は `C99-LAY-001` / `C99-SEMA-005` で拒否する（`#ifdef` や負サイズでのラップアラウンドを防止）。
3. **範囲外 Designated Initializer 書込み防止 (CWE-787)**:
   - `[idx] = val` 指定子に対し `0 <= idx < array_len`（定数評価結果）を厳格検証し、負インデックスや配列境界外の書込みをコンパイル時エラーとして即座に拒否する。
4. **型混乱 ＆ 不正アドレス取得の遮断 (CWE-843 / CWE-119)**:
   - ビットフィールドへの `&s.bf`、`sizeof(s.bf)`、`offsetof(S, bf)` を `C99-LAY-003` で禁止し、不完全型の実体化・`sizeof`・ポインタ逆参照を `C99-LAY-001` で遮断する。
5. **ULisp AOT 自己ホスト互換性規律**:
   - 新規・変更すべての `.scm` ファイルにおいてローカル `(set! var val)` を厳禁とし（ULisp AOT で未定義シンボル `ulisp_gvar_set_excl` となるため）、状態保持にはミュータブル `cons` セル（`car`/`set-car!`）またはレコードミューテータのみを使用し、`make -C ulisp build/ulisp-modular` / `bootstrap_verify_modular` を常時 100% クリーンに保つ。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] Lua 5.x の `Value`, `TValue`, `Table`, `Node`, `GCObject`, `lua_State`, `CallInfo`, `Proto` 相当のネスト構造体・共用体・無名複合体・柔軟配列メンバ・ビットフィールド（`: 0` 境界・無名幅含む）の `sizeof` / `_Alignof` / `offsetof` がホスト GCC（x86-64 SysV ABI）と 100% 一致すること。
- [x] 無名構造体/共用体・符号付き/符号なしビットフィールドの読み書き・Designated Initializer（ネスト `.a.b` / `[i]`・未指定ゼロ埋め）・グローバル構造体配列の `.data`/`.bss` 初期化が Reference VM (#834)・Pass 140/144a ネイティブ ELF・Pass 160 Portable C の 3 ターゲットすべてで一致動作すること。
- [x] SysV AMD64 ABI の構造体値渡し・戻り値（`<= 8B`, `9..16B` `{rax, rdx}` / `{rdi, rsi}`, `> 16B` 隠れ `sret`, 残レジスタ不足時のスタックスピル）がホスト GCC コンパイル済みオブジェクトとの相互リンク実行で完全互換動作すること。
- [x] 診断コード `C99-LAY-001`〜`C99-LAY-004` および境界・安全性検査（環状定義・負/幅超過ビットフィールド・`&bf`・配列外デザイン初期化子・不完全型誤用）が全件期待通りエラー報告されること。
- [x] `make -C ulisp test_c99_struct_union_layout`（Scheme 単体 ＋ ホスト GCC 突合 E2E）が全件 PASS し、既存スイート（`test_c99_e2e`, `test_c99_int_lowering`, `test_c99_parser`, `test_c99_peg_grammar`, `test_c`, `build/ulisp-modular`, `bootstrap_verify_modular`, `pytest tests/core/peg/compiler/test_c99_grammar.py`, `make check_format`, `make static_analysis`）に回帰がないこと。
