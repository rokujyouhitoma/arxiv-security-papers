/* ULisp C99 Built-in <errno.h> (ISO C99 §7.5 & Linux x86-64 glibc 2.39) */
#ifndef _ULISP_ERRNO_H
#define _ULISP_ERRNO_H

extern int *__errno_location(void);
#define errno (*__errno_location())

#define EPERM   1
#define ENOENT  2
#define ESRCH   3
#define EINTR   4
#define EIO     5
#define EBADF   9
#define ECHILD  10
#define EAGAIN  11
#define ENOMEM  12
#define EACCES  13
#define EEXIST  17
#define ENOTDIR 20
#define EISDIR  21
#define EINVAL  22
#define EMFILE  24
#define ENOSPC  28
#define EPIPE   32
#define EDOM    33
#define ERANGE  34
#define EILSEQ  84

#endif /* _ULISP_ERRNO_H */
