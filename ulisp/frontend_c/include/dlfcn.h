/* ULisp Built-in <dlfcn.h> (POSIX.1 dlopen Linux x86-64 glibc ABI) */
#ifndef _ULISP_DLFCN_H
#define _ULISP_DLFCN_H

#define RTLD_LOCAL  0x0
#define RTLD_LAZY   0x1
#define RTLD_NOW    0x2
#define RTLD_GLOBAL 0x100

void *dlopen(const char *filename, int flags);
int dlclose(void *handle);
void *dlsym(void *handle, const char *symbol);
char *dlerror(void);

#endif /* _ULISP_DLFCN_H */
