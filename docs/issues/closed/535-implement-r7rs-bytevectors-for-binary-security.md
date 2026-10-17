---
ID: 535
種別: Feature
優先度: High
ステータス: Closed (Fixed)
担当: PM & IT Specialist (PLC / Compilers) & SWD
ターゲットブランチ: feat/535-ulisp-r7rs-bytevectors
---

# [FEAT/ENH] 低レベルバイナリ・暗号ハッシュ・生パケット解析向け R7RS バイトベクタ (bytevector) 型の実装 (ID: 535)

## 1. 概要 / Summary
セキュリティ研究および低レベルバイナリ解析（ELF/Mach-O ヘッダ走査、暗号ハッシュ SHA-256/HMAC 計算、パケットキャプチャのペイロード解析等）において、Unicode 文字列ではなく連続した生の 8-bit バイト列（`uint8_t[]`）をゼロコピーかつ $O(1)$ で直接操作できる機構が不可欠である。
現在の ULisp は文字列型（`STRING_TAG = 0x03`）とペア型しか持たず、任意バイナリ（特に `0x00` ヌルバイトを含むバイナリデータ）を走査する際にヌル終端起因の切り捨てや不要な文字境界チェックが発生する。
本 Issue では、R7RS Section 6.9（Bytevectors）に準拠した第一級バイトベクタ型 `bytevector` を新設し、`bytevector?`, `make-bytevector`, `bytevector-u8-ref`, `bytevector-u8-set!`, `bytevector-length`, `bytevector-copy`, `bytevector-copy!`, `bytevector-append` 等の操作プリミティブをベアメタルヒープ上に実装する。

---

## 2. ガバナンス & 多角的多専門エージェント審議 (16-Agent Review)

1. **Project Manager (PM)**:
   - ULisp のセキュリティドメイン特化（バイナリ静的解析・パケットインスペクション）における最重要基盤機能として承認。
   - 既存のブートストラップ・固定点完全一致（bit-for-bit identical）および C/x86_64 両バックエンドの完全対称性を維持することを必須要件とする。
2. **Information Security Specialist**:
   - バッファオーバーフロー（CWE-120/125/787）および境界外アクセス（OOB）の徹底防止。
   - `0x00` を含む任意バイト列の完全透過処理、暗号安全なインプレース更新の保証。
3. **Systems Architect**:
   - 64bit Tagged Pointer モデルにおいて、ポインタ下位 3-bit タグ `0x07` (`BYTEVECTOR_TAG`) を割り当て。
   - オブジェクト直前の 8B 接頭辞ヘッダに `((aligned_size << 16) | (4 << 2))` を格納し、先頭 8 バイトに Fixnum エンコードされた正確な `length` を保持する二重安全性レイアウトを採用。
4. **Software Development (SWD) & IT Specialist (Compilers / PLC)**:
   - `06_lir.scm` での LIR イントリンシック（`%load-byte-zx`, `%store-byte`）を活用し、`bytevector-u8-ref` および `bytevector-u8-set!` を 1 命令インライン展開。
   - C バックエンド（`07_backend_c.scm`）および x86-64 バックエンドの両方で完全同一の評価結果と ABI を保証。
5. **Software Quality Assurance Specialist**:
   - R7RS 標準テスト、境界値（空 bytevector、大容量バイナリ、0..255 全走査）、GC 回収・生存テストを含む包括的テストスイートの構築。

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Model & Security Safeguards)

| 脅威シナリオ / CWE | 影響度 | 対策・設計仕様 |
| :--- | :---: | :--- |
| **境界外読み取り / 書き込み (CWE-125 / CWE-787)** | Critical | `bytevector-u8-ref` / `bytevector-u8-set!` において、静的・動的境界チェック `$0 \le i < \text{len}$` を実施。違反時は即座にセーフティ例外を送出しスタック破壊を阻止。 |
| **型混同・タグ偽装 (CWE-843)** | High | Tagged Pointer 下位 3-bit `0x07` とヘッダ内 Type ID `4` の二重検証により、String (`0x03`) や Pair (`0x01`) との混同を排除。 |
| **ヌルバイト切り捨て (CWE-626)** | Medium | 文字列型と異なり、明示的な 64bit `length` フィールドを保持し、`0x00` を含むバイナリの長さを常に正確に判定。 |
| **GC による生データ破壊・リーク** | High | GC の Cheney スキャン時、バイトベクタを純粋な生バイト領域（ポインタなし）として扱い、内部バイト列への誤ったポインタ追跡を完全にバイパス。 |

---

## 4. アーキテクチャ設計とヒープレイアウト

### 4.1 64-bit Tagged Pointer とヒープ構造
- **Tagged Pointer**: `(addr + 8) | 0x07` (`BYTEVECTOR_TAG = 7`)
- **ポインタアンタグ**: `val & ~7` により、8バイト境界に整列した `base` アドレス（`addr + 8`）を取得。
- **ヒープメモリ配置**:
  ```text
  [addr - 8]: 8B GC Prefix Header: ((aligned_payload_bytes << 16) | (4 << 2))
  [addr + 0]: 8B Length (Fixnum: len << 2)  <-- base (val & ~7)
  [addr + 8]: Byte 0
  [addr + 9]: Byte 1
  ...
  [addr + 8 + i]: Byte i
  [addr + 8 + len .. 8 + aligned_payload]: Zero padding (8B aligned)
  ```
