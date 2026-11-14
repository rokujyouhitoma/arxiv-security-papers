---
ID: 831
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] 160 Portable C バックエンドにおける型付き機械語 LIR セマンティクスの完全同期と差分ファジング検証 (ID: 831)

## 1. 概要 / Summary
Pass 160（`ulisp/backend/160_backend_c.scm`）による Portable C99 コード生成器を改修し、新設される型付き機械語 LIR（幅指定ロード/ストア、符号なし演算、オーバーフロー検知、IEEE 754 `f64` 演算）に完全追従させる。
さらに、同一の LIR スクリプトを入力として x86_64 ネイティブ実行（140）と C トランスパイル実行（160）の結果を自動比較する「LIR レベル差分ファジング（Differential Fuzzing）テストハーネス（K3）」を構築し、バックエンド間のセマンティクス完全一致を恒常的に保証する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §2 (E10: C backend 対応, K3: LIR レベル差分ファジング)
- **関連 Issue**: #695 (Windows C backend), #696 (macOS C backend), #826 (Typed LIR), #828 (Overflow Arithmetic)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm): 型付き LIR 命令群の C99 コード生成対応
- [ ] [ulisp/tests/fuzz_lir_differential.scm](../../ulisp/tests/fuzz_lir_differential.scm): ランダム LIR 生成および 140 vs 160 出力突合ハーネス
- [ ] [Makefile](../../Makefile): `make fuzz_lir` ターゲットの追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/831-c-backend-typed-lir-fuzzing`

1. 160_backend_c.scm のセマンティクス同期：
   - `int8_t`, `uint8_t`, `int16_t`, `uint16_t`, `int32_t`, `uint32_t`, `int64_t`, `uint64_t`, `double` の明確な型付き変数宣言。
   - `memcpy` による安全なビットキャスト（float ↔ 整数レジスタ）の生成。
   - オーバーフロー検査付き算術における Clang/GCC ビルトイン `__builtin_add_overflow` のフォールバックマクロ生成。
2. 差分ファジングハーネスの構築：
   - 決定論的擬似乱数を用いた型付き LIR 命令シーケンス（算術・論理・ポインタ演算・分岐）の自動生成器を設計。
   - 生成された LIR を「x86_64 JIT/AOT」および「GCC/Clang 経由の C 実行」の双方で走らせ、最終レジスタ値および戻り値をビットレベルでアサート。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 160 C バックエンドが、Issue #826, #828 で定義された全 LIR 命令をサポートし、C コンパイラの警告 0 件でビルドできること。
- [ ] 差分ファジングテストにおいて、10,000 件以上のランダム LIR 命令列で 140 と 160 の実行結果が 100% 一致すること。
- [ ] `make fuzz_lir` が CI パイプラインで正常に実行可能であること。
