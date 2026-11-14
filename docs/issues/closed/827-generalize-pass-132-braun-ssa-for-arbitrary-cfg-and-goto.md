---
ID: 827
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-11-15
---

# [FEAT] Pass 132 Braun SSA の任意 CFG (基本ブロック・多方向分岐・goto) 汎用対応化 (ID: 827)

## 1. 概要 / Summary
Pass 132（`ulisp/lir/132_lir_braun_ssa.scm`）で実装されている Braun et al. (2013) SSA & 基本ブロック引数（Block Arguments）エンジンを拡張し、構造化された木構造のみならず、多方向ジャンプ（`%switch`）、任意ジャンプ（`goto` / 前方・後方ジャンプ）、およびループのバックエッジを含む任意の制御フローグラフ（CFG）に対して堅牢に適用可能にする。
あわせて、Braun アルゴリズムの真価である「未完了ブロック（Incomplete Block）の遅延解決と `seal-block!` プロトコル」および「再帰的自明 Phi（Trivial Phi）除去」を完全化する。
これにより、Scheme における例外処理（`dynamic-wind`, `guard`）やエスケープ継続（`call/cc`）が生成する非局所的・複雑な CFG を最適化するとともに、C 言語由来のローカルスタック変数（`alloca` / `%load` / `%store`）を SSA 仮想レジスタへ昇格させる mem2reg 最適化（DSN-38 §2 D1, DSN-33-02 §6.1）の強固な基盤を提供する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33-02 仕様書**: §6.1 (Pass 132 Braun SSA の任意 CFG (goto/switch) 汎用対応), §3 (多言語フロントエンドと LIR パイプライン)
- **DSN-33 仕様書**: §8.1 (基本ブロック引数型 SSA と Braun 法オンザフライ構築)
- **DSN-38 仕様書**: §2 (D1: mem2reg 最適化, C1: 式と文の lowering, C5: switch と goto)
- **学術論文**: Braun et al. (2013) *"Simple and Efficient Construction of Static Single Assignment Form"* (CC 2013)
- **関連 Issue**:
  - #816: 090_rtyper エスケープ走査 O(N) 化と 133_lir_peephole 最適化
  - #826: 機械型を備えた Typed LIR への移行とボクシング操作の直交分離
  - #840: パスマネージャにおける解析結果キャッシュ自動無効化と再計算

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lir/132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm): 任意 CFG（switch, goto, ループ・バックエッジ）対応、再帰的自明 Phi 除去、および未完了ブロック封印（`seal-block!`）プロトコルの完全実装
- [x] [ulisp/lir/lir_lang.scm](../../ulisp/lir/lir_lang.scm): 基本ブロック終端子（Terminator）における `%switch` 多方向分岐構文の形式定義確認・同期
- [x] [ulisp/tests/passes/test_132_lir_braun_ssa.scm](../../ulisp/tests/passes/test_132_lir_braun_ssa.scm): 既存 Braun SSA 単体テスト（リグレッションなし確認）
- [x] [ulisp/tests/test_braun_ssa_arbitrary_cfg.scm](../../ulisp/tests/test_braun_ssa_arbitrary_cfg.scm): 前方・後方 goto、多分岐 switch、相互再帰ループ、mem2reg 昇格、自明 Phi 連鎖除去の包括的単体テスト（新規作成）
- [x] [ulisp/Makefile](../../ulisp/Makefile): `test_braun_ssa_arbitrary_cfg` ターゲット追加および検証スイート統合

---

## 4. セキュリティ・設計分析 (Threat Modeling & Constraints)
- **CWE-400 (Uncontrolled Resource Consumption / Infinite Phi Elimination Recursion & Cycles)**:
  - 不可約な CFG（Irreducible CFG）や循環参照する自明 Phi（例: $v_1 = \phi(v_2), v_2 = \phi(v_1)$）が存在する場合、再帰的な自明 Phi 除去処理や値解決（`braun-resolve-val`）が無限ループに陥りコンパイラがハングアップするリスク。
  - **対策**: 自明 Phi 除去の再帰走査において訪問済みセット（`visited`）による閉路検知を導入し、循環参照を検出した場合は即座に探索を打ち切り安全に解決する。
- **CWE-843 (Type Confusion / Dangling & Incomplete Block Argument Reference)**:
  - ブロックが封印（`seal-block!`）される前に中間コード生成が行われたり、先行節（Predecessor）が 1 つも存在しない未達ブロックから未解決のブロック引数が参照され、実行時に未初期化レジスタ・スタック領域が読み出されるリスク。
  - **対策**: CFG 終端化時に `braun-verify-cfg` を実行し、全ブロックが確実に `sealed` であること、未解決の `incomplete` 引数が 0 件であること、および先行節とブロック引数の個数・型が完全一致することを検証する。
