---
ID: 858
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] SRFI 143 Fixnums 特化高速演算ライブラリおよび (scheme fixnum) の実装 (ID: 858)

## 1. 概要 / Summary
R7RS-large Tangerine Edition において定められている SRFI 143 (Fixnums) は、プラットフォーム固有の固定長整数 (Fixnum) に特化した型安全かつアンボックス高速演算 API を規定する。
ULisp はスタンドアロン 62-bit 即値 Fixnum アーキテクチャ（下位 2 ビットタグ `00`、62 ビット符号付き整数）を採用している。
本 Issue では、SRFI 143 準拠の Fixnum 専用算術・比較・キャリー付き演算・ビット演算ライブラリを完全実装し、`(scheme fixnum)` および `(srfi 143)` として提供する。

---

## 2. トレーサビリティ / Traceability
- **関連標準仕様**:
  - R7RS-large Tangerine Edition: `(scheme fixnum)`
  - SRFI 143: Fixnums
  - R7RS-small (IEEE 1178-1990, Revised^7 Report on the Algorithmic Language Scheme)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.2
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [Issue #857 (SRFI 151 Bitwise Operations)](857-implement-srfi-151-bitwise-operations-and-scheme-bitwise.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/fixnum.scm](../../ulisp/lib/fixnum.scm) (新規作成: SRFI 143 手続き群の完全実装)
- [ ] [ulisp/lib/scheme/fixnum.sld](../../ulisp/lib/scheme/fixnum.sld) (新規作成: `(scheme fixnum)` ライブラリ定義)
- [ ] [ulisp/lib/srfi/143.sld](../../ulisp/lib/srfi/143.sld) (新規作成: `(srfi 143)` ライブラリ定義)
- [ ] [ulisp/tests/test_srfi_143.scm](../../ulisp/tests/test_srfi_143.scm) (新規作成: 包括的単体テストスイート)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`ULISP_LARGE_LIBS`, `test_srfi_143`, `test:` ターゲットの登録)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (SRFI 143 および `(scheme fixnum)` のトレーサビリティ反映)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳更新)

---

## 4. 仕様定義と手続きマッピング / Specification & Procedure Mapping

### 4.1 定数 (Constants)
| 手続き/定数名 | 型/値 | 説明 |
|---|---|---|
| `fx-width` | Fixnum (`62`) | ULisp 64-bit タグ付きアーキテクチャにおける Fixnum のビット幅 |
| `fx-greatest` | Fixnum (`2305843009213693951`) | 最大正 Fixnum ($2^{61} - 1$) |
| `fx-least` | Fixnum (`-2305843009213693952`) | 最小負 Fixnum ($-2^{61}$) |

### 4.2 述語 (Predicates)
| 手続き名 | 引数 | 説明 |
|---|---|---|
| `fixnum?` | `(fixnum? obj)` | `obj` が Fixnum の場合 `#t`、それ以外 `#f` |
| `fx=?` | `(fx=? i j ...)` | Fixnum 同値比較 |
| `fx<?` | `(fx<? i j ...)` | Fixnum 単調増加比較 |
| `fx>?` | `(fx>? i j ...)` | Fixnum 単調減少比較 |
| `fx<=?` | `(fx<=? i j ...)` | Fixnum 単調非減少比較 |
| `fx>=?` | `(fx>=? i j ...)` | Fixnum 単調非増加比較 |
| `fxzero?` | `(fxzero? i)` | `(= i 0)` |
| `fxpositive?` | `(fxpositive? i)` | `(> i 0)` |
| `fxnegative?` | `(fxnegative? i)` | `(< i 0)` |
| `fxodd?` | `(fxodd? i)` | 奇数判定 |
| `fxeven?` | `(fxeven? i)` | 偶数判定 |
| `fxmax` | `(fxmax i j ...)` | 最大値取得 |
| `fxmin` | `(fxmin i j ...)` | 最小値取得 |

### 4.3 基本算術 (Basic Arithmetic)
| 手続き名 | 引数 | 説明 |
|---|---|---|
| `fx+` | `(fx+ i j ...)` | Fixnum 加算 (引数なし: `0`、1引数: `i`、多引数: 左結合畳み込み) |
| `fx-` | `(fx- i j ...)` | Fixnum 減算 (1引数: 符号反転、多引数: 差分) |
| `fxneg` | `(fxneg i)` | 単項符号反転 (`(- 0 i)`) |
| `fx*` | `(fx* i j ...)` | Fixnum 乗算 (引数なし: `1`、1引数: `i`、多引数: 左結合畳み込み) |
| `fxquotient` | `(fxquotient i j)` | 0 方向切り捨て商 |
| `fxremainder` | `(fxremainder i j)` | 剰余 |
| `fxabs` | `(fxabs i)` | 絶対値 |
| `fxsquare` | `(fxsquare i)` | 平方 (`(* i i)`) |
| `fxsqrt` | `(fxsqrt i)` | 非負 Fixnum の整数平方根 (floor of square root) |

### 4.4 キャリー付き算術 (Arithmetic with Carry)
| 手続き名 | 引数 | 返り値 | 説明 |
|---|---|---|---|
| `fx+/carry` | `(fx+/carry i j k)` | `(values sum carry)` | $i + j + k = \text{carry} \cdot 2^{62} + \text{sum}$ |
| `fx-/carry` | `(fx-/carry i j k)` | `(values diff borrow)` | $i - j - k = \text{borrow} \cdot 2^{62} + \text{diff}$ |
| `fx*/carry` | `(fx*/carry i j k)` | `(values low high)` | $i \cdot j + k = \text{high} \cdot 2^{62} + \text{low}$ |

