---
ID: 830
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-11-15
---

# [FEAT] 144a アセンブラおよび 144 ELF リンカにおける複数セクション (.rodata/.data/.bss) と再配置の抽象化 (ID: 830)

## 1. 概要 / Summary
現在、ULisp の自前 x86-64 アセンブラ（`ulisp/backend/144a_x86_assembler.scm`）および ELF ビルダー／リンカ（`ulisp/backend/elf64_builder.scm`, `ulisp/backend/144_backend_x86_elf.scm`）は、実行ファイル直接生成（`assemble-x86-lines` による ET_EXEC 出力）と再配置可能オブジェクト生成（`assemble-x86-relocatable` による ET_REL 出力）の 2 系統のコードパスに分かれており、セクションの管理がハードコードされた固定テーブル（`.text`, `.rodata`, `.data`, `.bss`, `.init_array`, `ulisp_globals_sec`）に基づいている。

また、現状のアセンブラには以下の課題が存在する：
1. **データディレクティブの不足**:
   - `.long`（32ビット整数）、`.short` / `.2byte`（16ビット整数）、`.4byte`, `.8byte`, `.string`（`.asciz` エイリアス）、`.fill` 等の一般的な GAS データディレクティブが未実装であり、将来の C コンパイラフロントエンド（DSN-38）やリテラルプールが生成するアセンブリコードの解釈に支障をきたす。
2. **シンボル属性・可視性トラッキングの分離**:
   - `assemble-x86-lines` では `.globl`, `.weak`, `.type` が単に読み飛ばされており、シンボルのグローバル／ローカル／ウィーク属性や関数／オブジェクト種別が ET_EXEC 側のシンボルテーブルに反映されない。
3. **再配置種別の限定性**:
   - 現在サポートされている再配置は `R_X86_64_64` (1), `R_X86_64_PC32` (2), `R_X86_64_PLT32` (4) のみであり、32ビット絶対アドレスや符号付き32ビット再配置（`R_X86_64_32`, `R_X86_64_32S`）の抽象化が不足している。
4. **セクション抽象化の未整備**:
   - セクションが第一級のデータ構造（レコード／マップ）として抽象化されておらず、任意名前のセクション（例: `.rodata.str1.1` やカスタムメタデータセクション）の動的追加やアライメント・フラグ（SHF_ALLOC, SHF_WRITE, SHF_EXECINSTR）の直交制御が困難である。

本 Issue では、セクション表現を統一的な第一級レコード構造として抽象化し、データディレクティブ群の完全対応、シンボル属性（`STB_LOCAL`, `STB_GLOBAL`, `STB_WEAK`、`STT_FUNC`, `STT_OBJECT`）の統合追跡、および再配置エンジン（`R_X86_64_64`, `R_X86_64_PC32`, `R_X86_64_PLT32`, `R_X86_64_32`, `R_X86_64_32S`）のモジュール化を実現する。
これにより、自前リンカ（144）および GNU binutils（`as`, `ld`, `readelf`）の双方で相互運用可能な堅牢な ELF64 バイナリ生成基盤を確立する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38 仕様書**: §2 (C3: 大域変数と静的初期化, E7: データセクション, F1/F2: エンコードとシンボル, H2: リンカ選択)
- **DSN-33 仕様書**: §2.1 (Tagged Pointer メモリモデル), §3.3 (LIR 最適化・コード生成パイプライン)
- **関連 Issue**:
  - #616: Layer 2 Pure Scheme ELF64 Builder (Direct ET_EXEC Generation)
  - #617: 外部ツール完全非依存な自給自足 3-Stage セルフホスティングブートストラップの確立
  - #783: Builtin as アセンブラ CLI オプションと ELF64 再配置可能オブジェクト (.o) 出力
  - #784: Builtin ld 静的リンカ CLI オプションによる複数 .o の結合と単一実行ファイル生成
  - #829: 呼出規約 (Calling Convention) の多重化・モジュール分離とゼロオーバーヘッド C-FFI の実現

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/144a_x86_assembler.scm](../../ulisp/backend/144a_x86_assembler.scm):
  - データディレクティブ拡充（`.long`, `.4byte`, `.short`, `.2byte`, `.8byte`, `.string`, `.fill`, `.zero`, `.space`）
  - セクション状態管理の抽象化（セクションレコード導入・任意セクション切替）
  - シンボル属性・型ディレクティブ（`.globl`, `.weak`, `.type`）の統合追跡
  - 再配置レコード（`R_X86_64_64`, `R_X86_64_PC32`, `R_X86_64_PLT32`, `R_X86_64_32`, `R_X86_64_32S`）の抽象化
- [ ] [ulisp/backend/elf64_builder.scm](../../ulisp/backend/elf64_builder.scm):
  - セクションヘッダテーブル（SHT）の動的構築と `sh_offset` / `sh_size` / `sh_addralign` の厳密計算
  - `R_X86_64_32` (10) および `R_X86_64_32S` (11) 再配置適用のサポート
  - `elf64-build-rel-symtab` および `elf64-build-rela-section` のセクション抽象化適応
  - 静的リンカ `link-elf64-relocatable-objects` におけるセクションマージと再配置解決の汎用化
