/* ULisp C99 Built-in <stdlib.h> (ISO C99 §7.20 & Linux x86-64 glibc 2.39 ABI) */
#ifndef _ULISP_STDLIB_H
#define _ULISP_STDLIB_H

#include <stddef.h>

#define EXIT_FAILURE 1
#define EXIT_SUCCESS 0
#define RAND_MAX     2147483647
#define MB_CUR_MAX   1

typedef struct {
  int quot;
  int rem;
} div_t;

typedef struct {
  long quot;
  long rem;
} ldiv_t;

typedef struct {
  long long quot;
  long long rem;
} lldiv_t;

double atof(const char *nptr);
int atoi(const char *nptr);
long atol(const char *nptr);
long long atoll(const char *nptr);

double strtod(const char *nptr, char **endptr);
float strtof(const char *nptr, char **endptr);
long double strtold(const char *nptr, char **endptr);
long strtol(const char *nptr, char **endptr, int base);
long long strtoll(const char *nptr, char **endptr, int base);
unsigned long strtoul(const char *nptr, char **endptr, int base);
unsigned long long strtoull(const char *nptr, char **endptr, int base);

int rand(void);
void srand(unsigned int seed);

void *calloc(size_t nmemb, size_t size);
void free(void *ptr);
void *malloc(size_t size);
void *realloc(void *ptr, size_t size);

void abort(void);
int atexit(void (*func)(void));
void exit(int status);
void _Exit(int status);
char *getenv(const char *name);
int system(const char *string);

void *bsearch(const void *key, const void *base, size_t nmemb, size_t size,
              int (*compar)(const void *, const void *));
void qsort(void *base, size_t nmemb, size_t size,
           int (*compar)(const void *, const void *));

int abs(int j);
long labs(long j);
long long llabs(long long j);
div_t div(int numer, int denom);
ldiv_t ldiv(long numer, long denom);
lldiv_t lldiv(long long numer, long long denom);

/* POSIX / XSI extensions */
int mkstemp(char *template_path);

#endif /* _ULISP_STDLIB_H */
