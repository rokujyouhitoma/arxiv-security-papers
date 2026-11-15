---
ID: 836
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT] `define-value-repr` による値表現・ボクシング方式のプラグイン化 (ID: 836)

## 1. 概要 / Summary

現在 ULisp コンパイラの各パス（`frontend/090_rtyper.scm`, `lir/129_lir_primitives.scm`, `lir/130_lir.scm`, `lir/131_lower_managed_dialect.scm`）に分散・ハードコードされている Scheme 64-bit タグ付き値表現（Fixnum の 2 ビット左シフト `<< 2` / `* 4` と下位マスク `#b11`、即値リテラル `#f = 47 (0x2F)` / `#t = 111 (0x6F)` / `'() = 63 (0x3F)` / `eof = 79 (0x4F)` / `char` / `symbol`、および 8 バイト境界ヒープポインタの下位 3 ビット型タグ `pair/closure = 1`, `string = 3`, `vector = 5`, `bytevector = 7`, `flonum = 11`）を、単一の宣言的スペック DSL（`define-value-repr`）および値表現エンジン `ulisp/compiler/value_repr.scm` へと集約・プラグイン化する。

このプラグイン化により以下の 3 つのアーキテクチャ目標を達成する：
1. **C 言語の「タグ幅 0・アンボックス生値表現 (`repr:c-unboxed`)」の統一的取り扱い**:
   C 言語フロントエンド（DSN-38）やアンボックス最適化領域を特別扱い（アドホックな条件分岐）するのではなく、`(:fixnum (:shift 0) (:tag-bits 0) (:tag-mask 0))` を持つ正規の値表現スペック `repr:c-unboxed` として記述し、同一のコード生成抽象（`repr-emit-box-fixnum`, `repr-emit-unbox-fixnum`, `repr-encode-immediate` 等）からゼロコスト（No-op / 恒等移動）の LIR を自動導出する。
2. **マジックナンバーの完全排除と保守性・安全性向上**:
   `47`, `111`, `63`, `79`, `-1`, `7` などのタグ・オフセット定数を表現スペックから数学的に導出（例：`offset = field_index * word_size - pointer_tag`）し、CWE-843（Type Confusion）やポインタ非整列バグを防止する。
3. **多様な値表現モデルへの拡張性 (`repr:nan-boxing-64bit` 等)**:
   IEEE 754 Quiet NaN ペイロード空間を利用する 64-bit NaN-boxing 表現スペック `repr:nan-boxing-64bit` を同一 DSL 上に定義・検証可能とし、将来的な他言語ランタイム連携およびインタプリタ／AOT 間のゼロコピー FFI 共有基盤を確立する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [DSN-33-02 (ULisp 多言語フロントエンド統合および機械型付き LIR 拡張設計書)](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md): §5.1 (`define-value-repr` による値表現・ボクシングのプラグイン化), §2.2 (Scheme インタプリタのゼロコスト FFI)
  - [DSN-33 (ULisp Underlying x86 Native AOT Compiler Architecture)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md): §2.1 (Tagged Pointer メモリモデル & 即値表現)
  - [LIR 正典仕様書 (ULisp Canonical LIR Specification)](../../ulisp/docs/spec_lir.md): §3 (ボクシング命令・型付きメモリアクセス仕様)