### 4.5 丸め除算 (SRFI 141 整合)
| 手続き名 | 引数 | 説明 |
|---|---|---|
| `fxfloor/` | `(fxfloor/ i j)` | `(values (fxfloor-quotient i j) (fxfloor-remainder i j))` |
| `fxfloor-quotient` | `(fxfloor-quotient i j)` | 負の無限大方向丸め商 |
| `fxfloor-remainder` | `(fxfloor-remainder i j)` | 負の無限大方向丸め剰余 |
| `fxtruncate/` | `(fxtruncate/ i j)` | `(values (fxtruncate-quotient i j) (fxtruncate-remainder i j))` |
| `fxtruncate-quotient` | `(fxtruncate-quotient i j)` | 0 方向丸め商 (`fxquotient` と同等) |
| `fxtruncate-remainder` | `(fxtruncate-remainder i j)` | 0 方向丸め剰余 (`fxremainder` と同等) |

### 4.6 ビット演算 (Bitwise Operations)
| 手続き名 | 引数 | 説明 |
|---|---|---|
| `fxnot` | `(fxnot i)` | ビット単位 NOT (Fixnum 表現における反転) |
| `fxand` | `(fxand i j ...)` | ビット単位 AND |
| `fxior` | `(fxior i j ...)` | ビット単位 IOR |
| `fxxor` | `(fxxor i j ...)` | ビット単位 XOR |
| `fxif` | `(fxif mask i j)` | ビットマージ: `(fxior (fxand mask i) (fxand (fxnot mask) j))` |
| `fxbit-count` | `(fxbit-count i)` | ポップカウント (非負: 1の数、負: 0の数) |
| `fxlength` | `(fxlength i)` | 最低限必要なビット長 |
| `fxfirst-set-bit` | `(fxfirst-set-bit i)` | 最下位セットビットのインデックス (0なら -1) |
| `fxbit-set?` | `(fxbit-set? index i)` | 指定インデックスのビット検査 |
| `fxcopy-bit` | `(fxcopy-bit index i boolean)` | 指定インデックスのビット設定/クリア |
| `fxarithmetic-shift` | `(fxarithmetic-shift i count)` | 算術シフト (count > 0: 左シフト, count < 0: 算術右シフト) |
| `fxarithmetic-shift-left` | `(fxarithmetic-shift-left i count)` | 算術左シフト |
| `fxarithmetic-shift-right` | `(fxarithmetic-shift-right i count)` | 算術右シフト |
| `fxbit-field` | `(fxbit-field i start end)` | 指定ビットフィールドの抽出 |
| `fxbit-field-rotate` | `(fxbit-field-rotate i count start end)` | フィールド内循環ビットシフト |
| `fxbit-field-reverse` | `(fxbit-field-reverse i start end)` | フィールド内ビット順序反転 |

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/858-implement-srfi-143-fixnums-and-scheme-fixnum`

1. **Fixnum 境界値保護とオーバーフロー検証**:
   - ULisp の 62-bit Fixnum 上限・下限を定数化。
   - `fx+/carry`, `fx-/carry`, `fx*/carry` において、64-bit 演算および BigInt 変換または分割計算により正確なキャリー・ボローを導出。
2. **SRFI 151 との相互運用**:
   - 先行実装された `ulisp/lib/bitwise.scm` の高精度ビット演算ロジックを活用し、Fixnum 範囲にクランプされた高速実装を提供。
3. **モジュール定義**:
   - `ulisp/lib/scheme/fixnum.sld` および `ulisp/lib/srfi/143.sld` を作成。
   - すべての exported 識別子を定義し、`../fixnum.scm` をインクルード。
   - `Traceability: ulisp/docs/ref_r7rs_compliance.md` ヘッダーを付与。
4. **テストスイート `test_srfi_143.scm`**:
   - 定数・境界値テスト (Group 1)
   - 述語テスト (Group 2)
   - 基本算術・丸めテスト (Group 3)
   - キャリー付き演算テスト (Group 4)
   - ビット演算テスト (Group 5)
   - 各種エッジケース・62-bit 極限値テスト (Group 6)
5. **ビルド & トレーサビリティ検証**:
   - `Makefile` に `test_srfi_143` ターゲットを追加。
   - `scripts/verify_r7rs_traceability.py` による監査合格。
   - `make -C ulisp bootstrap` での自己ホストブートストラップ固定点収束。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp/lib/fixnum.scm` が作成され、SRFI 143 規定の全手続き（定数3、述語13、算術9、キャリー3、丸め除算6、ビット演算16の計47手続き）が完全実装されていること。
- [ ] `(scheme fixnum)` および `(srfi 143)` の `.sld` ライブラリファイルが作成されていること。
- [ ] `ulisp/tests/test_srfi_143.scm` が作成され、全テストが 100% PASS すること。
- [ ] `python3 scripts/verify_r7rs_traceability.py` が 100% PASS すること。
- [ ] `make -C ulisp bootstrap` による自己ホスト 5 モジュール並列ビルドが固定点収束すること。
- [ ] `make -C ulisp test` の全テストスイートがエラーなく完走すること。
- [ ] 絶対パスリンクが排除され、相対パスのみが使用されていること。
