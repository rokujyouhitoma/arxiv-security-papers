---
ID: 826
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-11-15
---

# [FEAT] 機械型 (i8..i64, f32, f64, ptr) を備えた Typed LIR への移行とボクシング操作の直交分離 (ID: 826)

## 1. 概要 / Summary
低レベル中間表現（LIR）の仮想レジスタおよびオペランドに明示的な機械型（Machine Types: `i8`, `i16`, `i32`, `i64`, `f32`, `f64`, `ptr`, `raw-bits`）注釈を導入し、Typed LIR として再構築する。
Scheme 特有の動的型ボクシング（`%box-fixnum`, `%unbox-fixnum`, `%alloc` 等）を、純粋なビット操作（`%shl`, `%shr`, `%or` 等）およびヒープメモリ割り当て（GC ランタイム呼出し）に直交分離する。
これにより、Scheme における連続した浮動小数点演算ループのアンボックス最適化（Unboxed Flonum / XMM レジスタ直接演算）を可能にするとともに、C 言語のプリミティブ型・ポインタ型・幅指定メモリアクセスを同一の LIR インフラで統一的に扱えるアーキテクチャを実現する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38 仕様書**: §2 (B5: 型付き C の LIR 表現, E1: 幅指定ロード/ストア, E4: f64 浮動小数点演算, E9: LIR 形式意味論)
- **DSN-33 仕様書**: §2.1 (Tagged Pointer メモリモデル: Fixnum 1bit tag `val << 1 | 1`), §3.3 (LIR 最適化・コード生成パイプライン)
- **関連 Issue**:
  - #816: Nanopass 型アノテーションによる型推論（090_rtyper）とエスケープ解析
  - #828: 符号付き・符号なしオーバーフロー検出付き算術演算
  - #831: C バックエンドと AOT ネイティブ ELF バックエンドの命令セット同期

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lir/lir_lang.scm](../../../ulisp/lir/lir_lang.scm): 機械型ターミナル、型付きレジスタ/オペランド、浮動小数点命令（`%fadd` 等）、幅指定メモリアクセス（`%load-typed`, `%store-typed`）の言語定義
- [x] [ulisp/lir/lir_verifier.scm](../../../ulisp/lir/lir_verifier.scm): Typed LIR 型整合性検証器の拡張（レジスタ型チェック、幅整合性）
- [x] [ulisp/lir/130_lir.scm](../../../ulisp/lir/130_lir.scm): AST/ANF から Typed LIR への Lowering ロジック、ボクシング直交化
- [x] [ulisp/lir/133_lir_peephole.scm](../../../ulisp/lir/133_lir_peephole.scm): アンボックス化された冗長な `%box` / `%unbox` ペアの相殺除去
- [x] [ulisp/backend/140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm): 機械型に応じた x86_64 レジスタ（RAX/EAX/AX/AL, XMM0〜XMM15）選択および命令生成
- [x] [ulisp/backend/160_backend_c.scm](../../../ulisp/backend/160_backend_c.scm): C バックエンドにおける機械型（`int8_t`〜`int64_t`, `double`, `uintptr_t`）の出力
- [x] [ulisp/tests/test_typed_lir.scm](../../../ulisp/tests/test_typed_lir.scm): Typed LIR 生成・型検証・アンボックス最適化の単体テスト（新規作成）

---

## 4. セキュリティ・設計分析 (Threat Modeling & Constraints)
- **CWE-843 (Type Confusion / Type Inconsistency in Intermediate Representation)**:
  - 整数演算命令に浮動小数点レジスタが渡されたり、`ptr` 型ポインタ演算に不正なオフセットが混入し、メモリ破損を招くリスク。
  - **対策**: `lir_verifier.scm` にて、命令ごとの許容型シグネチャ（例: `%fadd` は `(f64, f64) -> f64` のみ受理、`%load-typed` は基底レジスタが `ptr` であることを必須化）を静的に全走査・厳格検証。
- **CWE-119 / CWE-125 / CWE-787 (Memory Access & Buffer Bounds Boundary Violations)**:
  - 8bit/16bit/32bit/64bit 幅のストア操作において、境界外書き込みやゼロ拡張・符号拡張の不一致による未初期化領域読み取りのリスク。
  - **対策**: 幅指定メモリアクセス命令（`%load-typed type reg mem` / `%store-typed type mem opnd`）において、サイズ（1, 2, 4, 8バイト）および符号属性（`:signed` / `:unsigned`）を命令定義段階で明示化。
