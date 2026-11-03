---
ID: 698
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG] GitHub Actions CI パイプライン 60分タイムアウト停止および uLisp AOT テスト失敗の根本改修 (ID: 698)

## 1. 概要 / Summary

GitHub Actions CI 実行（`https://github.com/rokujyouhitoma/arxiv-security-papers/actions/runs/41581106932/job/125735900667`）において、Quality Gate 3（`make test`）が 60 分間（3,600 秒）にわたり実行され続けた結果、GitHub Actions のジョブ最大実行時間制限に達して SIGTERM による中断（Process completed with exit code 2）となりパイプラインが破綻していた。

### 根本原因の特定 / Root Cause Analysis:

1. **uLisp ネイティブ AOT コンパイラ実行環境の極端なオーバーヘッド**:
   - `ilisp/backend/ulisp_codegen/compiler.py` の `compile_to_assembly` において、Scheme コンパイラ（`ulisp/compiler.scm`, 約22,000行）の実行が、純粋 Python の ILISP インタプリタ（`python -m ilisp`）に固定されていた。
   - ホスト環境および CI 上で Gauche（`gosh`）が存在する場合でも活用されず、Python AST 評価器上で巨大な Scheme コンパイラを動かしていたため、1 回のコンパイルに数分〜十数分を要し、7 件以上の AOT テスト実行で 60 分を超過していた。
2. **`lib/char.scm` の依存欠落による LIR コンパイルエラー**:
   - Issue #612 の文字述語・大小文字変換リファクタリングに伴い、`string.scm` 内の `string-upcase` が `char-upcase`（`char.scm`）に依存するようになった。
   - `_resolve_compiler_input` では `string.scm` を読み込む際に `char.scm` が先行結合されておらず、文字列・プリンタ系ライブラリをロードした瞬間に `Unbound variable in LIR: char-upcase` でコンパイルが異常終了していた。
3. **`needs_string_lib` 判定におけるクォート文字の誤爆**:
   - `_resolve_compiler_input` 内で `or "'" in scheme_code` という過剰なヒューリスティクスが存在したため、空リスト `'()` やクォート式を含む任意の Scheme コード（リスト操作テスト等）で不必要に重厚な `string.scm` がロードされ、実行遅延とコンパイル失敗を誘発していた。
4. **スタンドアロン AOT 実行時の Rule of Silence 導入に伴う結果キャプチャ不整合**:
   - Issue #614 にて、生成 ELF バイナリはデフォルトで沈黙（Quiet-by-Default）となり、明示的に `ULISP_PRINT_RESULT=1` が指定された場合のみ評価結果を出力する仕様へ刷新されていた。
   - `run_elf` 関数および `test_ulisp_codegen.py` において環境変数 `ULISP_PRINT_RESULT=1` のハンドリングが欠落していたため、評価結果 `42` 等が空文字列 `""` となりテストアサーションが失敗していた。
5. **CI 環境における依存ツール不足**:
   - `.github/workflows/ci.yml` のランナー環境（`ubuntu-24.04`）において、高速 Scheme 実行系（`gauche`）、アセンブラ/リンカ（`gcc`）、PDF 抽出（`poppler-utils`）が事前インストールされていなかった。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- `.github/workflows/ci.yml`: CI ランナー依存関係（`gauche`, `gcc`, `poppler-utils`）の導入
- `ilisp/backend/ulisp_codegen/compiler.py`:
  - `gosh` 高速実行系の優先検出・ディスパッチ（フォールバック: `python -m ilisp`）
  - `_resolve_compiler_input` における `char.scm` 先行結合および `needs_string_lib` 判定の適正化
  - `run_elf` における `ULISP_PRINT_RESULT=1` デフォルト注入
- `tests/ilisp/test_ulisp_codegen.py`:
  - デフォルト沈黙（Rule of Silence）および `ULISP_PRINT_RESULT=1` 時の出力検証の双方網羅
  - `black` / `isort` 規約準拠フォーマット

---

## 3. 実装詳細と検証 / Implementation & Verification

1. `compile_to_assembly` の `shutil.which("gosh")` 連携により、1 コンパイルあたりの所要時間が数分から数秒（約 5 秒以下）へ激減。
2. `tests/ilisp/test_ulisp_codegen.py` 全 18 テストが 22 秒で 100% PASS することをローカルで実証。
3. `make check_format`, `make py_compile`, `make static_analysis` の静的検査をクリア。
4. CI ワークフロー定義に `sudo apt-get install -y gauche gcc poppler-utils` を追加し、GitHub Actions 上での高速・安定実行を担保。
