---
ID: 849
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-11-16
---

# [FEAT] char-ready? および u8-ready? のノンブロッキング入力準備状態判定の実装 (ID: 849)

## 1. 概要 / Summary

R7RS §6.13.2 仕様において、`char-ready?` および `u8-ready?` は「指定ポートから文字/バイトが即座に読み取り可能か」を問い合わせる述語である。
仕様書には以下のように明記されている：
> *"Returns `#t` if a character is ready on the input port and returns `#f` otherwise. If `char-ready?` returns `#t` then the next `read-char` operation on the given port is guaranteed not to hang. If the port is at end of file then `char-ready?` returns `#t`."*

しかし現状の `ulisp/lib/port.scm`（L722-L728）では：
```scheme
(define (port-char-ready? p)
  (cond
    ((string-input-port? p) #t)
    ((bytevector-input-port? p) #t)
    ((file-input-port? p) #t)
    ((standard-input-port? p) #t)
    (else #t)))
```
全ポートに対して無条件に定数 `#t` を返却するダミースタブとなっている。これにより、標準入力やパイプからデータが未到着の状態で `char-ready?` が `#t` を返し、直後の `read-char` でプロセスがブロッキングハングする重大な規格違反が発生している。

本 Issue では、内部バッファ検査、EOF 状態判定、および POSIX `poll` システムコール連携（タイムアウト 0ms）を実装し、真にブロックしない準備状態判定を提供する。

```mermaid
flowchart TD
    Req["(char-ready? [port]) / (u8-ready? [port])"] --> CheckBuf{"ポート内部バッファに先読みデータあり？"}
    CheckBuf -->|Yes| RetTrue["#t を即時返却 (読込保証)"]
    CheckBuf -->|No| CheckEOF{"ポートは既に EOF 状態？"}
    CheckEOF -->|Yes| RetTrueEOF["#t を返却 (R7RS §6.13.2 規定)"]
    CheckEOF -->|No| Type{"ポート種別"}
    Type -->|"String / Bytevector Port"| MemEOF{"未読込データ残存？"}
    MemEOF -->|Yes| RetTrue
    MemEOF -->|No| RetTrueEOF
    Type -->|"File / Stdin Port (fd)"| SysPoll["sys-poll (fd, POLLIN, timeout=0)"]
    SysPoll --> Ready{"POLLIN イベント検知？"}
    Ready -->|Yes| RetTrue
    Ready -->|No (または未準備)| RetFalse["#f を返却 (ブロック回避)"]
```

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書: S式メタコンパイラ基盤)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md): §2.5 (I/O ポートと非同期/ノンブロッキング規約)
  - [DSN-33-02 (ULisp 多言語フロントエンド＆型付き機械語 LIR アーキテクチャ)](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md): §7.2 (POSIX ランタイム)
- **規格仕様**:
  - R7RS-small Section 6.13.2 (Input procedures: `char-ready?`, `u8-ready?`)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.13.2)
