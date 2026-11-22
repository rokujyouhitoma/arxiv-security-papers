;;; =======================================================================
;;; test_c99_pointers_and_escape.scm - C99 Pointer Scaling, Array Decay & Escape Analysis (Issue #919)
;;;
;;; Validates:
;;; 1. ISO C99 §6.3.2.1p3 Array-to-Pointer Decay and 3 Exceptions (sizeof, _Alignof, &)
;;; 2. Multidimensional array indexing, pointers to arrays, and subscript symmetry (i[a] == a[i])
;;; 3. Pointer arithmetic scaling by element size (char, short, int, long, struct)
;;; 4. Pointer difference (p1 - p2) yielding signed 64-bit ptrdiff_t (positive and negative)
;;; 5. Pointer increments, decrements, and compound assignments (++, --, +=, -=)
;;; 6. Pointer comparisons (<, <=, >, >=, ==, !=) and NULL pointer checks
;;; 7. Static escape analysis (c99-collect-escaped-bindings) and Pass 132 Braun SSA mem2reg protection
;;; 8. Semantic diagnostics (C99-PTR-001, C99-PTR-002, C99-PTR-003, C99-PTR-004)
;;; =======================================================================

(define *tests-passed* 0)
(define *tests-failed* 0)

(define (assert-true desc val)
  (if val
      (begin
        (set! *tests-passed* (+ *tests-passed* 1))
        (display "  [PASS] ") (display desc) (newline))
      (begin
        (set! *tests-failed* (+ *tests-failed* 1))
        (display "  [FAIL] ") (display desc) (newline)
        (error "Assertion failed: expected #t" desc))))

(define (assert-equal desc expected actual)
  (if (equal? expected actual)
      (begin
        (set! *tests-passed* (+ *tests-passed* 1))
        (display "  [PASS] ") (display desc) (newline))
      (begin
        (set! *tests-failed* (+ *tests-failed* 1))
        (display "  [FAIL] ") (display desc)
        (display " (expected ") (write expected)
        (display ", got ") (write actual) (display ")") (newline)
        (error "Assertion failed: values not equal" desc))))

(define (c99-run-code src)
  (let* ((lir (c99-compile-string-to-lir src "<test-code>"))
         (res (eval-lir-program lir)))
    res))

(define (c99-expect-error err-code src)
  (guard (ex
          ((and (pair? ex) (pair? (cdr ex)) (equal? (cadr ex) err-code))
           #t)
          (else
           (display "  [UNEXPECTED ERROR] Expected ") (display err-code)
           (display ", got: ") (write ex) (newline)
           #f))
    (let* ((ast (parse-c99-preprocessed-string src "<test-error>"))
           (typed (c99-analyze-program ast)))
      (c99-lower-to-lir typed)
      #f)))

(display "=== [Test Suite: C99 Pointer Scaling, Array Decay & Escape Analysis (Issue #919)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Array-to-Pointer Decay & 3 Exceptions (ISO C99 §6.3.2.1p3)
;;; -----------------------------------------------------------------------
(display "--- Group 1: Array-to-Pointer Decay & 3 Exceptions ---\n")

(assert-equal "1.1 Array decays to pointer in expression"
  60
  (c99-run-code "
int main(void) {
    int arr[3] = {10, 20, 30};
    int *p = arr;
    return *p + *(p + 1) + *(p + 2);
}"))

(assert-equal "1.2 Exception 1: sizeof(arr) yields total array byte size"
  16
  (c99-run-code "
int main(void) {
    int arr[4] = {1, 2, 3, 4};
    return sizeof(arr);
}"))

(assert-equal "1.3 Exception 2: _Alignof(arr) yields element alignment"
  4
  (c99-run-code "
int main(void) {
    int arr[4];
    return _Alignof(arr);
}"))

(assert-equal "1.4 Exception 3: &arr yields pointer to array (int (*)[3])"
  20
  (c99-run-code "
int main(void) {
    int arr[3] = {10, 20, 30};
    int (*parr)[3] = &arr;
    return (*parr)[1];
}"))

(assert-equal "1.5 Multidimensional array sizeof hierarchy"
  48
  (c99-run-code "
int main(void) {
    int m[3][4];
    if (sizeof(m) != 48) return 1;
    if (sizeof(m[0]) != 16) return 2;
    if (sizeof(m[0][0]) != 4) return 3;
    return 48;
}"))

(assert-equal "1.6 Multidimensional array decays to pointer to array"
  15
  (c99-run-code "
int main(void) {
    int m[2][3] = {{10, 20, 30}, {40, 50, 60}};
    int (*prow)[3] = m;
    prow = prow + 1;
    return (*prow)[0] - (*prow)[1] / 2;
}"))

;;; -----------------------------------------------------------------------
;;; Group 2: Multidimensional Array Indexing & Symmetry (ISO C99 §6.5.2.1)
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Multidimensional Array Indexing & Symmetry ---\n")

(assert-equal "2.1 2D array read m[i][j]"
  77
  (c99-run-code "
int main(void) {
    int m[2][3] = {{10, 20, 30}, {40, 77, 60}};
    return m[1][1];
}"))

(assert-equal "2.2 2D array write m[i][j] = val"
  99
  (c99-run-code "
int main(void) {
    int m[2][3] = {{0, 0, 0}, {0, 0, 0}};
    m[1][2] = 99;
    return m[1][2];
}"))

(assert-equal "2.3 3D array access cube[i][j][k]"
  123
  (c99-run-code "
int main(void) {
    int cube[2][3][4];
    cube[1][2][3] = 123;
    return cube[1][2][3];
}"))

(assert-equal "2.4 Subscript symmetry: i[a] == a[i]"
  42
  (c99-run-code "
int main(void) {
    int a[5] = {10, 20, 30, 42, 50};
    return 3[a];
}"))

(assert-equal "2.5 2D subscript symmetry: j[m[i]] and 1[m][2]"
  66
  (c99-run-code "
int main(void) {
    int m[2][3] = {{11, 22, 33}, {44, 55, 66}};
    return 2[1[m]];
}"))

(assert-equal "2.6 Lvalue subscript symmetry: i[a] = val"
  88
  (c99-run-code "
int main(void) {
    int a[4] = {1, 2, 3, 4};
    2[a] = 88;
    return a[2];
}"))

(assert-equal "2.7 Array of pointers with nested indexing"
  55
  (c99-run-code "
int main(void) {
    int row0[2] = {10, 20};
    int row1[2] = {30, 55};
    int *ptrs[2];
    ptrs[0] = row0;
    ptrs[1] = row1;
    return ptrs[1][1];
}"))

;;; -----------------------------------------------------------------------
;;; Group 3: Pointer Arithmetic Scaling (ISO C99 §6.5.6)
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Pointer Arithmetic Scaling ---\n")

(assert-equal "3.1 Pointer scaling with char (sizeof = 1)"
  67
  (c99-run-code "
int main(void) {
    char s[4] = {'A', 'B', 'C', 'D'};
    char *p = s;
    return *(p + 2);
}"))

(assert-equal "3.2 Pointer scaling with short (sizeof = 2)"
  300
  (c99-run-code "
int main(void) {
    short arr[4] = {100, 200, 300, 400};
    short *p = arr;
    return *(p + 2);
}"))

(assert-equal "3.3 Pointer scaling with int (sizeof = 4)"
  3000
  (c99-run-code "
int main(void) {
    int arr[4] = {1000, 2000, 3000, 4000};
    int *p = arr;
    return *(2 + p);
}"))

(assert-equal "3.4 Pointer scaling with long (sizeof = 8)"
  70000
  (c99-run-code "
int main(void) {
    long arr[3] = {10000, 70000, 90000};
    long *p = arr + 1;
    return *p;
}"))

(assert-equal "3.5 Pointer scaling with struct (16 bytes)"
  50
  (c99-run-code "
struct Vec4 {
    int x;
    int y;
    int z;
    int w;
};
int main(void) {
    struct Vec4 pts[3];
    pts[0].x = 10;
    pts[1].y = 50;
    pts[2].z = 90;
    struct Vec4 *p = pts;
    struct Vec4 *p1 = p + 1;
    return p1->y;
}"))

(assert-equal "3.6 Pointer subtraction with integer (ptr - n)"
  20
  (c99-run-code "
int main(void) {
    int a[4] = {10, 20, 30, 40};
    int *p = &a[3];
    int *q = p - 2;
    return *q;
}"))

;;; -----------------------------------------------------------------------
;;; Group 4: Pointer Subtraction (p1 - p2 -> ptrdiff_t)
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Pointer Subtraction (ptrdiff_t) ---\n")

(assert-equal "4.1 Positive pointer difference"
  3
  (c99-run-code "
int main(void) {
    int a[5] = {1, 2, 3, 4, 5};
    int *p1 = &a[4];
    int *p2 = &a[1];
    long diff = p1 - p2;
    return (int)diff;
}"))

(assert-equal "4.2 Negative pointer difference"
  -3
  (c99-run-code "
int main(void) {
    int a[5] = {1, 2, 3, 4, 5};
    int *p1 = &a[1];
    int *p2 = &a[4];
    long diff = p1 - p2;
    return (int)diff;
}"))

(assert-equal "4.3 Struct pointer difference"
  2
  (c99-run-code "
struct Item {
    long id;
    int value;
    int flag;
};
int main(void) {
    struct Item items[4];
    struct Item *first = &items[0];
    struct Item *third = &items[2];
    return (int)(third - first);
}"))

;;; -----------------------------------------------------------------------
;;; Group 5: Pointer Increments, Decrements & Compound Assignments
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Pointer Increments, Decrements & Compound Assignments ---\n")

(assert-equal "5.1 Pointer pre-increment (++p)"
  20
  (c99-run-code "
int main(void) {
    int a[3] = {10, 20, 30};
    int *p = a;
    int *q = ++p;
    return *q;
}"))

(assert-equal "5.2 Pointer post-increment (p++)"
  10
  (c99-run-code "
int main(void) {
    int a[3] = {10, 20, 30};
    int *p = a;
    int *q = p++;
    if (*q != 10) return 1;
    if (*p != 20) return 2;
    return *q;
}"))

(assert-equal "5.3 Pointer compound assignment (p += n, p -= n)"
  30
  (c99-run-code "
int main(void) {
    int a[5] = {10, 20, 30, 40, 50};
    int *p = a;
    p += 3; // a[3] == 40
    p -= 1; // a[2] == 30
    return *p;
}"))

;;; -----------------------------------------------------------------------
;;; Group 6: Pointer Comparisons & NULL Checks
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: Pointer Comparisons & NULL Checks ---\n")

(assert-equal "6.1 Pointer relational comparison (<, <=, >, >=)"
  1
  (c99-run-code "
int main(void) {
    int a[4];
    int *p = &a[1];
    int *q = &a[3];
    if (!(p < q)) return 0;
    if (!(p <= q)) return 0;
    if (!(q > p)) return 0;
    if (!(q >= p)) return 0;
    return 1;
}"))

(assert-equal "6.2 Pointer equality and NULL comparison"
  1
  (c99-run-code "
int main(void) {
    int x = 42;
    int *p = &x;
    int *nil = 0;
    if (p == nil) return 0;
    if (nil != 0) return 0;
    if (!p) return 0;
    if (p == 0) return 0;
    return 1;
}"))

;;; -----------------------------------------------------------------------
;;; Group 7: Escape Analysis & Pass 132 Braun SSA Protection
;;; -----------------------------------------------------------------------
(display "\n--- Group 7: Escape Analysis & Pass 132 Braun SSA Protection ---\n")

(define (test-string-contains str sub)
  (let ((n (string-length str))
        (m (string-length sub)))
    (let loop ((i 0))
      (cond
        ((> (+ i m) n) #f)
        ((string=? (substring str i (+ i m)) sub) #t)
        (else (loop (+ i 1)))))))

(let* ((ast-src "
void helper(int *p) {
    *p = 777;
}
int compute(int arg) {
    int status = 0;
    helper(&status);
    int pure_local = 10;
    pure_local = pure_local + 5;
    return status + pure_local;
}")
       (ast (parse-c99-preprocessed-string ast-src "<test-escape>"))
       (typed (c99-analyze-program ast))
       (funcs (list-ref typed 2))
       (compute-fn (cadr funcs))
       (escaped (c99-collect-escaped-bindings compute-fn)))
  (assert-true "7.1 c99-collect-escaped-bindings identifies &status"
               (let loop ((xs escaped))
                 (cond
                   ((null? xs) #f)
                   ((let ((s (symbol->string (car xs))))
                      (test-string-contains s "status")) #t)
                   (else (loop (cdr xs))))))
  (assert-true "7.2 c99-collect-escaped-bindings does not include pure_local"
               (let loop ((xs escaped))
                 (cond
                   ((null? xs) #t)
                   ((let ((s (symbol->string (car xs))))
                      (test-string-contains s "pure_local")) #f)
                   (else (loop (cdr xs)))))))

(assert-equal "7.3 E2E out-parameter &status modified across function call"
  777
  (c99-run-code "
void set_val(int *out) {
    *out = 777;
}
int main(void) {
    int status = 0;
    set_val(&status);
    return status;
}"))

(assert-equal "7.4 Pointer aliasing write (*p = val) updates local variable"
  42
  (c99-run-code "
int main(void) {
    int target = 10;
    int *p = &target;
    *p = 42;
    return target;
}"))

;;; -----------------------------------------------------------------------
;;; Group 8: Semantic Diagnostics Validation (C99-PTR-001..004)
;;; -----------------------------------------------------------------------
(display "\n--- Group 8: Semantic Diagnostics Validation ---\n")

(assert-true "8.1 C99-PTR-001 on pointer addition (p1 + p2)"
  (c99-expect-error "C99-PTR-001"
    "int main(void) { int a[2]; int *p = a; int *q = a; return (int)(p + q); }"))

(assert-true "8.2 C99-PTR-001 on integer - pointer (n - ptr)"
  (c99-expect-error "C99-PTR-001"
    "int main(void) { int a[2]; int *p = a; return (int)(10 - p); }"))

(assert-true "8.3 C99-PTR-002 on incompatible pointer subtraction (int* - char*)"
  (c99-expect-error "C99-PTR-002"
    "int main(void) { int a; char c; int *p = &a; char *q = &c; return (int)(p - q); }"))

(assert-true "8.4 C99-PTR-002 on void* pointer arithmetic"
  (c99-expect-error "C99-PTR-002"
    "int main(void) { int a; void *p = &a; return *(int*)(p + 1); }"))

(assert-true "8.5 C99-PTR-003 on address of rvalue (&(x + 1))"
  (c99-expect-error "C99-PTR-003"
    "int main(void) { int x = 1; void *p = &(x + 1); return 0; }"))

(assert-true "8.6 C99-PTR-004 on incompatible pointer comparison (int* < char*)"
  (c99-expect-error "C99-PTR-004"
    "int main(void) { int a; char c; int *p = &a; char *q = &c; return p < q; }"))

(assert-true "8.7 C99-PTR-004 on pointer compared with non-zero integer"
  (c99-expect-error "C99-PTR-004"
    "int main(void) { int a; int *p = &a; return p == 100; }"))

(assert-true "8.8 C99-PTR-004 on incompatible pointer assignment without cast"
  (c99-expect-error "C99-PTR-004"
    "int main(void) { int a; char c; int *p = &c; return 0; }"))

(display "\n-------------------------------------------------------\n")
(display " [RESULT] C99 Pointers, Array Decay & Escape Analysis (Issue #919): ")
(display *tests-passed*) (display " passed, ")
(display *tests-failed*) (display " failed (Total: ")
(display (+ *tests-passed* *tests-failed*)) (display ")\n")
(display "-------------------------------------------------------\n")

(if (> *tests-failed* 0)
    (exit 1)
    (exit 0))
