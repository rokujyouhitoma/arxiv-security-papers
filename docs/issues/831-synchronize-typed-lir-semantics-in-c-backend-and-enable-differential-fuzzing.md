---
ID: 831
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT] 160 Portable C バックエンドにおける型付き機械語 LIR セマンティクスの完全同期と差分ファジング検証 (ID: 831)

## 1. 概要 / Summary
現在、ULisp コンパイラは Nanopass フレームワークに基づき、純粋 Scheme から機械語 LIR（Low-level Intermediate Representation）を経て複数のバックエンドコード生成器（140 x86-64 ネイティブ、150 AArch64、160 Portable C99）へ至るパイプラインを備えている。
先行する Issue #826（Typed Machine LIR）および Issue #828（Overflow-Checked Arithmetic & Unsigned Operations）により、LIR 命令セットには幅指定メモリアクセス（`%load-typed` / `%store-typed`）、型変換・符号拡張（`%trunc`, `%zext`, `%sext`）、IEEE 754 浮動小数点演算（`%fmov`, `%fadd`, `%fsub`, `%fmul`, `%fdiv`, `%fcmp`, `%sitofp`, `%fptosi`）、符号なし算術（`%udiv`, `%urem`, `%shr`）、オーバーフロー検知算術（`%add-overflow`, `%sub-overflow`, `%mul-overflow`）、および符号なし条件コード（`%setb`, `%setbe`, `%seta`, `%setae`）が導入された。

しかしながら、Pass 160（`ulisp/backend/160_backend_c.scm`）による Portable C99 コード生成器には以下の課題が存在する：
1. **セマンティクスの一部乖離・曖昧性**:
   - `%trunc`, `%zext`, `%sext` が同一のハンドラにまとめられており、`%trunc i8` や `%zext i8` において符号拡張（sign-extension）が行われてしまう不整合が存在する（x86-64 では `movzx` によるゼロ拡張が規格動作）。
   - `%fcmp` における浮動小数点数比較状態が C のフラグ変数に正確に反映されておらず、NaN や非順序比較（unordered comparison）における挙動の整合性が未検証である。
2. **C99 規格未定義動作 (Undefined Behavior) の回避**:
   - 符号付き整数オーバーフロー（Signed Overflow）は C99 規格上 UB であるため、Clang/GCC の最適化（`-O2`）によってオーバーフロー検知ロジックが消去（dead code elimination）されないよう、`__builtin_*_overflow` または unsigned キャストによる厳格な UB フリー実装が不可欠である。
   - 浮動小数点数と整数レジスタ間のビットキャストにおける Strict Aliasing 違反（CWE-843 / CWE-704）を回避し、規格準拠の安全なメモリ変換を保証する必要がある。
3. **バックエンド間差分検証（Differential Testing / Fuzzing）ハーネスの未整備**:
   - x86-64 ネイティブ実行（Pass 140）と C トランスパイル実行（Pass 160）が同一の LIR 入力に対して bit-for-bit で同一の結果を出力することを自動検証する差分ファジングテストハーネス（DSN-38 §2 K3）が未構築である。

本 Issue では、Pass 160 の C99 コード生成セマンティクスを x86-64 ネイティブ実装と 100% 同期・純化し、決定論的擬似乱数を用いた「LIR レベル差分ファジング検証スイート（`ulisp/tests/fuzz_lir_differential.scm`）」を実装することで、バックエンド間の恒常的セマンティクス完全一致を保証する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38 仕様書**: §2 (E10: C backend 対応, K3: LIR レベル差分ファジング, E1: 拡張命令, E2: 符号なし命令, E4: f64 浮動小数点演算, E9: LIR 形式意味論)
- **DSN-33-02 仕様書**: §4.3 (機械語命令セット不変条件), §5.1 (呼出規約と ABI 整合性)
- **関連 Issue**:
  - #695: ULisp Portable C99 バックエンドの Windows (MinGW/MSVC) 移植と Wine 実行検証
  - #696: ULisp Portable C99 バックエンドの macOS (Clang) 対応および GitHub Actions CI マトリクス検証の確立
  - #826: 機械型 (i8..i64, f32, f64, ptr) を備えた Typed LIR への移行とボクシング操作の直交分離
  - #828: LIR におけるオーバーフロー検知付き算術および符号なし演算オペコードの新設
  - #829: 呼出規約 (Calling Convention) の多重化・モジュール分離とゼロオーバーヘッド C-FFI の実現
  - #830: 144a アセンブラおよび 144 ELF リンカにおける複数セクション (.rodata/.data/.bss) と再配置の抽象化