- **関連 Issue**:
  - [Issue #660 (バイトベクタポートの実装)](closed/660-implement-r7rs-bytevector-ports-and-ready-predicates.md)
  - [Issue #847 (ポート I/O 未実装手続きの実装)](847-implement-missing-r7rs-io-read-string-and-bytevector.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/lib/port.scm](../../ulisp/lib/port.scm): `port-char-ready?`, `char-ready?`, `u8-ready?` の判定ロジック刷新
- [x] [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm): ノンブロッキング `sys-poll` システムコールラッパーの追加
- [x] [ulisp/tests/test_ports.scm](../../ulisp/tests/test_ports.scm): 文字列ポート・空ポート・境界条件テスト拡充
- [x] [ulisp/tests/test_r7rs_bytevector_ports.scm](../../ulisp/tests/test_r7rs_bytevector_ports.scm): バイナリポートの `u8-ready?` テスト拡充

---

## 4. セキュリティ・設計分析 / Threat Modeling & Constraints

| 脅威 / リスク ID | 脅威内容 | CWE 分類 | 潜在的影響 | 本 Issue での対策・設計的緩和策 |
| :--- | :--- | :--- | :--- | :--- |
| **THREAT-849-1** | 誤った準備判定によるプロセス永続ハング DoS | **CWE-400** (Uncontrolled Resource Consumption) / **CWE-834** | 入力データが存在しないのに `char-ready?` が `#t` を返したため、直後の `read-char` で待機スレッドが永久ブロックし、サービスが停止する。 | 1. ファイルディスクリプタに対してはカーネルの `poll(2)` で `POLLIN` フラグを直接検証する。<br>2. タイムアウトは 0ms（非待機）を厳守する。 |
| **THREAT-849-2** | シグナル割り込み (EINTR) 時の誤判定 | **CWE-703** (Improper Check or Handling of Exceptional Conditions) | `poll(2)` 実行中にタイマーシグナルや SIGCHLD が発生して `EINTR (-4)` が返された際、例外でクラッシュするか誤って `#t` を返す。 | `EINTR` 発生時は即座に 1 回再試行するか、安全側として `#f`（未準備）を返却する。 |

---

## 5. 実装方針 / Detailed Implementation Plan

Target Branch: `feat/849-implement-true-non-blocking-readiness-for-char-and-u8-ready`

### Step 1: POSIX ノンブロッキング ポーリングの導入 (`ulisp/lib/posix.scm`)
1. `sys-fd-poll-in` 手続きを定義:
   - システムコール番号 7 (`sys-poll`) を呼び出し。
   - `struct pollfd { int fd; short events; short revents; }` (8 バイト) をスタックまたは一時バッファに構築。
   - `events = 0x0001` (`POLLIN`), `timeout = 0`.
   - 返り値 $> 0$ かつ `(revents & POLLIN) != 0` の場合に `#t` を返却。エラーまたは未準備は `#f`。

### Step 2: ポート準備判定の階層的評価 (`ulisp/lib/port.scm`)
1. **`port-char-ready?` の実装**:
   ```scheme
   (define (port-char-ready? p)
     (cond
       ;; 1. 先読みバッファに文字が存在する場合
       ((port-has-peek-char? p) #t)
       ;; 2. 既に EOF 到達済みのポート (R7RS: EOF は #t)
       ((port-eof? p) #t)
       ;; 3. メモリ文字列ポート
       ((string-input-port? p)
        (< (string-port-index p) (string-port-length p)))
       ;; 4. メモリバイトベクタポート
       ((bytevector-input-port? p)
        (< (bv-port-index p) (bv-port-length p)))
       ;; 5. ファイルポート / 標準入力
       ((or (file-input-port? p) (standard-input-port? p))
        (let ((fd (port-file-descriptor p)))
          (sys-fd-poll-in fd)))
       (else #t)))
   ```
2. **第一級手続きとしての公開**:
   - `char-ready?` および `u8-ready?` を `case-lambda` による第一級手続きとして再定義（ポート省略時は `(current-input-port)`）。

### Step 3: テストケース作成
1. 空の文字列ポート・末尾到達ポートで `#t` (EOF) を確認。
2. データが残っている文字列ポートで `#t` を確認。
3. `pipe(2)` で作成した未書き込みパイプに対して `char-ready?` が `#f` を返すことを確認。
4. パイプに 1 文字書き込み後、`char-ready?` が `#t` に変化し、`read-char` でブロックせず取得できることを確認。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] データが未到着のパイプ／標準入力に対して `char-ready?` および `u8-ready?` が `#f` を返すこと。
- [x] 文字列ポート、バイトベクタポート、EOF 到達ポートで仕様通り `#t` を返すこと。
- [x] `(char-ready?)` / `(u8-ready?)` が引数なし（カレントポート）および引数ありの両方で第一級手続きとして動作すること。
- [x] `test_ports.scm` のテストが全 PASS すること。

### 検証完了記録 (DoD Verification)
- 実施日: 2026-11-16
- 検証スイート:
  - `make -C ulisp test_phase1_r7rs` (58/58 PASS)
  - `make -C ulisp test_ports` (57/57 PASS)
  - `make -C ulisp test_stdlib` (193/193 PASS)
  - `make -C ulisp test_numeric_tower` (229/229 PASS)
  - `python3 scripts/verify_r7rs_traceability.py` (100% PASS)
  - `make -C ulisp test_lint_sexpr` (23/23 PASS)
- 判定: 全ての受入基準・完了条件 (DoD) を充足。Issue #849 クローズ完了。
