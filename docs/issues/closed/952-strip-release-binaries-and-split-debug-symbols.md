---
ID: 952
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] 配布用 `ulisp-boot` / `ulisp-cc` の strip と `.debug` 分離ファイル化 (ID: 952)

## 1. 概要 / Summary

`ulisp-boot` / `ulisp-modular` / `ulisp-cc` の配布・シードバイナリにおいて、ELF の非実行（非アロケート）シンボルテーブル `.symtab` と `.strtab` がバイナリ全体容量の約 18〜19% を占有している（#951 適用後・Linux x86-64 実測値）。

| バイナリ | 全体サイズ | `.symtab` | `.strtab` | シンボル合計 (占有率) | シンボル数 (local) | strip 後の実測サイズ |
|---|---:|---:|---:|---:|---:|---:|
| `ulisp/bin/ulisp-boot` | 13,221,648 B (12.61 MB) | 1,621,608 B | 775,205 B | 2,396,813 B (18.1%) | 67,559 (59,573) | 10,824,800 B (**−2.29 MB**) |
| `ulisp/bin/ulisp-cc` | 16,621,240 B (15.85 MB) | 2,172,744 B | 982,887 B | 3,155,631 B (19.0%) | 90,520 (80,042) | 13,465,560 B (**−3.01 MB**) |

`ulisp/bin/ulisp-modular` は `stage3-modular` をそのままコピーした同一バイナリであり、`ulisp-boot` と同等の削減が得られる。

### 安全性・動作への影響

