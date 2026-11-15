---
ID: 832
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT] 純粋 Scheme による多倍長整数 (Bignum) および IEEE 754 相互変換標準ライブラリの実装 (ID: 832)

## 1. 概要 / Summary
外部の C ライブラリ（GMP や LibC の `strtod` / `snprintf` 等）に一切依存せず、純粋な Scheme（ポータブル R7RS 準拠コード）のみで完結する「多倍長整数ライブラリ（`ulisp/lib/bignum.scm`）」および「10進表記 ↔ IEEE 754 浮動小数点数相互変換モジュール（`ulisp/lib/ieee754.scm`）」を設計・実装する。

### 背景とアーキテクチャ上の動機
1. **完全自給自足セルフホスティング（Self-Contained Bootstrap Chain）の確立 (DSN-38 §2 A1/A2, Issue #617)**:
   - ULisp はホストコンパイラ依存を排除した完全自給自足のブートストラップチェーンを目指している。しかし、コンパイラ内部における 64bit を超える定数の畳み込み、C プリプロセッサ `#if` 定数式評価（DSN-38 §2 B1）、および高精度数値変換において、ホスト Scheme や C ライブラリに依存することはアーキテクチャ上の単一障害点（Single Point of Failure）および移植性阻害要因となる。
2. **C プリプロセッサ `#if` 式における $2^{64}$ 法演算とビット演算 (DSN-38 §2 B1)**:
   - C プリプロセッサ（CPP）の定数評価では `uint64_t` / `int64_t` の範囲（特に $2^{63}$ や $2^{64}-1$、負値の 2 の補数表現）で正確な剰余・ビット反転・シフト演算が要求される。62bit fixnum しか持たない軽量処理系単体体質では中間演算オーバーフローが生じるため、正確な 64bit モジュロ演算および多倍長演算基盤が不可欠である。
3. **IEEE 754 64bit 浮動小数点数（Binary64）の決定論的パースと書式化 (DSN-38 §2 A2)**:
   - ソースコード中の浮動小数点リテラル（例: `0.1`, `1e308`, `2.2250738585072011e-308`）をネイティブの 64bit バイナリ表現（IEEE 754 Double Precision）に変換する際、単純な乗算・除算では浮動小数点丸め誤差が累積し、GCC/Clang のパース結果と最下位ビット（1 ULP: Unit in the Last Place）の不一致を引き起こす。
   - Clinger のアルゴリズム（Clinger 1990: "How to Read Floating Point Numbers Accurately"）に基づき、多倍長整数を用いて正確な比（Exact Rational $M \times 10^E$）として計算し、厳格な偶数丸め（Round to nearest, ties to even）を適用することで、C コンパイラおよび IEEE 754 規格と 1 ビットの狂いもない完全一致を保証する。
   - 逆に 64bit ビット列から十進文字列への変換には、最短かつ可逆（round-trip）な表現を生成する純粋 Scheme 版フォーマッタ（Dragon4 / Ryū 系アルゴリズム）を提供する。
4. **R7RS 数値塔（Numeric Tower）の自立的基盤形成**:
   - 将来的な R7RS 完全準拠の数値塔（任意精度整数、正確有理数 `numerator`/`denominator`、複素数）のバックボーンとして再利用可能なモジュラー設計とする。

---

## 2. トレーサビリティ / Traceability
- **DSN-38 仕様書**:
  - §2 A1: 多倍長整数ライブラリ (`ulisp/lib/bignum.scm`)
  - §2 A2: 10進表記から IEEE 754 への変換 (`ulisp/lib/ieee754.scm`)
  - §2 B1: プリプロセッサ `#if` 式 ($2^{64}$ 法演算およびビット演算)
  - §2 E4: f64 浮動小数点演算
- **DSN-33-02 仕様書**: §4.3 (機械型 LIR 定数セマンティクス), §6 (標準ライブラリ構成)
- **関連 Issue**:
  - #617: 外部ツール完全非依存な自給自足 3-Stage セルフホスティングブートストラップの確立
  - #712: R7RS §6.2 不正確実数 (Flonum) と正確性変換・IEEE 特殊値述語の実装
  - #715: R7RS §6.2.6 数値塔リテラル入出力の実装
  - #825: Nanopass AST 定数式評価器 (eval-in-language) およびコンパイル時計算 (CTFE) 基盤の導入
  - #826: 機械型 (i8..i64, f32, f64, ptr) を備えた Typed LIR への移行
  - #828: LIR におけるオーバーフロー検知付き算術および符号なし演算オペコードの新設
  - #831: 160 Portable C バックエンドにおける型付き機械語 LIR セマンティクスの完全同期と差分ファジング検証

---

## 3. 脅威モデルとセキュリティ要件 (Threat Model & Security Requirements)
多倍長整数および浮動小数点変換処理は、外部ソースコードの字句解析・構文解析・定数畳み込みに直結するため、入力値に起因するサービス不能攻撃（DoS）や不正確な丸めによるセキュリティ脆弱性を防止する必要がある。

| 脅威 ID | 脅威分類 (CWE) | 脅威シナリオ | 緩和策・設計上の防御不変条件 |
| :--- | :--- | :--- | :--- |
| **THREAT-832-1** | **CWE-400 / CWE-770**<br>制御不能なリソース消費による DoS | 悪意ある入力（例: `1e10000000` や極端に巨大なシフト数、過大な桁数の整数リテラル）を解析した際に、メモリ確保量が爆発しヒープ枯渇または無限ループ・長時間ハングが発生する。 | 多倍長整数の最大許容リム長上限（`*bignum-max-limbs* = 4096`：約 12 万ビット）および指数解析上限（絶対値 100,000）を設け、上限超過時は即座に明示的な例外（`&assertion`）を発行する。 |
| **THREAT-832-2** | **CWE-682 / CWE-190**<br>浮動小数点パース時の丸め誤差と境界値不正 | 偶数丸め（Round-to-nearest, ties to even）の境界判定で 1 ULP のずれが生じ、定数式や型境界判定で誤判定を引き起こす。また、非正規化数（Subnormal）の最小値付近でアンダーフロー判定を誤る。 | Clinger のアルゴリズムに従い、正確な比（Exact Ratio） $M \times 10^E = N / D$ を多倍長整数除算（Knuth Algorithm D）で求め、剰余と $D/2$ の厳密比較（Exact Sticky Bit）により IEEE 754 偶数丸め不変条件を厳格に順守する。 |
| **THREAT-832-3** | **CWE-369**<br>多倍長除算・剰余におけるゼロ除算 | `bignum-div-rem` や 64bit モジュロ除算において、除数に 0（空または 0 のリム）が与えられた場合に無限ループまたはクラッシュ（SIGFPE）が生じる。 | 除数が 0 であるかを先頭ガードで決定論的に検査し、`&assertion` (Division by zero) を送出する。 |
| **THREAT-832-4** | **CWE-843**<br>不正なリム表現による型混同と不変条件破壊 | 多倍長構造体のリム配列内に負の整数、Radix（$2^{30}$）以上の値、あるいは非 fixnum が混入し、内部演算の繰り上がり処理が破綻する。 | 多倍長整数の型識別子タグ（`'bignum`）と専用アクセサをカプセル化し、生成器（`make-bignum`）および正規化関数（`bignum-normalize`）においてリムが非負かつ Radix 未満であることを検証する。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/bignum.scm](../../ulisp/lib/bignum.scm): 純粋 Scheme による任意精度多倍長整数演算コアライブラリ（Radix-$2^{30}$、四則演算、Knuth Algorithm D、ビット演算、$2^{64}$ モジュロ演算）の実装
- [ ] [ulisp/lib/ieee754.scm](../../ulisp/lib/ieee754.scm): 純粋 Scheme による IEEE 754 64bit（Double Precision Binary64）双方向パース／フォーマットモジュール（Clinger's Algorithm、丸め判定、Subnormal/Inf/NaN 特殊値パック）の実装
- [ ] [ulisp/tests/test_bignum.scm](../../ulisp/tests/test_bignum.scm): 多倍長整数ライブラリの包括的単体テスト（加減乗除、ビットシフト、Knuth Algorithm D、64bit モジュロ演算、巨大階乗・フィボナッチ数検証）
- [ ] [ulisp/tests/test_ieee754.scm](../../ulisp/tests/test_ieee754.scm): IEEE 754 双方向変換の網羅的単体テスト（Clang/GCC 出力ビット列との照合、Subnormal、極限値、NaN/Inf、往復可逆性）
- [ ] [ulisp/Makefile](../../ulisp/Makefile): `test_bignum` および `test_ieee754` ターゲットの追加と `make test` 統合
- [ ] [docs/issues/README.md](README.md): Issue 台帳のステータス更新

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/832-pure-scheme-bignum-ieee754`

### ステップ 1: 多倍長整数（Bignum）のデータ構造と基本演算設計 (`ulisp/lib/bignum.scm`)
1. **リム（Limb）基数選定とデータ表現**:
   - 基数（Radix）: $B = 2^{30} = 1,073,741,824$ を採用。
     - ULisp の 62bit fixnum 上で、2つのリムの乗算最大値は $(2^{30}-1) \times (2^{30}-1) = 2^{60} - 2^{31} + 1 < 2^{60} < 2^{61}$ となり、fixnum 算術内で一切のオーバーフローなく積および累積加算を保持可能。
   - 表現構造: `#(bignum sign limbs-vector)`
     - `sign`: `1`（正）、`-1`（負）、`0`（ゼロ）。
     - `limbs-vector`: 最下位リム（Limb 0）から最上位リム（Limb $N-1$）へ昇順配置されたベクタ。各リムは $0 \le \text{limb}_i < 2^{30}$ の非負 fixnum。
     - 正規化不変条件: ゼロの場合は `#(bignum 0 #())`、非ゼロの場合は最上位リムが必ず非ゼロ（$\text{limb}_{N-1} > 0$）。
