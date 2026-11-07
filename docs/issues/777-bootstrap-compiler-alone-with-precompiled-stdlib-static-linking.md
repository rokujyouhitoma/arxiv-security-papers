---
ID: 777
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] 事前コンパイル済み標準ライブラリ (ulisp_stdlib.o) 静的リンクによるコンパイラ単体ブートストラップの導入 (ID: 777)

## 1. 概要 / Summary

現在、[ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) は `entry_core.scm` 経由で標準ライブラリ（`lib/*.scm` 全28モジュール）とランタイム（`runtime/*.scm` 全4モジュール）をコンパイラ本体と一緒に全結合した巨大ファイル `ulisp_core.scm`（約25,000行）を、Stage 1 / Stage 2 / Stage 3 で毎回フルコンパイルしている。
しかし、標準ライブラリおよびランタイムはコンパイラのメタサーキュラーな自己変換ロジックを含んでおらず、本来セルフホスティングの不動点（Fixed Point）証明の対象とする必要はない。

先行する [Issue #772](closed/772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md) では、標準ライブラリを1回だけ事前コンパイルしたオブジェクト（`build/ulisp_stdlib.o`）を静的リンクする方式により、テストスイートのコンパイル時間を 50〜100 倍（0.1s）に短縮した実績がある。また、[Issue #780](closed/780-optimize-symbol-to-string-with-direct-cache-and-bucket-lookup.md) によりシンボル探索の $O(N^2)$ ボトルネックが完全解消され、2分割静的リンクバイナリ（`build/ulisp-fast`）の検証スイート `test_split_link` は 2 秒で完走する基盤が整っている。

本 Issue では、この分割静的リンク基盤をブートストラップパイプラインへ適用する：
1. **ブートストラップ対象の極小化**:
   - `ulisp_core.scm` の全結合コンパイルを廃止（または opt-in フォールバック化）し、ブートストラップ対象を **`compiler_entry.scm`（コンパイラ本体）のみ** に絞る。
2. **事前コンパイル済み標準ライブラリとの静的結合**:
   - 事前ビルドされた `build/ulisp_stdlib.o` と生成された `stage_compiler.o` を `ld` で静的リンクして各ステージの実行可能バイナリ（`scheme-stage1`, `scheme-stage2`, `scheme-stage3`）を生成する。
3. **コンパイラ単体での不動点検証（Fixed Point Protocol）**:
   - 不動点検証を `stage2_compiler.s` と `stage3_compiler.s` の完全ビット一致（`cmp -s`）判定へ移行する。

これにより、各ステージの入力 S 式規模および出力アセンブリ（15MB $\to$ 12MB）が大幅にスリム化され、各ステージのコンパイル時間が短縮。3-Stage 全体でも **大幅な時間短縮（従来比 3〜5 倍高速化）** が達成される。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 5 章「3段階セルフホスティングブートストラップ連鎖と不動点検証」
- 依存・関連 Issue:
  - [Issue #607](closed/607-support-extern-symbols-and-split-stdlib-compiler-linking.md): 外部シンボル（extern）参照解決と標準ライブラリ・コンパイラの2分割 .o 静的リンク基盤の導入
  - [Issue #772](closed/772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md): ULisp 標準ライブラリの事前コンパイル済みオブジェクト化と分割静的リンクへの統一
  - [Issue #776](776-introduce-quick-bootstrap-mode-and-opt-in-post-tests.md): Quick Bootstrap モード導入
  - [Issue #780](closed/780-optimize-symbol-to-string-with-direct-cache-and-bucket-lookup.md): シンボル探索の $O(N^2)$ 解消（ダイレクトマップキャッシュ & バケット探索）
  - [Issue #781](closed/781-implement-record-based-symbols-with-direct-string-pointer.md): Tagged Immediate シンボルアーキテクチャの妥当性証明と確定

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (ブートストラップドライバスクリプト)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (分割ビルドルールと依存関係)
- [x] [ulisp/compiler_entry.scm](../../ulisp/compiler_entry.scm) (コンパイラ単体エントリ)
- [x] [ulisp/stdlib_entry.scm](../../ulisp/stdlib_entry.scm) (標準ライブラリエントリ)
- [x] [docs/issues/README.md](README.md) (Issue 台帳)

---

## 4. セキュリティ・信頼性脅威分析 / Threat Model & Boundary Analysis

1. **ABI ドリフト（ABI Drift & Calling Convention Mismatch）**:
   - *脅威*: コンパイラの内部表現（タグビット、レジスタ割付、クロージャレイアウト）に変更が入った際、古い `ulisp_stdlib.o` を静的リンクすると実行時セグメンテーション違反や未定義動作を引き起こす。
   - *対策*: `bootstrap.sh` 起動時に `build/ulisp_stdlib.o` のタイムスタンプを検証し、`stdlib_entry.scm` や `lib/*.scm`, `runtime/*.scm` が更新されている場合は必ず自動で `ulisp_stdlib.o` を再ビルドする依存性強制メカニズムを組み込む。
2. **外部シンボル解決の不整合（Unresolved External Symbols）**:
   - *脅威*: `compiler_entry.scm` が必要とするライブラリ関数が `stdlib_entry.scm` に含まれていない場合、リンク時エラー（`undefined reference`）となる。
   - *対策*: GNU `ld` の静的リンク（`-static -m elf_x86_64`）時に未解決シンボルを即座に検知し、リンクエラーログを `as_ld_err.log` 経由で捕捉・報告する。
3. **不動点決定論の保証（Fixed Point Determinism）**:
   - *脅威*: 分割静的リンクにおいて、シンボルアドレスや `.rodata` アライメントの違いがアセンブリ出力の非決定性を生むリスク。
   - *対策*: 比較対象をアセンブリテキスト（`stage2_compiler.s` vs `stage3_compiler.s`）に限定し、機械語アドレスの絶対値ではなくコンパイラが生成する IR/アセンブリ命令列の完全一致（`cmp -s`）で検証する。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking`

### Step 1: `build/compiler_input.scm` の自動生成と Makefile 連携
- `ulisp/Makefile` の `build/ulisp_stdlib.o` ターゲットを安定化し、ブートストラップ実行前に `make -C "$ULISP_DIR" build/ulisp_stdlib.o` を確実に実行する。
- `build/compiler_input.scm` を以下のディレクティブで構成：
  ```scheme
  (!gc none) (!allow-extern #t)
  (include "compiler_entry.scm")
  ```

### Step 2: `ulisp/bootstrap.sh` の CLI オプションとデフォルト動作の更新
- デフォルトを「分割静的リンクモード（`BOOTSTRAP_SPLIT_LINK=1`）」とし、レガシー全結合テストが必要な場合のために `--monolithic` オプションを追加：
  ```bash
  --split-link    # 事前コンパイル済み ulisp_stdlib.o と静的リンクする高速ブートストラップ (デフォルト)
  --monolithic    # 従来の全結合 ulisp_core.scm による 3-Stage フルビルド
  ```

### Step 3: ステージ実行および `compile_asm` の分割リンク対応
- `compile_asm` 関数を修正し、`BOOTSTRAP_SPLIT_LINK=1` 時は `ld` 呼び出しに `"$BUILD_DIR/ulisp_stdlib.o"` を追加：
  ```bash
  if [ "${BOOTSTRAP_SPLIT_LINK:-1}" = "1" ]; then
      ld -m elf_x86_64 -static "$obj_file" "$BUILD_DIR/ulisp_stdlib.o" -o "$bin_file"
  else
      ld -m elf_x86_64 -static "$obj_file" -o "$bin_file"
  fi
  ```
- 各ステージの入力を `"$BUILD_DIR/compiler_input.scm"`、出力アセンブリを `"$BUILD_DIR/stage${stage_num}_compiler.s"` とする。

### Step 4: 不動点検証およびプロモーション
- `diff` 比較対象を `stage2_compiler.s` と `stage3_compiler.s` に切り替え：
  ```bash
  if cmp -s "$BUILD_DIR/stage2_compiler.s" "$BUILD_DIR/stage3_compiler.s"; then
      echo "SUCCESS: Stage 2 and Stage 3 compiler outputs are bit-for-bit IDENTICAL!"
      verify_and_promote "$BUILD_DIR/scheme-stage3" "Stage 3"
  fi
  ```
- `verify_and_promote` では `scheme-stage3`（静的実行可能バイナリ）の `42` スモークテストを実施後、`bin/ulisp-boot` へプロモート。

### Step 5: テストスイートと品質ゲートの検証
- `make -C ulisp test_split_link`
- `./ulisp/bootstrap.sh --quick`
- `./ulisp/bootstrap.sh` (フル 3-Stage)
- `make check_format static_analysis py_compile`

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `build/ulisp_stdlib.o` と静的リンクしたコンパイラバイナリ（`scheme-stage1`, `scheme-stage2`, `scheme-stage3`）が正常にビルド・リンクされること。
- [ ] スモークテスト（`42`）が正常に通過すること。
- [ ] 3-Stage ブートストラップが完走し、`stage2_compiler.s` と `stage3_compiler.s` のビット完全一致（Bit-for-bit identical）が PASS すること。
- [ ] `--quick` オプション実行時に Stage 1 完了時点でスモークテストを通過し即座に終了すること。
- [ ] `--monolithic` オプション指定時に従来のモノリシックブートストラップが互換性を持って動作すること。
- [ ] `make -C ulisp test_split_link` および `make check_format static_analysis py_compile` が 0 エラーで通過すること。
