---
ID: 874
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] 4値束縛時間束（Lattice）モデルに基づく BTA 型推論パスの実装 (ID: 874)

## 1. 概要 / Summary
DSN-33-03 §4.1 および §2.5 に基づき、$\bot \sqsubset \mathbf{Static} \sqsubset \mathbf{PSDS} \sqsubset \mathbf{Dynamic} \sqsubset \top$ の4値束（Lattice）モデルに従ってプログラム中の全式の束縛時間を推論するオフライン BTA（Binding-Time Analysis）パスを実装した。
式がコンパイル時（Now）に計算可能か、部分静的（PSDS: 静的骨格・動的リーフ）か、実行時（Later）計算必須かを静的に型付けし、二村射影における部分評価器の決定論的簡約と残余化の境界を画定。

---

## 2. トレーサビリティ / Traceability
- 関連仕様書:
  - [DSN-33-03 §2.5, §4.1 (4-valued BTA Lattice Model)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#41-4値束縛時間束latticeモデル)
  - [DSN-33 §3.1 (Nanopass Architecture)](docs/designs/DSN-33-ulisp_compiler_pipeline_architecture_and_nanopass_infrastructure.md)
- 関連 Issue:
  - #870 (stage-dict および Now / Later 辞書)
  - #871 (PSDS `<stage-val>`)
  - #872 (eval-in-stage コアループ)
  - #873 (単一ソース意味論オラクル回帰検証)
  - #875 (動的分岐配下の純粋性解析と投機的副作用・例外の降格)
  - #876 (CSP 越境バリデータと Dual Span 診断レポーター)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/dataflow.scm](ulisp/compiler/dataflow.scm) - 4値束モデル（`bta-lattice`、合流演算子 $\sqcup$、順序判定 $\sqsubseteq$）の実装
- [x] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm) - BTA 型推論エンジン（`bta-infer-expr`、`bta-annotate-ast`）の実装
- [x] [ulisp/tests/test_bta_lattice.scm](ulisp/tests/test_bta_lattice.scm) - 束代数および BTA 型推論の単体テストスイート
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_bta_lattice` ターゲットの追加
- [x] [docs/issues/README.md](docs/issues/README.md) - 台帳ステータス更新

---

## 4. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/874-implement-4-valued-bta-lattice-type-inference-pass`

### 4.1 4値束縛時間束モデル（`bta-lattice`）
1. **要素定義**:
   - `'bot`: 未解析・到達不能
   - `'static`: コンパイル時（Now）に完全確定
   - `'psds`: 骨格・タグ構造は静的、引数・リーフは動的
   - `'dynamic`: 実行時（Later）計算必須
   - `'top`: 矛盾・過剰一般化
2. **順序関係 ($\sqsubseteq$)**:
   - $\bot \sqsubseteq \mathbf{Static} \sqsubseteq \mathbf{PSDS} \sqsubseteq \mathbf{Dynamic} \sqsubseteq \top$
3. **合流演算 ($\sqcup$, Join)**:
   - $\mathrm{join}(\bot, x) = x$
   - $\mathrm{join}(\top, x) = \top$
   - $\mathrm{join}(\mathbf{Static}, \mathbf{PSDS}) = \mathbf{PSDS}$
   - $\mathrm{join}(\mathbf{Static}, \mathbf{Dynamic}) = \mathbf{Dynamic}$
   - $\mathrm{join}(\mathbf{PSDS}, \mathbf{Dynamic}) = \mathbf{Dynamic}$
   - 等しい要素同士の join はその要素自身。
4. **交差演算 ($\sqcap$, Meet)**:
   - 双対定義。

### 4.2 BTA 型推論エンジン (`bta-infer-expr`)
`(bta-infer-expr expr env)`
1. **定数・リテラル**:
   - `number?`, `boolean?`, `char?`, `string?`, `quote` $\to \mathbf{Static}$
2. **変数参照**:
   - `env` から探索。見つかればその BTA 型、未束縛なら $\mathbf{Dynamic}$
3. **データ構造コンストラクタ（`cons`）**:
   - 両引数が Static $\implies \mathbf{Static}$
   - いずれかが Dynamic / PSDS $\implies \mathbf{PSDS}$
4. **データ構造アクセサ（`car`, `cdr`）**:
   - 引数が Static $\implies \mathbf{Static}$
   - 引数が PSDS $\implies$ （コンパイル時要素追跡可能ならその型、一般には Dynamic / PSDS への安全降格）
   - 引数が Dynamic $\implies \mathbf{Dynamic}$
5. **プリミティブ演算（`+`, `-`, `*`, `<`, `=` 等）**:
   - すべての引数が Static $\implies \mathbf{Static}$
   - 動的引数が 1 つでも含まれる $\implies \mathbf{Dynamic}$
6. **条件分岐（`if test then else`）**:
   - `test` が Static $\implies \mathrm{join}(\mathrm{bta}(then), \mathrm{bta}(else))$
   - `test` が Dynamic $\implies \mathbf{Dynamic}$（動的分岐配下は残余化必須）
7. **局所束縛（`let ((var val) ...) body`）**:
   - 各 `val` の BTA 型を推論し、環境 `env` を拡張して `body` の BTA 型を推論。

### 4.3 セルフホスト No-set! / Fixed-Arity 規律
- 評価器・推論器内部で `set!` は一切使用せず、純粋関数型辞書渡しで実装。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 4値束（Bot, Static, PSDS, Dynamic, Top）の束公理（推移律、反射律、Join 結合律）が満たされること。
- [x] 定数式が `'static`、動的変数参照が `'dynamic`、対生成が `'psds` に正しく型推論されること。
- [x] 静的 `if` と動的 `if` の束縛時間が健全に伝播されること。
- [x] `make -C ulisp test_bta_lattice` が 0件エラー PASS すること。
- [x] 既存の全テストスイート（`test_single_source_oracle`, `test_eval_in_stage`, `test_stage_dict`, `test_psds_provenance`, `test_eval_in_language`）が PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。

