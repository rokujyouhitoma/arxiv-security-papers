#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <ucontext.h>
#include <execinfo.h>

static void crash_handler(int sig, siginfo_t *info, void *ucontext) {
    ucontext_t *uc = (ucontext_t *)ucontext;
    uint64_t rip = uc->uc_mcontext.gregs[REG_RIP];
    uint64_t rsp = uc->uc_mcontext.gregs[REG_RSP];
    uint64_t rax = uc->uc_mcontext.gregs[REG_RAX];
    uint64_t rdx = uc->uc_mcontext.gregs[REG_RDX];
    fprintf(stderr, "*** CRASH: signal %d at fault addr %p (RIP=0x%lx, RSP=0x%lx, RAX=0x%lx, RDX=0x%lx) ***\n",
            sig, info->si_addr, rip, rsp, rax, rdx);
    void *bt[32];
    int size = backtrace(bt, 32);
    
    fprintf(stderr, "=== STACK DUMP AT CRASH (RSP=0x%lx) ===\n", rsp);
    uint64_t *sp = (uint64_t *)rsp;
    for (int i = -8; i < 16; i++) {
        fprintf(stderr, "  [RSP%+4d (0x%lx)]: 0x%016lx\n", i*8, (uint64_t)&sp[i], sp[i]);
    }
    backtrace_symbols_fd(bt, size, 2);

    exit(139);
}

#define FIXNUM_MASK     0x03
#define FIXNUM_TAG      0x00
#define FIXNUM_SHIFT    2

#define PAIR_MASK       0x03
#define PAIR_TAG        0x01

#define CHAR_MASK       0xFF
#define CHAR_TAG        0x0E
#define CHAR_SHIFT      8

#define BOOL_FALSE      0x2F
#define BOOL_TRUE       0x6F
#define EMPTY_LIST      0x3F
#define EOF_OBJECT      0x4F

#define HEAP_SIZE       (128 * 1024 * 1024)

uint64_t ulisp_read_char(void) {
    int c = getchar();
    if (c == EOF) {
        return EOF_OBJECT;
    }
    return ((uint64_t)c << CHAR_SHIFT) | CHAR_TAG;
}

uint64_t ulisp_peek_char(void) {
    int c = getchar();
    if (c == EOF) {
        return EOF_OBJECT;
    }
    ungetc(c, stdin);
    return ((uint64_t)c << CHAR_SHIFT) | CHAR_TAG;
}

uint64_t ulisp_write_char(uint64_t val) {
    char c;
    if ((val & CHAR_MASK) == CHAR_TAG) {
        c = (char)(val >> CHAR_SHIFT);
    } else if ((val & FIXNUM_MASK) == FIXNUM_TAG) {
        c = (char)(val >> FIXNUM_SHIFT);
    } else {
        c = (char)val;
    }
    putchar(c);
    return BOOL_TRUE;
}

#define STRING_MASK     0x03
#define STRING_TAG      0x03

#define SYMBOL_MASK     0xFF
#define SYMBOL_TAG      0x02
#define SYMBOL_SHIFT    8

static struct {
    char *name;
    uint64_t id;
} g_symbols[1024];
static int g_num_symbols = 0;

static void print_scheme_value_raw(uint64_t val);

uint64_t ulisp_display(uint64_t val) {
    if ((val & STRING_MASK) == STRING_TAG) {
        fputs((const char *)(val - STRING_TAG), stdout);
    } else if ((val & SYMBOL_MASK) == SYMBOL_TAG) {
        for (int i = 0; i < g_num_symbols; i++) {
            if (g_symbols[i].id == val) {
                fputs(g_symbols[i].name, stdout);
                return BOOL_TRUE;
            }
        }
        printf("#<symbol-%ld>", val >> SYMBOL_SHIFT);
    } else {
        print_scheme_value_raw(val);
    }
    return BOOL_TRUE;
}

uint64_t ulisp_newline(void) {
    putchar('\n');
    return BOOL_TRUE;
}

