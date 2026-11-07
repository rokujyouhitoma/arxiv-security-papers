---
ID: 779
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] コンパイラ初期アリーナヒープ一括確保およびダイレクト ELF 出力によるブートストラップ I/O 高速化 (ID: 779)

## 1. 概要 / Summary

ULisp のブートストラップ実行時において、コンパイラプロセスは数十万から数百万個の AST ノードや中間命令列を短時間のバッチ処理でアロケーションする。
現在、以下の 2 点がプロセスレベルでの実行速度を低下させている：
1. **メモリ断片化と動的ヒープ伸長（`brk` / `mmap`）オーバーヘッド**:
   - 初期ヒープが小さいため、コンパイル中にメモリ伸長システムコールが頻発し、ページフォールトおよびキャッシュラインの局所性低下を招いている。
2. **巨大アセンブリテキスト（15MB）のファイル I/O と外部ツールチェーン起動**:
   - コンパイラが巨大なアセンブリ文字列をディスクへ書き出し、外部の `as`（GNU Assembler）がそれを再パースして機械語へ変換、さらに `ld` がリンクするという 3 重のプロセス起動とテキストシリアライズ/デシリアライズが発生している。

本 Issue では、コンパイラ内部のメモリ管理および出力パイプラインを最適化する：
1. **コンパイラプロファイル時の初期アリーナヒープ一括確保（Huge Arena Reservation）**:
   - `ULISP_GC_PROFILE=compiler` 時、起動時に 512MB〜1GB のフラットアリーナを一括で事前マッピング（`mmap` / `MAP_ANONYMOUS`）し、コンパイル中のヒープ伸長・GC 停止・断片化を極小化する。
2. **ダイレクト ELF バックエンド（`backend/144_backend_x86_elf.scm`）の統合**:
   - 既存のネイティブ ELF ビルダーを活用し、アセンブリテキストを介さずメモリ内で直接 ELF オブジェクト（`.o`）または実行可能バイナリを出力する Fast-Path をブートストラップに試験導入する。

これにより、コンパイラ単体の実行時間およびツールチェーンオーバーヘッドを 30〜50% 削減する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 4 章「バックエンド・コード生成およびゼロ libc ELF ビルダー」
- 依存・関連 Issue:
  - [Issue #617](617-establish-self-contained-bootstrap-chain-free-from-external-toolchains.md): 外部ツール完全非依存な自給自足 3-Stage セルフホスティングブートストラップの確立
  - [Issue #777](777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md): 事前コンパイル済み標準ライブラリ静的リンクによるコンパイラ単体ブートストラップ

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/runtime/gc.scm](../../ulisp/runtime/gc.scm)
- [ ] [ulisp/backend/144_backend_x86_elf.scm](../../ulisp/backend/144_backend_x86_elf.scm)
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh)
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
- [ ] [docs/issues/README.md](README.md)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/779-optimize-bootstrap-heap-allocation-and-direct-elf-codegen`

1. **コンパイラ向け初期アリーナヒープサイズ環境変数（`ULISP_COMPILER_ARENA_MB`）の導入**:
   - `runtime/gc.scm` の初期化ルーチンにおいて、コンパイラ実行時は 512MB 以上の巨大アリーナを即時確保し、コンパイル中のメモリリサイズを排除。
2. **ダイレクト ELF パスの検証と接続**:
   - `backend/144_backend_x86_elf.scm` を用いた直接 `.o` 出力モード（`--emit-elf`）を検証し、`as` 起動をバイパス。
3. **ベンチマークと速度計測**:
   - 単一翻訳単位のコンパイル速度およびメモリ消費量を測定し、ボトルネック解消を確認。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `ULISP_GC_PROFILE=compiler` 実行時のヒープ伸長システムコール回数が劇的に減少し、コンパイル速度が 20% 以上向上すること。
- [ ] ダイレクト ELF 出力によって `as` 起動コストおよび 15MB のテキスト I/O が排除され、バイナリ出力が正常に動作すること。
- [ ] スモークテストおよび全回帰テストが 100% PASS すること。
- [ ] `make check` / `make verify_quality` がエラー 0 件で通過すること。

