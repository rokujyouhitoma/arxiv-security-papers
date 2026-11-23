/* ULisp Built-in <sys/wait.h> (POSIX.1 Linux x86-64 glibc waitstatus ABI) */
#ifndef _ULISP_SYS_WAIT_H
#define _ULISP_SYS_WAIT_H

#define WTERMSIG(status)    ((status) & 0x7f)
#define WEXITSTATUS(status) (((status) & 0xff00) >> 8)
#define WSTOPSIG(status)    WEXITSTATUS(status)
#define WIFEXITED(status)   (WTERMSIG(status) == 0)
#define WIFSIGNALED(status) (((signed char)(((status) & 0x7f) + 1) >> 1) > 0)
#define WIFSTOPPED(status)  (((status) & 0xff) == 0x7f)

int waitpid(int pid, int *wstatus, int options);

#endif /* _ULISP_SYS_WAIT_H */
