---
ID: 906
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] Verify Freestanding Static -nostdlib ELF E2E Execution (ID: 906)

## 1. 概要 / Summary

[[DSN-33-07]](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md) 第 5 章に基づき、ULisp AOT コンパイラが `-nostdlib -static` フラグのみで出力した完全自立型静的 ELF64 バイナリの E2E 実行可能性を包括検証し、動的リンカ（`ld-linux.so`）や C 言語ランタイム（`runtime.c` / libc）が一切存在しない極小・Scratch 環境（ベアメタル、Unikernel、セキュアコンテナ）における自給自足・自立走行を保証する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-07] ULisp Zero-libc / Freestanding Pure Scheme ベアメタルランタイム包括設計書 (第5章 検証とテスト)](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md)
  - [[DSN-33] ULISP 包括設計仕様書 (第2章 ハードウェア・ABI 整合)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [[DSN-33-06] ILisp・ULisp AOT・ULisp JIT 3種実行系 継続的性能評価基盤 設計仕様書](../designs/DSN-33-06-ulisp_ilisp_aot_jit_continuous_benchmarking_framework.md)
- 先行 Issue:
  - [Issue #905: ベアメタル自立型 Demand-Paged BSS バンプアロケータおよび Zero-libc 2-Space GC の実装](closed/905-implement-freestanding-demand-paged-bss-bump-allocator-and-gc.md)
  - [Issue #904: 外部 C ランタイム完全排除と Pure Scheme _start エントリポイント・Raw Syscall 直結](closed/904-eliminate-external-c-runtime-and-establish-pure-scheme-start-entry.md)
  - [Issue #903: 統計的性能退行（Regression Detector）自動検知器および日本語ベンチマークレポート自動生成](closed/903-implement-performance-regression-detector-and-automated-markdown-reporting.md)

---

## 3. STRIDE 脅威分析とセキュリティ対策 / STRIDE Threat Modeling

| 脅威分類 (STRIDE) | 脅威シナリオ | 影響度 | 対策・緩和策 (Mitigation) |
|---|---|---|---|
| **Spoofing (なりすまし)** | 動的リンカや共有ライブラリの乗っ取り・DLLハイジャック | High | 静的バイナリから `PT_INTERP`（動的リンカパス）および `PT_DYNAMIC`（動的セクション）を完全に排除し、外部共有ライブラリのロード経路自体を物理的に根絶。 |
| **Tampering (改ざん)** | 実行時の未認可共有ライブラリ注入（`LD_PRELOAD` / `LD_LIBRARY_PATH`） | Critical | 動的シンボル解決機構を一切含まない純粋な静的 ELF64 としてリンクし、動的リンカによる外部ライブラリ差し替え攻撃を無効化。 |
| **Repudiation (否認)** | 異常終了時のカーネル終了ステータスの不整合・追跡不能 | Medium | Linux Raw Syscall `sys-exit (60)` を Pure Scheme エントリから直接呼び出し、プロセス終了コードを確実にカーネルへ伝達。 |
| **Information Disclosure (情報漏洩)** | 動的シンボルテーブルやデバッグ情報による内部レイアウト露出 | Low | ストリップ（`strip`）または不要シンボル除外により、バイナリフットプリントを最小化し、不要なメタデータ漏洩を防止。 |
| **Denial of Service (サービス妨害)** | libc の巨大な初期化オーバーヘッドによる起動遅延・DoS | Medium | `_start` から `scheme_entry` へのダイレクトジャンプにより、C ランタイムスタートアップコード（`crt1.o` 等）を排除し、サブミリ秒の即時起動を保証。 |
| **Elevation of Privilege (権限昇格)** | libc 内部の脆弱性（バッファオーバーフロー、フォーマット文字列バグ等）の悪用 | Critical | Zero-libc アーキテクチャにより libc コードをバイナリ内に 1 バイトも含まないため、libc 起因の既知および未知の脆弱性を根本的に排除。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- `ulisp/Makefile`:
  - `build/ulisp-baremetal` ビルドターゲットおよび `test_freestanding_e2e` テストターゲットの追加。
- `ulisp/tests/test_freestanding_e2e.sh`:
  - シェルレベルでの E2E 検証スクリプト。`-nostdlib -static` ビルド、`ldd` / `readelf` 依存検査、実行出力検証を一括実行。
- `tests/test_bare_metal_ulisp.py`:
  - `test_bare_metal_freestanding_e2e_suite` を追加し、pytest スイートでの継続的検証を統合。

---

## 5. 実装方針と詳細手順 / Implementation Plan

Target Branch: `feat/906-verify-freestanding-static-nostdlib-elf-e2e-execution`

### 5.1 E2E 検証スクリプト作成 (`ulisp/tests/test_freestanding_e2e.sh`)
1. 入力プログラムとして、四則演算・文字列フォーマット・動的メモリ確保（BSS ヒープ）・Cheney GC・正常終了（exit code 0）を含む包括的な Pure Scheme テストプログラムを準備。
2. `ulisp/compiler.scm` で x86-64 アセンブリを出力。
3. `as --64` および `ld -m elf_x86_64 -static`（または `gcc -nostdlib -static`）でリンク。
4. 静的解析チェック：
   - `ldd <binary>` が `not a dynamic executable` を返すこと。
   - `readelf -l <binary> | grep INTERP` が空（0 件）であること。
   - `readelf -d <binary> | grep NEEDED` が空（0 件）であること。
   - バイナリサイズが 64KB 以内であることを確認。
5. 実行チェック：
   - バイナリを直接実行し、終了ステータス 0 および期待出力を確認。

### 5.2 Python 側 pytest テスト統合 (`tests/test_bare_metal_ulisp.py`)
1. `test_bare_metal_freestanding_e2e_suite` を追加。
2. `subprocess.run` を用いて、`ulisp/tests/test_freestanding_e2e.sh` の実行または同等の E2E パイプラインを自動検証。

### 5.3 Makefile ターゲット追加 (`ulisp/Makefile`)
1. `test_freestanding_e2e` ターゲットを追加し、`make -C ulisp test_freestanding_e2e` で即時検証可能にする。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `ldd` 実行結果が「not a dynamic executable」となり、外部共有ライブラリ依存が 0 件であること。
- [x] `readelf -l` において `INTERP` プログラムヘッダが完全に存在しないこと。
- [x] `readelf -d` において動的依存ライブラリ（`NEEDED`）が 0 件であること。
- [x] 外部 libc を一切介さず、Pure Scheme `_start` および Raw Syscall 経由で正常終了（exit code 0）すること。
- [x] `ulisp/tests/test_freestanding_e2e.sh` が作成され、全検証ステップが PASS すること。
- [x] `make -C ulisp test_freestanding_e2e` が PASS すること。
- [x] `pytest tests/test_bare_metal_ulisp.py` が 100% PASS すること。
- [x] `make py_compile && make static_analysis` がエラー 0 件で合格すること。

---

## 7. 検証手順 / Verification Steps

```bash
# 1. シェルスクリプトによる E2E 検証
bash ulisp/tests/test_freestanding_e2e.sh

# 2. Makefile 経由の E2E 検証
make -C ulisp test_freestanding_e2e

# 3. pytest によるベアメタル回帰検証
pytest -v tests/test_bare_metal_ulisp.py

# 4. 静的解析とコンパイル検証
make py_compile && make static_analysis
```

