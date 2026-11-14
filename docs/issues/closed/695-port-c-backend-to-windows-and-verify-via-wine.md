---
ID: 695
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] ULisp Portable C99 バックエンドの Windows (MinGW/MSVC) 移植と Wine 実行検証 (ID: 695)

## 1. 概要 / Summary
Pass 160（`ulisp/backend/160_backend_c.scm`）による ANSI C99 出力コードを、Windows プラットフォーム（MinGW-w64 / MSVC）において警告・エラー 0 件でネイティブビルド可能に適合させる。
POSIX 特有のシステムコール（`sys/mman.h` の `mmap` / `mremap`、`sigaction`、`unistd.h`）に依存しているランタイム初期化部を、`#ifdef _WIN32` プリプロセッサ分岐により Win32 API（`VirtualAlloc`、`signal`、`<io.h>`、`<fcntl.h>`）へ透過的に切り替える。
また、Windows のテキストモード標準入出力における `\r\n` 改行変換に伴うバイナリ破損を防止するため `_setmode` によるバイナリモード強制（`_O_BINARY`）を組み込み、クロスコンパイラ `x86_64-w64-mingw32-gcc` でビルドした Windows 向け `.exe` バイナリが `wine64` 環境上で Scheme の全基本テストスイートを 100% PASS することを実証する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §2.1 (Tagged Pointer メモリモデル), §3 (言語機能と低レイヤコード生成仕様)
- **DSN-33-02**: §2.1 (Pass 160 Portable C Backend), §7.2 (C バックエンド同期とクロスプラットフォーム検証)
- **関連 Issue**: #504 (Portable C Backend via LIR), #543 (Fix C Backend Syntax Error), #694 (MinGW & Wine Environment), #831 (C Backend Typed LIR Sync)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm):
  - ヘッダーインクルード部の Windows 分岐（`<windows.h>`, `<io.h>`, `<fcntl.h>` の追加）
  - ヒープメモリ確保の Win32 抽象化（`mmap` $\to$ `VirtualAlloc`）
  - シグナルハンドラ登録の移植（`sigaction` $\to$ `signal(SIGSEGV, ...)`）
  - 標準入出力のバイナリモード強制（`_setmode`）
  - タイマー・環境変数アクセスの互換性確保（`clock_gettime` / `_environ`）
- [x] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm):
  - `--target=c-windows`（または `--target=c` への Windows フラグ伝播）およびクロスコンパイルドライバ関数の整備
- [x] [ulisp/tests/test_c_backend_windows.scm](../../ulisp/tests/test_c_backend_windows.scm):
  - Scheme 式を C コードへ変換し、MinGW で `.exe` をビルド、`wine64` で実行して戻り値・出力をアサートする自動検証テストスイート
- [x] [Makefile](../../Makefile):
  - `make test_c_windows` ターゲットの追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/695-port-c-backend-to-windows`

### 4.1 `ulisp/backend/160_backend_c.scm` の改修詳細
1. **プラットフォーム判定ヘッダーの導入**:
   - `#ifdef _WIN32` / `#elif defined(__linux__) || defined(__APPLE__)` による条件分岐。
   - Windows 側では `<windows.h>`, `<io.h>`, `<fcntl.h>` をインクルードし、`<sys/mman.h>`, `<unistd.h>` のインクルードをスキップ。
   - `environ` 変数の定義：MinGW-w64 互換のため `#define environ _environ` または `extern char **_environ;` を使用。

