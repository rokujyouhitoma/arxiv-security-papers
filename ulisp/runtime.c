#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <ucontext.h>
#include <execinfo.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>

/* =======================================================================
 * [DEPRECATED / LEGACY REFERENCE ONLY]
 * ULisp Thin Debug Runtime (Conforms to DSN-33 / Issue 494)
 * NOTE: As of Issue 516 / DSN-36, ULisp has fully transitioned to a 100%
 * Pure Scheme Bare-Metal Freestanding architecture (-nostdlib -static).
 * All I/O, memory mapping (mmap), and formatting are now performed natively
 * via Scheme (lib/posix.scm) and assembly syscalls without C or libc.
 * This file is retained only for legacy reference and debugging fallback.
 * ======================================================================= */

static void crash_handler(int sig, siginfo_t *info, void *ucontext) {
    ucontext_t *uc = (ucontext_t *)ucontext;
#if defined(__x86_64__)
    uint64_t rip = uc->uc_mcontext.gregs[REG_RIP];
    uint64_t rsp = uc->uc_mcontext.gregs[REG_RSP];
    uint64_t rax = uc->uc_mcontext.gregs[REG_RAX];
    uint64_t rdx = uc->uc_mcontext.gregs[REG_RDX];
    fprintf(stderr, "*** CRASH: signal %d at fault addr %p (RIP=0x%lx, RSP=0x%lx, RAX=0x%lx, RDX=0x%lx) ***\n",
            sig, info->si_addr, rip, rsp, rax, rdx);
    fprintf(stderr, "=== STACK DUMP AT CRASH (RSP=0x%lx) ===\n", rsp);
    uint64_t *sp = (uint64_t *)rsp;
    for (int i = -8; i < 16; i++) {
        fprintf(stderr, "  [RSP%+4d (0x%lx)]: 0x%016lx\n", i*8, (uint64_t)&sp[i], sp[i]);
    }
#elif defined(__aarch64__)
    uint64_t pc = (uint64_t)uc->uc_mcontext.pc;
    uint64_t sp_val = (uint64_t)uc->uc_mcontext.sp;
    uint64_t x0 = (uint64_t)uc->uc_mcontext.regs[0];
    uint64_t x1 = (uint64_t)uc->uc_mcontext.regs[1];
    fprintf(stderr, "*** CRASH: signal %d at fault addr %p (PC=0x%lx, SP=0x%lx, X0=0x%lx, X1=0x%lx) ***\n",
            sig, info->si_addr, pc, sp_val, x0, x1);
    fprintf(stderr, "=== STACK DUMP AT CRASH (SP=0x%lx) ===\n", sp_val);
    uint64_t *sp = (uint64_t *)sp_val;
    for (int i = -8; i < 16; i++) {
        fprintf(stderr, "  [SP%+4d (0x%lx)]: 0x%016lx\n", i*8, (uint64_t)&sp[i], sp[i]);
    }
#else
    fprintf(stderr, "*** CRASH: signal %d at fault addr %p ***\n", sig, info->si_addr);
#endif
    void *bt[32];
    int size = backtrace(bt, 32);
    backtrace_symbols_fd(bt, size, 2);

    exit(139);
}

#define FIXNUM_MASK     0x03
#define FIXNUM_TAG      0x00
#define FIXNUM_SHIFT    2

#define PAIR_MASK       0x03
#define PAIR_TAG        0x01

#define STRING_MASK     0x03
#define STRING_TAG      0x03

#define CHAR_MASK       0xFF
#define CHAR_TAG        0x0E
#define CHAR_SHIFT      8

#define SYMBOL_MASK     0xFF
#define SYMBOL_TAG      0x02
#define SYMBOL_SHIFT    8

#define BOOL_FALSE      0x2F
#define BOOL_TRUE       0x6F
#define EMPTY_LIST      0x3F
#define EOF_OBJECT      0x4F

#define HEAP_SIZE       (16384ULL * 1024 * 1024)

/* Static Generational GC state buffer (16 words):
 * [0]: nursery_base, [1]: nursery_size, [2]: mature_from, [3]: mature_to
 * [4]: mature_size, [5]: mature_free, [6]: stack_bottom, [7]: gc_minor_count
 * [8]: gc_major_count, [9]: remset_ptr, [10]: remset_count, [11]: generational_mode
 */
uint64_t ulisp_gc_state[16];

/* Minimal write barrier hook for C debug runtime (conforms to DSN-33 / Issue 525) */
__attribute__((weak)) void ulisp_gc_write_barrier(uint64_t mature_obj_addr, uint64_t val) {
    if (ulisp_gc_state[11] == 1) { /* generational mode */
        uint64_t n_base = ulisp_gc_state[0];
        uint64_t n_size = ulisp_gc_state[1];
        uint64_t val_addr = val & ~7ULL;
        if (val_addr >= n_base && val_addr < (n_base + n_size)) {
            uint64_t *remset = (uint64_t *)ulisp_gc_state[9];
            uint64_t count = ulisp_gc_state[10];
            if (remset && count < 4096) {
                remset[count] = mature_obj_addr;
                ulisp_gc_state[10] = count + 1;
            }
        }
    }
}