2. **基盤手続き群**:
   - `bignum?`, `fixnum->bignum`, `bignum->fixnum` (fixnum 範囲外の場合は `#f`)。
   - `bignum-normalize`: 末尾のゼロリムをトリミングし、符号を正規化。
   - `bignum-cmp-abs`, `bignum-cmp`, `bignum-zero?`, `bignum-positive?`, `bignum-negative?`。
3. **加算・減算**:
   - `bignum-add-abs` / `bignum-sub-abs`: リム単位の加算（キャリー伝播）および減算（ボロー伝播）。
   - `bignum-add` / `bignum-sub`: 符号に応じた絶対値加減算へのディスパッチ。

### ステップ 2: 乗算・除算（Knuth Algorithm D）およびビット演算の実装
1. **乗算 (`bignum-mul`)**:
   - 基本乗算: $O(N \times M)$ の Schoolbook 乗算。二重ループでリム積を蓄積しキャリー正規化。
   - Karatsuba 乗算: リム長が閾値（例: 16 リム）以上の場合に $O(N^{\log_2 3}) \approx O(N^{1.585})$ で分割統治。
2. **除算・剰余 (`bignum-div-rem`)**:
   - 単一リム除算: 除数が 1 リムの場合は $O(N)$ の単純走査。
   - 多倍長除算: クヌース「The Art of Computer Programming, Vol 2 §4.3.1」に基づく **Algorithm D**（正規化シフト、推定商 $\hat{q}$ の算出と補正、除算・引き戻し）を純粋 Scheme で厳格実装。
   - `bignum-quotient`, `bignum-remainder`, `bignum-modulo` の提供。
