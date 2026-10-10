#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <ucontext.h>
#include <execinfo.h>

/* =======================================================================
 * ULisp Thin Debug Runtime (Conforms to DSN-33 / Issue 494)
 * Minimal C cushion providing crash backtraces and basic I/O primitives.
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

#define HEAP_SIZE       (8192ULL * 1024 * 1024)

/* Static GC state buffer: from, to, size, bottom, count */
uint64_t ulisp_gc_state[8];

/* Minimal 3 I/O Primitives bound directly to libc stdin/stdout */
uint64_t ulisp_read_char(void) {
    int c = getchar();
    if (c == EOF) return EOF_OBJECT;
    return ((uint64_t)c << CHAR_SHIFT) | CHAR_TAG;
}

uint64_t ulisp_peek_char(void) {
    int c = getchar();
    if (c == EOF) return EOF_OBJECT;
    ungetc(c, stdin);
    return ((uint64_t)c << CHAR_SHIFT) | CHAR_TAG;
}

uint64_t ulisp_write_char(uint64_t val) {
    char c = (char)(val >> CHAR_SHIFT);
    putchar(c);
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
        if (!freopen(argv[1], "r", stdin)) {
            perror(argv[1]);
            return 1;
        }
    }

    char *heap = (char *)malloc(HEAP_SIZE);
    if (!heap) {
        fprintf(stderr, "Failed to allocate %zu bytes of heap\n", (size_t)HEAP_SIZE);
        return 1;
    }

    uint64_t result = scheme_entry(heap);
    if (!quiet) {
        print_scheme_value(result);
    }

    free(heap);
    return 0;
}
