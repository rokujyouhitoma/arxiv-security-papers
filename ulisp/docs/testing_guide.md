# ULisp テストおよび検証ガイド (Testing & Verification Guide)

本ドキュメントは、ULisp コンパイラの品質保証（QA）、パス別単体テスト、インクリメンタル統合テスト、および 3 段階セルフホスティング不動点検証の実行・デバッグ手順を解説する。

正典アーキテクチャ仕様書: [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 1. テストスイート体系

ULisp のテスト体系は、以下の 4 層から構成される。

```text
+---------------------------------------------------------------+
| Layer 4: ILisp AOT 連携テスト (.venv/bin/pytest tests/ilisp/)  |
+---------------------------------------------------------------+
| Layer 3: 3段階セルフホスティング不動点検証 (bootstrap.sh)       |
+---------------------------------------------------------------+
| Layer 2: compilerbook 準拠 インクリメンタル E2E テスト (test.sh)|
+---------------------------------------------------------------+
| Layer 1: Nanopass 別 単体テスト (tests/test_passes.scm)       |
+---------------------------------------------------------------+
```

---

## 2. 各レイヤーの実行方法

### Layer 1: パス別単体テスト (Nanopass Unit Tests)
各パス（Pass 1〜Pass 7）が期待通りの S 式変換を行っているかを個別に検査する。

```bash
cd ulisp
# ILisp ホスト上で単体テストを実行
python3 -m ilisp tests/test_passes.scm
```

- **検証対象**:
  - `Pass 1`: `cond`, `case`, `let*`, `named-let`, `and`, `or` の脱糖
  - `Pass 2`: `free-vars` 集合抽出
  - `Pass 3`: 定数計算の畳み込み、自明分岐剪定、不要束縛削除
  - `Pass 4`: 複合引数のアトミック化、`%t0`〜`%t8` 束縛
  - `Pass 5`: ラムダリフティング、フラットクロージャ、`letrec` バックパッチ
  - `Pass 6`: LIR 命令列の正当性

### Layer 2: インクリメンタル E2E テスト (`test.sh`)
Abdulaziz Ghuloum 論文および *compilerbook* 準拠の 27 ステップ・全 7 フェーズテスト。

```bash
cd ulisp
./test.sh
```

- **テストフェーズ一覧**:
  - `Phase 1`: 整数、即値リテラル、単項演算、ブール述語
  - `Phase 2`: 二項演算（`+`, `-`, `*`, 比較）、局所変数（`let`）、条件分岐（`if`）
  - `Phase 3`: ペアとリスト（`cons`, `car`, `cdr`）、`quote` リテラル
  - `Phase 4`: 第一級関数・クロージャ、相互再帰（`letrec`）、末尾呼び出し最適化（TCO 深度 100,000）
  - `Phase 5`: 標準ライブラリ脱糖（`cond`, `case`, `let*`, `and`, `or`, `string-append`）
  - `Phase 6`: システムコール I/O（`read-char`, `peek-char`, `write-char`）、自前 S 式パーサ（`read`）
  - `Phase 7`: 3段階セルフホスティングブートストラップ連鎖

### Layer 3: 3段階セルフホスティング不動点検証 (`bootstrap.sh`)
コンパイラが自らを完全にコンパイルできる能力（Self-Hosting）を数学的・決定論的に証明する最重要テスト。

```bash
cd ulisp
./bootstrap.sh
```

- **検証フロー**:
  1. `Stage 1`: Python ILisp を使って `ulisp_core.scm` を x86-64 にコンパイル $\to$ `scheme-stage1` バイナリ生成。
  2. `Stage 2`: `scheme-stage1` を使って `ulisp_core.scm` を再コンパイル $\to$ `stage2.s` 出力。
  3. `Stage 3`: `scheme-stage2` を使って `ulisp_core.scm` を再コンパイル $\to$ `stage3.s` 出力。
  4. **不動点検証**: `diff build/stage2.s build/stage3.s == 0` を確認。完全一致すれば合格。

### Layer 4: ILisp AOT 連携テスト (`pytest`)
ILisp（R7RS Scheme）から ULisp コード生成バックエンドを呼び出し、ネイティブ ELF を生成・実行する統合テスト。

```bash
.venv/bin/pytest tests/ilisp/test_ulisp_codegen.py -v
```

---

## 3. トラブルシューティング

### Q1. ブートストラップ中に SIGSEGV (signal 11) でクラッシュする
- **原因 1: ヒープ枯渇**: `runtime.c` のバンプアロケータは単調増加（Bump Allocator）であり、GC 実装前はコンパイラが自らを処理する際のメモリ消費量が `HEAP_SIZE`（1GB）を超えるとクラッシュする。
  - **対策**: パス内部で不要な `string->symbol` や無駄なクロージャ生成（CPS 乱用）を排除し、Scoped Temporary Variable Pool を使用すること。
- **原因 2: スタックアライメント違反**: x86-64 System V ABI では、`call` 命令発行時点で `rsp` が 16 バイト境界にアライメントされている必要がある。`sub rsp, N` で 16 バイトの倍数を維持しているか確認すること。

### Q2. Stage 2 と Stage 3 で `diff` が発生する (不動点が成立しない)
- **原因 1: 非決定論的シンボル名**: `unique-symbol` や `unique-label` のカウンタがパス間で共有され、評価順序によってラベル番号がずれている。
  - **対策**: カウンタを決定論的に初期化するか、固定プール（`%t0`〜`%t8`）を使用すること。
- **原因 2: ハッシュ順序の揺らぎ**: 辞書やシンボルテーブルの走査順序がランダム化されている場合。
  - **対策**: 決定論的リスト（FIFO）または整列済み探索を行うこと。
