---
ID: 536
種別: Feature
優先度: High
ステータス: Closed (Fixed)
担当: PM & IT Specialist (PLC / Compilers) & SWD
ターゲットブランチ: feat/536-ulisp-complete-r7rs-vectors
---

# [FEAT/ENH] O(1) ランダムアクセス配列および高速ハッシュ辞書基盤向け R7RS ベクタ (vector) の完全実装 (ID: 536)

## 1. 概要 / Summary
現在の ULisp では、データ構造の大部分が線形リスト（ペアの連鎖）に依存しており、要素アクセスや辞書検索、インターンテーブルの走査に $O(N)$ の時間がかかっている。
コンパイラのシンボル解決やグラフ解析の規模拡大に伴い、$O(1)$ の時間計算量で任意要素にアクセス・更新できる固定長ポインタ配列（Vector）が不可欠となっている。
本 Issue では、R7RS Section 6.8（Vectors）に準拠した第一級ベクタ型 `vector`、`vector?`, `make-vector`, `vector-ref`, `vector-set!`, `vector-length`, `vector`, `vector-copy`, `vector-copy!`, `vector-append`, `vector-fill!`, `vector->list`, `list->vector` をネイティブ実装し、高速なハッシュテーブルやキャッシュテーブルの基盤を確立する。

---

## 2. ガバナンス & 多角的多専門エージェント審議 (16-Agent Review)

1. **Project Manager (PM)**:
   - ULisp の計算量ボトルネック（$O(N)$ から $O(1)$ への短縮）を解消し、コンパイラおよびセキュリティ解析基盤の高速化を実現する重要マイルストーンとして承認。
   - 3 段階固定点セルフホスティング（bit-for-bit identical）の完全保持を必須要件とする。
2. **Information Security Specialist**:
   - ベクタ境界外アクセス（CWE-125: Out-of-bounds Read, CWE-787: Out-of-bounds Write）の防止。
   - 型混同攻撃（CWE-843）を防ぐため、Tagged Pointer 下位 3-bit `0x05` とヘッダ内 Type ID `5` の完全整合を義務付け。
3. **Systems Architect**:
   - 64bit Tagged Pointer モデルにおいて、ポインタ下位 3-bit タグ `0x05` (`VECTOR_TAG`) を割り当て。
   - ペア (`0x01`)、文字列 (`0x03`)、ベクタ (`0x05`)、バイトベクタ (`0x07`) の 4 大ポインタ型が下位 3-bit マスク `0x07` で完全直交する美しい直交設計を採用。
4. **Software Development (SWD) & IT Specialist (Compilers / PLC)**:
   - `06_lir.scm` での LIR イントリンシック（`%load`, `%store`）による $O(1)$ スケールアドレスアクセス `[base + 8 + i*8]` の展開。
   - C バックエンド（`07_backend_c.scm`）および x86-64 バックエンドの両方で完全同一の評価結果と ABI を保証。
5. **Software Quality Assurance Specialist**:
   - R7RS Section 6.8 準拠テスト、空ベクタ、入れ子ベクタ、GC サイクルをまたぐ生存・更新テストを含む包括的テストスイートの構築。

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Model & Security Safeguards)

| 脅威シナリオ / CWE | 影響度 | 対策・設計仕様 |
| :--- | :---: | :--- |
| **境界外読み取り / 書き込み (CWE-125 / CWE-787)** | Critical | `vector-ref` / `vector-set!` において、ハードウェアスケールアクセス時のポインタ破壊を防止。 |
| **型混同・タグ偽装 (CWE-843)** | High | Tagged Pointer 下位 3-bit `0x05` とヘッダ内 Type ID `5` の二重検証により、Pair (`0x01`) や Bytevector (`0x07`) との混同を排除。 |
| **GC による要素ポインタ破壊・ダングリングポインタ** | Critical | ベクタはポインタ配列（Scheme 値の列）であるため、GC の Cheney スキャンおよび Stackmap スキャン時に全要素スロットを再帰的に走査し、移動先アドレスへの安全な書き換えを保証。 |

---

## 4. アーキテクチャ設計とヒープレイアウト

### 4.1 64-bit Tagged Pointer とヒープ構造
- **Tagged Pointer**: `(addr + 8) | 0x05` (`VECTOR_TAG = 5`)
- **ポインタアンタグ**: `val & ~7` または `val - 5` により、8バイト境界に整列した `base` アドレス（`addr + 8`）を取得。
- **ヒープメモリ配置**:
  ```text
  [addr - 8]: 8B GC Prefix Header: (((8 + len * 8) << 16) | (5 << 2))
  [addr + 0]: 8B Length (Fixnum: len << 2)  <-- base (val - 5)
  [addr + 8]: Element 0 (64-bit Scheme value)
  [addr + 16]: Element 1 (64-bit Scheme value)
  ...
  [addr + 8 + i*8]: Element i (64-bit Scheme value)
  ```
