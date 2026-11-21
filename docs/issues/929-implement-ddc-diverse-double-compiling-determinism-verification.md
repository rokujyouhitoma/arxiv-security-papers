---
ID: 929
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] DDC (Diverse Double-Compiling) による C コンパイル出力の決定論性・ビット一致検証ハーネスの実装 (ID: 929)

## 1. 概要 / Summary
ULisp による C99 コンパイルパイプラインの決定論性（Deterministic Compilation）および供給網信頼性（Ken Thompson の "Trusting Trust" 対策 / David A. Wheeler の Diverse Double-Compiling）を証明するため、同一の Lua / musl C ソースコード群を異なるビルド環境・コンパイラ連鎖（GCC ビルド版 ULisp / Clang または ILisp / セルフホスト版 ULisp）でビルド・突合し、出力 `.o` および静的 ELF バイナリの SHA-256 ハッシュ完全一致を検証する DDC ハーネスを実装する（Phase S8 / Task T17）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §6.1, §6.3](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-13 §6.3](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤（実装済・先行）:
  - `#886`: セルフホスティング不動点検証（[ulisp/tests/test_self_hosting_fixed_point.scm](../../ulisp/tests/test_self_hosting_fixed_point.scm)）
  - `#925`: Lua 一括ビルド（[[#925]](925-build-lua-5x-c-codebase-compilation-pipeline-with-ulisp.md)）
  - `#928`: Pass 144 完全静的リンク移行（[[#928]](928-compile-musl-libc-with-ulisp-and-migrate-to-pass-144-elf-linker.md)）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/driver/c_driver.scm` / `ulisp/frontend_c/` (ハッシュ表走査順・`gensym`/ラベル採番・`<source-span>` ID の完全決定論化)
- [ ] [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm) (ELF セクション配置順決定論化・未定義パディングゼロクリア・非決定タイムスタンプ排除)
- [ ] `ulisp/tests/test_c_ddc_determinism.sh` (新規: Stage-A vs Stage-B vs 異環境ビルドの `.o`/`lua` ELF SHA-256 ビット一致検証)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_c_ddc` ターゲット追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/929-implement-ddc-determinism-verification`

### 4.1 コンパイラ非決定性の完全排除 (Reproducible Build Invariants)
1. **データ構造 ＆ シンボル生成**:
   - フロントエンド／LIR／リンカの連想リスト・シンボル表はポインタアドレスや乱数・Wall-Clock 時刻に依存せず、ソース出現順または辞書順ソートを厳守する。
   - 毎回の翻訳単位開始時にカウンタ（`reset-alpha-symbol-counter!`, `next-source-span-id!` 等のローカルカウンタ）を明示初期化し、ファイル絶対パスではなく正規化相対パスを使用（`__FILE__` の再現性確保）。
2. **ELF 出力のゼロ埋め決定論性**:
   - `144_backend_x86_elf.scm` / `elf64_builder.scm` のアライメントパディングバイトおよびセクションヘッダ余白を常に `0x00` 充填する。

### 4.2 DDC (Diverse Double-Compiling) 検証ハーネス (`test_c_ddc_determinism.sh`)
1. 異なるコンパイラ系統でコンパイルされた ULisp 本体（例: ホスト GCC 系譜 ULisp と別環境系譜または ILisp 出力系譜 ULisp）で同一の Lua + musl C ソース群をビルドし、全 `.o` と最終 `lua` ELF バイナリの `sha256sum` を比較して **全件ビット一致** をアサートする（不一致時は `objdump`/`readelf` で差分箇所を自動特定）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 異なるビルド環境・複数回実行でビルドした Lua オブジェクト群（`.o`）および静的 ELF バイナリの SHA-256 ハッシュが 100% 一致すること。
- [ ] DDC 相互コンパイル検証（`make -C ulisp test_c_ddc`）が安定 PASS すること。
