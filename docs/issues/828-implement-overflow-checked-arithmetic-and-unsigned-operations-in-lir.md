---
ID: 828
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT] LIR におけるオーバーフロー検知付き算術および符号なし演算オペコードの新設 (ID: 828)

## 1. 概要 / Summary
低レベル中間表現（LIR）に、符号なし整数演算（符号なし除算 `%udiv`、符号なし剰余 `%urem`、論理右シフト `%shr`、符号なし比較条件コード `%setb`/`%setbe`/%seta`/%setae`）と、CPU フラグ直結のペア出力型オーバーフロー検知付き算術命令（`%add-overflow`, `%sub-overflow`, `%mul-overflow`）を第一級オペコードとして新設する。
これにより、Scheme における Fixnum 算術のオーバーフロー判定（Bignum への昇格ガード）を、冗長な事前分岐演算からハードウェアフラグ（x86-64 の `seto`/`jo`、AArch64 の `VS` 条件フラグ）直結の最短コードへ最適化するとともに、C 言語の符号なし型（`uint8_t`〜`uint64_t`, `size_t` 等）の厳密な規格準拠演算（DSN-33-02 §4.3, DSN-38 §2 E2）を実現する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33-02 仕様書**: §4.3 (オーバーフロー検知付き算術 ＆ 符号なし演算オペコード), §3.1 (多言語 AST からの Lowering)
- **DSN-33 仕様書**: §2.1 (Tagged Pointer メモリモデル), §3.3 (LIR 最適化・コード生成パイプライン)
- **DSN-38 仕様書**: §2 (E1: 拡張命令, E2: 符号なし命令, E9: LIR 意味論)
- **関連 Issue**:
  - #826: 機械型を備えた Typed LIR への移行とボクシング操作の直交分離
  - #831: 160 Portable C バックエンドにおける型付き機械語 LIR セマンティクスの完全同期と差分ファジング検証
  - #832: 純粋 Scheme による多倍長整数 (Bignum) および IEEE 754 相互変換標準ライブラリの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lir/lir_lang.scm](../../ulisp/lir/lir_lang.scm): 新設オペコード（`%add-overflow`, `%sub-overflow`, `%mul-overflow`, `%udiv`, `%urem`, `%setb`, `%setbe`, `%seta`, `%setae`）の構文定義
- [ ] [ulisp/lir/lir_verifier.scm](../../ulisp/lir/lir_verifier.scm): オーバーフロー算術・符号なし命令のオペランド数・型・レジスタ制約の静的型整合性検証（CWE-843, CWE-190/191 防御）
- [ ] [ulisp/lir/129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm): 新設命令の LIR プリミティブディスパッチ定義
- [ ] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm): AST/ANF からの新設命令への Lowering ロジック
- [ ] [ulisp/compiler/primitives.scm](../../ulisp/compiler/primitives.scm): 新設オペコードの述語（`binop-prim?`, `lir-primitive?` 等）登録
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm): x86_64 命令生成（`add`+`seto`/`jo`, `sub`+`seto`/`jo`, `imul`+`seto`/`jo`, `xor edx, edx`+`div`, `setb`/`setbe`/`seta`/`setae`）
- [ ] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm): C99 バックエンド生成（`__builtin_add_overflow`, `__builtin_sub_overflow`, `__builtin_mul_overflow`, `uint64_t` キャスト除算・剰余）
- [ ] [ulisp/backend/150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm): AArch64 バックエンド生成（`adds`+`cset vs`, `subs`+`cset vs`, `udiv`, `msub`）
- [ ] [ulisp/tests/test_lir_overflow_and_unsigned.scm](../../ulisp/tests/test_lir_overflow_and_unsigned.scm): 演算検証テストスイート（新規作成）
- [ ] [ulisp/Makefile](../../ulisp/Makefile): `test_lir_overflow_and_unsigned` ターゲット追加

---

## 4. セキュリティ・設計分析 (Threat Modeling & Constraints)
- **CWE-190 / CWE-191 (Integer Overflow or Wraparound)**:
  - 整数演算の桁あふれが見逃され、不正な小さな値や負値として扱われることで、バッファサイズ計算ミス、ヒープ境界破壊、またはポインタ計算の破綻を招くリスク。
  - **対策**: ペア出力型命令（`%add-overflow dst-val dst-flag src1 src2` 等）により、演算結果と同時にオーバーフローフラグ（0 or 1 / 真偽値）を確実に返却。Scheme ランタイムではフラグを即座に判定し、Bignum 昇格ハンドラまたは例外へと確実にディスパッチする。
- **CWE-369 (Divide By Zero)**:
  - `%udiv` および `%urem` において除数（Denominator）が 0 の場合に CPU 例外（SIGFPE）が発生し、プロセスがクラッシュするリスク。
  - **対策**: LIR レベルでの静的ゼロ検証または除数 0 ガード規約を策定。テストスイートにてゼロ除算時の明確な例外捕捉および動作境界を検証する。
- **CWE-843 (Type Confusion / Register Role Inconsistency)**:
  - `dst-val`（計算結果）と `dst-flag`（オーバーフロー真偽値）のレジスタ混同や、浮動小数点レジスタの誤用。
  - **対策**: `lir_verifier.scm` にて、`dst-flag` は必ず GPR（汎用レジスタ）であり、各引数が整数型オペランドであることを厳格に検査する。
