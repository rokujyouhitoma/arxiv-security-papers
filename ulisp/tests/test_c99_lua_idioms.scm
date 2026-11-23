;;; =======================================================================
;;; ULisp C99 Lua Idioms & Multi-TU Linkage Regression Tests (Issue #925)
;;; Verifies:
;;;   1. static function internal linkage (.L_c99_static_fn_* / STB_LOCAL)
;;;   2. Forward declaration of static unsized array completed later in TU
;;;   3. File-scope & block-scope static/extern linkage reuse
;;;   4. Binary string literals (\x1bLua, \x19\x93\r\n\x1a\n, embedded \000)
;;;   5. Driver flag whitelisting (-Wl,-E, -rdynamic, -std=c99, -Wall, -O3)
;;;      while preserving CWE-78 shell metacharacter blocking (C99-DRV-002)
;;;   6. Cross-engine parity: Native ELF multi-TU vs Portable C vs Reference VM
;;; =======================================================================

(define *lua-idiom-pass* (cons 0 '()))
(define *lua-idiom-fail* (cons 0 '()))

(define (lua-idiom-assert-true name pred)
  (if pred
      (begin
        (set-car! *lua-idiom-pass* (+ (car *lua-idiom-pass*) 1))
        (display "  [PASS] ") (display name) (newline))
      (begin
        (set-car! *lua-idiom-fail* (+ (car *lua-idiom-fail*) 1))
        (display "  [FAIL] ") (display name) (newline))))

(define (lua-idiom-assert-equal name expected actual)
  (if (equal? expected actual)
      (begin
        (set-car! *lua-idiom-pass* (+ (car *lua-idiom-pass*) 1))
        (display "  [PASS] ") (display name) (newline))
      (begin
        (set-car! *lua-idiom-fail* (+ (car *lua-idiom-fail*) 1))
        (display "  [FAIL] ") (display name)
        (display " expected=") (write expected)
        (display " actual=") (write actual)
        (newline))))

(display "========================================================================\n")
(display " C99 Multi-TU Static Linkage, Binary Strings & Lua Idioms Suite (#925)\n")
(display "========================================================================\n")

(let* ((tmp-dir "build/test_c99_lua_idioms_tmp")
       (tu1 (string-append tmp-dir "/tu1.c"))
       (tu2 (string-append tmp-dir "/tu2.c"))
       (obj1 (string-append tmp-dir "/tu1.o"))
       (obj2 (string-append tmp-dir "/tu2.o"))
       (elf-bin (string-append tmp-dir "/multi_tu_bin"))
       (c-bin (string-append tmp-dir "/multi_tu_c_bin"))
       (tu1-src
        (string-append
         "#include <string.h>\n"
         "struct Reg { const char *name; int (*fn)(int); };\n"
         "static const struct Reg tbl[];\n"
         "static int helper(int x);\n"
         "static int call_helper(int x) { return helper(x) + 100; }\n"
         "static int helper(int x) { return x * 3 + 1; }\n"
         "static const struct Reg tbl[] = {\n"
         "  {\"h\", call_helper},\n"
         "  {NULL, NULL}\n"
         "};\n"
         "typedef int (*fn_t)(int);\n"
         "static fn_t pick_fn(int sel, fn_t f) {\n"
         "  fn_t g = NULL;\n"
         "  if (g != NULL || NULL != g) return NULL;\n"
         "  g = (sel > 0) ? f : NULL;\n"
         "  if (g == NULL) return NULL;\n"
         "  return (sel > 1) ? NULL : g;\n"
         "}\n"
         "static int accept_fn_null(fn_t f) { return f == NULL ? 1 : 0; }\n"
         "struct DummyNode { int tag; int val; };\n"
         "struct Holder { int pad; const struct DummyNode *node; };\n"
         "static const struct DummyNode dummynode_ = { 16, 777 };\n"
         "static void assign_dummynode(struct Holder *h) {\n"
         "  h->node = &dummynode_;\n"
         "}\n"
         "static const char lua_sig[] = \"\\x1bLua\";\n"
         "static const char lua_data[] = \"\\x19\\x93\\r\\n\\x1a\\n\";\n"
         "static const char emb_nul[] = \"ab\\0001c\";\n"
         "int from_tu1(int x) {\n"
         "  const char *p = \"\\x1b\" \"Lua\";\n"
         "  const char *q = \"\\000\" \"12\";\n"
         "  int ok = 1;\n"
         "  struct Holder h;\n"
         "  h.pad = 0;\n"
         "  h.node = NULL;\n"
         "  assign_dummynode(&h);\n"
         "  if (h.node == NULL || h.node->tag != 16 || h.node->val != 777) ok = 0;\n"
         "  fn_t pf = pick_fn(1, tbl[0].fn);\n"
         "  if (pf == NULL) ok = 0;\n"
         "  if (pick_fn(0, tbl[0].fn) != NULL) ok = 0;\n"
         "  if (pick_fn(2, tbl[0].fn) != NULL) ok = 0;\n"
         "  if (!accept_fn_null(NULL)) ok = 0;\n"
         "  if (accept_fn_null(pf)) ok = 0;\n"
         "  if ((unsigned char)lua_sig[0] != 0x1b || lua_sig[1] != 'L') ok = 0;\n"
         "  if ((unsigned char)p[0] != 0x1b || p[2] != 'u') ok = 0;\n"
         "  if ((unsigned char)lua_data[0] != 0x19 || (unsigned char)lua_data[1] != 0x93) ok = 0;\n"
         "  if ((unsigned char)lua_data[4] != 0x1a || lua_data[5] != '\\n') ok = 0;\n"
         "  if (emb_nul[2] != '\\0' || emb_nul[3] != '1' || emb_nul[4] != 'c') ok = 0;\n"
         "  if (q[0] != '\\0' || q[1] != '1' || q[2] != '2') ok = 0;\n"
         "  return ok ? pf(x) : -999;\n"
         "}\n"))
       (tu2-src
        (string-append
         "#include <stdio.h>\n"
         "extern int from_tu1(int x);\n"
         "static int helper_val;\n"
         "static int helper(int x) {\n"
         "  extern int helper_val;\n"
         "  return x * 5 + helper_val;\n"
         "}\n"
         "static int helper_val = 2;\n"
         "static int call_helper(int x) { return helper(x); }\n"
         "int main(void) {\n"
         "  int a = from_tu1(7);\n"
         "  int b = call_helper(7);\n"
         "  return (a + b) == 159 ? 0 : (a + b);\n"
         "}\n")))
  (if (file-exists? elf-bin) (delete-file elf-bin))
  (if (file-exists? c-bin) (delete-file c-bin))
  (if (file-exists? obj1) (delete-file obj1))
  (if (file-exists? obj2) (delete-file obj2))
  (if (not (file-exists? tmp-dir))
      (process-exec (list "mkdir" "-p" tmp-dir)))
  (%c-drv-write-text-file! tu1 tu1-src)
  (%c-drv-write-text-file! tu2 tu2-src)

  ;; 1. Sema checks static function & forward static array lowering
  (let* ((ast1 (parse-c99-preprocessed-string tu1-src tu1))
         (typed1 (c99-analyze-program ast1))
         (lir1 (c99-lower-to-lir typed1))
         (fns1 (cdr (assq '%lir-functions (cdr lir1))))
         (fn-names1 (map cadr fns1)))
    (lua-idiom-assert-true
     "static function helper lowered with .L_c99_static_fn_ prefix"
     (and (memq '.L_c99_static_fn_helper fn-names1) #t))
    (lua-idiom-assert-true
     "global function from_tu1 retains external symbol name"
     (and (memq 'from_tu1 fn-names1) #t)))

  (lua-idiom-assert-true
   "non-constant void* assignment to function pointer is rejected with C99-PTR-004"
   (guard (ex ((and (pair? ex) (eq? (car ex) 'c99-sema-error)
                    (equal? (cadr ex) "C99-PTR-004"))
               #t)
              (else #f))
     (c99-analyze-program
      (parse-c99-preprocessed-string
       "int f(void *vp) { int (*fp)(int) = vp; return fp == 0; }\n"
       "neg_void_ptr.c"))
     #f))

  (lua-idiom-assert-true
   "(int *)0 comparison with function pointer is rejected with C99-PTR-004"
   (guard (ex ((and (pair? ex) (eq? (car ex) 'c99-sema-error)
                    (equal? (cadr ex) "C99-PTR-004"))
               #t)
              (else #f))
     (c99-analyze-program
      (parse-c99-preprocessed-string
       "int f(int (*fp)(int)) { return fp == (int *)0; }\n"
       "neg_int_ptr_zero.c"))
     #f))

  ;; 2. Driver CLI flag whitelist & CWE-78 blocking
  (let ((opts (parse-c-driver-args
               '("-std=c99" "-Wall" "-Wextra" "-g" "-O3" "-Wl,-E" "-rdynamic" "a.c"))))
    (lua-idiom-assert-equal "-O3 maps to opt-level 2" 2 (c-drv-opt-level opts))
    (lua-idiom-assert-equal "ld-flags preserves -Wl,-E and -rdynamic"
                            '("-Wl,-E" "-rdynamic")
                            (c-drv-ld-flags opts)))

  (lua-idiom-assert-true
   "CWE-78 blocks shell metachars inside -Wl, argument"
   (guard (ex ((and (pair? ex) (eq? (car ex) 'c99-driver-error)) #t)
              (else #f))
     (parse-c-driver-args '("-Wl,-E;id" "a.c"))
     #f))

  ;; 3. Compile both TUs to ET_REL .o with whitelisted flags and verify no global static collision
  (lua-idiom-assert-equal
   "tu1.c compiles with -std=c99 -Wall -Wextra -O3 -c"
   0 (c-driver-cli-main (list "-std=c99" "-Wall" "-Wextra" "-O3" "-c" tu1 "-o" obj1)))
  (lua-idiom-assert-equal
   "tu2.c compiles with -std=c99 -Wall -Wextra -O3 -c"
   0 (c-driver-cli-main (list "-std=c99" "-Wall" "-Wextra" "-O3" "-c" tu2 "-o" obj2)))
  (lua-idiom-assert-equal
   "both .o files have no GLOBAL binding for static helper"
   1 (process-exec (list "sh" "-c" (string-append "readelf -s '" obj1 "' '" obj2 "' | grep -E 'GLOBAL.*helper'"))))

  ;; 4. Link and run Native ELF binary (with -Wl,-E -rdynamic)
  (lua-idiom-assert-equal
   "multi-TU Native ELF links with -Wl,-E -rdynamic"
   0 (c-driver-cli-main (list "-Wl,-E" "-rdynamic" obj1 obj2 "-o" elf-bin)))
  (lua-idiom-assert-equal
   "multi-TU Native ELF executes and returns 0 (exact sum 159)"
   0 (process-exec (list elf-bin)))

  ;; 5. Cross-check Portable C backend (--target=c) multi-TU merge & execute
  (lua-idiom-assert-equal
   "multi-TU --target=c merges colliding static fn names cleanly"
   0 (c-driver-cli-main (list "--target=c" "-O2" "-Wl,-E" tu1 tu2 "-o" c-bin)))
  (lua-idiom-assert-equal
   "multi-TU Portable C binary executes and returns 0"
   0 (process-exec (list c-bin)))

  ;; 6. Cross-check Reference LIR VM multi-TU execution
  (let* ((vm-res (c-driver-cli-main (list "--target=vm" tu1 tu2))))
    (lua-idiom-assert-equal "multi-TU --target=vm returns 0" 0 vm-res))

  (if (file-exists? elf-bin) (delete-file elf-bin))
  (if (file-exists? c-bin) (delete-file c-bin))
  (if (file-exists? obj1) (delete-file obj1))
  (if (file-exists? obj2) (delete-file obj2))
  (if (file-exists? tu1) (delete-file tu1))
  (if (file-exists? tu2) (delete-file tu2))
  (if (file-exists? tmp-dir) (process-exec (list "rmdir" tmp-dir))))

(display "Summary: ")
(display (car *lua-idiom-pass*))
(display " passed, ")
(display (car *lua-idiom-fail*))
(display " failed.\n")
(if (> (car *lua-idiom-fail*) 0)
    (exit 1))
