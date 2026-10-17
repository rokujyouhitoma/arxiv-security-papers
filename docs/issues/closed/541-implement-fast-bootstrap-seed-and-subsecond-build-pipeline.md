---
ID: 541
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] ブートストラップシード (bin/ulisp-boot) 導入による ULisp 開発サイクル「即時0.3秒化」および高速ビルドパイプラインの構築 (ID: 541)

## 1. 概要 / Summary
現在、ULisp のセルフホスティングコンパイラ（`compiler.scm` + `lib/*.scm`）の規模拡大に伴い、初期ビルド（Stage 1 生成）時に Python 製の純粋インタプリタである ILisp (`python3 -m ilisp`) を経由することで、膨大な AST 探索と Nanopass パイプラインのオーバーヘッドにより数分以上の待ち時間や中断（`KeyboardInterrupt`）が発生し、日々の機能開発・テストの重大なボトルネックとなっている。

本 Issue では、すでに正常に不動点（Fixed Point）を達成している自己完結型ネイティブバイナリを、公式ブートストラップシード **`ulisp/bin/ulisp-boot`** として配備・固定化し、`bootstrap.sh`、`Makefile`、`test.sh` をシードバイナリ駆動の Fast Bootstrap パイプラインへと再構築する。
これにより、開発時のコンパイル時間を数分から **約 0.3 秒（1秒未満）** へと劇的に短縮し、将来的な処理系リポジトリ分離に向けた外部依存ゼロの自己完結型ビルド基盤を確立する。

---

## 2. トレーサビリティ / Traceability
- [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 5 章「3段階セルフホスティングブートストラップ連鎖と不動点検証」
- [DSN-31 (ILisp 包括設計仕様書)](../designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) 第 3.2 節「Backend B: Native C99 AOT コンパイラ」
- GCC / Chez Scheme / RPython ブートストラップシード方式アーキテクチャ規約

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/bin/ulisp-boot](../ulisp/bin/ulisp-boot) (ローカルキャッシュ配備: 外部依存ゼロのネイティブコンパイラシード)
- [x] [ulisp/bootstrap.sh](../ulisp/bootstrap.sh) (シード駆動 Fast Bootstrap ディスパッチおよび完全検証フラグ追加)
- [x] [ulisp/Makefile](../ulisp/Makefile) (コンパイル・テストターゲットのネイティブバイナリ直結化)
- [x] [ulisp/test.sh](../ulisp/test.sh) (シードバイナリ優先・高速テストパイプライン整備)
- [x] [docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (Fast Bootstrap プロトコルの仕様追記)
- [x] [docs/issues/README.md](README.md) (Issue 台帳登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/541-fast-bootstrap-seed`

1. **シードバイナリ `bin/ulisp-boot` の配備と動作検証**:
   - `build/scheme-stage2` の不動点整合性を確認し、`ulisp/bin/ulisp-boot` としてコピー配置して実行権限を付与。
   - `echo 42 | ./ulisp/bin/ulisp-boot` 等のスモークテストを実施。
2. **`bootstrap.sh` のスマート高速化**:
   - デフォルト動作として `ulisp/bin/ulisp-boot` が存在する場合は Python (ILisp) をスキップし、シードバイナリで `stage1.s` を生成。
   - `FULL_BOOTSTRAP=1` または `BOOTSTRAP_FROM_ILISP=1` 指定時のみ、Python/ILisp を介するフル検証モードを起動する後方互換性を保持。
3. **`Makefile` および `test.sh` のネイティブ直結化**:
   - `make stage1` が `bin/ulisp-boot` 経由で 0.3 秒で完了するように改修。
   - テストランナー群もネイティブバイナリを優先活用するように整備。
4. **仕様書および台帳の更新**:
   - DSN-33 にシードバイナリ駆動プロトコルおよびリポジトリ独立境界を明記。
   - `make verify_quality` / `make py_compile` をパスさせる。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/bin/ulisp-boot` が外部依存ゼロ（`gcc -nostdlib -static`）で配備され、実行可能であること
- [x] `./bootstrap.sh` が通常実行時に ILisp をスキップし、1 秒未満（目標 0.3 秒、全3段階15秒）で Stage 1/Stage 2/Stage 3 の不動点検証（`diff stage2.s stage3.s` ゼロ）を PASS すること
- [x] `FULL_BOOTSTRAP=1 ./bootstrap.sh` により、従来の ILisp 経由フルブートストラップも選択実行可能であること
- [x] `make test` が高速に完走すること
- [x] `make py_compile` および `make static_analysis` がエラーゼロで通過すること
