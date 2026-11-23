/* ULisp C99 Built-in <stdio.h> (ISO C99 §7.19 & Linux x86-64 glibc 2.39 ABI) */
#ifndef _ULISP_STDIO_H
#define _ULISP_STDIO_H

#include <stddef.h>

typedef struct _IO_FILE FILE;
typedef long fpos_t;

extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;

#define EOF          (-1)
#define BUFSIZ       8192
#define FOPEN_MAX    16
#define FILENAME_MAX 4096
#define L_tmpnam     20
#define TMP_MAX      238328

#define SEEK_SET     0
#define SEEK_CUR     1
#define SEEK_END     2

#define _IOFBF       0
#define _IOLBF       1
#define _IONBF       2

int remove(const char *filename);
int rename(const char *oldname, const char *newname);
FILE *tmpfile(void);
char *tmpnam(char *s);

int fclose(FILE *stream);
int fflush(FILE *stream);
FILE *fopen(const char *filename, const char *mode);
FILE *freopen(const char *filename, const char *mode, FILE *stream);
void setbuf(FILE *stream, char *buf);
int setvbuf(FILE *stream, char *buf, int mode, size_t size);

int fprintf(FILE *stream, const char *format, ...);
int fscanf(FILE *stream, const char *format, ...);
int printf(const char *format, ...);
int scanf(const char *format, ...);
int snprintf(char *s, size_t n, const char *format, ...);
int sprintf(char *s, const char *format, ...);
int sscanf(const char *s, const char *format, ...);

int vfprintf(FILE *stream, const char *format, __builtin_va_list arg);
int vprintf(const char *format, __builtin_va_list arg);
int vsnprintf(char *s, size_t n, const char *format, __builtin_va_list arg);
int vsprintf(char *s, const char *format, __builtin_va_list arg);

int fgetc(FILE *stream);
char *fgets(char *s, int n, FILE *stream);
int fputc(int c, FILE *stream);
int fputs(const char *s, FILE *stream);
int getc(FILE *stream);
int getchar(void);
int putc(int c, FILE *stream);
int putchar(int c);
int puts(const char *s);
int ungetc(int c, FILE *stream);

size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);

int fgetpos(FILE *stream, fpos_t *pos);
int fseek(FILE *stream, long offset, int whence);
int fsetpos(FILE *stream, const fpos_t *pos);
long ftell(FILE *stream);
void rewind(FILE *stream);

void clearerr(FILE *stream);
int feof(FILE *stream);
int ferror(FILE *stream);
void perror(const char *s);

/* POSIX extensions commonly enabled with LUA_USE_POSIX / _POSIX_C_SOURCE */
FILE *fdopen(int fd, const char *mode);
int fileno(FILE *stream);
FILE *popen(const char *command, const char *type);
int pclose(FILE *stream);
int fseeko(FILE *stream, long offset, int whence);
long ftello(FILE *stream);
int getc_unlocked(FILE *stream);
void flockfile(FILE *filehandle);
void funlockfile(FILE *filehandle);

#endif /* _ULISP_STDIO_H */
