/* ULisp Built-in <unistd.h> (POSIX.1 LP64 Linux x86-64 ABI) */
#ifndef _ULISP_UNISTD_H
#define _ULISP_UNISTD_H

#include <stddef.h>
#include <sys/types.h>

#define STDIN_FILENO  0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2

int isatty(int fd);
int close(int fd);
int unlink(const char *pathname);
ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
void _exit(int status);

#endif /* _ULISP_UNISTD_H */
