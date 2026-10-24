---
ID: 595
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] LIR層: define-pass による分岐融合・DCE・ピープホール最適化の宣言化 (ID: 595)

## 1. 概要 / Summary
現在、LIR 層の最適化パス（Pass 128 `lir/128_lir_branch_fusion.scm` 等）は手続き的な再帰走査や個別のアドホックなパターンマッチングによって実装されており、命令列に対する安全な変形契約やトレーサビリティが十分に形式化されていない。
Issue 593 により Canonical LIR の形式言語 `define-language L_lir_canonical` が導入されたことで、LIR 命令列に対する自己変換パスを Nanopass DSL（`define-pass`）として宣言的かつ安全に記述する基盤が整った。

本 Issue では、以下の 2 点を主軸として LIR 最適化層を刷新・拡充する：
1. **Pass 128（分岐融合）の再設計**: 手続き的なフラグ融合処理を `define-pass (L_lir_canonical -> L_lir_canonical)` として再構築し、関係演算と比較ジャンプの融合を宣言的に記述する。
2. **新規 Pass 133（LIR ピープホール最適化 & DCE）の導入**: 冗長なレジスタ移動、直後ラベルへの無条件ジャンプ、自己演算、および到達不能コード除去をスライディングウィンドウ型ピープホール最適化パスとして独立実装する。

これにより、生成されるネイティブコードの実行時オーバーヘッドおよびバイナリサイズを削減しつつ、各パスの前後で `L_lir_canonical?` による不変条件検証を自動適用してコンパイラの安全性と保守性を極限まで高める。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/pipeline_architecture.md)
  - [LIR 命令セット仕様書](../../ulisp/docs/lir_specification.md)
- **関連 Issue**:
  - Issue 571: Pass 128 LIR 分岐融合 & 条件比較低レベル化
  - Issue 593: LIR層 `define-language L_lir_canonical` の導入と検証器統合（依存完了）
  - Issue 596: Backend層 `L_asm` 命令選択とコード生成の分離（後続）
  - Issue 597: IR Verifier 基盤の共通化・階層分離と LIR 検証パフォーマンス最適化

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lir/128_lir_branch_fusion.scm](../../ulisp/lir/128_lir_branch_fusion.scm) (`define-pass` 形式へのリファクタリング)
- [x] [ulisp/lir/133_lir_peephole.scm](../../ulisp/lir/133_lir_peephole.scm) (新規: スライディングウィンドウ型 LIR ピープホール最適化パス)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`LIR_PASSES` への `133_lir_peephole.scm` 追加およびビルドルール更新)
- [x] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (パイプラインシーケンスへの Pass 133 統合)
- [x] [ulisp/tests/passes/test_128_lir_branch_fusion.scm](../../ulisp/tests/passes/test_128_lir_branch_fusion.scm) (`define-pass` 化後の単体テスト整合性検証)
- [x] [ulisp/tests/passes/test_133_lir_peephole.scm](../../ulisp/tests/passes/test_133_lir_peephole.scm) (新規: ピープホール各パターンの網羅的単体テスト)

---

## 3.2 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

低水準中間言語（LIR）の命令削除や分岐融合は、わずかな変換ミスがプログラムの制御フロー破綻や未初期化レジスタの参照を引き起こし、セキュリティ脆弱性につながるリスクを孕む。

