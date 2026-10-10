---
ID: 502
種別: Refactor
優先度: High
ステータス: Closed (Done)
---

# [REFACTOR] Introduce Low-Level IR (LIR) and Decouple Backend Codegen for ULisp (ID: 502)

## 1. 概要 / Summary
現在、ULisp のコード生成器（`ulisp/passes/07_codegen.scm`）は、クロージャ変換後の S 式 AST（HIR: High-Level IR）から直接 x86-64 アセンブリ文字列（`mov rax, ...` 等）を生成している。このため、バックエンドが x86-64 に密結合しており、AArch64（ARM64）や C言語/WebAssembly などのマルチターゲット展開が困難である。

本 Issue では、Chez Scheme などの正統派コンパイラアーキテクチャに準拠し、**「低レベルIR（LIR: Low-level IR / 機械抽象レベル S式表現）」** を導入してバックエンドを完全分離する。
また、ユーザー要求に基づき、**各 Nanopass（Pass 1 脱糖、Pass 2 スコープ解析、Pass 3 CP0 最適化、Pass 4 ANF 正規化、Pass 5 クロージャ変換、Pass 6 LIR 生成、Pass 7 バックエンド）ごとに独立したパス別単体テストスイートを網羅的に拡充** する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §2.5 (直列 Nanopass 型アーキテクチャと 2段階 IR 設計), §3.8 (Pass 0〜Pass 8 仕様), §6.1 (セルフホスティングパイプライン)
- **DSN-31**: §3.2 (Backend B: ULisp AOT Native Backend)
- **先行 Issue**: #498 (Closure Conversion Nanopass), #499 (ANF & CP0 Nanopass)
- **後続 Issue**: #503 (AArch64 Backend via LIR), #504 (Portable C / Wasm Backend via LIR)
- **設計ドキュメント**: [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md), [ulisp/docs/lir_specification.md](../../ulisp/docs/lir_specification.md), [ulisp/docs/testing_guide.md](../../ulisp/docs/testing_guide.md)

---

## 3. セキュリティ & 脅威分析 / Security Analysis & Threat Model
1. **スタックフレーム境界破壊・アライメント不正 (Stack Frame Corruption)**:
   - LIR 生成段階でローカル変数のスタックオフセット計算やフレームサイズ計算を誤り、ABI の 16 バイト境界を破壊して未定義動作やメモリ破壊を引き起こす脅威。
   - **対策**: LIR レベルで各関数の総フレームサイズを静的計算し、常に 16 バイト整列パディング（`align16`）を強制する不変条件を検証。
2. **中間命令インジェクション・不正オペコード (Invalid LIR Opcode)**:
   - 悪意ある入力や変換バグにより未定義の LIR オペコードがバックエンドに渡され、異常終了または不正命令が生成される脅威。
   - **対策**: LIR スキーマ述語（`valid-lir-instruction?`）による事前バリデーションおよびパス境界での厳格な構文検査。