- [ ] [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm):
  - ET_EXEC および ET_REL 出力パイプラインにおける抽象セクションインタフェースとの整合性確保
- [ ] [ulisp/tests/test_elf_sections_and_reloc.scm](../../ulisp/tests/test_elf_sections_and_reloc.scm):
  - セクションディレクティブ、データ生成、シンボル可視性、再配置解決の包括的単体・結合テストスイート（新規作成）
- [ ] [ulisp/Makefile](../../ulisp/Makefile):
  - `test_elf_sections_and_reloc` ターゲットの追加および `test` スイートへの登録

---

## 4. セキュリティ・設計分析 (Threat Modeling & Constraints)
- **CWE-119 / CWE-120 (Buffer Out-of-Bounds & Section Overflow)**:
  - 不正なオフセットや過大なセクションデータがパッチ適用時やセクション配置時にバッファ外アクセスを引き起こすリスク。
  - **対策**: セクションへのデータ追加および再配置パッチ適用時、常にバッファ境界検証（`offset + sizeof(val) <= bytevector-length`）を厳格に行い、逸脱時は安全にコンパイラ診断エラーを出力して中断する。
- **CWE-787 (Out-of-Bounds Write via Malformed Relocation Addend / Offset)**:
  - 不正なアセンブリ構文（例: `label + 0x8000000000000000`）や負のオフセットにより、再配置解決時に想定外のメモリ領域が上書きされるリスク。
  - **対策**: `r-offset` および `r-addend` の符号・ビット幅境界（32ビット符号付き／符号なし範囲チェック）を事前検証し、オーバフローを防止する。
- **CWE-843 (Type Confusion in Symbol Binding / Section Index)**:
  - 特殊セクションインデックス（`SHN_UNDEF = 0`, `SHN_ABS = 0xfff1`, `SHN_COMMON = 0xfff2`）やシンボル種別（`STB_LOCAL`, `STB_GLOBAL`, `STB_WEAK`）の混同により、リンカがシンボルを誤解決または衝突させるリスク。
  - **対策**: シンボルインデックスおよびセクションインデックスの管理を型安全な辞書・構造体で行い、`STB_LOCAL` シンボルが必ず `STB_GLOBAL` より前に並ぶ ELF 仕様規則（`sh_info` = 最初の非ローカルシンボルのインデックス）を厳格に維持する。
- **W^X メモリ保護（Write XOR Execute）の厳格順守**:
  - セクションの ELF フラグおよびプログラムヘッダのパーミッションにおいて、`.text` は `RX`（読取／実行）、`.rodata` は `R`（読取専用）、`.data` / `.bss` は `RW`（読取／書込）として完全に直交分離する。実行可能かつ書込可能なページ（`RWX`）の生成を恒久的に禁止する。