3. **ビット演算・シフト (`bignum-shift-left`, `bignum-shift-right`, etc.)**:
   - 2 の補数セマンティクスに基づく任意ビットシフト。
   - `bignum-bitwise-and`, `bignum-bitwise-ior`, `bignum-bitwise-xor`, `bignum-bitwise-not`。
4. **C プリプロセッサ / コンパイラ向け 64bit モジュロ演算**:
   - `bignum->u64`, `bignum->s64`, `u64->bignum`, `s64->bignum`。
   - `bignum-u64-add`, `bignum-u64-sub`, `bignum-u64-mul`, `bignum-u64-div`, `bignum-u64-rem`, `bignum-u64-shift-left`, `bignum-u64-shift-right`。
   - 常に $2^{64}$ でラップアラウンドする C99 準拠の符号なし演算を完備。
5. **進数文字列変換 (`string->bignum`, `bignum->string`)**:
   - 2進、8進、10進、16進文字列との相互変換。

### ステップ 3: IEEE 754 64bit 浮動小数点数パーサの実装 (`ulisp/lib/ieee754.scm`)
1. **IEEE 754 Binary64 ビット仕様のカプセル化**:
   - 符号 (1bit) : bit 63
   - バイアス付き指数 (11bit) : bits 62..52 (Bias = 1023)
   - 仮数部 (52bit) : bits 51..0 (正規化数では暗黙の先頭 1bit が存在)
   - 特殊値:
     - `+0.0` / `-0.0` (Exp = 0, Frac = 0)
     - サブノーマル数（非正規化数）: Exp = 0, Frac > 0 ($0.f \times 2^{-1022}$)
     - `+inf.0` / `-inf.0` : Exp = 2047, Frac = 0
     - `+nan.0` / `-nan.0` : Exp = 2047, Frac $\neq 0$
