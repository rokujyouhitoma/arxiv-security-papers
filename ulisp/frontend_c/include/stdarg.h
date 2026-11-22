/* ULisp C99 Built-in <stdarg.h> (ISO C99 §7.15 & System V AMD64 psABI §3.5.7) */
#ifndef _ULISP_STDARG_H
#define _ULISP_STDARG_H

typedef __builtin_va_list va_list;
typedef __builtin_va_list __gnuc_va_list;

#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_arg(ap, type)   __builtin_va_arg(ap, type)
#define va_end(ap)         __builtin_va_end(ap)
#define va_copy(dst, src)  __builtin_va_copy(dst, src)

#endif /* _ULISP_STDARG_H */