3. **レジスタ競合・呼び出し規約破壊 (Calling Convention Violation)**:
   - TCO（末尾再帰）やクロージャ間接呼び出し時、引数レジスタや `%self` コンテキストレジスタが意図せず上書きされる脅威。
   - **対策**: LIR の `%tail-call` および `%call` のセマンティクスにおいて、一時スロット経由の安全なレジスタ退避順序を保証。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/06_lir.scm](file:///workspace/arxiv-security-papers/ulisp/passes/06_lir.scm): 新設する HIR $\to$ LIR 変換 Nanopass
- [x] [ulisp/passes/07_backend_x86_64.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_x86_64.scm): 旧 `07_codegen.scm` を LIR $\to$ x86-64 展開ルーチンへ純化
- [x] [ulisp/passes/08_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/08_driver.scm): 新パイプライン直列接続
- [x] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): `PASSES` 構成の同期
- [x] [ulisp/tests/test_passes.scm](file:///workspace/arxiv-security-papers/ulisp/tests/test_passes.scm): 各パス単体テストランナー（新設）
- [x] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh): パス別単体テスト実行ステップの統合
- [x] [ulisp/bootstrap.sh](file:///workspace/arxiv-security-papers/ulisp/bootstrap.sh): セルフホスティング不動点検証
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

---

## 5. 実装方針 / Implementation Plan
Target Branch: `refactor/502-introduce-ulisp-low-level-ir-and-decouple-backend`

1. **LIR (Low-level IR) の S 式仕様策定**:
   - 制御フロー: `(%label L)`, `(%jump L)`, `(%jump-if-false operand L)`, `(%return val)`, `(%tail-call target args...)`, `(%call dst target args...)`
   - メモリ/転送: `(%mov dst src)`, `(%load dst base offset)`, `(%store base offset src)`
   - 算術・論理: `(%add dst s1 s2)`, `(%sub dst s1 s2)`, `(%mul dst s1 s2)`, `(%bit-and dst s1 s2)`, `(%bit-shift-left dst s1 n)`
   - ヒープ: `(%alloc dst bytes tag)`
2. **Pass 6 (`06_lir.scm`) の実装**:
   - クロージャ変換済みフラット関数群（`%function`）から、スタックフレームオフセットを計算し、ターゲット非依存な 3 番地 LIR 命令列へ変換。
3. **Pass 7 (`07_backend_x86_64.scm`) の純化**:
   - LIR 命令を受け取り、直截に GNU x86-64 アセンブリを発行するエミッタへ単純化。
4. **各パス単位のテストスイート拡充 (`ulisp/tests/test_passes.scm`)**:
   - `test-pass01`: `cond`, `case`, `let*`, `named-let`, `and`, `or` の正規化テスト
   - `test-pass02`: `free-vars`, スコープ解析テスト
   - `test-pass03`: 定数畳み込み、自明分岐剪定、不要 let 削除テスト
   - `test-pass04`: 複合式引数のアトミック化、3番地コード正規化テスト
   - `test-pass05`: ラムダリフティング、フラットクロージャ生成、letrec 相互再帰テスト
   - `test-pass06`: HIR $\to$ LIR 変換命令列テスト
   - `test-pass07`: x86-64 出力命令テスト

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] LIR がターゲット非依存な S 式命令列として定義され、Pass 6 `06_lir.scm` で生成されること。
- [x] Pass 7 `07_backend_x86_64.scm` が LIR のみを入力として x86-64 コード生成を行うこと。
- [x] 各パス（Pass 1〜Pass 7）を個別に検証する単体テストスイート（`test_passes.scm`）が新設され、全件 PASS すること。
- [x] `ulisp/test.sh` および `ulisp/bootstrap.sh` の不動点検証（`diff stage2.s stage3.s == 0`）が 100% 成立すること。
- [x] `tests/ilisp/test_ulisp_codegen.py` が全 18 件 PASS すること。
- [x] `make check_format` & `make py_compile` をパスすること。

---

## 7. 実装・検証結果 / Results
1. **Pass 6 (HIR $\to$ LIR) & Pass 7 (LIR $\to$ x86-64) の導入完了**:
   - `passes/06_lir.scm`: 抽象 3 番地 S 式中間表現命令（`%mov`, `%load`, `%store`, `%alloc`, `%call`, `%tail-call` 等）および 16 バイト整列スタックフレーム計算を実装。
   - `passes/07_backend_x86_64.scm`: LIR 命令列のみを受け取り GAS x86-64 intel-syntax を発行する純粋なバックエンドエミッタに純化。
2. **Nanopass 独立単体テストスイート (`test_passes.scm`)**:
   - Pass 1〜Pass 7 を網羅する 43 項目の Scheme 単体テストを作成。`make test_passes` にて 43/43 PASS。
3. **セルフホスティング検証**:
   - `ulisp/test.sh` 全件 PASS。
   - `ulisp/bootstrap.sh` 不動点検証において、`build/stage2.s` と `build/stage3.s` が bit-for-bit に完全一致（0 diff）し、3段セルフホスティングブートストラップを達成。
4. **Python AOT バックエンド統合テスト**:
   - `pytest tests/ilisp/test_ulisp_codegen.py` 全 18 件 PASS。
5. **品質ゲート**:
   - `make check_format` および `make py_compile` が 0 エラーで正常終了。