| 脅威分類 (STRIDE / CWE) | 脅威シナリオ | 影響度 | 対策要件 (Mitigation) |
| :--- | :--- | :---: | :--- |
| **制御フロー破壊 (CWE-670 / CWE-698)** | 分岐条件の反転ミスや直後ラベルジャンプ削除時のラベル消失により、誤った基本ブロックへ制御が遷移する。 | Critical | 条件コード（`je`, `jne`, `jl`, `jle`, `jg`, `jge`）の反転論理を代数的に厳密化し、削除対象は「直後に同名ラベルが存在する無条件ジャンプ」に限定する。 |
| **レジスタ値消失 (CWE-457)** | 冗長代入除去（`mov r1, r2`）において、後続の副作用や生存区間（Liveness）の解析ミスにより必要なレジスタ書き換えがスキップされる。 | High | ピープホール最適化の適用範囲を厳格な局所連続命令ウィンドウ（N=2〜3）に制限し、跨ぎジャンプやラベル境界を越えた投機的除去は行わない。 |
| **スキーマ破壊 (CWE-20)** | 最適化パスの変換結果が LIR 構文仕様に違反する不正な S 式を出力する。 | High | パス実行の出口において `L_lir_canonical?`（Issue 593）による完全検証を実施し、違反時は Fail-Fast でコンパイルを中断する。 |

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/595-define-pass-lir-optimizations-and-peephole`

### 4.1 Pass 128: 分岐融合の `define-pass` 形式化 (`ulisp/lir/128_lir_branch_fusion.scm`)
`L_lir_canonical` から `L_lir_canonical` への自己変換パスとして定義し、LIR 命令列を走査して関係比較と条件分岐を単一の `%jump-cond` 命令へ融合する。

```scheme
(define-pass lir-fuse-branches : L_lir_canonical (ir) -> L_lir_canonical ()
  (entry Program)
  (Program : Program (p) -> Program ()
    ((%lir-program (strings ,se) (stackmaps ,sm) (%lir-functions ,f ...) ,m)
     (list '%lir-program
           (list 'strings se)
           (list 'stackmaps sm)
           (cons '%lir-functions (map FunctionDecl f))
           (MainDecl m))))
  (FunctionDecl : FunctionDecl (f) -> FunctionDecl ()
    ((%lir-function ,lbl (params (,x ...)) (frame-size ,frame_size) (body ,inst ...))
     (list '%lir-function
           lbl
           (list 'params x)
           (list 'frame-size frame_size)
           (cons 'body (optimize-branch-fusion inst)))))
  (MainDecl : MainDecl (m) -> MainDecl ()
    ((%lir-main (frame-size ,frame_size) (body ,inst ...))
     (list '%lir-main
           (list 'frame-size frame_size)
           (cons 'body (optimize-branch-fusion inst))))))
```

#### 融合パターン:
1. `((%cmp reg const) (%jump-if-false reg2 lbl))` → `((%jump-cond (lir-cmp-false-cc op) lbl))`
2. `((%set-boolean reg op) (%jump-if-false reg lbl))` → `((%jump-cond (invert-cc op) lbl))`

### 4.2 新規 Pass 133: LIR ピープホール最適化 (`ulisp/lir/133_lir_peephole.scm`)
局所スライディングウィンドウ（Window Size = 2〜3）を用いて命令列を走査し、以下の無駄な命令シーケンスを消去・簡約する。

```scheme
(define-pass lir-peephole-optimize : L_lir_canonical (ir) -> L_lir_canonical ()
  (entry Program)
  (Program : Program (p) -> Program ()
    ((%lir-program (strings ,se) (stackmaps ,sm) (%lir-functions ,f ...) ,m)
     (list '%lir-program
           (list 'strings se)
           (list 'stackmaps sm)
           (cons '%lir-functions (map FunctionDecl f))
           (MainDecl m))))
  (FunctionDecl : FunctionDecl (f) -> FunctionDecl ()
    ((%lir-function ,lbl (params (,x ...)) (frame-size ,frame_size) (body ,inst ...))
     (list '%lir-function
           lbl
           (list 'params x)
           (list 'frame-size frame_size)
           (cons 'body (optimize-peephole-fixpoint inst)))))
  (MainDecl : MainDecl (m) -> MainDecl ()
    ((%lir-main (frame-size ,frame_size) (body ,inst ...))
     (list '%lir-main
           (list 'frame-size frame_size)
           (cons 'body (optimize-peephole-fixpoint inst))))))
```

#### 最適化規則テーブル:
| 最適化カテゴリ | 検出パターン | 置換結果 | 意図・効果 |
| :--- | :--- | :--- | :--- |
| **冗長移動消去** | `(%mov reg reg)` | `()` (削除) | 同一レジスタ自己代入の完全除去 |
| **往復移動消去** | `(%mov r1 r2)` 直後に `(%mov r2 r1)` | `(%mov r1 r2)` | 連続する無意味なレジスタ往復の除去 |
| **無効ジャンプ消去** | `(%jump L1)` 直後に `(%label L1)` | `(%label L1)` | 直下の次ブロックへの冗長なジャンプ除去 |
| **恒等算術簡約** | `(%add reg 0)` / `(%sub reg 0)` | `()` (削除) | 加減算 0 の消去 |
| **恒等乗算簡約** | `(%imul reg 1)` | `()` (削除) | 乗算 1 の消去 |
| **到達不能コード消去** | `(%jump L1)` 直後の命令群（次ラベル `(%label L2)` まで） | `(%jump L1)` | 無条件分岐直後のデッドコード除去 |

### 4.3 パイプライン統合と Makefile 更新
- `ulisp/Makefile` の `LIR_PASSES` に `lir/133_lir_peephole.scm` を `lir/132_lir_braun_ssa.scm` の直後に追加。
- `compiler/driver.scm` にて、LIR 生成（Pass 130）の後に `lir-fuse-branches`（Pass 128）および `lir-peephole-optimize`（Pass 133）を連続適用するパイプラインを確立。

### 4.4 不変条件検証とテストスイート
- `ulisp/tests/passes/test_133_lir_peephole.scm` を新規作成し、各ピープホールパターンが意図通り削除・簡約されることをアサーション検証。
- パス通過後に `(validate-lir ir)` を実行し、`L_lir_canonical` スキーマが 100% 保持されていることを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `lir/128_lir_branch_fusion.scm` が `define-pass` 形式で動作し、既存の `test_128_lir_branch_fusion.scm` が全件 PASS すること。
- [x] `lir/133_lir_peephole.scm` が新規実装され、6 種類以上のピープホール最適化パターンが正常に適用されること。
- [x] 新規テストスイート `ulisp/tests/passes/test_133_lir_peephole.scm` が 100% PASS すること。
- [x] 最適化適用後の全関数・メインルーチンが `L_lir_canonical?`（Issue 593）のスキーマ検証に 100% 合格すること。
- [x] 自己ホスティング・ブートストラップ（`bash ulisp/bootstrap.sh`）において固定点検証（Stage 2/3 bit-for-bit または 1-generation convergence）が維持されること。
- [x] `make test_unit` および `bash ulisp/test.sh` が 100% PASS すること。
