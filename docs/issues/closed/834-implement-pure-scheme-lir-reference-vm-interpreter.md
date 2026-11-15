---
ID: 834
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] 純粋 Scheme 製 LIR 参照インタプリタ (Reference VM) の実装 (ID: 834)

## 1. 概要 / Summary
x86_64 バックエンド（Pass 140）や C バックエンド（Pass 160）などのネイティブコード生成器・外部アセンブラ・リンカに一切依存せず、低レベル中間表現（Canonical LIR: Low-level Intermediate Representation）の命令シーケンスを純粋 Scheme プロセス内で直接ステップ実行・検証できる参照仮想マシン（LIR Reference VM: `ulisp/vm/lir_interpreter.scm`）を設計・実装する。

DSN-33-02 §7.1 および S1 マイルストーン（基盤整備 ＆ Reference VM）の中核を担い、C 言語フロントエンドからの Lowering パスや各種 LIR 最適化パス（Pass 132 Braun SSA、Pass 133 Peephole）の正当性をミリ秒単位のサイクルで自動検証可能にする。また、将来の Scheme インタプリタ用バイトコード VM の参照モデルや、コンパイル時計算（CTFE / `eval-in-language`）の実行基盤としても直交活用する。

### 背景とアーキテクチャ上の動機
1. **コンパイル・テストサイクルの劇的高速化 (DSN-33-02 §7.1, S1マイルストーン)**:
   - 従来のテストフローでは、LIR を x86-64 アセンブリ（`.s`）または C ソース（`.c`）へ変換し、外部の `as`/`ld` または `gcc`/`clang` でバイナリをビルドしてプロセス実行する必要があった。純粋 Scheme による Reference VM が存在することで、外部ツールチェイン呼び出しのオーバーヘッドを完全に排除し、インメモリで即座に LIR プログラムを評価・検証できる。
2. **多言語 Lowering パスおよび LIR 最適化の直接検証 (DSN-38 §2 K3)**:
   - C フロントエンドや Scheme 脱糖パスから生成された LIR 命令列が、意図した通りのセマンティクス（レジスタ値、メモリアクセスパターン、制御フロー分岐）を維持しているかを、最小単位のユニットテストで直接アサーション可能にする。