- **関連 Issue**:
  - [Issue #826 (機械型を備えた Typed LIR への移行とボクシング操作の直交分離)](closed/826-introduce-typed-machine-lir-and-orthogonalize-boxing-operations.md)
  - [Issue #829 (呼出規約の多重化・モジュール分離とゼロオーバーヘッド C-FFI の実現)](closed/829-modularize-calling-conventions-for-sysv-abi-and-scheme-fast-calls.md)
  - [Issue #834 (純粋 Scheme 製 LIR 参照インタプリタ (Reference VM) の実装)](closed/834-implement-pure-scheme-lir-reference-vm-interpreter.md)
  - [Issue #835 (Core Machine LIR と Managed Runtime Dialect の完全直交分離)](closed/835-separate-core-machine-lir-from-managed-runtime-dialect.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/value_repr.scm](../../ulisp/compiler/value_repr.scm): `define-value-repr` 宣言マクロ、値表現スペック構造体・レジストリ、標準表現スペック（`repr:scheme-64bit-tagged`, `repr:c-unboxed`, `repr:nan-boxing-64bit`）、即値エンコーダ、ポインタオフセット計算器、およびボクシング／アンボクシング LIR コード生成器の実装
- [ ] [ulisp/frontend/090_rtyper.scm](../../ulisp/frontend/090_rtyper.scm): S-RTyper におけるアクティブ値表現スペック（`current-value-repr` / `repr-requires-boxing?`）との連携インターフェース追加
- [ ] [ulisp/lir/129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm): `fxadd1`, `fxsub1`, `fixnum?`, `null?`, `boolean?`, `char?`, `symbol?`, `pair?`, `string?`, `vector?`, `bytevector?`, `car`, `cdr` 等のタグ・マスク・オフセット計算への `value_repr.scm` 定数・ヘルパ適用
- [ ] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm): `lir-immediate` における即値エンコーディングの `repr-encode-immediate` への統合
- [ ] [ulisp/lir/131_lower_managed_dialect.scm](../../ulisp/lir/131_lower_managed_dialect.scm): Pass 131 の `%box-fixnum`, `%unbox-fixnum`, `%managed-box`, `%managed-unbox` 展開における `repr-emit-box-fixnum` / `repr-emit-unbox-fixnum` / `repr-emit-box-flonum` / `repr-emit-unbox-flonum` の呼び出し統合
- [ ] [ulisp/compiler/module_header.scm](../../ulisp/compiler/module_header.scm): モジュール分割コンパイル用 `%declare-extern-identifiers` への `value_repr.scm` 公開シンボル登録
- [ ] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm): シンボル文字列変換テーブルへの新規識別子登録（必要な場合）
- [ ] [ulisp/Makefile](../../ulisp/Makefile): `COMPILER_BASE` への `compiler/value_repr.scm` 追加および `test_value_representation` テストターゲットの登録
- [ ] [ulisp/tests/test_value_representation.scm](../../ulisp/tests/test_value_representation.scm): `define-value-repr` マクロ・3種の表現スペック・LIR コード生成・Pass 131 Lowering・Reference VM 実行検証を網羅する単体テストスイート

---

## 4. セキュリティ・設計分析 (Threat Modeling & Constraints)

| 脅威 / リスク ID | 脅威内容 | CWE 分類 | 潜在的影響 | 本 Issue での対策・設計的緩和策 |
| :--- | :--- | :--- | :--- | :--- |
| **THREAT-836-1** | タグ・マスク定義の不整合や表現混在による型混同 (Tag / Mask Representation Confusion) | **CWE-843** (Type Confusion) | Fixnum タグとヒープポインタタグのビットパターンが衝突したり、異なる表現スペック間でポインタ逆参照オフセットがずれて不正メモリアクセスを引き起こす。 | `validate-value-repr` 検証器を実装し、Fixnum タグ・即値タグ・ヒープポインタタグ間のビットマスク排他性とアライメント条件を登録時に静的検査する。 |
| **THREAT-836-2** | Fixnum シフト・エンコード時の整数オーバーフローと符号消失 (Shift Overflow & Sign Bit Corruption) | **CWE-190 / CWE-681** (Integer Overflow / Incorrect Numeric Conversion) | アンボックス時に論理右シフト（`%shr`）を誤用して負数の符号ビットが破壊されたり、シフト量が不正値（負数や 64 以上）に設定される。 | `define-value-repr` でシフト量を `0 <= shift < 63` に制限し、符号付き Fixnum のアンボクシングには必ず算術右シフト（`%sar`）またはシフト 0 時の恒等移動を生成する。 |
| **THREAT-836-3** | ポインタタグ減算後のメモリアライメント違反 (Tagged Pointer Misalignment) | **CWE-119 / CWE-787** (Out-of-bounds Write / Memory Corruption) | ヒープオブジェクトのタグ値 `tag` がポインタアライメント `align` 以上である場合、`base + offset - tag` が隣接オブジェクト領域を破壊する。 | ヒープタグ定義時に `0 <= tag < align` かつ `align` が 2 のべき乗であることを不変条件として検証し、フィールドオフセットを `(repr-field-offset repr type-sym byte-offset)` で一元算出する。 |
| **THREAT-836-4** | コンパイル途中の表現プロファイル汚染 (Dynamic Representation Context Leak) | **CWE-665** (Improper Initialization) | C モード (`repr:c-unboxed`) でコンパイルした後にグローバル状態が戻らず、後続の Scheme 関数までアンボックス表現で誤コンパイルされる。 | `with-value-repr` スコープヘルパを提供し、例外や早期リターンが発生しても元の `*current-value-repr*`（デフォルト `repr:scheme-64bit-tagged`）へ確実に復元する。 |

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/836-plugin-value-representation`

### ステップ 1: `ulisp/compiler/value_repr.scm` の設計と `define-value-repr` DSL 実装
1. **データ構造とレジストリ**:
   - 値表現スペックを保持する連想構造 `(value-repr (name . <sym>) (word-bits . 64) (fixnum . <alist>) (immediates . <alist>) (pointer . <alist>) (heap-tags . <alist>) (nan-box . <alist>))` を定義。
   - グローバルレジストリ `*value-repr-registry*` とアクティブ表現ポインタ `*current-value-repr*` を管理。
   - API:
     - `(register-value-repr! spec)` / `(get-value-repr name)` / `(value-repr? x)`
     - `(current-value-repr)` / `(set-current-value-repr! name-or-spec)` / `(with-value-repr name-or-spec thunk)`
     - `(validate-value-repr spec)`: タグシフト範囲（`0 <= shift <= 16`）、ポインタアライメント（1, 2, 4, 8, 16）、ヒープタグ範囲（`0 <= tag < align`）を検証。
2. **`define-value-repr` マクロ**:
   - `DSN-33-02 §5.1` の宣言構文および Issue 要件の識別子をサポートする `syntax-rules` マクロ：
     ```scheme
     (define-value-repr repr:scheme-64bit-tagged
       (:word-bits 64)
       (:fixnum (:shift 2) (:tag-bits #b00) (:tag-mask #b11) (:step 4))
       (:immediates
         (:boolean-false 47)
         (:boolean-true  111)
         (:boolean-mask  -65)
         (:null          63)
         (:eof           79)
         (:void          111)
         (:char-shift    8)
         (:char-op-shift 6)
         (:char-tag      14)
         (:char-mask     255)
         (:symbol-shift  6)
         (:symbol-tag    2)
         (:symbol-mask   255))
       (:pointer
         (:align 8)
         (:tag-mask 7)
         (:pair-tag       1)
         (:closure-tag    1)
         (:string-tag     3)
         (:vector-tag     5)
         (:bytevector-tag 7)
         (:flonum-tag     11)
         (:flonum-cell-bytes 16)))
     ```
   - エイリアスとして `scheme-standard`（`repr:scheme-64bit-tagged` と同一実体）および `c-unboxed`（`repr:c-unboxed` と同一実体）もレジストリに登録し、DSN-33-02 §5.1 表記と Issue #836 表記の両方で透過的に参照可能にする。

### ステップ 2: 3つの標準表現スペックの定義
1. **`repr:scheme-64bit-tagged` (エイリアス: `scheme-standard`)**:
   - 現行 ULisp 64-bit タグ方式（Fixnum 2-bit shift, `#f=47`, `#t=111`, `'()=63`, `eof=79`, pair tag `1`, string tag `3`, vector tag `5`, bytevector tag `7`, flonum tag `11`）。
2. **`repr:c-unboxed` (エイリアス: `c-unboxed`)**:
   - タグなし生値方式：Fixnum `:shift 0`, `:tag-bits 0`, `:tag-mask 0`, `:step 1`、即値 `:boolean-false 0`, `:boolean-true 1`, `:null 0`, `:eof -1`, `:char-shift 0`, `:char-tag 0`、ポインタ `:align 1` (または `8`), `:tag-mask 0`, 各ヒープタグ `0`。
3. **`repr:nan-boxing-64bit` (エイリアス: `nan-boxing-64bit`)**:
   - IEEE 754 Quiet NaN ボクシング方式：`:nan-base #x7FF8000000000000`、`:payload-mask #x0000FFFFFFFFFFFF`（48-bit ペイロード）、`:tag-shift 48`、Fixnum / Pointer / Immediate を NaN タグ空間に格納し、`f64` は生ビットのまま保持するスペック。

### ステップ 3: 即値エンコード・オフセット計算・ボクシング LIR コード生成器の実装
`ulisp/compiler/value_repr.scm` に以下のジェネレータ関数群を実装する（省略時は `(current-value-repr)` を使用）：
- **クエリ & エンコード API**:
  - `(repr-requires-boxing? [repr])`: `:shift > 0` または `:tag-mask > 0` または NaN-boxing なら `#t`、`repr:c-unboxed` なら `#f`。
  - `(repr-fixnum-shift [repr])`, `(repr-fixnum-tag [repr])`, `(repr-fixnum-mask [repr])`, `(repr-fixnum-step [repr])`
  - `(repr-encode-fixnum n [repr])`, `(repr-decode-fixnum raw [repr])`
  - `(repr-encode-boolean b [repr])`, `(repr-encode-null [repr])`, `(repr-encode-eof [repr])`, `(repr-encode-void [repr])`, `(repr-encode-char ch [repr])`
  - `(repr-encode-immediate expr [repr])`: 整数・真偽値・文字・空リストをアクティブな表現スペックに従って即値整数へ変換。
  - `(repr-heap-tag kind [repr])`: `'pair`, `'closure`, `'string`, `'vector`, `'bytevector`, `'flonum` のタグ値を返却。
  - `(repr-field-offset kind byte-offset [repr])`: `(- byte-offset (repr-heap-tag kind repr))` を返却（例：`repr:scheme-64bit-tagged` の `'pair` で `byte-offset=0` → `-1`、`byte-offset=8` → `7`；`repr:c-unboxed` では `0` と `8`）。
- **LIR 命令列ジェネレータ (`box-code-generator` / `unbox-code-generator`)**:
  - `(repr-emit-box-fixnum dst src [repr])`:
    - `shift = 0` かつ `tag = 0` (`repr:c-unboxed`) の場合：`(equal? dst src)` なら `'()`、異なれば `((%mov dst src))`。
    - `shift > 0` (`repr:scheme-64bit-tagged`) の場合：`(%shl dst shift)`（および `tag != 0` なら `(%bit-or dst tag)`）。
  - `(repr-emit-unbox-fixnum dst src [repr])`:
    - `shift = 0` (`repr:c-unboxed`) の場合：`(equal? dst src)` なら `'()`、異なれば `((%mov dst src))`。
    - `shift > 0` (`repr:scheme-64bit-tagged`) の場合：`(%sar dst shift)`。
  - `(repr-emit-box-flonum dst src [repr])` / `(repr-emit-unbox-flonum dst src [repr])`:
    - `repr:scheme-64bit-tagged`: `%r12` への 16 バイト確保＋タグ `11` 付与＋`(%store-typed f64 dst -3 src)` / `(%load-typed f64 dst src -3)`。
    - `repr:c-unboxed` / `repr:nan-boxing-64bit`: タグ付きヒープ確保不要な生ビット転送または直接浮動小数点移動を生成。
  - `(repr-emit-type-tag-check dst src mask expected-tag [repr])`:
    - タグ判定用の LIR 命令列を生成。

### ステップ 4: 既存コンパイラパス (`090`, `129`, `130`, `131`) との統合
1. **`ulisp/frontend/090_rtyper.scm`**:
   - `(rtyper-Current-repr-requires-boxing?)` 等を介して `(repr-requires-boxing?)` を参照可能にし、`repr:c-unboxed` 下ではボクシング境界挿入を抑止できるようにする。
2. **`ulisp/lir/130_lir.scm`**:
   - `(lir-immediate expr)` 内のハードコードされた `(* expr 4)`, `111`, `47`, `(+ (* (char->integer expr) 256) 14)`, `63` を `(repr-encode-immediate expr)` 呼び出しに置換。
3. **`ulisp/lir/129_lir_primitives.scm`**:
   - `eof-object`, `fxadd1`, `fxsub1`, `fixnum?`, `null?`, `not`, `car`, `cdr`, `pair?`, `string?`, `vector?`, `bytevector?` のハードコード定数を `repr-encode-eof`, `repr-fixnum-step`, `repr-fixnum-mask`, `repr-encode-null`, `repr-encode-boolean`, `repr-field-offset`, `repr-heap-tag`, `repr-pointer-mask` 経由に置換。
4. **`ulisp/lir/131_lower_managed_dialect.scm`**:
   - `%box-fixnum`, `%unbox-fixnum`, `%managed-box`, `%managed-unbox`, `%box-flonum`, `%unbox-flonum` の展開ロジックを `repr-emit-box-fixnum`, `repr-emit-unbox-fixnum`, `repr-emit-box-flonum`, `repr-emit-unbox-flonum` に委譲。

### ステップ 5: 単体テストと品質ゲート検証
- `ulisp/tests/test_value_representation.scm` を新設し、以下を検証：
  1. `define-value-repr` によるスペック定義・バリデーション・エイリアス解決（`repr:scheme-64bit-tagged` / `scheme-standard`, `repr:c-unboxed` / `c-unboxed`, `repr:nan-boxing-64bit`）
  2. 各表現における Fixnum / Boolean / Null / Char / EOF の即値エンコード・デコードおよびヒープフィールドオフセット算出
  3. `repr:scheme-64bit-tagged` と `repr:c-unboxed` の切り替えによる `repr-emit-box-fixnum` / `repr-emit-unbox-fixnum` / Pass 131 `lower-managed-dialect` の出力差分検証（Scheme では `%shl`/`%sar` 2、C Unboxed ではシフト命令ゼロ）
  4. 生成された Core Machine LIR を Reference VM (`ulisp/vm/lir_interpreter.scm`) で直接評価し、両表現で算術・メモリアクセスが意図通り動作することの実証

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp/compiler/value_repr.scm` が実装され、`define-value-repr` マクロによって `repr:scheme-64bit-tagged`（`scheme-standard`）、`repr:c-unboxed`（`c-unboxed`）、`repr:nan-boxing-64bit` が宣言的に定義されていること。
- [ ] `ulisp/lir/130_lir.scm`, `ulisp/lir/129_lir_primitives.scm`, `ulisp/lir/131_lower_managed_dialect.scm` における即値・タグ・ボクシングのマジックナンバーが `value_repr.scm` の API 呼び出しに集約されていること。
- [ ] `with-value-repr` により `repr:scheme-64bit-tagged` と `repr:c-unboxed` を切り替えて同一のコードジェネレータ・Pass 131 Lowering を駆動でき、それぞれ適切な LIR 命令列（タグシフト付き vs シフトなし恒等命令）が出力されること。
- [ ] 新規単体テストスイート `ulisp/tests/test_value_representation.scm`（`make -C ulisp test_value_representation`）が 100% PASS すること。
- [ ] 既存の全テストスイート（`test_lir_dialect_separation`, `test_typed_lir`, `test_lir_interpreter`, `test_passes` 等）および `make py_compile && make static_analysis` に一切の回帰がないこと。
