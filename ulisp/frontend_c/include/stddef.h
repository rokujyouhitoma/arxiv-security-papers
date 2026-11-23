/* ULisp C99 Built-in <stddef.h> (ISO C99 §7.17, LP64 x86-64 SysV ABI) */
#ifndef _ULISP_STDDEF_H
#define _ULISP_STDDEF_H

typedef long ptrdiff_t;
typedef unsigned long size_t;
typedef int wchar_t;

typedef struct {
  long long __max_align_ll;
  double __max_align_d;
} max_align_t;

#ifndef NULL
#define NULL ((void *)0)
#endif

#ifndef offsetof
#define offsetof(type, member) __builtin_offsetof(type, member)
#endif

#endif /* _ULISP_STDDEF_H */
