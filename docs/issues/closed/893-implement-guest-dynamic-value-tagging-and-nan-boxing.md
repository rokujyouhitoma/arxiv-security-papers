---
ID: 893
種別: Feature
優先度: High
ステータス: Closed (完了日: 2026-11-21)
---

# [FEAT/ENH] Implement Guest Dynamic Value Tagging and NaN-Boxing (ID: 893)

## 1. 概要 / Summary
[[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) 第 2.3 節（動的型タグ表現と NaN-boxing / Tagged Pointer 最適化）に基づき、言語ワークベンチにおいてゲスト言語が動的型付き言語（Python, Ruby, JavaScript, Lua 等）である場合に、実行時オーバーヘッドおよびメモリフットプリントを極小化する **3-bit Tagged Pointer** および **64-bit Quiet NaN-boxing** のデュアル表現モジュールを実装する。

ナイーブな動的言語処理系では、すべての値がヒープ上のボックスオブジェクト（ヘッダ・型タグ・値のポインタ）として割り当てられ、算術演算や関数適用のたびにメモリトラフィックと型チェック分岐が発生する。本 Issue では以下の 2 つの高度な値表現系をワークベンチコンポーネントとして提供し、さらにステージ多相メタコンパイラ（`stage-poly-lower` / `eval-in-stage`）と連携させることで、静的型推論によって不要なタグ付け（Boxing）および型判定（Tag Check）を残余コードから完全に消去（Tag Stripping）する。

1. **3-bit Pointer Tagging**: x86-64 の 8 バイトメモリアライメント（下位 3 ビット 0）を活用し、61-bit Fixnum、Pair、Symbol、Closure、Vector、Instance、Flonum、特殊値を単一 64-bit ワードに多重化。
2. **64-bit Quiet NaN-Boxing**: IEEE-754 64-bit 浮動小数点数の非正規化 Quiet NaN 空間（上位 16 ビット）に型タグを埋め込み、下位 48 ビットにポインタまたは 32 ビット即値を格納。倍精度浮動小数点数をゼロアロケーションで直接演算可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-04] ULisp 言語ワークベンチ・インタプリタ自動生成 ＆ ゲスト言語ランタイムアーキテクチャ設計書 (第2.3節 動的型タグ表現と NaN-boxing)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [[DSN-33-03] ULisp ステージ多相メタコンパイラ ＆ 二村射影フラクタル実行基盤設計書 (第4.4節 Data Plane 境界 Tag Stripping)](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md)
  - [[DSN-33-02] ULisp 多言語フロントエンド ＆ 型付き機械語 LIR 設計書 (第5.1節 プラガブル値表現)](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md)
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
- 先行 Issue:
  - [[Issue #892] ゲスト言語スタックフレーム抽象（FrameDescriptor）とローカルスロット降格の実装](closed/892-implement-guest-frame-descriptor-and-local-slot-lowering.md)
  - [[Issue #884] Data Plane 境界の Tag Stripping と 64-bit 単一ワード正規化の実装](closed/884-implement-data-plane-tag-stripping-and-single-word-repr.md)
  - [[Issue #836] define-value-repr による値表現・ボクシング方式のプラグイン化](closed/836-plugin-value-representation-and-boxing-scheme.md)

---

## 3. セキュリティ分析と脅威モデル / Security Threat Analysis
動的言語の値表現とポインタタギングは、型混同（Type Confusion）や境界破壊の攻撃対象になりやすい。以下の脅威モデルに基づき多層防御を講じる。

1. **CWE-843: Type Confusion (型混同)**:
   - *脅威*: ゲスト言語プログラムが未初期化領域や不正なビット列をオブジェクトポインタとして逆参照し、任意のヒープ破壊や制御フローハイジャックを引き起こす。
   - *防御策*: 
     - 実行時（Later）のアンパッキング操作には、タグビット一致判定の安全アサーション命令（`guest-tag-assert!`）を標準付与。
     - BTA（束縛時間解析）により静的に型安全が数学的に証明されたパスのみ、コンパイル時にタグ検査命令を除去（Sound Tag Elimination）。
2. **CWE-190: Integer Overflow / Improper Shift Operations**:
   - *脅威*: 61-bit Fixnum（3-bit shift）や 32-bit Int のパッキング時にビットあふれが発生し、上位ビットが型タグ領域を上書きして別型へ化ける。
   - *防御策*: パッキング API（`guest-pack-fixnum`）において、61-bit（または 32-bit）境界超過を検知し、オーバーフロー時は自動的に Bignum/Flonum またはエラーへトラップ。
3. **CWE-119 / CWE-125: Memory Access Out-of-Bounds (48-bit 正準アドレス破壊)**:
   - *脅威*: NaN-boxing において、下位 48 ビットペイロードに 48 ビットを超える非正準（Non-canonical）アドレスが格納され、一般保護違反（#GP）や不正メモリアクセスが発生する。
   - *防御策*: ポインタの NaN パッキング時に `0x0000FFFFFFFFFFFF`（下位 48 ビット）マスクおよび正準符号拡張チェックを強制。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/workbench/value_tagging.scm](../../ulisp/workbench/value_tagging.scm) (新規: 3-bit Pointer Tagging 定義・パッキング・アンパッキング・型述語 API)
- [x] [ulisp/workbench/nan_boxing.scm](../../ulisp/workbench/nan_boxing.scm) (新規: 64-bit Quiet NaN-boxing 定義・浮動小数点アンボクシング API)
- [x] [ulisp/compiler/eval_in_language.scm](../../ulisp/compiler/eval_in_language.scm) (ステージ多相メタコンパイラへのゲスト言語タグ操作プリミティブ登録と Now/Later 簡約規則)
- [x] [ulisp/tests/test_workbench_tagging.scm](../../ulisp/tests/test_workbench_tagging.scm) (新規: タギングおよび NaN-boxing の単体・部分評価残余コード検証テスト)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`COMPILER_BASE` へのモジュール追加および `test_workbench_tagging` ターゲット追加)
- [x] [docs/issues/README.md](README.md) (Issue 台帳ステータス更新)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/893-implement-guest-dynamic-value-tagging-and-nan-boxing`

### Phase 1: 3-bit Pointer Tagging モジュール (`ulisp/workbench/value_tagging.scm`)
1. DSN-33-04 第 2.3 節に準拠した 3-bit タグ定数群を定義：
   ```scheme
   (define GUEST_TAG_FIXNUM   0) ; 000: 61-bit signed int (n << 3 | 0)
   (define GUEST_TAG_PAIR     1) ; 001: Pair / Cons cell (ptr | 1)
   (define GUEST_TAG_SYMBOL   2) ; 010: Symbol / Interned string (ptr | 2)
   (define GUEST_TAG_CLOSURE  3) ; 011: Guest Closure (ptr | 3)
   (define GUEST_TAG_VECTOR   4) ; 100: Array / Vector (ptr | 4)
   (define GUEST_TAG_INSTANCE 5) ; 101: Guest Object Instance (ptr | 5)
   (define GUEST_TAG_FLONUM   6) ; 110: Heap Flonum (ptr | 6)
   (define GUEST_TAG_SPECIAL  7) ; 111: Immediates (#f, #t, nil, undef)
   (define GUEST_TAG_MASK     7) ; 3 bits
   ```
2. パッキング / アンパッキング / 述語 API 群：
   - `(guest-pack-fixnum n)`, `(guest-unpack-fixnum v)`, `(guest-fixnum? v)`
   - `(guest-pack-pointer ptr tag)`, `(guest-unpack-pointer v tag)`, `(guest-pointer-of-tag? v tag)`
   - `(guest-pack-special id)`, `(guest-unpack-special v)`
3. 残余コード / LIR 向けエミッタヘルパー：
   - `(guest-emit-tag-check v tag)`: `(= (bitwise-and v 7) tag)` を生成
   - `(guest-emit-untag v tag)`: `(- v tag)` を生成

### Phase 2: 64-bit Quiet NaN-Boxing モジュール (`ulisp/workbench/nan_boxing.scm`)
1. IEEE-754 64-bit Quiet NaN レイアウト定数群：
   - NaN Base: `0x7FF8000000000000` (Exponent 11 bits all 1, Quiet bit = 1)
   - Payload Mask: `0x0000FFFFFFFFFFFF` (下位 48 ビット)
   - Tag Shift: 48, Tag Unit: `1 << 48`
   - NaN Tag 分類:
     - `0`: Raw Flonum (IEEE-754 倍精度浮動小数点数そのもの)
     - `1`: 32-bit Integer (`int32` payload)
     - `2`: Special Immediates (`false`, `true`, `nil`, `undefined`)
     - `3`: Heap Pointer (48-bit pointer payload)
2. パッキング / アンパッキング / 判定 API 群：
   - `(nan-box-flonum f)`, `(nan-unbox-flonum v)`, `(nan-is-flonum? v)`
   - `(nan-box-int32 n)`, `(nan-unbox-int32 v)`, `(nan-is-int32? v)`
   - `(nan-box-pointer ptr)`, `(nan-unbox-pointer v)`, `(nan-is-pointer? v)`
   - `(nan-box-special id)`, `(nan-is-special? v)`
3. 浮動小数点演算のゼロアロケーション性：
   - `(nan-is-flonum? v)` が真の場合、ビット列をそのまま倍精度浮動小数点レジスタ（`xmm`）にロードしてハードウェア演算可能にする。

### Phase 3: ステージ多相メタコンパイラ (`eval_in_language.scm`) への統合とタグ消去最適化
1. `eval_in_language.scm` の既知プリミティブ群にゲスト言語タグ操作関数を登録：
   - `guest-pack-fixnum`, `guest-unpack-fixnum`, `guest-fixnum?`
   - `guest-pack-pointer`, `guest-unpack-pointer`, `guest-tag-of`
   - `nan-box-flonum`, `nan-unbox-flonum`, `nan-is-flonum?`
2. Later 辞書における条件分岐簡約と Tag Stripping 規則の実装：
   - `(guest-fixnum? (guest-pack-fixnum x))` → `#t` （Now 簡約）
   - `(guest-unpack-fixnum (guest-pack-fixnum x))` → `x` （静的打消し簡約）
   - 静的型ヒント（GFD slot-types や BTA 4値束型注釈）により対象変数が確実に Fixnum / Flonum である場合、前後の packing / unpacking / tag-check をすべてバイパスし、生の演算コード（例: `(+ a b)`）のみを残余 ANF に出力。

### Phase 4: テストスイートの実装と検証 (`ulisp/tests/test_workbench_tagging.scm`)
1. **Group 1: 3-bit Tagged Pointer 基本特性テスト**:
   - 各データ型（Fixnum, Pair, Symbol, Closure, Vector, Instance, Flonum, Special）のパッキング・アンパッキング可逆性検証。
   - 境界値（負の数、61-bit 最大値・最小値）でのビット整合性検証。
2. **Group 2: 64-bit NaN-Boxing 基本特性テスト**:
   - 倍精度浮動小数点数の同一性保持（正負の 0.0、極小値、極大値、Inf）。
   - 32-bit 整数および 48-bit ポインタの埋め込み・抽出検証。
3. **Group 3: セキュリティ境界テスト (CWE-843 / CWE-190 防御)**:
   - 型タグ不一致時の検出とトラップ動作。
   - 48-bit ペイロードマスクによる非正準ポインタ防御。
4. **Group 4: 第1二村射影 × Tag Stripping 結合テスト**:
   - 動的型付きゲスト言語の小さな算術式（例: `(+ x y)`）を部分評価し、残余コードからタグ検査分岐およびパッキング操作が 100% 消去され、純粋な算術命令（`+`）のみが出力されることをアサーション検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/workbench/value_tagging.scm` が新規作成され、3-bit Tagged Pointer API が実装されていること。
- [x] `ulisp/workbench/nan_boxing.scm` が新規作成され、64-bit Quiet NaN-Boxing API が実装されていること。
- [x] `eval_in_language.scm` において、静的に型が確定した値に対するパッキング・アンパッキングがコンパイル時に相殺・除去されること。
- [x] CWE-843（型混同）および CWE-190（オーバーフロー）に対する安全防御がテストで実証されること。
- [x] `make -C ulisp test_workbench_tagging` が 100% PASS すること。
- [x] `make -C ulisp lint_sexpr verify_zero_gauche` が PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。
- [x] [docs/issues/README.md](README.md) のステータスが更新されていること。
