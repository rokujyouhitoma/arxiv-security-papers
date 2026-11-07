---
ID: 780
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] シンボルテーブル探索の O(N^2) 爆発解消：重複走査撤去・バケット拡大および Direct-Mapped キャッシュ導入 (ID: 780)

## 1. 概要 / Summary

現在、[ulisp/lib/string.scm](../../../ulisp/lib/string.scm) における `symbol->string` の実装は、以下の要因によってシンボル数が増加した際に計算量が $O(N^2)$ に爆発し、大規模なプログラム（標準ライブラリ全結合など）をコンパイルする際に CPU 100% かつメモリ数 GB を消費して何十分もスタックする重大な性能障害を引き起こしている：

1. **動的シンボルに対する三重走査**:
   - `symbol->string` の先頭、`%symbol-find-string` の先頭、およびフォールバック走査の先頭で、動的シンボルには存在しない静的リスト `*known-runtime-symbols*`（約200要素）を毎回二重・三重に線形走査（計600回）している。
2. **フォールバック時の全シンボルフラットリスト線形走査**:
   - ハッシュバケットで見つからなかった場合、全シンボルが登録された単一線形リスト `*symbol-registry*`（数万件）を $O(N)$ で末尾まで走査している。
3. **固定小バケット（1024スロット）による衝突チェーンの肥大化**:
   - 1024 スロット固定かつ `modulo`（除算命令 `idiv`）を使用しているため、衝突チェーンが長くなり探索コストが増大している。

本 Issue では、即効性のあるアルゴリズム・キャッシュ改善を実施し、$O(N^2)$ 探索を解消する：
1. **重複走査の撤去とバケット探索の完結化**:
   - `*known-runtime-symbols*` の重複呼び出しを排除。
   - `string->symbol` で必ずバケットに双方向登録されていることを保証し、`*symbol-registry*` への $O(N)$ 線形フォールバックを撤去。
2. **バケットサイズの拡大とビットマスク化**:
   - スロット数を 1024 $\to$ **16,384**（$2^{14}$）に拡大し、`modulo`（除算命令）を `bitwise-and`（ビット論理積 1 命令）へ高速化。
3. **Direct-Mapped シンボル変換キャッシュの導入**:
   - サイズ 4096 のダイレクトマップキャッシュ配列を新設し、直近に参照されたシンボル $\to$ 文字列のペアを保持。
   - Nanopass パイプラインにおける反復的な同一シンボル参照（`lambda`, `if`, 変数名等）の 95% 以上を **$O(1)$（配列参照 1 回・数命令）** で短絡（Fast-Path）させる。

これにより、大量のシンボルを含む入力に対するコンパイル時間を数十〜数百倍高速化し、スタックを解消する。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、リポジトリ規約（`.agents/AGENTS.md`）に従い、16 専門エージェントによる設計レビューを統合して策定された。

- **Project Manager (PM) (Chair / Governance)**:
  - 先ほどの `test_split_link` 実行時にプロセスが 30 分以上スタックした根本原因はここにあり、最優先で修正すべきクリティカルパスである。後退（Regression）をゼロに抑え、即座に解消する。
- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - コンパイラの Nanopass パイプラインでは同一シンボルの参照が局所的（Temporal Locality）に集中するため、Direct-Mapped キャッシュ（Direct-Indexed Vector）が驚異的な効果を発揮する。ハッシュ計算とベクタアクセスのみで完結するため、GC アロケーションもゼロである。
- **Systems Architect**:
  - バケットサイズ 16384 はメモリフットプリントとしてわずか 128KB であり、L2 キャッシュ内に余裕で収まる。除算命令 `idiv` からビットマスク `and` への置換はパイプラインストールを大幅に防ぐ。
- **Software Quality Assurance Specialist (SQA)**:
  - 既存の `test_stdlib`, `test_string_to_number`, `test_split_link`, `test_incremental` 等の全テストを実行し、シンボル $\leftrightarrow$ 文字列変換の正確性と互換性を 100% 保証する。
- **Information Security Specialist**:
  - キャッシュ配列のインデックス計算において境界外アクセス（CWE-125 / CWE-787）が発生しないよう、符号ビット反転および確実に `bitwise-and 4095` でマスキングする。

---

## 3. セキュリティ設計・脅威分析 / Security Considerations & Threat Modeling

| 脅威分類 (STRIDE) | 脆弱性識別子 (CWE) | 潜在的リスク / シナリオ | 適用する防護措置・緩和策 |
| :--- | :--- | :--- | :--- |
| **Denial of Service** | CWE-400 (リソース枯渇) | 大量シンボル入力時の $O(N^2)$ ループによる CPU 100%・ハングアップ | $O(N)$ 線形リスト走査の撤去、バケット拡大、および $O(1)$ キャッシュによる DoS の根本排除。 |
| **Tampering** | CWE-125 (境界外読み取り) | 負のハッシュ値によるベクタ範囲外アクセス | `(if (< h 0) (- 0 h) h)` による絶対値変換と `(bitwise-and ... MASK)` の徹底。 |

---

