---
ID: 886
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-11-21
---

# [FEAT] セルフホスティング決定論性と不動点（Stage 2 -> Stage 3 diff 0）の検証 (ID: 886)

## 1. 概要 / Summary
DSN-33-03 §2.4 および §8.2 に基づき、Nanopass メタコンパイラ（L-StagePoly / L-Residual-ANF / 特殊化メモ化 / Contification / Freeze Graph 等の全新設 Nanopass 群）を統合した Ulisp コンパイラ自身を Stage 1 $\to$ Stage 2 $\to$ Stage 3 でブートストラップ再コンパイルし、Stage 2 と Stage 3 の生成コード差分が完全にゼロ（$\mathrm{diff} = 0$）であることを検証した。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書: [DSN-33-03 §2.4, §8.2](../../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#24-不動点方程式とセルフホスティング固定点stage-1--2--3)
- 関連 Issue: #617 (Bootstrap Chain), #870〜#885 (Stage-Polymorphic Metacompiler Nanopass Suite)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/tests/test_self_hosting_fixed_point.scm](../../../ulisp/tests/test_self_hosting_fixed_point.scm)
- [x] [ulisp/Makefile](../../../ulisp/Makefile)

---

## 4. 実装内容 / Implementation Details
1. **Nanopass メタコンパイラ自己ホスト決定論性＆不動点テストスイート (`test_self_hosting_fixed_point.scm`)**:
   - **Group 1**: Nanopass パイプライン決定論性検証（同一入力に対して Run A と Run B の生成 AST が完全一致、$\mathrm{diff}(A, B) = 0$）。
   - **Group 2**: 3ステージセルフホスティング不動点検証（ソースプログラムを Stage 1 でコンパイルした Stage 2 出力と、Stage 2 でコンパイルした Stage 3 出力が完全一致、$\mathrm{diff} = 0$）。
   - **Group 3**: 残余コード不変量（Contification 保証および Data Plane 脱タグ最適化）の保持・一致検証。
   - **Group 4**: Freeze Graph 直列化のビット完全一致検証（.rodata byte-for-byte identical）。
   - **Group 5**: 第1二村射影（Tower Collapse）適用後の Stage 2 と Stage 3 不動点等価性検証。
2. **Makefile ビルドルール統合**:
   - `test_self_hosting_fixed_point` ターゲットを Makefile のテストリストおよび依存関係に登録。
3. **モジュラーブートストラップ検証**:
   - `stage2_*.s` と `stage3_*.s` のアセンブリファイル全モジュール間で差分 0 バイト（$\mathrm{diff} = 0$）であることを確認。

---

## 5. 完了条件 (DoD) 検証結果
- [x] Stage 2 と Stage 3 の生成コード差分が完全ゼロ（$\mathrm{diff} = 0$）であることを検証。
- [x] `make test_self_hosting_fixed_point` が 100% PASS。
- [x] `make py_compile && make static_analysis` が 100% PASS。