---

## 3. 脅威モデルとセキュリティ要件 (Threat Model & Security Requirements)
本 Issue が扱う C コード生成および差分ファジングは、低レベルコンパイル基盤における堅牢性に直結するため、以下の脅威ベクトルを特定し緩和策を講じる：

| 脅威 ID | 脅威分類 (CWE) | 脅威シナリオ | 緩和策・設計上の防御不変条件 |
| :--- | :--- | :--- | :--- |
| **THREAT-831-1** | **CWE-843 / CWE-704**<br>型混同 & Strict Aliasing 違反 | 整数レジスタと浮動小数点レジスタのキャスト時にポインタ経由のキャスト（`*(double *)&reg_rax` 等）を行うと、C99 Strict Aliasing 規則違反による未定義動作（UB）となり、コンパイラ最適化で値が破壊される。 | レジスタ間のビットレベル転送には `memcpy` または共有共用体（`union`）を用い、ポインタの不正キャストを完全に排除する。 |
| **THREAT-831-2** | **CWE-190 / CWE-191**<br>符号付き整数オーバーフローの UB | 符号付き整数加算 `a + b` が `INT64_MAX` を超える場合、C99 規格上 UB となるため、`-O2` 時にコンパイラがオーバーフロー判定ブランチを消去する脆弱性。 | GCC/Clang の `__builtin_add_overflow` / `__builtin_sub_overflow` / `__builtin_mul_overflow` を最優先使用し、フォールバック時もすべての演算を `uint64_t` にキャストして明示的境界判定を行う。 |
| **THREAT-831-3** | **CWE-369**<br>ファジング生成命令によるゼロ除算 (SIGFPE) | ランダム LIR 生成器が無作為に 0 を除数として `%idiv` / `%udiv` / `%urem` を発行し、ファジングプロセスが SIGFPE クラッシュする。 | ファジング生成器において除数オペランドが 0 の場合は非ゼロ定数（`1` 等）に正規化するか、事前ガード条件を挿入してゼロ除算クラッシュを決定論的に防止する。 |
| **THREAT-831-4** | **CWE-125 / CWE-787**<br>不正メモリアドレスへの幅指定ロード／ストア | ファジングが生成した無作為な基底・オフセットがスタック領域やヒープ外のアドレスを指し、SEGV を引き起こす。 | ファジングハーネス専用の安全なスクラッチバッファ（1KB 境界整列バッファ）を静的配置し、メモリオフセットをそのバッファ境界内（0〜64 バイト）にクランプする。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/backend/160_backend_c.scm](file:///workspace/arxiv-security-papers/ulisp/backend/160_backend_c.scm): C99 バックエンドコード生成器（型付き LIR、幅指定メモリアクセス、符号拡張/ゼロ拡張の分離、オーバーフロー演算の純化）
- [ ] [ulisp/tests/fuzz_lir_differential.scm](file:///workspace/arxiv-security-papers/ulisp/tests/fuzz_lir_differential.scm): LIR レベル差分ファジングテストハーネス（決定論的擬似乱数、LIR 自動生成、x86-64 vs C99 出力突合）
- [x] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): `test_fuzz_lir` ターゲットの追加および `test` 統合
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の進捗更新

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/831-c-backend-typed-lir-fuzzing`

### ステップ 1: Pass 160 (`160_backend_c.scm`) のセマンティクス完全同期
1. **型変換・拡張オペコードの独立ハンドラ化**:
   - `%trunc`: 幅指定（`i8`, `u8`, `i16`, `u16`, `i32`, `u32`）に応じたマスクとゼロ拡張 `(uint64_t)(uintN_t)(src)` を生成。
   - `%zext`: 幅指定に応じたゼロ拡張 `(uint64_t)(uintN_t)(src)` を生成。
   - `%sext`: 幅指定に応じた符号拡張 `(uint64_t)(int64_t)(intN_t)(src)` を生成。
2. **幅指定ロード・ストア (`%load-typed`, `%store-typed`) の精密化**:
   - `i8`: `(uint64_t)(int64_t)(*(int8_t *)(base + off))`（符号拡張）
   - `u8`: `(uint64_t)(*(uint8_t *)(base + off))`（ゼロ拡張）
   - `i16`: `(uint64_t)(int64_t)(*(int16_t *)(base + off))`（符号拡張）
   - `u16`: `(uint64_t)(*(uint16_t *)(base + off))`（ゼロ拡張）
   - `i32`: `(uint64_t)(int64_t)(*(int32_t *)(base + off))`（`movsxd` 準拠の符号拡張）
   - `u32`: `(uint64_t)(*(uint32_t *)(base + off))`（`mov r32` 準拠のゼロ拡張）
   - `f32` / `f64`: 浮動小数点アラインメント保証と IEEE 754 準拠キャスト。
3. **符号なし演算およびオーバーフロー演算ヘルパーの強化**:
   - `__builtin_add_overflow`, `__builtin_sub_overflow`, `__builtin_mul_overflow` の安全なラッパー。
   - 符号なし除算 `%udiv` および余剰 `%urem` の 1-operand / 3-operand 形式の規格準拠生成。
   - 符号なし比較条件コード `%setb`, `%setbe`, `%seta`, `%setae` の境界値網羅。

### ステップ 2: LIR レベル差分ファジングハーネス (`ulisp/tests/fuzz_lir_differential.scm`) の構築
1. **決定論的 LIR 生成エンジン (Linear Congruential Generator / LCG)**:
   - 外部ライブラリ非依存の軽量 PRNG を実装し、シード値による完全再現性を保証。
   - 以下の命令カテゴリから有効な LIR 命令列を動的合成：
     - Category A (ALU): `%add`, `%sub`, `%mul`, `%idiv`, `%udiv`, `%urem`, `%shl`, `%shr`, `%sar`, `%bit-and`, `%bit-or`, `%bit-xor`, `%neg`, `%not`
     - Category B (Overflow): `%add-overflow`, `%sub-overflow`, `%mul-overflow`
     - Category C (Comparisons): `%cmp`, `%raw-cmp`, `%setb`, `%setbe`, `%seta`, `%setae`, `%set-boolean`
     - Category D (Conversions): `%trunc`, `%zext`, `%sext`, `%sitofp`, `%fptosi`
     - Category E (Memory): 専用スクラッチバッファに対する `%load-typed` / `%store-typed`（i8..i64, u8..u64, f64）
     - Category F (Floating-Point): `%fmov`, `%fadd`, `%fsub`, `%fmul`, `%fdiv`
2. **デュアルバックエンド並列実行とビット突合**:
   - 生成された LIR プログラムを Pass 140（x86-64 アセンブリ）および Pass 160（C99 ソース）の双方へ変換。
   - x86-64 側: アセンブル（`as --64`）およびリンク（`ld -m elf_x86_64 -static`）して実行。
   - C 側: GCC/Clang（`$CC -std=c99 -O2 -Wall -Wextra -Werror`）でコンパイルして実行。
   - 双方の終了ステータス、標準出力、および最終レジスタ状態（`%rax`, `%rbx`, `%rcx`, `%rdx`, `%rsi`, `%rdi`, `%xmm0`..`%xmm3`）を突合し、1 ビットの差異も許容せず一致をアサート。

### ステップ 3: Makefile ターゲット統合と品質ゲート検証
1. `ulisp/Makefile` に `test_fuzz_lir` ターゲットを追加（デフォルト 1,000 件のシードイテレーション実行、`FUZZ_ITERATIONS=10000` 対応）。
2. S式構文チェック (`lint_sexpr.py`)、`make -C ulisp build/ulisp-modular`、および 3-Stage セルフホスティングブートストラップ（`make -C ulisp bootstrap`）を通過。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp/backend/160_backend_c.scm` において、`%trunc`, `%zext`, `%sext` のセマンティクスが分離され、x86-64 の動作と 100% 一致すること。
- [ ] `ulisp/backend/160_backend_c.scm` が生成する C コードが、GCC/Clang の `-std=c99 -O2 -Wall -Wextra -Werror -pedantic` オプション下で警告 0 件でコンパイルできること。
- [ ] `ulisp/tests/fuzz_lir_differential.scm` が実装され、x86-64 ネイティブと C99 実行の出力が完全一致すること。
- [ ] 差分ファジングテストにおいて、最低 1,000 件（拡張 10,000 件）のランダム LIR 命令列で差異検出 0 件（PASS 率 100%）を達成すること。
- [ ] S式括弧チェック (`python3 ulisp/scripts/lint_sexpr.py`) が全変更ファイルでエラー 0 件であること。
- [ ] `make -C ulisp build/ulisp-modular` および `make -C ulisp bootstrap`（3-Stage 不動点検証）がエラー・警告 0 件で通過すること。

