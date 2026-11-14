---
ID: 843
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] Makefile および bootstrap.sh からの Gauche (gosh) フォールバック機構の疎結合化・純化 (ID: 843)

## 1. 概要 / Summary
現在、`ulisp/Makefile` や `ulisp/bootstrap.sh` では、ホスト環境に `gosh` が存在する場合、`RUN_SCHEME` や Stage 1 ブートストラップ実行系として Gauche を自動検出して優先的に利用する挙動となっている（例: `Makefile` の `else ifneq ($(GOSH_BIN),)` による分岐や、ルール内の `$(if $(GOSH_BIN),$(GOSH_BIN)...)` 展開）。

この自動検出により、開発者が意図しないホスト環境依存の挙動差が生じたり、セルフホストバイナリの検証がスキップされる問題が起き得る。
本 Issue では、自立型バイナリ（`bin/ulisp-boot` / 内蔵シードバイナリ）および純粋 Scheme/Python 参照系をデフォルト最優先とし、Gauche の利用は明示的なオプトイン（環境変数 `USE_GOSH=1` 等）に限定するよう疎結合化する。

---

## 2. トレーサビリティ / Traceability
- **関連仕様・ドキュメント**:
  - `ulisp/docs/spec_pipeline.md` (自立型 3-Stage セルフホスティング仕様)
  - `ulisp/docs/guide_portable_build.md` (ポータブルビルドガイド)
  - `ulisp/tests/test_pure_bootstrap.sh` (外部ツール完全スタブ化検証テスト)
- **依存関係**:
  - Issue 841, 842 の成果を基盤として、ビルドシステム全体の依存関係を純化する。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/Makefile](../../ulisp/Makefile) (行 34〜44: `GOSH_BIN` 定義と `RUN_SCHEME` 解決ロジック、行 365, 1289, 1311: `$(if $(GOSH_BIN),...)` 直書き箇所)
- [x] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (行 28, 49, 130, 260: `BOOTSTRAP_WITH_GOSH`, `GOSH_BIN` 自動検出とフォールバック処理)
- [x] [ulisp/tests/test_bootstrap_diagnostics.sh](../../ulisp/tests/test_bootstrap_diagnostics.sh) (行 16: `GOSH_BIN` 検出処理)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/843-decouple-gauche-fallbacks`

1. **`ulisp/Makefile` のリファクタリング**:
   - `RUN_SCHEME` の自動判別ロジックを変更：
     ```makefile
     # 変更前:
     ifeq ($(USE_ILISP),1)
     RUN_SCHEME = PYTHONPATH=$(ROOT_DIR) $(ILISP)
     else ifneq ($(GOSH_BIN),)
     RUN_SCHEME = $(GOSH_BIN) -ugauche.uvector -uscheme.file -I $(CURDIR) -I $(ROOT_DIR)
     else
     RUN_SCHEME = PYTHONPATH=$(ROOT_DIR) $(ILISP)
     endif

     # 変更後:
     ifeq ($(USE_GOSH),1)
     RUN_SCHEME = $(GOSH_BIN) -ugauche.uvector -uscheme.file -I $(CURDIR) -I $(ROOT_DIR)
     else
     RUN_SCHEME = PYTHONPATH=$(ROOT_DIR) $(ILISP)
     endif
     ```
   - ルール内（行 365, 1311 等）の `$(if $(GOSH_BIN),$(GOSH_BIN) -I ulisp ulisp/compiler.scm,$(RUN_SCHEME) ulisp/compiler.scm)` を、統一された `$(RUN_SCHEME) ulisp/compiler.scm` に一本化。
2. **`ulisp/bootstrap.sh` の整理**:
   - `--with-gosh` を明示指定した場合のみ Gauche を使用するようガード。
   - ネイティブ seed 失敗時の暗黙の `gosh` フォールバックは、`BOOTSTRAP_ALLOW_HOST_FALLBACK=1` などの明示フラグがない限り実行せず、自立バイナリの診断メッセージを出力して終了するよう整理。
3. **完全自立ブートストラップの検証**:
   - `ulisp/tests/test_pure_bootstrap.sh`（gcc, clang, ld, python, gosh 完全スタブ環境）を実行し、自給自足の 3-Stage 連鎖が成功することを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `Makefile` において、`gosh` がインストールされている環境でもデフォルトで Gauche を呼ばず、自立バイナリおよび `RUN_SCHEME` が正しく選択されること。
- [x] `USE_GOSH=1` を明示的に指定した場合にのみ Gauche がオプショナルに呼び出されること。
- [x] `make -C ulisp check` および `./ulisp/tests/test_pure_bootstrap.sh` が 100% PASS すること。
