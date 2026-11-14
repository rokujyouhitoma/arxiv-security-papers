---
ID: 838
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] レジスタ制約付きインライン・アセンブリ (%inline-asm) の LIR 統合 (ID: 838)

## 1. 概要 / Summary
低レベル中間表現（LIR）において、入出力レジスタ制約（Constraints）および破壊レジスタ（Clobbers）を明示可能なインライン・アセンブリ命令ノード（`%inline-asm`）を正式にサポートする。
レジスタ割り当て器（Pass 140）がこの制約（例: `rax` 固定、`rcx` 固定、メモリ参照制約、フラグ破壊）を尊重して仮想レジスタの割り当てや退避（Spill）を調停できるようにする。
これにより、musl の移植（J1）における `_start`、`setjmp`/`longjmp`、システムコール発行ラッパー、アトミック CAS（Compare-And-Swap）等の低水準システムプログラミングを最小限の C コード修正で実現し、同時に Scheme ランタイムの低水準プリミティブの自己記述化を可能にする。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §2 (J1: musl 移植, C4: setjmp の扱い, E5: 外部呼出と入口/出口)
- **関連 Issue**: #826 (Typed LIR), #829 (Calling Conventions)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/lir.scm](../../ulisp/compiler/lir.scm): `%inline-asm` ノードの構文定義および制約チェッカー
- [ ] [ulisp/backend/140_backend_x86.scm](../../ulisp/backend/140_backend_x86.scm): レジスタ割り当て器における固定レジスタ制約およびクロバー処理
- [ ] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm): GCC/Clang 拡張構文 `__asm__ volatile (...)` へのフォールバック出力
- [ ] [ulisp/tests/test_inline_asm.scm](../../ulisp/tests/test_inline_asm.scm): インラインアセンブリおよびレジスタ退避テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/838-lir-inline-assembly-with-constraints`

1. `%inline-asm` ノード構文の策定：
   ```scheme
   (%inline-asm <template-string>
     (:outputs ((<vreg> <constraint-spec>) ...))
     (:inputs  ((<vreg/imm> <constraint-spec>) ...))
     (:clobbers (<reg-name> ...))
     (:volatile? #t/#f))
   ```
2. レジスタ割り当て器（140）の拡張：
   - 制約付き入力/出力を固定物理レジスタへの事前結合（Pre-colored Virtual Registers）として表現。
   - クロバーレジスタに生存区間（Live Range）が重なる他の仮想レジスタを強制退避（Spill）させる干渉グラフ（Interference Graph）の構築。
3. アセンブラ出力器（144a）との連携：
   - テンプレート文字列へのオペランド番号展開およびアセンブル。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 固定レジスタ（例: `syscall` における `rax`, `rdi`, `rsi`, `rdx`, `r10`, `r8`, `r9`）を介したインラインアセンブリが、レジスタ破壊を起こさずに正しくコード生成されること。
- [ ] 生存中のローカル変数が正しくスタックへ退避され、インラインアセンブリ終了後に復元されること。
- [ ] 単体テスト `test_inline_asm.scm` がパスすること。