3. **型付き機械語 LIR およびフラグ直結演算の完全シミュレーション (Issue #826, #828)**:
   - 64 ビット汎用レジスタ（`%rax`〜`%r15`）と XMM 浮動小数点レジスタ（`%xmm0`〜`%xmm15`）、型付きメモリ操作（`i8`〜`i64`, `f32`, `f64`, `ptr`）、およびオーバーフロー検知付き算術命令（`%add-overflow`, `%sub-overflow`, `%mul-overflow`, `%udiv`, `%urem`）を厳密にシミュレートする。
4. **SSA 基本ブロック引数と並列コピーの正確な解釈 (Issue #827, Pass 132)**:
   - `%block <lbl> (<p1> ...)` に対する `%jump <lbl> (<a1> ...)` のブロック引数渡しを、SSA 並列代入セマンティクスに基づいて安全にディスパッチする。

---

## 2. トレーサビリティ / Traceability
- **DSN-33 包括設計書**:
  - §2: Canonical LIR 境界契約と抽象マシンモデル
  - §3.1: Nanopass パイプライン・中間表現構造
- **DSN-33-02 設計書**:
  - §7.1: 純粋 Scheme 製 LIR 参照仮想マシン (Reference VM) (Issue #834)
  - §8.1: ロードマップ S1 (基盤整備 ＆ Reference VM)
  - §4.1: 機械型付き LIR 命令体系 (Issue #826)
  - §4.3: フラグ直結オーバーフロー算術命令 (Issue #828)
  - §6.1: Pass 132 Braun SSA の任意 CFG 対応 (Issue #827)
- **DSN-38 仕様書**:
  - §2 K3: LIR レベル差分テストおよび実行セマンティクス検証
  - §2 E9: LIR 形式意味論
  - §4: 未決事項 4 (実行速度と検証基盤)
- **関連 Issue**:
  - #824: Nanopass AST ノードにおける第一級ソース位置情報 (Source Span)
  - #826: 機械型 (i8..i64, f32, f64, ptr) を備えた Typed LIR への移行
  - #827: Pass 132 Braun SSA の任意 CFG (goto/switch) 汎用対応
  - #828: LIR におけるオーバーフロー検知付き算術および符号なし演算オペコード
  - #829: 呼出規約の多重化・モジュール分離とゼロオーバーヘッド C-FFI
  - #831: 160 C バックエンドのセマンティクス同期 ＆ 差分ファジング検証
  - #832: 純粋 Scheme による多倍長整数 (Bignum) および IEEE 754 相互変換ライブラリ
  - #833: コンパイラ・マクロ展開・インタプリタ共通の統合エラー診断エンジン

---

## 3. 脅威モデルとセキュリティ要件 (Threat Model & Security Mitigation)

参照仮想マシンは任意の LIR 命令シーケンス（コンパイラ中間出力やファジング生成コード）をインタープリテーション実行するため、不正メモリアクセス、ホストクラッシュ、無限ループ DoS 等の脅威に対する厳格な防護機構を備える。

| 脅威 ID | 脅威分類 (CWE) | 脅威シナリオ | 緩和策・設計上の防御不変条件 |
| :--- | :--- | :--- | :--- |
| **THREAT-834-1** | **CWE-119 / CWE-125 / CWE-787**<br>シミュレートメモリ境界外アクセス | 不正なポインタ演算や未初期化レジスタにより、LIR の `%load` や `%store` がシミュレート仮想アドレス空間外（負のアドレスやヒープ/スタック領域外）を指定し、ホストプロセスのメモリ破壊や異常終了を引き起こす。 | 仮想マシン内部でシミュレートされるリニアメモリ（`bytevector`）の境界検査を毎メモリアクセス時に強制。NULL ポインタ（アドレス `< 4096`）および上限超過アクセスに対しては即座にトラップ `<vm-trap-out-of-bounds>` を発生させ、ホストの安全性を 100% 保証する。 |
| **THREAT-834-2** | **CWE-400 / CWE-835**<br>無限ループによるリソース枯渇 (DoS) | 循環ジャンプや無限再帰を含むバグのある LIR プログラムを実行した際、VM の実行ループが停止せず、CPU 時間を占有してコンパイラやテストランナーがフリーズする。 | 実行ステップ数制限（Fuel / Step Counter）を導入。デフォルトで一定命令数（例: 10,000,000 ステップ）を超えた場合に自動停止し、`<vm-trap-out-of-fuel>` を送出して安全に実行を中断する。 |
| **THREAT-834-3** | **CWE-369**<br>ゼロ除算による未補足例外クラッシュ | `%idiv`, `%udiv`, `%urem` 命令において、除数オペランドが 0 である場合にホスト Scheme 処理系がゼロ除算例外（ZeroDivisionError 等）を発生させて VM 全体がクラッシュする。 | 整数除算・剰余命令の実行前に除数レジスタが 0 であるかを明示的に判定し、ゼロ除算を検知した場合は `<vm-trap-division-by-zero>` を送出して安全にエラー状態へ遷移する。 |
| **THREAT-834-4** | **CWE-822 / CWE-824**<br>未定義ジャンプ先・呼出先による制御フロー逸脱 | `%jump`, `%jump-cond`, `%direct-call` 等で未定義のラベルや関数シンボルが指定された場合、未初期化状態へのアクセスや不正な命令インデックス参照が発生する。 | プログラムロード時にラベル辞書（`label-table`）および関数辞書（`function-table`）を静的に事前検証。未定義ターゲットへの遷移が発生した場合は即座に `<vm-trap-undefined-target>` を発生させる。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/vm/lir_interpreter.scm](../../ulisp/vm/lir_interpreter.scm):
  - 新設：LIR Reference VM コア実装（`<lir-vm>` レコード、仮想レジスタ、64-bit リニアメモリ、ステータス、トラップ）。
  - 新設：リニアメモリ・Little-Endian 読込・書込エンジン（`u8`〜`u64`, `i8`〜`i64`, `f32`, `f64`）。
  - 新設：LIR オペランド評価器（レジスタ、即値、スタックスロット、メモリオフセット、SIB、文字列参照）。
  - 新設：命令ディスパッチャ（ALU、オーバーフロー算術、ビット演算、Typed メモリ、条件フラグ、SSA ブロック遷移）。
  - 新設：呼出規約・関数フレーム管理（`%direct-call`, `%c-call`, `%return`）。
  - 新設：ステップ実行・トレーシング・デバッグフック（`lir-vm-step!`, `set-lir-vm-tracer!`）。
- [x] [ulisp/tests/test_lir_interpreter.scm](../../ulisp/tests/test_lir_interpreter.scm):
  - 新設：参照 VM の網羅的単体テストスイート（算術、ビット演算、オーバーフロー、メモリ、SSA、多方向分岐、関数呼出し、再帰、浮動小数点、トラップ）。
- [x] [ulisp/Makefile](../../ulisp/Makefile):
  - `test_lir_interpreter` ターゲットの新設および `test:` 依存関係への追加。
- [x] [docs/issues/README.md](README.md):
  - Issue #834 のステータスを `Closed (Completed)` へ更新。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/834-pure-scheme-lir-reference-vm`

### ステップ 1: 仮想マシン状態 (`<lir-vm>`) とリニアメモリモデルの設計 (`ulisp/vm/lir_interpreter.scm`)
1. **VM 状態レコード `<lir-vm>` の定義**:
   ```scheme
   (define-record-type <lir-vm>
     (make-lir-vm-raw registers xmm-registers flags memory heap-ptr
                      strings functions blocks current-fn current-block
                      pc call-stack status fuel step-count tracer last-trap globals)
     lir-vm?
     (registers vm-registers-vector vm-set-registers-vector!)
     (xmm-registers vm-xmm-vector vm-set-xmm-vector!)
     (flags vm-flags-record vm-set-flags-record!)
     (memory vm-memory-bytes vm-set-memory-bytes!)
     (heap-ptr vm-heap-ptr vm-set-heap-ptr!)
     (strings vm-strings-table vm-set-strings-table!)
     (functions vm-functions-table vm-set-functions-table!)
     (blocks vm-blocks-table vm-set-blocks-table!)
     (current-fn vm-current-fn vm-set-current-fn!)
     (current-block vm-current-block vm-set-current-block!)
     (pc vm-pc vm-set-pc!)
     (call-stack vm-call-stack vm-set-call-stack!)
     (status vm-status vm-set-status!)
     (fuel vm-fuel vm-set-fuel!)
     (step-count vm-step-count vm-set-step-count!)
     (tracer vm-tracer vm-set-tracer!)
     (last-trap vm-last-trap vm-set-last-trap!)
     (globals vm-globals-table vm-set-globals-table!))
   ```
2. **リニアメモリ配置と Little-Endian アクセサ**:
   - デフォルトメモリサイズ: 16MB（テストやシミュレーションに十分かつ高速）。
   - アドレス `0x00000000 - 0x00000fff`: NULL ページ（アクセス時トラップ）。
   - アドレス `0x00001000 - 0x0000ffff`: 文字列リテラル静的領域。
   - アドレス `0x00010000 - 0x007fffff`: ヒープ領域（`%r12` 初期値 `0x00010000`、上向き伸長）。
   - アドレス `0x00800000 - 0x00ffffff`: スタック領域（`%rsp` 初期値 `0x00ffff00`、下向き伸長）。
   - Little-Endian 変換関数群:
     - `vm-mem-read-u8`, `vm-mem-read-i8`, `vm-mem-write-u8!`, `vm-mem-write-i8!`
     - `vm-mem-read-u16`, `vm-mem-read-i16`, `vm-mem-write-u16!`, `vm-mem-write-i16!`
     - `vm-mem-read-u32`, `vm-mem-read-i32`, `vm-mem-write-u32!`, `vm-mem-write-i32!`
     - `vm-mem-read-u64`, `vm-mem-read-i64`, `vm-mem-write-u64!`, `vm-mem-write-i64!`
     - `vm-mem-read-f32`, `vm-mem-read-f64`, `vm-mem-write-f32!`, `vm-mem-write-f64!`

### ステップ 2: レジスタファイル・フラグ・オペランド解決機構
1. **汎用レジスタ (GPR) および浮動小数点レジスタ (XMM)**:
   - 16 本の 64-bit 汎用レジスタ: `%rax`, `%rbx`, `%rcx`, `%rdx`, `%rsi`, `%rdi`, `%rbp`, `%rsp`, `%r8`〜`%r15`。
   - `%al` への読み書きは `%rax` の下位 8 ビットに透過的にマッピング。
   - 16 本の 64-bit XMM レジスタ: `%xmm0`〜`%xmm15`。
   - 抽象仮想レジスタ `(%reg <name>)`, `(%reg <type> <name>)`, `(%freg <name>)` の連想配列/テーブル解決。
2. **条件フラグ (EFLAGS シミュレーション)**:
   - `ZF` (Zero Flag), `SF` (Sign Flag), `OF` (Overflow Flag), `CF` (Carry Flag)。
   - 算術・比較演算（`%cmp`, `%add`, `%sub` 等）実行時にフラグを更新。
   - 条件コード判定関数 `vm-check-condition-code (cc flags)`:
     - `e` / `z`: `ZF == 1`
     - `ne` / `nz`: `ZF == 0`
     - `l`: `SF != OF`
     - `le`: `ZF == 1 or SF != OF`
     - `g`: `ZF == 0 and SF == OF`
     - `ge`: `SF == OF`
     - `b` / `c`: `CF == 1`
     - `be`: `CF == 1 or ZF == 1`
     - `a`: `CF == 0 and ZF == 0`
     - `ae`: `CF == 0`
     - `o`: `OF == 1`
     - `no`: `OF == 0`
3. **オペランド解決器 `(vm-eval-operand vm opnd)`**:
   - 即値整数 $\to$ そのまま返却。
   - レジスタシンボル $\to$ レジスタファイルから現在値を取得。
   - `(%stack offset)` $\to$ `*(int64_t*)(%rsp + offset)` を読出。
   - `(%mem base offset)` $\to$ `base` と `offset`（整数またはレジスタ、SIB形式）から実効アドレスを計算し読出。

### ステップ 3: LIR 命令ディスパッチエンジンの実装
1. **データ転送・メモリ命令**:
   - `%mov dst src`, `%load dst base offset`, `%store base offset src`
   - `%load-byte-zx`, `%store-byte`
   - `%load-typed type dst base offset`, `%store-typed type base offset src`
   - `%push src`, `%pop dst`
   - `%str-ref dst lbl`, `%code-ref dst lbl`, `%global-ref dst var`, `%global-set! var src`
2. **整数・ビット・オーバーフロー算術命令**:
   - `%add`, `%raw-add`, `%sub`, `%raw-sub`, `%imul`, `%raw-mul`, `%neg`, `%inc`
   - `%cqo`: `%rax` の符号ビットを `%rdx` に拡張（`rdx = if rax < 0 then -1 else 0`）。
   - `%idiv src`: 符号付き除算（`rax = rax / src`, `rdx = rax % src`）。
   - `%udiv src`, `%urem src`: 符号なし 64 ビット除算および剰余。
   - `%bit-and`, `%bit-or`, `%bit-xor`, `%not`, `%shl`, `%shr`, `%sar`
   - `%add-overflow`, `%sub-overflow`, `%mul-overflow`（Issue #828 準拠の 64-bit 符号付きオーバーフロー判定および OF 設定）。
   - `%uadd`, `%usub`, `%umul`（符号なし演算および CF 設定）。
   - `%box-fixnum dst src` (`dst = src << 2`), `%unbox-fixnum dst src` (`dst = src >> 2`)
   - `%cmp`, `%raw-cmp`, `%set-boolean dst cc`
3. **浮動小数点演算 (XMM)**:
   - `%sitofp f-dst i-src`, `%fptosi i-dst f-src`
   - `%fadd`, `%fsub`, `%fmul`, `%fdiv`, `%fcmp`
4. **制御フロー・SSA 基本ブロック遷移**:
   - `%label lbl`, `%block lbl (params...) body...`
   - `%jump lbl (args...)`: 遷移先 `%block` の仮引数リストに対して引数を並列代入（Parallel Copy）し、ブロック先頭へ PC を遷移。
   - `%jump-if reg t-lbl (ta...) e-lbl (ea...)`: `reg` の真偽値（Scheme `#f` = 0x2F 以外は真）に応じた分岐。
   - `%jump-if-false reg lbl (args...)`: `reg` が `#f` (0x2F) の場合ジャンプ。
   - `%jump-cond cc lbl`, `%jump-if-zero lbl`
   - `%return [val]`: 呼び出し元フレームへ復帰（または main 終了）。

### ステップ 4: 手続き呼出・スタックフレーム・C ランタイムスタブ
1. **呼出規約とスタックフレーム管理**:
   - `%direct-call func-lbl shift [safepoint]`:
     - リターンアドレス（呼出元関数・ブロック・次命令インデックス）および現在のレジスタ退避状態を `call-stack` にプッシュ。
     - `%rsp` を `shift` 分だけ減算してフレーム境界を調整。
     - 遷移先 `%lir-function` の `body` 先頭へ PC を移動。
   - `%return`:
     - `call-stack` からフレームをポップし、呼び出し元コンテキストへ復帰。戻り値は `%rax`（または引数で指定された値）。
2. **C ランタイム ABI 呼出 (`%c-call`) ディスパッチャ**:
   - 組み込み C ランタイムスタブを標準提供:
     - `ulisp_alloc(bytes, tag)`: 仮想マシンヒープ（`%r12`）から領域を割り当て、タグを付与したポインタを `%rax` に返却。
     - `printf`, `puts`, `putchar`: シミュレートメモリ内の文字列・文字を出力。
     - `exit(code)`: 仮想マシンを即時停止。
   - 外部関数テーブル `(register-c-foreign-handler! vm name proc)` による拡張可能な FFI スタブフック。

### ステップ 5: 実行制御、安全トラップ、デバッグトレーサ
1. **実行制御 API**:
   - `(make-lir-vm [mem-size])`: 新規 VM インスタンスの生成。
   - `(lir-vm-load! vm lir-program)`: `%lir-program` の読み込み、文字列・関数・ブロックのインデックス構築、初期レジスタ・スタック設定。
   - `(lir-vm-run! vm)`: プログラム終了またはトラップ発生まで連続実行。
   - `(lir-vm-step! vm)`: 1 命令のステップ実行。
   - `(eval-lir-program lir-prog [fuel])`: 一括実行し、終了時の `%rax`（Fixnum の場合は自動アンボックス可能）を返却する高水準ファサード。
2. **安全トラップ機構**:
   - `<vm-trap>` レコード: `type` (`'out-of-bounds`, `'out-of-fuel`, `'division-by-zero`, `'undefined-target`), `message`, `pc`, `details`。
   - トラップ発生時は VM のステータスを `'trapped` に設定し、`last-trap` に記録して安全に復帰（または例外送出）。
3. **デバッグ・トレーシングフック**:
   - `(set-lir-vm-tracer! vm proc)`: 各ステップ実行前に `(proc vm current-inst)` を呼び出し、実行命令、オペランド値、変更前後のレジスタ差分を出力可能にする。

### ステップ 6: テストスイートの実装 (`ulisp/tests/test_lir_interpreter.scm`)
以下の全 9 グループにわたる単体テストおよび差分検証テストを実装する：
- **Group 1: 基本 ALU ＆ ビット演算**（`%mov`, `%add`, `%sub`, `%imul`, `%neg`, `%bit-and`, `%shl`, `%shr`）
- **Group 2: オーバーフロー検知 ＆ 符号なし演算**（`%add-overflow`, `%sub-overflow`, `%mul-overflow`, `%udiv`, `%urem`, OF/CF フラグ）
- **Group 3: メモリ・型付きロード/ストア**（`%store-typed`, `%load-typed` across `i8`, `u16`, `i32`, `i64`, SIB 形式）
- **Group 4: SSA ブロック引数と並列代入**（`%block` と `%jump` によるループおよびフィボナッチ計算）
- **Group 5: 条件分岐・制御フロー**（`%jump-if`, `%jump-if-false`, `%jump-cond`, 多重ループ）
- **Group 6: 関数呼出しと再帰**（`%direct-call`, `%return`, 再帰的階乗計算、フレームサイズ調整）
- **Group 7: 浮動小数点演算**（`%sitofp`, `%fadd`, `%fsub`, `%fmul`, `%fdiv`, `%fcmp`）
- **Group 8: 安全トラップ ＆ 境界検査**（NULL ポインタ参照、メモリ境界外書込、ゼロ除算、Fuel 枯渇 DoS 防御）
- **Group 9: 既存 LIR フィクスチャとの差分検証**（`ulisp/tests/fixtures/lir/` の既存 LIR プログラムを実行し、期待結果と完全一致することを確認）

### ステップ 7: Makefile 統合と CI 回帰検証
1. `ulisp/Makefile` に `test_lir_interpreter` ターゲットを追加。
2. `make test` の実行依存ターゲットに `test_lir_interpreter` を追加。
3. `make -C ulisp test_lir_interpreter` および `make py_compile && make static_analysis` のパスを確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/vm/lir_interpreter.scm` が純粋 Scheme で実装され、外部依存ゼロで読み込み可能であること。
- [x] 64-bit 汎用レジスタ、XMM 浮動小数点レジスタ、EFLAGS 条件フラグ、および 16MB リニアメモリモデルが完全に動作すること。
- [x] 基本 ALU、符号なし演算、Issue #828 オーバーフロー算術、および Issue #826 型付きロード/ストア命令が仕様通り実行できること。
- [x] SSA `%block` 引数の並列コピー、`%jump-if`/`%jump-cond` 条件分岐、および `%direct-call`/`%return` 関数呼出し・再帰が正確に動作すること。
- [x] メモリ境界外アクセス、ゼロ除算、および Fuel 枯渇に対する安全トラップ（THREAT-834-1〜834-4）が 100% 機能すること。
- [x] 単体テスト `ulisp/tests/test_lir_interpreter.scm` の全テストケースが 100% PASS すること。
- [x] `make -C ulisp test_lir_interpreter` が正常終了し、`make test` に統合されていること。
- [x] `docs/issues/README.md` のステータスが更新されていること。