- **純粋 Scheme (Zero External / Gauche Dependency)**:
  - 外部 Gauche 拡張や非標準手続きを一切排除し、R7RS / ULisp 標準の純粋 Scheme 構文（S式括弧整合性 100%）で実装する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/827-braun-ssa-arbitrary-cfg`

### ステップ 1: 未完了ブロック (`incomplete`) の遅延解決と `seal-block!` プロトコルの強化
1. ループヘッダや前方 `goto` の飛び先など、先行節が確定していない時点でブロックを生成し、変数の読み出し要求（`braun-read-variable`）を受け付ける。
2. 未封印ブロックに対する `braun-read-variable` は仮のブロック引数（Incomplete Phi）を即座に割り当て、`incomplete` リスト `((param . var) ...)` に登録。
3. 全ての先行節エッジ（`braun-add-edge!`）が登録された後、明示的に `braun-seal-block!` を呼出し。未解決引数に対して各先行節の現在定義を収集し確定する。

### ステップ 2: 再帰的自明 Phi（Trivial Phi）除去アルゴリズムの実装 (Braun et al. 2013 §3.2)
1. 従来の局所的な単一 `braun-try-remove-trivial!` を拡張し、自明 Phi が置換（Replacement）された際、その引数をオペランドとして使用している全ての外部 Phi（Users）を逆引き追跡して再帰的に `braun-try-remove-trivial!` を呼び出すカスケード除去を実装。
2. 相互依存する Phi ループを検知するためのガードセット（`visited-phis`）を導入。

### ステップ 3: 多方向分岐 (`%switch`) および任意ジャンプ (`%goto`) 終端子の対応
1. `braun-set-terminator!` および `braun-cfg->lir` において、`%switch` 終端子（`(%switch val default-lbl ((case1 . lbl1) ...))`）を第一級サポート。
2. switch の各 case ターゲットおよび default ターゲットへ遷移する際、各飛び先ブロックの要求するブロック引数（Block Arguments）を正確に収集・引数渡し（`(%switch val (default-lbl default-args ...) ((case1 lbl1 args1 ...) ...))` または中間トランポリンブロック）に変換。
3. 間接ジャンプや任意の前方・後方 `goto` を安全に SSA CFG としてエンコード可能にする。

### ステップ 4: mem2reg (Stack Variable Promotion) ヘルパーの整備
1. スタック配置されたローカル変数（`alloca` / アドレス非エスケープ変数）を検出し、初期値ストアを `braun-write-variable!`、ロードを `braun-read-variable` へ置き換える変換器 `braun-promote-alloca-to-ssa` を提供。
2. 余計なスタックメモリアクセスを排除し、純粋な仮想レジスタ SSA への昇格を実現。

### ステップ 5: 包括的テストスイートの構築と検証
1. `ulisp/tests/test_braun_ssa_arbitrary_cfg.scm` を新規作成:
   - 前方 `goto`（先行節の順序が不規則なブロック構造）の SSA 変換
   - 後方 `goto`（ループ・バックエッジおよびループ不変変数の自明 Phi 除去）
   - 多分岐 `switch`（複数の分岐先と合流節への引数伝播）
   - mem2reg スタック変数昇格テスト（load/store が完全にブロック引数へ変換されること）
   - CWE-400 対策（循環自明 Phi の無限再帰防止）の境界値テスト
2. `make -C ulisp test_braun_ssa_arbitrary_cfg` ターゲットを Makefile に追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/lir/132_lir_braun_ssa.scm` にて未完了ブロックの遅延解決、`seal-block!` プロトコル、および再帰的自明 Phi 除去が仕様通り実装されていること。
- [x] `%switch` 多分岐終端子および任意 `goto` 制御フローからのブロック引数 LIR 変換（`braun-cfg->lir`）が完全動作すること。
- [x] mem2reg 昇格ヘルパーにより、アドレス非取得スタック変数が SSA 仮想レジスタへ昇格されること。
- [x] 単体テスト `test_braun_ssa_arbitrary_cfg.scm`（全テストケース）および既存の `test_132_lir_braun_ssa.scm` が 100% PASS すること。
- [x] `make -C ulisp verify_zero_gauche` および `make -C ulisp lint_sexpr` が PASS すること。
- [x] 既存の 782 件の Nanopass 単体テストおよび 3-Stage セルフホスティングブートストラップ（`test_pure_bootstrap.sh`）にリグレッションがないこと。