- **純粋 Scheme (Zero External / Gauche Dependency)**:
  - 外部 Gauche ライブラリに一切依存せず、純粋な R7RS / ULisp S式構文で完結させる。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/828-lir-overflow-and-unsigned-ops`

### ステップ 1: `lir_lang.scm` における命令構文の形式定義
1. ペア出力型オーバーフロー算術命令:
   - `(%add-overflow dst-val dst-flag src1 src2)`
   - `(%sub-overflow dst-val dst-flag src1 src2)`
   - `(%mul-overflow dst-val dst-flag src1 src2)`
2. 符号なし除算・剰余・論理右シフト命令:
   - `(%udiv dst src1 src2)`
   - `(%urem dst src1 src2)`
   - `(%shr dst src1 count)`（定義確認と拡張）
3. 符号なし比較条件コード命令:
   - `(%setb dst)` (Below / Unsigned less than: CF=1)
   - `(%setbe dst)` (Below or Equal / Unsigned less than or equal: CF=1 or ZF=1)
   - `(%seta dst)` (Above / Unsigned greater than: CF=0 and ZF=0)
   - `(%setae dst)` (Above or Equal / Unsigned greater than or equal: CF=0)

### ステップ 2: `lir_verifier.scm` の型および引数検査器の実装
1. `%add-overflow`, `%sub-overflow`, `%mul-overflow` に対する厳格な形式チェック:
   - 4 引数（dst-val: GPR, dst-flag: GPR, src1: operand, src2: operand）の構造確認。
   - `dst-val` と `dst-flag` が同一レジスタでないことの検証（非破壊的フラグ出力）。
2. `%udiv`, `%urem` に対する 3 引数（dst: GPR, src1: operand, src2: operand）の構造確認。
3. 浮動小数点レジスタ（`%xmm0` 等）が渡された場合は CWE-843 エラーとして弾く。

### ステップ 3: x86_64 バックエンド (`140_backend_x86_64.scm`) のコード生成
1. `%add-overflow dst-val dst-flag src1 src2`:
   - `dst-val` に `src1` をロードし、`add dst-val, src2` を発行。
   - 直後に `seto byte ptr <flag-reg>` + `movzx dst-flag, byte ptr <flag-reg>` を生成。
2. `%sub-overflow dst-val dst-flag src1 src2`:
   - `dst-val` に `src1` をロードし、`sub dst-val, src2` を発行。
   - 直後に `seto` + `movzx` を生成。
3. `%mul-overflow dst-val dst-flag src1 src2`:
   - `imul dst-val, src2` 発行後、`seto` + `movzx` を生成。
4. `%udiv dst src1 src2` / `%urem dst src1 src2`:
   - `rax` に被除数をロード、`rdx` を `xor edx, edx` で 0 クリア。
   - `div <divisor>` を発行し、商（`rax`）または余り（`rdx`）を `dst` へ格納。
5. 符号なし比較:
   - `cmp src1, src2` 後の `setb`, `setbe`, `seta`, `setae` 命令生成。

### ステップ 4: Portable C99 (`160_backend_c.scm`) および AArch64 (`150_backend_aarch64.scm`) の対応
1. C99 バックエンド:
   - GCC/Clang 拡張 `__builtin_add_overflow(src1, src2, &dst-val)` を用いて真偽値を `dst-flag` へ代入。
   - `%udiv` / `%urem` は `(uint64_t)src1 / (uint64_t)src2` および `%` を出力。
2. AArch64 バックエンド:
   - `adds` / `subs` 発行後に `cset dst-flag, vs` を出力。
   - `udiv` 命令および `msub` 命令による符号なし除算・剰余出力。

### ステップ 5: 包括的テストスイートの構築
1. `ulisp/tests/test_lir_overflow_and_unsigned.scm` を新規作成:
   - 正常系算術演算（オーバーフローなし、フラグ = 0）
   - 境界値加算（`0x7fffffffffffffff + 1` でフラグ = 1）
   - 境界値減算（`-0x8000000000000000 - 1` でフラグ = 1）
   - 境界値乗算（`0x4000000000000000 * 4` でフラグ = 1）
   - 符号なし除算（`0xffffffffffffffff / 2` が正の大きな商を返すこと）
   - 符号なし比較（`-1` と `1` の比較で unsigned では `-1` が Above と判定されること）
   - Verifier による不正レジスタ混在の検出
2. `make -C ulisp test_lir_overflow_and_unsigned` ターゲットを Makefile に追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp/lir/lir_lang.scm` にオーバーフロー検知付き算術命令および符号なし除算・剰余・比較命令が定義されていること。
- [ ] `ulisp/lir/lir_verifier.scm` にて引数構造およびレジスタ制約が静的検証され、不正な型混在が検出されること。
- [ ] x86_64 バックエンド（140）、C99 バックエンド（160）、および AArch64 バックエンド（150）で各命令が正確なマシンコード / C コードへと Lowering されること。
- [ ] 新規単体テスト `test_lir_overflow_and_unsigned.scm` が全項目（正常系・境界値・エラー系）で 100% PASS すること。
- [ ] `make -C ulisp verify_zero_gauche` および `make -C ulisp lint_sexpr` が PASS すること。
- [ ] 既存の全テストスイート（782 件の Nanopass 単体テスト）およびセルフホストブートストラップ（`test_pure_bootstrap.sh`）にリグレッションがないこと。
