---
ID: 828
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] LIR におけるオーバーフロー検知付き算術および符号なし演算オペコードの新設 (ID: 828)

## 1. 概要 / Summary
LIR に符号なし整数演算（符号なし除算 `udiv`、剰余 `urem`、論理右シフト `shr`、符号なし比較条件コード `setb`/`setbe`/`seta`/`setae`）と、CPU フラグ直結のオーバーフロー検知付き加減算命令（`add_overflow`, `sub_overflow`, `mul_overflow`）を第一級オペコードとして新設する。
これにより、Scheme における Fixnum 算術のオーバーフロー判定（Bignum への昇格ガード）を、冗長な事前分岐からハードウェアフラグ（`jo`/`jc`）直結の最短コードへ最適化するとともに、C 言語の符号なし型（`uint32_t`, `size_t` 等）の厳密な規格準拠を達成する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §2 (E1: 拡張命令, E2: 符号なし命令, E9: LIR 意味論)
- **関連 Issue**: #826 (Typed LIR), #832 (Pure Scheme Bignum)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/lir.scm](../../ulisp/compiler/lir.scm): オーバーフロー算術・符号なし命令定義および verifier 更新
- [ ] [ulisp/backend/140_backend_x86.scm](../../ulisp/backend/140_backend_x86.scm): x86 命令（`div`, `shl cl`, `setcc`, `jo`）のコード生成
- [ ] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm): C 言語における `__builtin_add_overflow` および unsigned キャストによるエミュレーション
- [ ] [ulisp/tests/test_lir_overflow_and_unsigned.scm](../../ulisp/tests/test_lir_overflow_and_unsigned.scm): 演算検証テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/828-lir-overflow-and-unsigned-ops`

1. LIR 命令セットの拡張：
   - `(%add-overflow dst-val dst-flag src1 src2)`
   - `(%sub-overflow dst-val dst-flag src1 src2)`
   - `(%mul-overflow dst-val dst-flag src1 src2)`
   - `(%udiv dst src1 src2)`, `(%urem dst src1 src2)`, `(%shr dst src1 count)`
2. x86_64 バックエンド（140）への命令選択の組み込み：
   - `add`/`sub` 直後の `into` または `jo` 分岐の生成。
   - `div` 命令における `rdx:rax` の初期化（0クリア）および商・余りの抽出。
3. Scheme コンパイラの Fixnum 算術パス（120）の更新：
   - 事前オーバフロー予測条件式を `%add-overflow` によるフラグ分岐へ置換。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Fixnum の加減算において、オーバーフロー時に Bignum 昇格ハンドラへジャンプする x86_64 機械語コードが 2 命令以内で生成されること。
- [ ] 符号なし除算および 64bit シフト演算が、エッジケース（0除算、64ビット以上のシフト量）を含め定義通りに動作すること。
- [ ] 単体テスト `test_lir_overflow_and_unsigned.scm` が全項目合格すること。
