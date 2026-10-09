---
ID: 502
種別: Refactor
優先度: High
ステータス: Open (New)
---

# [REFACTOR] Introduce Low-Level IR (LIR) and Decouple Backend Codegen for ULisp (ID: 502)

## 1. 概要 / Summary
現在、ULisp のコード生成器（`ulisp/passes/07_codegen.scm`）は、クロージャ変換後の S 式 AST（HIR: High-Level IR）から直接 x86-64 アセンブリ文字列（`mov rax, ...` 等）を生成している。このため、バックエンドが x86-64 に密結合しており、AArch64（ARM64）や C言語/WebAssembly などのマルチターゲット展開が困難である。

本 Issue では、Chez Scheme などの正統派コンパイラアーキテクチャに準拠し、**「低レベルIR（LIR: Low-level IR / 機械抽象レベル S式表現）」** を導入してバックエンドを完全分離する。
また、ユーザー要求に基づき、**各 Nanopass（Pass 1 脱糖、Pass 2 スコープ解析、Pass 3 CP0 最適化、Pass 4 ANF 正規化、Pass 5 クロージャ変換、Pass 6 LIR 生成、Pass 7 バックエンド）ごとに独立したパス別単体テストスイートを網羅的に拡充** する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §3 (言語機能と低レイヤコード生成仕様), §4 (フェーズ別コンパイラ設計), §6.1 (セルフホスティングパイプライン)
- **DSN-31**: §3.2 (Backend B: ULisp AOT Native Backend)
- **先行 Issue**: #498 (Closure Conversion Nanopass), #499 (ANF & CP0 Nanopass)
- **後続 Issue**: #503 (AArch64 Backend via LIR), #504 (Portable C / Wasm Backend via LIR)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/06_lir.scm](file:///workspace/arxiv-security-papers/ulisp/passes/06_lir.scm): 新設する HIR $\to$ LIR 変換 Nanopass
- [ ] [ulisp/passes/07_backend_x86_64.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_x86_64.scm): 旧 `07_codegen.scm` を LIR $\to$ x86-64 展開ルーチンへ純化
- [ ] [ulisp/passes/08_driver.scm](file:///workspace/arxiv-security-papers/ulisp/passes/08_driver.scm): 新パイプライン直列接続
- [ ] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): `PASSES` 構成の同期
- [ ] [ulisp/tests/test_passes.scm](file:///workspace/arxiv-security-papers/ulisp/tests/test_passes.scm): 各パス単体テストランナー（新設）
- [ ] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh): パス別単体テスト実行ステップの統合
- [ ] [ulisp/bootstrap.sh](file:///workspace/arxiv-security-papers/ulisp/bootstrap.sh): セルフホスティング不動点検証
- [ ] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/502-introduce-ulisp-low-level-ir-and-decouple-backend`

1. **LIR (Low-level IR) の S 式仕様策定**:
   - 制御フロー: `(%label L)`, `(%jump L)`, `(%jump-if-false operand L)`, `(%return val)`, `(%tail-call target args...)`, `(%call dst target args...)`
   - メモリ/転送: `(%mov dst src)`, `(%load dst base offset)`, `(%store base offset src)`
   - 算術・論理: `(%add dst s1 s2)`, `(%sub dst s1 s2)`, `(%mul dst s1 s2)`, `(%bit-and dst s1 s2)`, `(%bit-shift-left dst s1 n)`
   - ヒープ: `(%alloc dst bytes)`
2. **Pass 6 (`06_lir.scm`) の実装**:
   - クロージャ変換済みフラット関数群（`%function`）から、スタックフレームオフセットを計算し、ターゲット非依存な 3 番地 LIR 命令列へ変換。
3. **Pass 7 (`07_backend_x86_64.scm`) の純化**:
   - LIR 命令を受け取り、直截に GNU x86-64 アセンブリを発行するエミッタへ単純化。
4. **各パス単位のテストスイート拡充**:
   - `test_pass01_desugar`: `cond`, `case`, `let*`, `named-let`, `and`, `or` の正規化テスト
   - `test_pass02_analysis`: `free-vars`, スコープ解析テスト
   - `test_pass03_cp0`: 定数畳み込み、自明分岐剪定、不要 let 削除テスト
   - `test_pass04_anf`: 複合式引数のアトミック化、3番地コード正規化テスト
   - `test_pass05_closure_convert`: ラムダリフティング、フラットクロージャ生成、letrec 相互再帰テスト
   - `test_pass06_lir`: HIR $\to$ LIR 変換命令列テスト
   - `test_pass07_codegen`: x86-64 出力命令テスト

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] LIR がターゲット非依存な S 式命令列として定義され、Pass 6 `06_lir.scm` で生成されること。
- [ ] Pass 7 `07_backend_x86_64.scm` が LIR のみを入力として x86-64 コード生成を行うこと。
- [ ] 各パス（Pass 1〜Pass 7）を個別に検証する単体テストスイートが新設され、全件 PASS すること。
- [ ] `ulisp/test.sh` および `ulisp/bootstrap.sh` の不動点検証（`diff stage2.s stage3.s == 0`）が 100% 成立すること。
- [ ] `tests/ilisp/test_ulisp_codegen.py` が全 18 件 PASS すること。
- [ ] `make check_format` & `make py_compile` をパスすること。
