---
ID: 538
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] ゼロヒープ割当複数値返却のための R7RS 多値機構 (values / call-with-values / let-values) の実装 (ID: 538)

## 1. 概要 / Summary
コンパイラ最適化パス（例: LVN、型推論、CPS 変換）では、変換後の AST 式と新設シンボル集合、あるいは型環境など、複数の計算結果を同時に呼び出し元へ返却するパターンが多用される。
現在、複数の値を返すにはリストやペア（`cons`）をヒープに割り当てる必要があり、一時的なオブジェクトの破棄による GC 負荷とメモリアロケーションのオーバーヘッドが生じている。
本 Issue では、R7RS Section 6.10（Control features: `values`, `call-with-values`）および Section 4.2.2（Binding constructs: `let-values`, `let*-values`）に準拠した多値返却機構を実装する。
ネイティブレジスタ（RAX, RDX 等）および軽量スレッドローカル多値バッファを活用することで、ヒープ割当ゼロ（Zero-allocation）での複数値受渡しを実現する。
なお本機構は、将来の完全な第一級継続（`call/cc`, Issue #540）において継続が多値を受け取って過去フレームへ復帰するための必須プロトコル基盤（3段階継続ロードマップの【ステップ2】）となる。

---

## 2. トレーサビリティ / Traceability
- **関連規格**:
  - R7RS Section 6.10 (Control features: `values`, `call-with-values`)
  - R7RS Section 4.2.2 (Binding constructs: `let-values`, `let*-values`)
- **継続アーキテクチャ・ロードマップ**:
  - 【ステップ1（Issue #531）】: 軽量大域脱出フレームによる例外処理 (`guard` / `raise`)
  - 【ステップ2（本Issue #538）】: ゼロヒープ多値受渡し (`values` / `call-with-values`)
  - 【ステップ3（Issue #540）】: スタックコピー方式による多重複帰可能な第一級継続 (`call/cc`)
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第3章 ABI および呼出規約)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-36: 完全ベアメタル自己完結型 Freestanding 実行基盤](../designs/DSN-36-ulisp_baremetal_freestanding_pure_scheme_runtime.md)
- **関連先行・後続 Issue**:
  - Issue #531: 軽量大域脱出ハンドラスタックに基づく R7RS 例外処理機構の実装
  - Issue #540: スタックコピー方式および dynamic-wind 統合に基づく完全な第一級継続 (call/cc) の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/07_backend_x86_64.scm](../../ulisp/passes/07_backend_x86_64.scm) (多値受渡し ABI: 第1値 RAX、第2値 RDX、3個以上のスライディングスタックバッファ)
- [ ] [ulisp/passes/07_backend_aarch64.scm](../../ulisp/passes/07_backend_aarch64.scm) (AArch64 向け X0, X1 多値レジスタ規約)
- [ ] [ulisp/passes/02_desugar.scm](../../ulisp/passes/02_desugar.scm) (`let-values`, `let*-values` 構文の展開)
- [ ] [ulisp/lib/values.scm](../../ulisp/lib/values.scm) (新規作成: 多値サポートライブラリ)
- [ ] [tests/test_bare_metal_ulisp.py](../../tests/test_bare_metal_ulisp.py) (多値返却・ゼロヒープ割当検証 E2E テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/538-ulisp-r7rs-multiple-values`

1. **多値呼出規約（Multi-value ABI）**:
   - 1 値返却（通常）: RAX に値を格納、多値フラグは 0。
   - 2 値返却: RAX に第1値、RDX に第2値、多値カウントレジスタ（R10=2）。
   - 3 値以上返却: RAX, RDX に加え、BSS 上の固定長スレッドローカル多値バッファ（`ulisp_value_buffer[64]`）に第3値以降を格納。
2. **`call-with-values` のネイティブ最適化**:
   - `(call-with-values (lambda () (values a b)) (lambda (x y) ...))` がローカルに閉起している場合、インライン展開してレジスタ間直接代入（ヒープ割当ゼロ）に最適化。
3. **`let-values` / `let*-values` の構文糖展開**:
   - 多値バインディング構文を `call-with-values` 形式へ自然に脱糖。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(call-with-values (lambda () (values 10 20)) (lambda (x y) (+ x y)))` が `30` を返すこと。
- [ ] `(let-values (((a b) (values 3 4))) (* a b))` が `12` を返すこと。
- [ ] `values` による 2 値返却ループがヒープメモリ消費量 0 バイト（GC 発生ゼロ）で動作すること。
- [ ] 自己ホスティング固定点ブートストラップが完全一致でパスすること。
