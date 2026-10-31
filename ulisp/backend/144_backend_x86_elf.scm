;;; =======================================================================
;;; ULisp Compiler Pass 144: Direct ELF64 Static Executable Generator
;;; Conforms to DSN-33 Architecture Specification & Issue #616
;;;
;;; Combines Pass 140 (x86-64 instruction selection & emission),
;;; Pass 144a (native 2-pass x86-64 machine code assembler),
;;; and Layer 2 (ELF64 static binary builder) to emit standalone ET_EXEC
;;; binaries directly from memory, eliminating GNU binutils (as, ld).
;;; =======================================================================

(define (with-emit-line-sink sink thunk)
  (let ((prev (get-emit-line-sink)))
    (set-emit-line-sink! sink)
    (let ((res (thunk)))
      (set-emit-line-sink! prev)
      res)))

(define (write-elf64-bytevector bv)
  (let loop ((i 0) (len (bytevector-length bv)))
    (if (< i len)
        (begin
          (write-char (integer->char (bytevector-u8-ref bv i)))
          (loop (+ i 1) len))
        (flush-output-port))))

;;; -----------------------------------------------------------------------
;;; Public Utility: Assemble assembly lines directly into ELF bytevector
;;; -----------------------------------------------------------------------
(define (assemble-and-build-elf lines)
  (let* ((assembled (assemble-x86-lines lines))
         (text-bv (car assembled))
         (rodata-bv (cadr assembled))
         (data-bv (caddr assembled))
         (bss-size (cadddr assembled))
         (entry-off (car (cddddr assembled)))
         (file-table (if (> (length assembled) 5) (list-ref assembled 5) '()))
         (line-table (if (> (length assembled) 6) (list-ref assembled 6) '()))
         (sym-table (if (> (length assembled) 7) (list-ref assembled 7) '()))
         (debug-payload (if (or (pair? file-table) (pair? line-table))
                            (list file-table line-table sym-table)
                            #f)))
    (build-elf64-executable-ex text-bv rodata-bv data-bv bss-size entry-off debug-payload)))

;;; -----------------------------------------------------------------------
;;; Pass 144 Entrypoint: Direct-to-ELF Native Code Generator
;;; -----------------------------------------------------------------------
(define (emit-x86-64-elf prog gc-mode)
  (let ((lines-box (vector '())))
    (with-emit-line-sink
      (lambda (line)
        (vector-set! lines-box 0 (cons line (vector-ref lines-box 0))))
      (lambda ()
        (emit-x86-64 prog gc-mode)))
    (let* ((asm-lines (reverse (vector-ref lines-box 0)))
           (elf-bv (assemble-and-build-elf asm-lines)))
      (write-elf64-bytevector elf-bv)
      elf-bv)))
