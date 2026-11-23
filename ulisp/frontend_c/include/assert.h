/* ULisp C99 Built-in <assert.h> (ISO C99 §7.2) */
#undef assert

#ifdef NDEBUG
#define assert(expr) ((void)0)
#else
#ifndef _ULISP_ASSERT_DECLARED
#define _ULISP_ASSERT_DECLARED
extern void abort(void);
#endif
#define assert(expr) ((expr) ? (void)0 : abort())
#endif