- **Tagged Pointer と Raw Bits の完全分離**:
  - Scheme のタグ付きポインタ（最下位ビット `0b01` = Fixnum 等）と、C 言語ネイティブの純粋な 64bit 整数（Raw bits）が混同されないよう、LIR レベルで `scheme-val` 型と `i64` / `u64` 型を区別可能にする。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/826-typed-machine-lir-orthogonal-boxing`

### ステップ 1: `lir_lang.scm` における機械型および型付き命令の形式定義
1. **Machine Types ターミナル**:
   - `(MachineType (mty) i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 ptr raw-bits scheme-val)`
2. **型付きレジスタ・オペランド**:
   - `(TypedReg (%reg mty x))`
   - `(FloatReg %xmm0 %xmm1 ... %xmm15 (%freg x))`
3. **直交化されたプリミティブ命令の追加**:
   - 幅指定ロード・ストア:
     - `(%load-typed mty reg mem)`
     - `(%store-typed mty mem opnd)`
   - 浮動小数点演算:
     - `(%fadd f_reg1 f_reg2)`
     - `(%fsub f_reg1 f_reg2)`
     - `(%fmul f_reg1 f_reg2)`
     - `(%fdiv f_reg1 f_reg2)`
     - `(%fcmp f_reg1 f_reg2)`
   - ビット分解されたボクシング・アンボクシング:
     - Tagged Fixnum Box: `(%shl raw_val 1)` + `(%or shifted_val 1)`
     - Tagged Fixnum Unbox: `(%sar tagged_val 1)`
     - Heap Flonum Box: `(%alloc box_reg 16 flonum_tag)` + `(%store-typed f64 (%mem box_reg 8) f_val)`

### ステップ 2: `lir_verifier.scm` の型規則検査器の実装
1. レジスタ定義-使用連鎖（Def-Use Chain）における型の単一性（Type Consistency）の検証。
2. 算術・論理命令のオペランド型整合性チェック:
   - `%add`, `%sub`, `%imul` は整数型（`i8`〜`i64`）または `scheme-val` に限定。
   - `%fadd`, `%fsub`, `%fmul`, `%fdiv` は `f32` / `f64` に限定。
3. 不正な型混在（例: `(%fadd (%reg i64 a) (%reg f64 b))`）を検出した場合は明確な Verifier エラーメッセージを出力してコンパイルを中断。

### ステップ 3: `130_lir.scm` における Lowering とボクシングの直交分離
1. `090_rtyper` の推論型情報を引き継ぎ、型が `flonum` と確定している中間式に対しては、ヒープアロケーションを伴う `%box-flonum` を即座に発行せず、XMM 仮想レジスタ（`f64`）を用いたネイティブ浮動小数点 LIR を出力。
2. Scheme 関数の境界（ABI）やヒープオブジェクトへの格納時のみ明示的な Box 命令を発行。
3. `133_lir_peephole.scm` に `%box` -> 直後の `%unbox` を相殺・バイパスするピープホール最適化ルールを追加。

### ステップ 4: バックエンド（x86_64 & C）のコード生成対応
1. `140_backend_x86_64.scm`:
   - `f64` 型命令に対して `addsd`, `subsd`, `mulsd`, `divsd`, `ucomisd`, `movsd` 命令を出力。
   - 幅指定ロード・ストアに対して `movzbq`, `movzwq`, `movsbl`, `movswl`, `movl`, `movq` を使い分け。
2. `160_backend_c.scm`:
   - 各機械型を標準 C99 ヘッダ（`<stdint.h>`）の `int8_t`, `int16_t`, `int32_t`, `int64_t`, `double`, `uintptr_t` にトランスパイル。

### ステップ 5: 単体テスト `test_typed_lir.scm` の構築
1. **型検証テスト**: 不正な型の組み合わせが `lir_verifier.scm` で正しく拒絶されること。
2. **幅指定メモリアクセステスト**: `i8`, `i16`, `i32`, `i64` のロード・ストアが正しくコード生成されること。
3. **Unboxed 浮動小数点計算テスト**: 浮動小数点の連続計算において、不要な中間ヒープボクシングが排除され、XMM レジスタのみで完結すること。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/lir/lir_lang.scm` に機械型および型付き命令（幅指定メモリアクセス、浮動小数点演算）が定義されていること。
- [x] `ulisp/lir/lir_verifier.scm` にて型整合性・レジスタ型一致の静的検証が実装され、不正な型混在が検出されること。
- [x] `ulisp/lir/130_lir.scm` で Fixnum / Flonum のボクシングが直交分離され、型付き LIR が生成されること。
- [x] `make -C ulisp test_typed_lir` が新規作成され、型チェック・アンボックス最適化の全テストに PASS すること。
- [x] `make -C ulisp verify_zero_gauche` および `make -C ulisp lint_sexpr` が PASS すること。
- [x] 既存の全テストスイートおよびセルフホストブートストラップ検証（`test_pure_bootstrap.sh`）がリグレッションなく PASS すること。