/* Stackmap metadata table exported from compiler in .rodata */
__attribute__((weak)) uint64_t __ulisp_stackmap_table[1] = {0};

/* Minimal I/O Primitives bound directly to libc stdin/stdout */
__attribute__((weak)) uint64_t ulisp_read_char(void) {
    int c = getchar();
    if (c == EOF) return EOF_OBJECT;
    return ((uint64_t)c << CHAR_SHIFT) | CHAR_TAG;
}

__attribute__((weak)) uint64_t ulisp_peek_char(void) {
    int c = getchar();
    if (c == EOF) return EOF_OBJECT;
    ungetc(c, stdin);
    return ((uint64_t)c << CHAR_SHIFT) | CHAR_TAG;
}

__attribute__((weak)) uint64_t ulisp_write_char(uint64_t val) {
    char c = (char)(val >> CHAR_SHIFT);
    putchar(c);
    return BOOL_TRUE;
}

__attribute__((weak)) uint64_t ulisp_flush(void) {
    fflush(stdout);
    return BOOL_TRUE;
}

__attribute__((weak)) uint64_t ulisp_emit_str(const char *s) {
    if (s) fputs(s, stdout);
    return BOOL_TRUE;
}

__attribute__((weak)) uint64_t ulisp_write_string(uint64_t val) {
    const char *s = (const char *)(val - STRING_TAG);
    if (s) fputs(s, stdout);
    return BOOL_TRUE;
}

/* Minimal Debug Value Formatter for Test Assertion */
extern uint64_t scheme_entry(char *heap_base);

static void print_scheme_value_raw(uint64_t val);

static void print_pair_elements(uint64_t p) {
    int first = 1;
    while ((p & PAIR_MASK) == PAIR_TAG) {
        uint64_t *ptr = (uint64_t *)(p - 1);
        if (!first) printf(" ");
        first = 0;
        print_scheme_value_raw(ptr[0]);
        p = ptr[1];
    }
    if (p != EMPTY_LIST) {
        printf(" . ");
        print_scheme_value_raw(p);
    }
}

static void print_scheme_value_raw(uint64_t val) {
    if ((val & FIXNUM_MASK) == FIXNUM_TAG) {
        printf("%ld", ((int64_t)val) >> FIXNUM_SHIFT);
    } else if (val == BOOL_FALSE) {
        printf("#f");
    } else if (val == BOOL_TRUE) {
        printf("#t");
    } else if (val == EMPTY_LIST) {
        printf("()");
    } else if (val == EOF_OBJECT) {
        printf("#<eof>");
    } else if ((val & CHAR_MASK) == CHAR_TAG) {
        char c = (char)(val >> CHAR_SHIFT);
        switch (c) {
            case '\n': printf("#\\newline"); break;
            case ' ':  printf("#\\space"); break;
            case '\t': printf("#\\tab"); break;
            default:   printf("#\\%c", c); break;
        }
    } else if ((val & PAIR_MASK) == PAIR_TAG) {
        printf("(");
        print_pair_elements(val);
        printf(")");
    } else if ((val & STRING_MASK) == STRING_TAG) {
        printf("\"%s\"", (const char *)(val - STRING_TAG));
    } else if ((val & SYMBOL_MASK) == SYMBOL_TAG) {
        printf("#<symbol-%ld>", val >> SYMBOL_SHIFT);
    } else {
        printf("#<unknown: 0x%lx>", val);
    }
}

static void print_scheme_value(uint64_t val) {
    print_scheme_value_raw(val);
    printf("\n");
}

int main(int argc, char **argv) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = crash_handler;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGSEGV, &sa, NULL);

    int quiet = 0;
    if (getenv("ULISP_QUIET") != NULL) {
        quiet = 1;
    }
    if (argc > 1) {
        quiet = 1;
        int fd = open(argv[1], O_RDONLY);
        if (fd < 0) {
            perror(argv[1]);
            return 1;
        }
        if (dup2(fd, STDIN_FILENO) < 0) {
            perror("dup2");
            close(fd);
            return 1;
        }
        close(fd);
    }

    char *heap = (char *)mmap(NULL, HEAP_SIZE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (heap == MAP_FAILED) {
        fprintf(stderr, "Failed to mmap %zu bytes of heap\n", (size_t)HEAP_SIZE);
        return 1;
    }

    uint64_t result = scheme_entry(heap);
    if (!quiet) {
        print_scheme_value(result);
    }

    munmap(heap, HEAP_SIZE);
    return 0;
}