- **$O(1)$ 高速アクセスの利点**:
  - `(bytevector-length bv)`: `mov rax, [base + 0]`（すでに Fixnum エンコード済みのためシフト不要で 1 命令返却）。
  - `(bytevector-u8-ref bv i)`: `movzx rax, byte ptr [base + 8 + i]; shl rax, 2`。
  - `(bytevector-u8-set! bv i val)`: `sar val, 2; mov byte ptr [base + 8 + i], al; mov rax, 63`。

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/passes/00_helpers.scm](file:///workspace/arxiv-security-papers/ulisp/passes/00_helpers.scm) (プリミティブ登録: `bytevector?`, `make-bytevector`, `bytevector-length`, `bytevector-u8-ref`, `bytevector-u8-set!`)
- [x] [ulisp/passes/01_desugar.scm](file:///workspace/arxiv-security-papers/ulisp/passes/01_desugar.scm) (AST 脱糖: `bytevector`, `bytevector-append`, `make-bytevector`, `bytevector-copy`, `bytevector-copy!`, `string->utf8`, `utf8->string`)
- [x] [ulisp/passes/06_lir.scm](file:///workspace/arxiv-security-papers/ulisp/passes/06_lir.scm) (LIR 展開ロジックの実装: 割当、型述語、長さ取得、バイト参照・更新)
- [x] [ulisp/passes/07_backend_c.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_c.scm) (C バックエンドにおけるタグ定義 `BYTEVECTOR_TAG 7` とエミッタ対応)
- [x] [ulisp/passes/07_backend_x86_64.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_x86_64.scm) (x86-64 薄型ランタイム `#u8(...)` 出力ルーチン)
- [x] [ulisp/runtime.c](file:///workspace/arxiv-security-papers/ulisp/runtime.c) (C ランタイム: `BYTEVECTOR_TAG 0x07`, `BYTEVECTOR_MASK 0x07`, `#u8(...)` 書式化出力)
- [x] [ulisp/lib/bytevector.scm](file:///workspace/arxiv-security-papers/ulisp/lib/bytevector.scm) (新規作成: R7RS 高水準関数 `bytevector`, `bytevector-copy`, `bytevector-copy!`, `bytevector-append`, `bytevector=?`, `string->utf8`, `utf8->string`)
- [x] [ulisp/lib/gc.scm](file:///workspace/arxiv-security-papers/ulisp/lib/gc.scm) (GC ポインタ追跡・ポインタ判定における Type 4 スキップと Tag 7 登録)
- [x] [ulisp/compiler.scm](file:///workspace/arxiv-security-papers/ulisp/compiler.scm) (統合コンパイラへの反映)
- [x] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh) & [ulisp/test_c.sh](file:///workspace/arxiv-security-papers/ulisp/test_c.sh) (E2E テストの追加)

---

## 6. 実装ステップ / Implementation Plan

Target Branch: `feat/535-ulisp-r7rs-bytevectors`

1. **プリミティブ定義と LIR 具象化**:
   - `00_helpers.scm` に `bytevector?`, `make-bytevector`, `bytevector-length`, `bytevector-u8-ref`, `bytevector-u8-set!` を追加。
   - `06_lir.scm` にてヒープ確保、Fixnum 長さのストア、タグ 7 結合、バイト読み出し・書き出しの LIR 命令列を実装。
2. **C バックエンド & ランタイムの拡充**:
   - `07_backend_c.scm` および `runtime.c` に `BYTEVECTOR_TAG 0x07` を定義。
   - `print_scheme_value_raw` に R7RS 準拠の `#u8(0 127 255)` 表示ハンドラを追加。
3. **GC の安全化**:
   - `lib/gc.scm` において Tag 7 をヒープポインタ認識対象に追加。
   - Type 4 (Bytevector) を String と同様に生バッファとして扱い、ポインタ走査をスキップ。
4. **高水準 R7RS バイトベクタライブラリ (`lib/bytevector.scm`) の作成**:
   - `(bytevector byte ...)`
   - `(bytevector-copy bv [start [end]])`
   - `(bytevector-copy! to at from [start [end]])`
   - `(bytevector-append bv ...)`
   - `(bytevector=? bv1 bv2)`
5. **テスト作成・ブートストラップ・検証**:
   - `test.sh` および `test_c.sh` に網羅的なアサーションを追加。
   - `./ulisp/bootstrap.sh` を実行して 3 段階固定点完全一致（bit-for-bit identical）を検証。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `(bytevector? (make-bytevector 4 0))` が `#t`、非 bytevector に対して `#f` を返すこと。
- [x] `(let ((bv (make-bytevector 4 0))) (bytevector-u8-set! bv 0 127) (bytevector-u8-ref bv 0))` が `127` を返すこと。
- [x] `(bytevector-length (make-bytevector 10))` が `10` を $O(1)$ で返すこと。
- [x] `(bytevector 1 2 3)` および `(bytevector-copy ...)`、`(bytevector-append ...)` が正常に動作すること。
- [x] ヌルバイト `0x00` を含むバイナリデータが切り捨てられず完全に保持されること。
- [x] バイトベクタ生成・操作後に GC が発生しても、オブジェクトが破壊されず正常に生存・コピーされること。
- [x] x86-64 ネイティブバックエンド (`test.sh`) および Portable C バックエンド (`test_c.sh`) の両方で 100% PASS すること。
- [x] セルフホスティング固定点ブートストラップ（Stage 2 と Stage 3 の bit-for-bit 完全一致）が PASS すること。

