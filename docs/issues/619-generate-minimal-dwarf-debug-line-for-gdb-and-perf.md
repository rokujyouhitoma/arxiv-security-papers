---
ID: 619
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] ソース位置追跡情報（%source-loc）に基づく最小限 DWARF（.debug_line）セクション生成と GDB / perf デバッグ支援の実装 (ID: 619)

## 1. 概要 / Summary
現在 ULisp は Issue 606 によりコンパイル対象 AST 全体にソースファイル名・行番号・列番号（`%source-loc`）を保持しているが、バックエンド出力時に DWARF デバッグ情報を生成していない。そのため、生成された ELF 実行バイナリを `gdb` や `lldb` で検査した際、Scheme のソース行でブレークポイントを打つことやステップ実行（`step`, `next`）、クラッシュ時の行番号バックトレース（`bt`）表示ができない。また、Linux `perf` ツールでのボトルネック分析時にも関数シンボルや行番号が解決されないという課題がある。

本 Issue では、重厚な DWARF 規格全体を抱え込むことなく、開発に不可欠な「行番号とソースファイル対応」を可能にする「最小限 DWARF（`.debug_line` セクション）」の生成機能をバックエンドへ実装する。これにより、C 言語と同等の GDB 対話デバッグおよび `perf` プロファイリング環境を提供する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - DWARF Debugging Information Format Version 4 / 5 Specification (Section 6.2: Line Number Program)
- **関連 Issue**:
  - Issue 604: コンパイラ実行時のコールスタック追跡および未捕捉例外時のバックトレース表示機能の実装
  - Issue 606: ビルド時 cat 結合の廃止と R7RS include 構文によるソース位置追跡基盤の導入
  - Issue 615: ビルドパイプラインからの GCC 呼出し排除と GNU as / ld 直接駆動への移行
  - Issue 616: Scheme ネイティブ x86-64 マシン語エンコーダおよび ELF64 実行可能バイナリ直接出力バックエンドの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (アセンブリ出力時における `.file` / `.loc` ディレクティブの挿入)
- [ ] [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm) (Direct-to-ELF における `.debug_line` セクションのバイナリ構築)
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (`-g` デバッグシンボル生成フラグのサポート)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (デバッグビルドおよび GDB 動作検証ターゲットの追加)
- [ ] [ulisp/tests/test_dwarf_debug.sh](../../ulisp/tests/test_dwarf_debug.sh) (新規: GDB によるブレークポイント・行番号逆引き検証スクリプト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/619-generate-minimal-dwarf-debug-line-for-gdb-and-perf`

1. **アセンブリ出力パス（Pass 140）への DWARF ディレクティブ統合（Phase 1）**:
   - コンパイラドライバに `-g` オプション（または `(!debug #t)`）を導入。
   - コード生成ループにおいて、前後の命令でソース位置（ファイル名・行番号）が変わったタイミングを検知。
   - ファイルテーブルを管理し、ヘッダに `.file <file_id> "<path>"` を出力。
   - 命令直前に `.loc <file_id> <line> <col>` ディレクティブを emit。これにより GNU `as` が自動的に ELF `.debug_line` を合成。
2. **Direct-to-ELF バックエンド（Pass 144）への `.debug_line` エンコーダ組込み（Phase 2）**:
   - DWARF 4 Line Number Program ステートマシンを Scheme 上で実装。
   - ヘッダ情報（Unit Length, Version=4, Header Length, Min Instruction Length=1, Default is_stmt=1, Line Base, Line Range, Opcode Base, Standard Opcode Lengths, Include Dirs, File Names）をバイナリ出力。
   - オペコード（`DW_LNS_advance_pc`, `DW_LNS_advance_line`, `DW_LNS_copy`, `DW_LNE_end_sequence` 等）を `bytevector` 上に構築。
   - ELF セクションヘッダに `.debug_line`（`SHT_PROGBITS`）を追加登録。
3. **GDB / perf 連携の自動テスト**:
   - テスト用 Scheme プログラム（例: `tests/debug_sample.scm`）を `-g` でコンパイル。
   - `gdb --batch -ex "b 10" -ex "run" -ex "bt"` を実行し、指定した Scheme ソース行で停止してファイル名と行番号が表示されることを機械的にテスト。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `-g` オプションを付与してコンパイルしたバイナリに `.debug_line` セクションが含まれていること（`readelf -S` で確認）。
- [ ] `gdb` 上で Scheme ソースの行番号を指定したブレークポイント（`b file.scm:line`）が正常に機能すること。
- [ ] プログラムクラッシュ時、GDB の `bt`（バックトレース）で Scheme のファイル名と行番号が表示されること。
- [ ] `Linux perf` でプロファイリングした際、命令アドレスではなく Scheme のシンボル/行番号が解決されること。
- [ ] デバッグ情報を無効化（通常ビルド）した際、バイナリサイズおよびコンパイル速度への影響が皆無であること。