- **純粋 Scheme 実装 (Zero External Dependencies)**:
  - 外部の GNU binutils（`as`, `ld`）に依存せず、すべてのセクションアセンブリ・ELF パッキング・再配置解決が純粋な Scheme コードで自給自足動作することを保証する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/830-elf-sections-and-relocations`

### ステップ 1: アセンブラデータディレクティブの拡充 (`144a_x86_assembler.scm`)
1. 整数データディレクティブのパースとバイト列エンコード：
   - `.byte`: 8ビット整数（既存）
   - `.short` / `.2byte`: 16ビットリトルエンディアン整数（新設）
   - `.long` / `.4byte`: 32ビットリトルエンディアン整数（新設）
   - `.quad` / `.8byte`: 64ビットリトルエンディアン整数（拡充、シンボルラベル参照 + addend 対応）
2. 文字列およびパディングディレクティブのパース：
   - `.string`: `.asciz` と同等の null 終端文字列エンコード
   - `.ascii`: null 終端なし文字列エンコード（既存）
   - `.zero` / `.space`: ゼロパディング領域確保（既存拡充）
   - `.fill repeat, size, value`: 指定サイズ・値の繰り返しパディング（新設）
3. カンマ区切りの複数引数（例: `.long 10, 20, 30`）の連続パースに対応。

### ステップ 2: セクション状態・シンボル属性トラッキングの汎用化 (`144a_x86_assembler.scm`)
1. セクション表現の抽象化：
   - セクション記述構造体: `(make-asm-section name type flags align)`
   - 標準セクションの定義:
     - `.text`: `type: SHT_PROGBITS`, `flags: SHF_ALLOC | SHF_EXECINSTR`, `align: 16`
     - `.rodata`: `type: SHT_PROGBITS`, `flags: SHF_ALLOC`, `align: 8`
     - `.data`: `type: SHT_PROGBITS`, `flags: SHF_ALLOC | SHF_WRITE`, `align: 8`
     - `.bss`: `type: SHT_NOBITS`, `flags: SHF_ALLOC | SHF_WRITE`, `align: 8`
     - `.init_array`: `type: SHT_INIT_ARRAY`, `flags: SHF_ALLOC | SHF_WRITE`, `align: 8`
     - `ulisp_globals_sec`: `type: SHT_PROGBITS`, `flags: SHF_ALLOC | SHF_WRITE`, `align: 8`
2. シンボル属性ディレクティブの統一管理：
   - `.globl <name>`: `STB_GLOBAL` として登録
   - `.weak <name>`: `STB_WEAK` として登録
   - `.type <name>, @function | @object`: `STT_FUNC` / `STT_OBJECT` として登録
   - `assemble-x86-lines`（ET_EXEC）および `assemble-x86-relocatable`（ET_REL）の双方で共通のシンボル追跡マップを保持。

### ステップ 3: 再配置種別の拡充とセクション抽象化 (`144a_x86_assembler.scm`, `elf64_builder.scm`)
1. 再配置レコードの抽象化:
   - レコード形式: `(list sec-name offset sym r-type addend)`
   - サポート再配置型:
     - `R_X86_64_64` (1): 64ビット絶対アドレス
     - `R_X86_64_PC32` (2): 32ビット PC 相対アドレス
     - `R_X86_64_PLT32` (4): 32ビット PLT 相対ブランチ／コール
     - `R_X86_64_32` (10): 32ビット符号なし絶対アドレス（ゼロ拡張）
     - `R_X86_64_32S` (11): 32ビット符号付き絶対アドレス（符号拡張）
2. データセクション内のシンボル参照ディレクティブ：
   - `.long sym`: `R_X86_64_32` または `R_X86_64_32S` 再配置を登録
   - `.quad sym + addend`: `R_X86_64_64` 再配置を登録

### ステップ 4: ELF64 ビルダーおよび静的リンカの拡張 (`elf64_builder.scm`, `144_backend_x86_elf.scm`)
1. `elf64-build-rel-symtab`:
   - シンボルテーブル構築時に `STB_LOCAL` シンボルを先頭に集約し、`sh_info` に最初のグローバル／ウィークシンボルのインデックスを正確に設定。
2. `elf64-build-rela-section`:
   - 対象セクションごとの SHT_RELA セクションを動的に生成し、再配置レコードを 24 バイトの ELF64 Rela 構造体として正確にシリアライズ。
3. `link-elf64-relocatable-objects`:
   - 各オブジェクトファイルの `.rodata`, `.data`, `.bss` をアライメント境界を保って結合。
   - `R_X86_64_32`, `R_X86_64_32S`, `R_X86_64_64`, `R_X86_64_PC32` の各再配置を結合後の絶対／相対アドレスに基づいて解決。

### ステップ 5: 包括的テストスイート `test_elf_sections_and_reloc.scm` の作成と検証
1. `ulisp/tests/test_elf_sections_and_reloc.scm`:
   - Group 1: データディレクティブ単体テスト（`.byte`, `.short`, `.2byte`, `.long`, `.4byte`, `.quad`, `.8byte`, `.string`, `.fill`）
   - Group 2: セクション切替およびアライメント境界テスト（`.text`, `.rodata`, `.data`, `.bss`）
   - Group 3: シンボル属性・型ディレクティブテスト（`.globl`, `.weak`, `.type`）
   - Group 4: 再配置レコード生成テスト（`R_X86_64_64`, `R_X86_64_PC32`, `R_X86_64_32`, `R_X86_64_32S`）
   - Group 5: ET_REL オブジェクト生成および `readelf -a` による構造検証
   - Group 6: 自前リンカ（144）による複数セクションオブジェクトのリンクおよび実行結果検証
2. `ulisp/Makefile` に `test_elf_sections_and_reloc` ターゲットを追加し、`make -C ulisp test` に統合。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/backend/144a_x86_assembler.scm` において `.long`, `.short`, `.2byte`, `.4byte`, `.8byte`, `.string`, `.fill` 等の全データディレクティブが正しくアセンブルできること。
- [x] セクション抽象化が導入され、`.text`, `.rodata`, `.data`, `.bss` およびカスタムセクションが統一的なアライメント・フラグ規則で処理されること。
- [x] シンボル属性（`.globl`, `.weak`, `.type`）がアセンブラから ELF シンボルテーブルへ忠実に伝播され、`readelf -s` で `GLOBAL` / `WEAK` / `LOCAL` および `FUNC` / `OBJECT` が正しく認識されること。
- [x] 再配置種別（`R_X86_64_64`, `R_X86_64_PC32`, `R_X86_64_PLT32`, `R_X86_64_32`, `R_X86_64_32S`）が正確にエンコードおよびリンク解決されること。
- [x] `ulisp/tests/test_elf_sections_and_reloc.scm` の全テスト（データディレクティブ・セクション・シンボル・再配置）が 100% PASS すること。
- [x] S式括弧チェック (`python3 scripts/lint_sexpr.py`) が全変更ファイルでエラー 0 件であること。
- [x] `make -C ulisp bootstrap`、`make -C ulisp build/ulisp-modular`、`make -C ulisp test` の全ビルド・テストがエラー・警告 0 件で通過すること。