2. **Clinger's Algorithm による 10 進文字列から Binary64 への厳密変換 (`string->ieee754-u64`)**:
   - 字句解析: 符号、仮数整数部 $M$、10の冪指数 $E$ を抽出 ($V = M \times 10^E$)。
   - 境界値・特殊値（`+inf.0`, `-inf.0`, `+nan.0`, `0.0` 等）の事前処理。
   - 正確比の構成:
     - $E \ge 0$ の場合: 分子 $Num = M \times 10^E$、分母 $Den = 1$。
     - $E < 0$ の場合: 分子 $Num = M$、分母 $Den = 10^{|E|}$。
     - $10^k$ は `bignum` を用いて任意精度で正確に計算。
   - 2の冪指数 $p$ の決定: $2^p \le Num / Den < 2^{p+1}$。
   - 仮数 53bit（先頭 1bit + 52bit）および丸めビット（Round bit / Sticky bit）の抽出:
     - $Num$ を適切に左シフトし、$Den$ で除算（`bignum-div-rem`）。
     - 剰余 $Rem$ と $Den/2$ の比較により正確な Sticky bit を判定。
   - **Round to nearest, ties to even (偶数丸め)** の適用:
     - 最下位ビットが 0 の場合は切り捨て、1 の場合は切り上げ（タイブレーク）。
   - 指数範囲（$-1022 \le e \le 1023$）に応じた正規化数／サブノーマル数／オーバーフロー（Inf）処理。
   - 64bit 整数（`u64`）としてのビットパターン生成。

### ステップ 4: Binary64 から 10 進文字列への可逆フォーマッタの実装 (`ieee754-u64->string`)
1. 特殊値（NaN, Inf, 0.0）の文字列化。
2. 純粋 Scheme 版 Dragon4 / Ryū 系アルゴリズムによる、最短かつ再パース時に同一ビットパターンへ復元可能な 10 進文字列表現の生成。

### ステップ 5: 包括的テストスイートと C コンパイラ出力照合ハーネス
1. `ulisp/tests/test_bignum.scm`:
   - 小数リムから 100 リム超の巨大整数までの加減乗除・シフト・ビット演算の単体テスト。
   - $100!$, $2^{256}$, フィボナッチ数 $F_{1000}$ の計算結果検証。
   - 64bit モジュロ演算の境界値テスト（$2^{64}-1 + 1 = 0$, $0 - 1 = 2^{64}-1$ 等）。
2. `ulisp/tests/test_ieee754.scm`:
   - 有名な境界値（Clinger's test suite、David Gay テストセット、サブノーマル数境界値 `2.2250738585072014e-308`, `2.2250738585072011e-308`, `4.9406564584124654e-324` 等）。
   - Clang/GCC の `strtod` が出力する 64bit 16進ビットパターン（例: `0x3ff0000000000000` = `1.0`）との照合テスト。
   - 文字列 → u64 → 文字列 → u64 の往復可逆性（Round-trip Identity）テスト。
3. `ulisp/Makefile` へのテストターゲット追加と統合。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp/lib/bignum.scm` が純粋 Scheme で実装され、任意精度整数の加減乗除（Knuth Algorithm D）、ビット演算、および 64bit モジュロ演算（Modulo $2^{64}$）が正しく動作すること。
- [ ] `ulisp/lib/ieee754.scm` が純粋 Scheme で実装され、Clinger のアルゴリズムに基づく厳格な偶数丸め（Round to nearest, ties to even）とサブノーマル数・NaN・Inf のビット生成が行えること。
- [ ] 浮動小数点リテラル（`0.1`, `0.2`, `1e308`, `2.2250738585072011e-308` 等の境界値）から生成された 64bit ビット列が、Clang/GCC の `strtod` 出力と 1 ビットの狂いもなく完全一致すること。
- [ ] `ulisp/tests/test_bignum.scm` および `ulisp/tests/test_ieee754.scm` が作成され、全テスト項目が 100% 合格すること。
- [ ] `make -C ulisp test` に上記テストが統合され、既存の全テストスイートおよび品質ゲート（構文チェック、ブートストラップ検証）を通過すること。
- [ ] すべての新規コードおよびドキュメントにおいて、外部 C ライブラリへの依存がなく、内部リンクが相対パスのみで構成されていること。
