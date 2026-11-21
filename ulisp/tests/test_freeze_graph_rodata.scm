;;; =======================================================================
;;; Test Suite: Freeze Graph Serialization & .rodata Bloat Guard (Issue #883)
;;; Conforms to DSN-33-03 §7.3
;;; =======================================================================

(display "\n=== [Test Suite: Freeze Graph Serialization & .rodata Bloat Guard (Issue #883)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Non-cyclic Data Structure Freezing
;;; -----------------------------------------------------------------------
(display "--- Group 1: Non-cyclic Data Structure Freezing ---\n")

(let* ((data '(1 2 (3 4 "hello" #(5 6))))
       (frozen (freeze! data)))
  (assert-equal "1.1 Acyclic list structure preserved"
                data
                frozen))

(let* ((rodata (freeze-serialize-to-rodata '(a b c) #f)))
  (assert-equal "1.2 Rodata segment header tag"
                'rodata-segment
                (car rodata))
  (assert-true "1.3 Rodata size recorded"
               (> (cdr (cadr rodata)) 0)))

;;; -----------------------------------------------------------------------
;;; Group 2: Cyclic List Graph Serialization
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Cyclic List Graph Serialization ---\n")

;; Construct a cyclic list: x = (1 2 . x)
(let* ((cell (cons 2 '()))
       (cycle-list (cons 1 cell)))
  (set-cdr! cell cycle-list) ; create cycle!
  ;; Without freeze! with visited set, traversing cycle-list would loop infinitely
  (let ((frozen-cycle (freeze! cycle-list)))
    (assert-equal "2.1 Head element preserved"
                  1
                  (car frozen-cycle))
    (assert-equal "2.2 Second element preserved"
                  2
                  (car (cdr frozen-cycle)))
    ;; Cycle reference placeholder should be placed at the tail
    (assert-equal "2.3 Cycle back-edge resolved as cycle-ref placeholder"
                  '(cycle-ref 1)
                  (cdr (cdr frozen-cycle)))))

;;; -----------------------------------------------------------------------
;;; Group 3: Self-referential Vector Freezing
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Self-referential Vector Freezing ---\n")

(let ((vec (make-vector 2)))
  (vector-set! vec 0 42)
  (vector-set! vec 1 vec) ; self-reference!
  (let ((frozen-vec (freeze! vec)))
    (assert-equal "3.1 Vector element 0 preserved"
                  42
                  (vector-ref frozen-vec 0))
    (assert-equal "3.2 Vector self-reference resolved to cycle-ref"
                  '(cycle-ref 1)
                  (vector-ref frozen-vec 1))))

;;; -----------------------------------------------------------------------
;;; Group 4: .rodata Size Limit Bloat Guard (E-RODATA-OVERFLOW)
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: .rodata Size Limit Bloat Guard ---\n")

;; Normal small size limit pass
(let ((small-rodata (freeze-serialize-to-rodata '(x y z) 1000)))
  (assert-equal "4.1 Rodata serialization under limit succeeds"
                'rodata-segment
                (car small-rodata)))

;; Exceeding size limit triggers E-RODATA-OVERFLOW
(let ((orig-abort (car *compiler-abort-on-error*))
      (orig-suppress (car *compiler-suppress-diagnostics*)))
  (set-car! *compiler-abort-on-error* #f)
  (set-car! *compiler-suppress-diagnostics* #t)
  ;; Pass an artificially small max-size (10 bytes) for a large list
  (let ((res (freeze-serialize-to-rodata '(1 2 3 4 5 6 7 8 9 10 "large payload string") 16)))
    (set-car! *compiler-abort-on-error* orig-abort)
    (set-car! *compiler-suppress-diagnostics* orig-suppress)
    (assert-true "4.2 Rodata size limit overflow triggers safe error interception"
                 (number? res))))

;;; -----------------------------------------------------------------------
;;; Group 5: Binary Bytevector Packaging for Frozen .rodata (Issue #890)
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Binary Bytevector Packaging for Frozen .rodata ---\n")

;; 5.1 Primitive & constant bytevector packing
(let* ((ro (freeze-serialize-to-rodata '(1 2 "hello" #(3 4)) #f))
       (bv (freeze-serialized->bytevector ro)))
  (assert-true "5.1 Bytevector produced from rodata segment"
               (bytevector? bv))
  (assert-true "5.2 Bytevector length contains header and payload"
               (>= (bytevector-length bv) 16))
  ;; Check magic header: 'ULFRZDAT'
  (assert-equal "5.3 Magic header byte 0 ('U')" #x55 (bytevector-u8-ref bv 0))
  (assert-equal "5.4 Magic header byte 1 ('L')" #x4C (bytevector-u8-ref bv 1))
  (assert-equal "5.5 Magic header byte 2 ('F')" #x46 (bytevector-u8-ref bv 2))
  (assert-equal "5.6 Magic header byte 7 ('T')" #x54 (bytevector-u8-ref bv 7)))

;; 5.2 Cyclic list graph bytevector packaging
(let* ((cell (cons 2 '()))
       (cycle-list (cons 1 cell)))
  (set-cdr! cell cycle-list)
  (let* ((ro (freeze-serialize-to-rodata cycle-list #f))
         (bv (freeze-serialized->bytevector ro)))
    (assert-true "5.7 Cyclic list packaged into bytevector without infinite loop"
                 (bytevector? bv))
    (assert-true "5.8 Cyclic bytevector size valid"
                 (> (bytevector-length bv) 16))))

;; 5.3 E-RODATA-OVERFLOW guard in freeze-serialized->bytevector
(let ((orig-abort (car *compiler-abort-on-error*))
      (orig-suppress (car *compiler-suppress-diagnostics*)))
  (set-car! *compiler-abort-on-error* #f)
  (set-car! *compiler-suppress-diagnostics* #t)
  (let ((res (freeze-serialized->bytevector (list 'rodata-segment '(size . 1000) '(max-limit . 10) '(payload . ())))))
    (set-car! *compiler-abort-on-error* orig-abort)
    (set-car! *compiler-suppress-diagnostics* orig-suppress)
    (assert-true "5.9 Overflow in freeze-serialized->bytevector safely intercepted"
                 (number? res))))

;;; -----------------------------------------------------------------------
;;; Group 6: ELF .rodata Linker Integration & Symbol Binding (Issue #890)
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: ELF .rodata Linker Integration & Symbol Binding ---\n")

;; 6.1 elf64-append-rodata-payload 16-byte alignment
(let* ((orig (make-bytevector 7 65))       ; 7 bytes of 'A'
       (payload (make-bytevector 10 66))    ; 10 bytes of 'B'
       (app-res (elf64-append-rodata-payload-with-offset orig payload))
       (merged (car app-res))
       (offset (cdr app-res)))
  (assert-equal "6.1 Appended offset aligned to 16 bytes"
                16
                offset)
  (assert-equal "6.2 Total merged length is 16 + 10 = 26"
                26
                (bytevector-length merged))
  (assert-equal "6.3 Original bytes preserved at start"
                65
                (bytevector-u8-ref merged 0))
  (assert-equal "6.4 Padding byte zeroed"
                0
                (bytevector-u8-ref merged 7))
  (assert-equal "6.5 Payload byte placed at aligned offset"
                66
                (bytevector-u8-ref merged 16)))

;; 6.2 elf64-append-rodata-payload handles empty orig
(let* ((payload (make-bytevector 8 42))
       (merged (elf64-append-rodata-payload (make-bytevector 0) payload)))
  (assert-equal "6.6 Appending to empty rodata keeps payload length"
                8
                (bytevector-length merged)))

;; 6.3 E2E ELF executable generation with frozen .rodata and symbol binding
(let* ((lines '(".globl _start"
                ".text"
                "_start:"
                "mov $60, %rax"
                "mov $42, %rdi"
                "syscall"))
       (frozen (freeze-serialize-to-rodata '(100 200 "static-data") #f))
       (elf-bv (assemble-and-build-elf-with-rodata lines frozen)))
  (assert-true "6.7 ELF bytevector generated successfully"
               (bytevector? elf-bv))
  (assert-true "6.8 ELF bytevector exceeds header size"
               (> (bytevector-length elf-bv) 256))
  ;; Check ELF magic: \x7fELF
  (assert-equal "6.9 ELF magic byte 0" 127 (bytevector-u8-ref elf-bv 0))
  (assert-equal "6.10 ELF magic byte 1 ('E')" 69 (bytevector-u8-ref elf-bv 1))
  (assert-equal "6.11 ELF magic byte 2 ('L')" 76 (bytevector-u8-ref elf-bv 2))
  (assert-equal "6.12 ELF magic byte 3 ('F')" 70 (bytevector-u8-ref elf-bv 3)))

(display "\n[RESULT] All Freeze Graph Serialization & .rodata Bloat Guard tests PASSED!\n")