uint64_t ulisp_string_append2(uint64_t s1, uint64_t s2) {
    const char *str1 = (const char *)(s1 - STRING_TAG);
    const char *str2 = (const char *)(s2 - STRING_TAG);
    size_t len1 = strlen(str1);
    size_t len2 = strlen(str2);
    char *buf = (char *)malloc(len1 + len2 + 1);
    memcpy(buf, str1, len1);
    memcpy(buf + len1, str2, len2);
    buf[len1 + len2] = '\0';
    return ((uint64_t)buf) | STRING_TAG;
}

uint64_t ulisp_number_to_string(uint64_t val) {
    int64_t num = ((int64_t)val) >> FIXNUM_SHIFT;
    char *buf = (char *)malloc(32);
    snprintf(buf, 32, "%ld", num);
    return ((uint64_t)buf) | STRING_TAG;
}

static uint64_t intern_c_symbol(const char *name) {
    for (int i = 0; i < g_num_symbols; i++) {
        if (strcmp(g_symbols[i].name, name) == 0) {
            return g_symbols[i].id;
        }
    }
    uint64_t id = ((uint64_t)g_num_symbols << SYMBOL_SHIFT) | SYMBOL_TAG;
    g_symbols[g_num_symbols].name = strdup(name);
    g_symbols[g_num_symbols].id = id;
    g_num_symbols++;
    return id;
}

uint64_t ulisp_string_to_symbol(uint64_t s) {
    const char *name = (const char *)(s - STRING_TAG);
    return intern_c_symbol(name);
}

uint64_t ulisp_symbol_to_string(uint64_t sym) {
    for (int i = 0; i < g_num_symbols; i++) {
        if (g_symbols[i].id == sym) {
            return ((uint64_t)g_symbols[i].name) | STRING_TAG;
        }
    }
    static const char unk[] __attribute__((aligned(8))) = "unknown";
    return ((uint64_t)unk) | STRING_TAG;
}

static int skip_whitespace_and_comments(void) {
    int c;
    while ((c = getchar()) != EOF) {
        if (c == ';') {
            while ((c = getchar()) != EOF && c != '\n');
        } else if (c > 32) {
            return c;
        }
    }
    return EOF;
}

