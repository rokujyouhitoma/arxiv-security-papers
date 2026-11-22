/* ULisp C99 Built-in <setjmp.h> (ISO C99 §7.13 & SysV AMD64 ULisp 64B ABI) */
#ifndef _ULISP_SETJMP_H
#define _ULISP_SETJMP_H

/* 64-byte context buffer: rbx, rbp, r12, r13, r14, r15, rsp(+8), rip */
typedef long jmp_buf[8];
typedef long sigjmp_buf[8];

int setjmp(jmp_buf env);
int _setjmp(jmp_buf env);
int sigsetjmp(sigjmp_buf env, int savemask);
void longjmp(jmp_buf env, int val);
void _longjmp(jmp_buf env, int val);
void siglongjmp(sigjmp_buf env, int val);

#endif /* _ULISP_SETJMP_H */