2. **ヒープ割り当ての抽象化マクロ (`ULISP_MMAP_HEAP`)**:
   ```c
   #ifdef _WIN32
   static inline void *ulisp_platform_alloc_heap(size_t size) {
       return VirtualAlloc(NULL, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
   }
   static inline void ulisp_platform_free_heap(void *ptr, size_t size) {
       VirtualFree(ptr, 0, MEM_RELEASE);
   }
   #else
   static inline void *ulisp_platform_alloc_heap(size_t size) {
       void *p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
       return (p == MAP_FAILED) ? NULL : p;
   }
   #endif
   ```
   - `main()` 関数内の `char *heap = (char *)mmap(...);` を `ulisp_platform_alloc_heap(HEAP_SIZE)` 呼出しへ置換。
   - `ulisp_gc_grow_mature()` 内の `mremap` 処理において、Windows では再確保不能な場合のフォールバック（返り値 0）を安全に実行。

3. **クラッシュシグナルハンドラの適合**:
   - Linux: `sigaction(SIGSEGV, &sa, NULL);`
   - Windows:
     ```c
     #ifdef _WIN32
     signal(SIGSEGV, (void (*)(int))crash_handler_simple);
     #else
     struct sigaction sa;
     ...
     sigaction(SIGSEGV, &sa, NULL);
     #endif
     ```

4. **標準ストリームのバイナリモード強制**:
   - `main()` の冒頭で実行：
     ```c
     #ifdef _WIN32
     _setmode(_fileno(stdin), _O_BINARY);
     _setmode(_fileno(stdout), _O_BINARY);
     _setmode(_fileno(stderr), _O_BINARY);
     #endif
     ```

5. **高精度タイマー (`ULISP_GC_STATS`) の互換化**:
   - `clock_gettime(CLOCK_MONOTONIC, &g_prog_start_time)` について、Windows では `QueryPerformanceCounter` または `GetTickCount64` を用いた互換ラッパーを配置。

### 4.2 コンパイラドライバおよびテストスイート (`ulisp/tests/test_c_backend_windows.scm`) の構築
1. Scheme コンパイラ上でテスト対象 S式（算術、ペア、ベクタ、文字列、クロージャ、再帰）を LIR 経由で C99 コード文字列へコンパイル。
2. 一時ファイル `/tmp/ulisp_win_test_<id>.c` へ出力。
3. `x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -Wno-unused-label /tmp/ulisp_win_test_<id>.c -o /tmp/ulisp_win_test_<id>.exe` を実行し、コンパイルエラー・警告 0 件を確認。
4. `wine64 /tmp/ulisp_win_test_<id>.exe` をサブプロセスとして実行し、標準出力および終了コードが期待値と完全一致することを検証。

---

## 5. 脅威分析とセキュリティ対策 / Threat Modeling & Mitigations
- **脅威 1: 未初期化ポインタの参照による Windows 上での不正メモリアクセス**
  - *対策*: `VirtualAlloc` はコミット時にシステムによってメモリ領域が自動ゼロクリアされるため、Linux の `MAP_ANONYMOUS` と同等のクリーンなメモリ空間が保証される。
- **脅威 2: 改行文字コード変換によるバッファオーバーラン・パーサ誤動作**
  - *対策*: `_setmode(_fileno(...), _O_BINARY)` を標準入出力の全ストリームに適用し、`\r\n` $\leftrightarrow$ `\n` の透過変換によるオフセットずれを完全に排除。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/backend/160_backend_c.scm` が生成する C99 ソースが、`x86_64-w64-mingw32-gcc -Wall -Wextra -Werror`（未使用ラベル等の既知例外除く）で警告・エラー 0 件でコンパイルできること。
- [x] 生成された `.exe` が `wine64` 上で実行され、以下の機能が正常動作すること：
  - [x] 整数および浮動小数点の基本算術演算（Fixnum, Flonum）
  - [x] ペア・リストの `cons`, `car`, `cdr` 操作
  - [x] クロージャの生成と高階関数の呼出し
  - [x] 16MB ヒープへのメモリアロケーションと Cheney GC の動作
  - [x] 標準入出力（`write-char`, `display`, `read-char`）のバイナリ整合性
- [x] 単体テスト `test_c_backend_windows.scm` が全項目 PASS すること。
- [x] `make test_c_windows` が自動実行可能であること。