uint64_t ulisp_read(void) {
    int c = skip_whitespace_and_comments();
    if (c == EOF) {
        return EOF_OBJECT;
    }
    if (c == '(') {
        c = skip_whitespace_and_comments();
        if (c == ')') return EMPTY_LIST;
        if (c == EOF) return EOF_OBJECT;
        ungetc(c, stdin);
        
        uint64_t head = EMPTY_LIST;
        uint64_t tail = EMPTY_LIST;
        
        while (1) {
            c = skip_whitespace_and_comments();
            if (c == ')') break;
            if (c == '.') {
                uint64_t cdr_val = ulisp_read();
                skip_whitespace_and_comments(); // consume ')'
                if (tail != EMPTY_LIST) {
                    ((uint64_t *)(tail - 1))[1] = cdr_val;
                }
                break;
            }
            ungetc(c, stdin);
            uint64_t elem = ulisp_read();
            uint64_t *pair = (uint64_t *)malloc(16);
            pair[0] = elem;
            pair[1] = EMPTY_LIST;
            uint64_t p_tag = ((uint64_t)pair) | PAIR_TAG;
            if (head == EMPTY_LIST) {
                head = p_tag;
            } else {
                ((uint64_t *)(tail - 1))[1] = p_tag;
            }
            tail = p_tag;
        }
        return head;
    }
    if (c == '\'') {
        uint64_t datum = ulisp_read();
        uint64_t q_sym = intern_c_symbol("quote");
        uint64_t *p2 = (uint64_t *)malloc(16);
        p2[0] = datum; p2[1] = EMPTY_LIST;
        uint64_t *p1 = (uint64_t *)malloc(16);
        p1[0] = q_sym; p1[1] = ((uint64_t)p2) | PAIR_TAG;
        return ((uint64_t)p1) | PAIR_TAG;
    }
    if (c == '"') {
        char buf[4096];
        int len = 0;
        while ((c = getchar()) != EOF && c != '"' && len < 4095) {
            if (c == '\\') {
                int next = getchar();
                if (next == 'n') c = '\n';
                else if (next == 't') c = '\t';
                else if (next == 'r') c = '\r';
                else c = next;
            }
            buf[len++] = c;
        }
        buf[len] = '\0';
        char *str = strdup(buf);
        return ((uint64_t)str) | STRING_TAG;
    }
    if (c == '#') {
        int c2 = getchar();
        if (c2 == 't') return BOOL_TRUE;
        if (c2 == 'f') return BOOL_FALSE;
        if (c2 == '\\') {
            char name[64];
            int nlen = 0;
            int ch;
            while ((ch = getchar()) != EOF && ch > 32 && ch != '(' && ch != ')' && nlen < 63) {
                name[nlen++] = ch;
            }
            if (ch != EOF) ungetc(ch, stdin);
            name[nlen] = '\0';
            if (nlen == 1) return ((uint64_t)name[0] << CHAR_SHIFT) | CHAR_TAG;
            if (strcmp(name, "space") == 0) return ((uint64_t)' ' << CHAR_SHIFT) | CHAR_TAG;
            if (strcmp(name, "newline") == 0) return ((uint64_t)'\n' << CHAR_SHIFT) | CHAR_TAG;
            if (strcmp(name, "tab") == 0) return ((uint64_t)'\t' << CHAR_SHIFT) | CHAR_TAG;
            return ((uint64_t)name[0] << CHAR_SHIFT) | CHAR_TAG;
        }
    }
    char tok[1024];
    int tlen = 0;
    tok[tlen++] = c;
    while ((c = getchar()) != EOF && c > 32 && c != '(' && c != ')' && c != ';' && tlen < 1023) {
        tok[tlen++] = c;
    }
    if (c != EOF) ungetc(c, stdin);
    tok[tlen] = '\0';

    char *endptr;
    long num = strtol(tok, &endptr, 10);
    if (*endptr == '\0' && (tok[0] != '-' || tlen > 1)) {
        return (uint64_t)(num << FIXNUM_SHIFT);
    }
    return intern_c_symbol(tok);
}

/* Scheme entry point emitted by ULisp compiler */
extern uint64_t scheme_entry(char *heap_base);

static void print_scheme_value_raw(uint64_t val);

static void print_pair_elements(uint64_t p) {
    int first = 1;
    while ((p & PAIR_MASK) == PAIR_TAG) {
        uint64_t *ptr = (uint64_t *)(p - 1);
        if (!first) {
            printf(" ");
        }
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
    } else {
        
        if ((val & SYMBOL_MASK) == SYMBOL_TAG) {
            for (int i = 0; i < g_num_symbols; i++) {
                if (g_symbols[i].id == val) {
                    printf("%s", g_symbols[i].name);
                    return;
                }
            }
            printf("#<symbol-%ld>", val >> SYMBOL_SHIFT);
        } else {
            printf("#<unknown-value: 0x%lx>", val);
        }

    }
}

uint64_t ulisp_escape_gas_string(uint64_t s) {
    if ((s & STRING_MASK) != STRING_TAG) return s;
    const char *src = (const char *)(s - STRING_TAG);
    size_t len = strlen(src);
    char *buf = (char *)malloc(len * 4 + 1);
    char *dst = buf;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)src[i];
        if (c == '\n') { *dst++ = '\\'; *dst++ = 'n'; }
        else if (c == '\t') { *dst++ = '\\'; *dst++ = 't'; }
        else if (c == '\r') { *dst++ = '\\'; *dst++ = 'r'; }
        else if (c == '\\') { *dst++ = '\\'; *dst++ = '\\'; }
        else if (c == '"')  { *dst++ = '\\'; *dst++ = '"'; }
        else { *dst++ = c; }
    }
    *dst = '\0';
    return ((uint64_t)buf) | STRING_TAG;
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
        fprintf(stderr, "Failed to allocate %d bytes of heap\n", HEAP_SIZE);
        return 1;
    }

    uint64_t result = scheme_entry(heap);
    if (!quiet) {
        print_scheme_value(result);
    }

    free(heap);
    return 0;
}