- Scheme ランタイムが実行時の `symbol->string`、エラー診断表示、`.sbi` シンボル解決に参照するセクションはアロケート対象（フラグ `A`）の `ulisp_symtab_sec`（`PROGBITS`、`ulisp-boot`: 66.4 KB / `ulisp-cc`: 81.6 KB）および `ulisp_globals_sec` であり、`strip --strip-all` の影響を受けない（事前の `objcopy` / `strip` 実機検証で保持を確認済み）。
- `ulisp/build/` 配下の中間生成物（`build/stage3-modular`、`build/ulisp-modular`、`build/scheme-stage3`）は未 strip のまま維持し、配布先である `ulisp/bin/` 配下のみ `objcopy --only-keep-debug` で `*.debug`（`ulisp-boot.debug`, `ulisp-modular.debug`, `ulisp-cc.debug`）を分離したうえで `strip --strip-all` と `objcopy --add-gnu-debuglink` を適用する。
- これにより `nm` / `objdump` / `gdb` によるデバッグ・解析能力を一切損なわずに、git 管理下のシードバイナリ（`bin/ulisp-boot`）および配布バイナリ（`bin/ulisp-cc`）のディスク容量と I/O 負荷を即座に削減できる。`.gitignore` は既に `ulisp/bin/*`（`!ulisp/bin/ulisp-boot` と `!ulisp/bin/ulisp-cogen` のみ追跡）を指定しているため、`ulisp/bin/*.debug` はリポジトリを汚さない。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](../945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）
  - [Issue #932](932-build-native-aot-ulisp-cc-compiler-driver-binary.md)（`bin/ulisp-cc` ネイティブ AOT ドライバ構築）
  - [Issue #951](951-disable-safepoint-injection-in-single-threaded-compiler-modules.md)（本施策の計測ベースラインとなった safepoint 無効化）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [Makefile](../../../ulisp/Makefile)
  - ツール変数 `OBJCOPY ?= objcopy` / `STRIP ?= strip` と共通マクロ `STRIP_WITH_DEBUG` を定義
  - `bin/ulisp-cc` リンクレシピ（L2043 付近）
  - `build/ulisp-modular` → `bin/ulisp-modular` コピーレシピ（L1965 付近）
  - `bootstrap_verify_modular` 昇格処理（L2124-2129 付近）
  - `bootstrap_verify_monolithic` 昇格処理（L1798 付近）
- [x] [bootstrap.sh](../../../ulisp/bootstrap.sh)
  - `verify_and_promote()`（L483-500 付近）の `$ULISP_DIR/bin/ulisp-modular` および `$BOOT_BIN`（`bin/ulisp-boot`）昇格時にデバッグ分離と strip を適用
- [x] [test_ulisp_cc_native.sh](../../../ulisp/tests/test_ulisp_cc_native.sh)
  - `bin/ulisp-cc` に `.symtab` が存在しないこと、`.gnu_debuglink` と `ulisp_symtab_sec` が保持されていること、`bin/ulisp-cc.debug` が生成され `nm` でシンボル参照可能であることを検証
- [x] [bin/ulisp-boot](../../../ulisp/bin/ulisp-boot)
  - `bootstrap_verify_modular` の再実行により strip 済みバイナリへ更新される git 追跡対象シードバイナリ（`bin/*.debug` は `.gitignore` で除外）

### セキュリティ・ビルド互換性観点
- 新しい外部入力や実行時コードパスは追加しない。
- `--add-gnu-debuglink` は相対ファイル名（例: `ulisp-boot.debug`）のみを埋め込むため、リポジトリや環境の絶対パスがバイナリに混入しない（`cd $(dir $(1))` でカレントを揃えて実行する）。
- macOS 等 `objcopy` / `strip` の GNU 拡張オプションがない環境への配慮として、`command -v $(OBJCOPY)` やオプション失敗時のフォールバック（または GNU binutils 前提の明示ガード）を検討し、Linux CI / ローカルで確実に動作する形にする。

---

## 4. 実装方針 / Implementation Plan

Target Branch: `perf/952-strip-release-binaries`

1. **`ulisp/Makefile` にデバッグ分離・strip マクロを追加**:
   - 先頭ツール定義部に `OBJCOPY ?= objcopy`、`STRIP ?= strip` を追加する。
   - 次のような共通マクロ `STRIP_WITH_DEBUG` を定義する（$(1) は `bin/ulisp-boot` 等のパス）。
     ```make
     define STRIP_WITH_DEBUG
     	$(OBJCOPY) --only-keep-debug $(1) $(1).debug
     	$(STRIP) --strip-all $(1)
     	(cd $(dir $(1)) && $(OBJCOPY) --add-gnu-debuglink=$(notdir $(1)).debug $(notdir $(1)))
     endef
     ```
   - `rm -f $(1).debug` を先に実行するか、再リンク時に上書きできるよう `--remove-section=.gnu_debuglink` 衝突を避けて必ず未 strip 中間体（`build/stage3-modular` 等）または `ld` 直後の出力に対して 1 回だけ適用する。
2. **各配布ターゲットへの組み込み (`ulisp/Makefile`)**:
   - `bin/ulisp-cc`: `$(LD) $(LDFLAGS) $^ -o $@` の後に `$(call STRIP_WITH_DEBUG,$@)` を実行する。
   - `build/ulisp-modular`: `cp -f $@ bin/ulisp-modular` の後に `$(call STRIP_WITH_DEBUG,bin/ulisp-modular)` を実行する（`build/ulisp-modular` 自体は未 strip のまま残す）。
   - `bootstrap_verify_modular`: `cp -f build/stage3-modular bin/ulisp-boot` および `cp -f build/stage3-modular bin/ulisp-modular` の後にそれぞれ `STRIP_WITH_DEBUG` を適用する（`build/ulisp-modular` / `build/ulisp-fast` は未 strip のまま残す）。
   - `bootstrap_verify_monolithic`: `cp -f build/scheme-stage3 bin/ulisp-boot` の後に `STRIP_WITH_DEBUG` を適用する。
3. **`ulisp/bootstrap.sh` (`verify_and_promote`) の同期**:
   - L483-500 で `$final_compiler`（未 strip の `stage3-modular` / `scheme-stage3`）を `$ULISP_DIR/bin/ulisp-modular` や `$BOOT_BIN` にコピーした後、`objcopy --only-keep-debug` / `strip --strip-all` / `objcopy --add-gnu-debuglink` を適用する（`command -v objcopy >/dev/null 2>&1` を確認）。
   - コピー元 `$final_compiler` 自体は `build/` 内に未 strip で維持する。
4. **検証テストの追加 (`ulisp/tests/test_ulisp_cc_native.sh`)**:
   - `readelf -S "$ULISP_CC"` で `.symtab` が除去され、`ulisp_symtab_sec` と `.gnu_debuglink` が存在することを確認する。
   - `test -s "${ULISP_CC}.debug"` と `nm "${ULISP_CC}.debug" | grep -q "ulisp_fn_"` を確認する。
5. **再ビルドと実測**:
   - `make -C ulisp bootstrap_verify_modular` および `make -C ulisp ulisp-cc` を実行し、`bin/ulisp-boot`（および `.debug`）・`bin/ulisp-modular`・`bin/ulisp-cc` のサイズ、セクション一覧、自己コンパイル 5 回中央値、および `test_ulisp_cc_native`（Lua 33 TU SHA-256 一致含む）を計測・検証する。
6. **品質ゲートとクローズ**:
   - `make check_format` / `make static_analysis` / `make py_compile` / `make test` および `verify-quality-gates` を全 PASS させ、計測結果を「6. 計測結果」に追記してクローズ・マージする。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `ulisp-boot` ファイルサイズが 13,221,648 B → 約 10.82 MB（**−2.2 MB 以上削減**）かつ `bin/ulisp-boot.debug` が生成される
- [x] `ulisp-cc` ファイルサイズが 16,621,240 B → 約 13.47 MB（**−3.0 MB 以上削減**）かつ `bin/ulisp-cc.debug` が生成される
- [x] `readelf -S bin/ulisp-boot` および `bin/ulisp-cc` で `.symtab` がなく、`.gnu_debuglink`・`ulisp_symtab_sec`・`ulisp_globals_sec` が保持されている
- [x] `nm bin/ulisp-boot.debug` および `nm bin/ulisp-cc.debug` で全シンボルが参照でき、`bin/ulisp-boot` による `ulisp/build/` 下の未 strip 中間体も維持される
- [x] strip 後の `bin/ulisp-boot` で `make -C ulisp bootstrap_verify_modular`（5 モジュール stage2 == stage3 SHA-256 一致）およびスモークテスト・`symbol->string` 系テストが正常動作する
- [x] `make -C ulisp test_ulisp_cc_native`（追加した strip 検証および Lua 33 TU SHA-256 パリティ検証含む）が全 PASS
- [x] `git status` 上、`bin/*.debug` が `.gitignore` により追跡対象外であること
- [x] 施策前後の計測（自己コンパイル時間中央値 5 回・ELF/`.text` サイズ・ファイルサイズ）を本 Issue「6. 計測結果」に記録する
- [x] `make format` / `make static_analysis` / `make py_compile` / `make test` が全 PASS
- [x] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）

---

## 6. 計測結果 / Measurements

ベースライン（#951 適用直後、`main` 39c14ff66、Linux x86-64）と変更後を比較。

| 指標 | 変更前 (#951後) | 変更後 | 差分 |
|---|---:|---:|---:|
| `ulisp-boot` ファイルサイズ | 13,221,648 B | 10,824,800 B | **−2,396,848 B (−2.29 MB, −18.1%)** |
| `ulisp-boot.debug` サイズ | — | 2,398,016 B | 67,559 シンボル保持 |
| `ulisp-cc` ファイルサイズ | 16,621,240 B | 13,465,560 B | **−3,155,680 B (−3.01 MB, −19.0%)** |
| `ulisp-cc.debug` サイズ | — | 3,156,840 B | 90,520 シンボル保持 |
| `ulisp-boot` `.text` | 9,247,973 B | 9,247,973 B | 0 B（コード変更なし） |
| 自己コンパイル時間（5 モジュール合計・5 回中央値） | 13.72 s | 13.91 s | +0.19 s（計測誤差 ±1.4% 範囲） |

- 自己コンパイル時間詳細（5 回交互実測）: 旧 `14.67 / 13.71 / 14.99 / 13.72 / 13.61 s`（中央値 `13.72 s`）、新 `14.14 / 15.15 / 13.91 / 13.56 / 13.69 s`（中央値 `13.91 s`）。`.symtab`/`.strtab` は非アロケート領域のため実行速度への悪化・干渉はない。
- `readelf -S`: `bin/ulisp-boot`・`bin/ulisp-cc` のいずれも `.symtab` 除去、`ulisp_symtab_sec`・`ulisp_globals_sec`・`.gnu_debuglink` 保持を確認。`build/stage3-modular` は未 strip（13,221,648 B, 67,559 シンボル）で維持。
- テスト: `make -C ulisp bootstrap_verify_modular`（5 モジュール不動点 PASS）、`make -C ulisp test_ulisp_cc_native`（Strip 検証 Section 1b・C99/musl/Lua 33 TU SHA-256 パリティ・ベンチ 9.48x/20.75x 高速化 PASS）、`make -C ulisp test_pure_bootstrap`（10/10 PASS）、`make -C ulisp test_printer`（39/39 PASS）。