- **$O(1)$ 高速アクセスの利点**:
  - `(vector-length v)`: `mov rax, [base + 0]`（Fixnum エンコード済みのためシフト不要で 1 命令返却）。
  - `(vector-ref v i)`: `mov rax, [base + 8 + i*8]`。
  - `(vector-set! v i val)`: `mov [base + 8 + i*8], val`。

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/passes/00_helpers.scm](file:///workspace/arxiv-security-papers/ulisp/passes/00_helpers.scm) (プリミティブ登録: `vector?`, `make-vector`, `vector-length`, `vector-ref`, `vector-set!`)
- [ ] [ulisp/passes/01_desugar.scm](file:///workspace/arxiv-security-papers/ulisp/passes/01_desugar.scm) (AST 脱糖: `vector`, `vector-append`, `make-vector`, `vector-copy`, `vector-copy!`, `vector-fill!`, `vector->list`)
- [ ] [ulisp/passes/04b_annotator.scm](file:///workspace/arxiv-security-papers/ulisp/passes/04b_annotator.scm) (型推論: `vector?`, `vector-length`)
- [ ] [ulisp/passes/06b_alias_escape.scm](file:///workspace/arxiv-security-papers/ulisp/passes/06b_alias_escape.scm) (TBAA エイリアス解析: `vector-ref`, `vector-set!`)
- [ ] [ulisp/passes/06_lir.scm](file:///workspace/arxiv-security-papers/ulisp/passes/06_lir.scm) (LIR 展開ロジックの実装: 割当、型述語、長さ取得、要素参照・更新)
- [ ] [ulisp/passes/07_backend_x86_64.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_x86_64.scm) (x86-64 薄型ランタイム `#(...)` 出力ルーチン)
- [ ] [ulisp/runtime.c](file:///workspace/arxiv-security-papers/ulisp/runtime.c) (C ランタイム: `VECTOR_TAG 0x05`, `VECTOR_MASK 0x07`, `#(...)` 書式化出力)
- [ ] [ulisp/lib/vector.scm](file:///workspace/arxiv-security-papers/ulisp/lib/vector.scm) (新規作成: R7RS 高水準関数 `make-vector-fill`, `vector-copy-range`, `vector-copy-range!`, `vector-fill-range!`, `vector-append2`, `vector->list-range`, `list->vector`)
- [ ] [ulisp/lib/gc.scm](file:///workspace/arxiv-security-papers/ulisp/lib/gc.scm) (GC ポインタ追跡・Cheney スキャンにおける Type 5 スキャンと Tag 5 認識)
- [ ] [ulisp/lib/printer.scm](file:///workspace/arxiv-security-papers/ulisp/lib/printer.scm) (Scheme プリンタにおける `vector?` / `#(...)` 出力)
- [ ] [ulisp/compiler.scm](file:///workspace/arxiv-security-papers/ulisp/compiler.scm) (統合コンパイラへの反映)
- [ ] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh) & [ulisp/test_c.sh](file:///workspace/arxiv-security-papers/ulisp/test_c.sh) (E2E テストの追加)

---

## 6. 実装ステップ / Implementation Plan

Target Branch: `feat/536-ulisp-complete-r7rs-vectors`

1. **プリミティブ定義と LIR 具象化**:
   - `00_helpers.scm` に `vector?`, `make-vector`, `%make-vector`, `vector-length`, `vector-ref`, `vector-set!` を追加。
   - `06_lir.scm` にてヒープ確保、Fixnum 長さのストア、タグ 5 結合、64-bit ポインタ読み出し・書き込みの LIR 命令列を実装。
2. **C バックエンド & ランタイムの拡充**:
   - `runtime.c` に `PAIR_MASK 0x07`, `VECTOR_TAG 0x05`, `VECTOR_MASK 0x07` を定義。
   - `print_scheme_value_raw` に R7RS 準拠の `#(...)` 再帰表示ハンドラを追加。
   - `07_backend_x86_64.scm` に `ulisp_print_vector` を追加。
3. **GC の安全化**:
   - `lib/gc.scm` において Tag 5 をヒープポインタ認識対象に追加。
   - Type 5 (Vector) を Cheney スキャンおよび世代別 Minor GC の走査対象に追加し、要素スロットの Scheme ポインタを再帰的に更新。
4. **高水準 R7RS ベクタライブラリ (`lib/vector.scm`) の作成**:
   - `(make-vector-fill len fill)`
   - `(vector-copy-range vec start end)`
   - `(vector-copy-range! to at from start end)`
   - `(vector-fill-range! vec fill start end)`
   - `(vector-append2 v1 v2)`
   - `(vector->list-range vec start end)`
   - `(list->vector lst)`
5. **AST 脱糖 (`01_desugar.scm`)**:
   - `(vector ...)`, `(vector-append ...)`, `(make-vector ...)`, `(vector-copy ...)`, `(vector-copy! ...)`, `(vector-fill! ...)`, `(vector->list ...)`
6. **テスト作成・ブートストラップ・検証**:
   - `test.sh` および `test_c.sh` に網羅的なアサーションを追加。
   - `./ulisp/bootstrap.sh` を実行して 3 段階固定点完全一致（bit-for-bit identical）を検証。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `(vector? (make-vector 4))` が `#t`、非 vector に対して `#f` を返すこと。
- [x] `(let ((v (make-vector 3 'init))) (vector-set! v 1 42) (vector-ref v 1))` が `42` を返すこと。
- [x] `(vector-ref (make-vector 3 100) 0)` が `100` を返すこと。
- [x] `(vector-length (make-vector 10))` が `10` を $O(1)$ で返すこと。
- [x] `(vector 1 2 3)` および `(vector-copy ...)`, `(vector-append ...)`, `(vector->list ...)`, `(list->vector ...)` が正常に動作すること。
- [x] ベクタ内部に保持されたペアやクロージャが GC 後も正常に生存・参照可能であること。
- [x] x86-64 ネイティブバックエンド (`test.sh`) および Portable C バックエンド (`test_c.sh`) の両方で 100% PASS すること。
- [x] セルフホスティング固定点ブートストラップ（Stage 2 と Stage 3 の bit-for-bit 完全一致）が PASS すること。