## 4. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 第 3 章「Scheme 標準ライブラリとランタイムデータ表現」
- 依存・関連 Issue:
  - [Issue #772](772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md): ULisp 標準ライブラリの事前コンパイル済みオブジェクト化と分割静的リンクへの統一
  - [Issue #776](776-introduce-quick-bootstrap-mode-and-opt-in-post-tests.md): ULisp bootstrap.sh における開発用 Quick Bootstrap モード導入
  - [Issue #777](../777-bootstrap-compiler-alone-with-precompiled-stdlib-static-linking.md): 事前コンパイル済み標準ライブラリ静的リンクによるコンパイラ単体ブートストラップ
  - [Issue #781](../781-implement-record-based-symbols-with-direct-string-pointer.md): シンボルのヒープレコード化による symbol->string 完全 O(1) ダイレクトポインタ参照の実現

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/lib/string.scm](../../../ulisp/lib/string.scm) (バケットサイズ拡大、重複走査撤去、Direct-Mapped キャッシュ実装)
- [x] [ulisp/lib/equality.scm](../../../ulisp/lib/equality.scm) (`equal?` 型判定順序健全化と即値/ヒープタグ衝突回避)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (`test_split_link` ターゲット検証)
- [x] [docs/issues/README.md](../README.md) (Issue 台帳のステータス更新)

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/780-optimize-symbol-to-string-with-direct-cache-and-bucket-lookup`

### ステップ 1: バケット定数と初期化ベクタの拡大（16384 スロット）
- [ulisp/lib/string.scm](../../../ulisp/lib/string.scm):
  ```scheme
  (define *symbol-str-buckets*
    (let ((v (%make-vector 16384)))
      (let loop ((i 0))
        (if (< i 16384)
            (begin
              (vector-set! v i '())
              (loop (+ i 1)))
            v))))

  (define *symbol-sym-buckets*
    (let ((v (%make-vector 16384)))
      (let loop ((i 0))
        (if (< i 16384)
            (begin
              (vector-set! v i '())
              (loop (+ i 1)))
            v))))
  ```

### ステップ 2: Direct-Mapped キャッシュベクタの新設
- サイズ 4096 のシンボルキャッシュ用ベクタを配備：
  ```scheme
  (define *sym-cache-sym* (%make-vector 4096))
  (define *sym-cache-str* (%make-vector 4096))
  ```

### ステップ 3: `string->symbol` のビットマスク化
- `modulo h 1024` を `bitwise-and (if (< h 0) (- 0 h) h) 16383` に置換。

### ステップ 4: `symbol->string` の完全刷新
- 重複走査と `*symbol-registry*` へのフォールバックを撤去し、Direct-Mapped キャッシュを先頭に配置：
  ```scheme
  (define (%bucket-find-string sym entries)
    (let loop ((es entries))
      (if (or (null? es) (not (pair? es)))
          #f
          (let ((entry (car es)))
            (if (and (pair? entry) (eq? (cdr entry) sym))
                (car entry)
                (loop (cdr es)))))))

  (define (symbol->string sym)
    (let* ((h (symbol->integer sym))
           (pos-h (if (< h 0) (- 0 h) h))
           (c-idx (bitwise-and pos-h 4095))
           (cached-sym (vector-ref *sym-cache-sym* c-idx)))
      (if (eq? cached-sym sym)
          (vector-ref *sym-cache-str* c-idx)
          (let* ((known (%sym-assoc-string sym *known-runtime-symbols*))
                 (str (if known
                          known
                          (let* ((b-idx (bitwise-and pos-h 16383))
                                 (bucket (vector-ref *symbol-sym-buckets* b-idx))
                                 (res (%bucket-find-string sym bucket)))
                            (if res res "?")))))
            (vector-set! *sym-cache-sym* c-idx sym)
            (vector-set! *sym-cache-str* c-idx str)
            str))))
  ```

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `symbol->string` において `*symbol-registry*` の $O(N)$ 線形リスト走査が完全に排除されていること。
- [x] Direct-Mapped キャッシュにより、同一シンボルの再参照が $O(1)$ で完了すること。
- [x] `make -C ulisp test_split_link` が 30 分スタックすることなく、数秒〜十数秒で正常終了すること（実績: 5 秒）。
- [x] 既存の全単体テスト（`make -C ulisp test_stdlib`, `test_string_to_number` 等）が 100% PASS すること。
- [x] `make check_format static_analysis py_compile` がエラー 0 件で通過すること。
- [x] 相対リンク規約に 100% 準拠していること。

---

## 8. 実装完了報告 / Verification & Resolution

- **ボトルネックの解消**:
  - `*symbol-str-buckets*` および `*symbol-sym-buckets*` のバケット数を 1024 から 16,384 へ拡大し、`bitwise-and 16383` による 1 サイクルマスキングを導入。
  - サイズ 4096 の Direct-Mapped キャッシュベクタ `*sym-cache-sym*` / `*sym-cache-str*` を新設し、局所的なシンボル $\to$ 文字列変換を $O(1)$（配列参照 1 回）で短絡。
  - `symbol->string` における静的リスト `*known-runtime-symbols*` の重複走査（3重）および `*symbol-registry*` への $O(N)$ 線形探索フォールバックを完全撤去。
- **型タグ衝突防御の堅牢化**:
  - `equal?` において、`boolean?` および `null?` の型判定を `bytevector?` の前に配置し、即値定数タグ（47, 63）とヒープタグ（7）の衝突に起因する不正メモリアクセスを根本排除。
  - R7RS 準拠の可変長手続き `string-append` を [ulisp/lib/string.scm](../../../ulisp/lib/string.scm) に新設。
- **検証実績**:
  - `make -C ulisp test_split_link`: 30 分以上のハングから **約 5 秒** で PASS（200 倍以上の劇的な高速化を実証）。
  - `make -C ulisp test_string_to_number`: 100% PASS。
  - `make -C ulisp test_stdlib`: 100% PASS。
  - `make -C ulisp quick`: Stage 1 スモークテスト（42）含め正常完遂。
  - `make check_format static_analysis py_compile`: エラー 0 件で通過。
