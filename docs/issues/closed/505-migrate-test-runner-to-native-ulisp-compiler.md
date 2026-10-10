---
ID: 505
種別: Feature
優先度: High
ステータス: Closed (Done)
---

# [FEAT] Migrate ULisp Test Runner (test.sh) to Native Compiler Execution (ID: 505)

## 1. 概要 / Summary
現在、`ulisp/test.sh` ではテストケースごとに Python 実装の ILisp を起動して `compiler.scm` をツリー走査評価（`$ILISP "$COMPILER" <<< "$full_input"`）しているため、80 件を超えるテストスイートの全件実行に約 80 秒以上の時間を要している。

先行 Issue #502 において Low-Level IR (LIR) の導入および 3 段階セルフホスティングブートストラップの完全不動点（`diff stage2.s stage3.s == 0`）が実証されたことを受け、`test.sh` のコード生成エンジンを Python 版 ILisp から **ネイティブコンパイル済み ULisp バイナリ（`build/scheme-stage1`）** へと移行する。

これにより、テスト実行時間を 80 秒超から **1 秒未満（ミリ秒単位の超高速実行）** へと劇的に短縮し、日常のテスト駆動開発サイクルおよび「セルフホスティングされたバイナリが正しく動作すること」の常時検証を実現する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §6.1 (セルフホスティングパイプラインとブートストラップ検証), §6.2 (ビルドシステムとテスト自動化)
- **DSN-31**: §3.2 (Backend B: ULisp AOT Native Backend)
- **先行 Issue**: #493 (ULisp Phase 7 セルフホスティングブートストラップ), #502 (LIR 導入とバックエンド分離)
- **関連ドキュメント**: [ulisp/docs/testing_guide.md](../../ulisp/docs/testing_guide.md)

---

## 3. セキュリティ & 脅威分析 / Security Analysis & Threat Model
1. **未定義末尾出力混入・アセンブラ構文汚染 (Trailing Return Value Injection)**:
   - ULisp ランタイム（`runtime.c`）は非 quiet モード時、`scheme_entry` の返り値（非同期シンボルや NIL 等）を標準出力にプリントする。stdin 経由でアセンブリを出力させる際、末尾にガベージ文字列が混入すると GAS アセンブラが構文エラーとなる。
   - **対策**: `test.sh` において `export ULISP_QUIET=1` を強制し、C ランタイムの評価返り値出力を完全抑制して純粋な GAS アセンブリのみを安全にリダイレクトする。
2. **スタック・ヒープ競合および一時ファイル衝突 (Temporary File Collision)**:
   - 並列テスト実行や連続実行時、同一の一時アセンブリファイル（`tmp.s`）や実行ファイル（`tmp_bin`）への書き込み競合による意図しないバイナリ汚染。
   - **対策**: プロセス単位のトラップハンドラ（`trap cleanup EXIT`）を厳格維持し、安全なパイプラインを保証。
3. **ブートストラップ循環依存・環境非互換性破壊 (Architecture / Environment Incompatibility)**:
   - x86-64 以外のアーキテクチャ（ARM64 や macOS など）や実行バイナリ実行制限環境、またはクリーンな初回実行環境においてネイティブバイナリが動作しない場合、テストスイート全体が不当にクラッシュする脅威。
   - **対策**: スモークテスト（`echo "42" | ULISP_QUIET=1 "$ULISP_STAGE1"`）による動的実行可能性検証を行い、実行不能時や `FORCE_ILISP=1` 指定時は自動的かつ安全に Python 版 ILisp（`python3 -m ilisp`）へフォールバックする高耐障害性ランナーアーキテクチャを導入。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh): ネイティブバイナリ実行への切り替え、動的スモークテスト判定、および ILisp 自動フォールバックの実装
- [x] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile): `test` ターゲットでの `scheme-stage1` ビルド依存関係の整備
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の同期

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/505-migrate-test-runner-to-native-ulisp-compiler`

1. **前提コンパイラバイナリの自動準備**:
   - `test.sh` 実行時、`build/scheme-stage1` が未ビルドの場合は初回のみステージ1ビルドを自動実行。
   - `Makefile` に `build/scheme-stage1` ターゲットを追加し、`make test` の前提条件に組み込む。
2. **動的実行可能性判定と自動フォールバック機構**:
   - スモークテスト実行:
     ```bash
     if [ -x "$ULISP_STAGE1" ] && echo "42" | ULISP_QUIET=1 "$ULISP_STAGE1" >/dev/null 2>&1; then
         USE_NATIVE_ULISP=true
     else
         USE_NATIVE_ULISP=false
     fi
     ```
   - `USE_NATIVE_ULISP=true` の場合:
     ネイティブコンパイラ `"$ULISP_STAGE1"` を直接起動し超高速実行（< 1s）。
   - `USE_NATIVE_ULISP=false`（または `FORCE_ILISP=1`）の場合:
     Python 版 ILisp（`$ILISP "$COMPILER"`）へ透過的にフォールバック。
3. **テストアサーションのコンパイラ呼び出し部切り替え**:
   - `test.sh` 内の `assert` および `assert_stdin` 関数で共通コンパイラディスパッチャを使用。
4. **ベンチマークと互換性検証**:
   - 全 80+ 件のテストケースが 100% 同一の結果を出力することを確認。
   - ネイティブ実行時の所要時間を計測（1 秒未満）。
   - フォールバックモード（`FORCE_ILISP=1`）でも全件正常合格することを検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/test.sh` が利用可能な環境でネイティブコンパイラバイナリ（`scheme-stage1`）を用いて超高速テスト実行（数秒以内）すること。
- [x] `build/scheme-stage1` が未存在の場合でも自動的にビルドされ、初学者やクリーン環境でも `./test.sh` が単独で正常実行できること。
- [x] ネイティブバイナリ非対応環境や `FORCE_ILISP=1` の場合、自動的・安全に Python 版 ILisp へフォールバックし、テストが継続実行されること。
- [x] ネイティブモードおよびフォールバックモードの双方で、全 80+ 件のテストケースが 100% PASS すること。
- [x] `make test` およびブートストラップ検証が正常に完遂すること。
- [x] `make check_format` & `make py_compile` をパスすること。
