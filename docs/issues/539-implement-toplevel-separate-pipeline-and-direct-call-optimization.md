---
ID: 539
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] トップレベル定義の完全直列パイプライン分離および直接呼出 (%direct-call) 最適化 (ID: 539)

## 1. 概要 / Summary
Issue #529 において `free-vars-acc` 単一パス深さ優先アキュムレータおよび集合演算高速化により、ブートストラップ実行時間を 10 秒へと抜本短縮した。
本 Issue では次段階のアーキテクチャ最適化として、Pass 0 (`rewrite-top-level`) におけるトップレベル `define` の巨大 `letrec` 巻き上げを完全撤廃し、`(%program ((define name val) ...) main-expr)` 構造としてパイプライン全段を完全直列処理する。
これにより、相互再帰関数群をローカルフラットクロージャではなく静的コードラベルへの直接呼出（`%direct-call` / 直接ジャンプ）へと変換し、ヒープクロージャ割当と間接呼出オーバーヘッドをゼロ化する。

---

## 2. トレーサビリティ / Traceability
- **関連先行 Issue**:
  - Issue #529: トップレベル定義の独立コンパイル構造化および自由変数解析集合演算の高速化
  - Issue #522: ドミネータ解析に基づくコンティフィケーションと局所クロージャ割当完全消去の実装
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/01_desugar.scm](../../ulisp/passes/01_desugar.scm) (`rewrite-top-level` による `letrec` 撤廃と `%program` 分離)
- [ ] [ulisp/passes/05_closure_convert.scm](../../ulisp/passes/05_closure_convert.scm) (トップレベル関数の直接 `%function` 昇格および `%direct-call` 変換)
- [ ] [ulisp/passes/06_lir.scm](../../ulisp/passes/06_lir.scm) (`%direct-call` LIR 命令生成と TCO 直結)
- [ ] [ulisp/passes/07_backend_x86_64.scm](../../ulisp/passes/07_backend_x86_64.scm) (`%direct-call` x86-64 アセンブリ出力)
- [ ] [ulisp/passes/07_backend_aarch64.scm](../../ulisp/passes/07_backend_aarch64.scm) (`%direct-call` AArch64 アセンブリ出力)
- [ ] [ulisp/passes/07_backend_c.scm](../../ulisp/passes/07_backend_c.scm) (`%direct-call` C99 関数呼び出し出力)
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm) (統合コンパイラ再構築)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/539-implement-toplevel-separate-pipeline-and-direct-call-optimization`

1. **Pass 0 / 1 トップレベル定義の分離**:
   - `rewrite-top-level` において、トップレベル定義群を単一 `letrec` へ抱き込まず `(%program defs main-expr)` を出力。
2. **Pass 5 クロージャ変換の直列昇格**:
   - トップレベル関数を直接 `%function` へ昇格。
   - トップレベル関数呼出を `%call-closure` ではなく `%direct-call` へ直接変換。高階関数に渡される場合のみ引数ゼロのスタティッククロージャを生成。
3. **LIR および各バックエンドにおける直接呼出コード生成**:
   - 間接関数ポインタ読み出し（`mov rdx, [r10 - 1]`）を介さず、直接 `call label` / `bl label` を出力。
4. **自己ホスティング不動点検証**:
   - `bootstrap.sh` の Stage 2 / Stage 3 のビット完全一致（`cmp -s stage2.s stage3.s`）を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `rewrite-top-level` から巨大 `letrec` 巻き上げが完全に撤廃されること。
- [ ] トップレベル関数呼び出しが `%direct-call` を通じて静的ラベルへ直接分岐すること。
- [ ] 全 140+ Nanopass ユニットテスト、JIT テスト、C バックエンドテストが 100% 合格すること。
- [ ] `bootstrap.sh` の自己ホスティング不動点検証が 100% 合格すること。
