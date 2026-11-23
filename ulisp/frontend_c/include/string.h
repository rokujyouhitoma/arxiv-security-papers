/* ULisp C99 Built-in <string.h> (ISO C99 §7.21) */
#ifndef _ULISP_STRING_H
#define _ULISP_STRING_H

#include <stddef.h>

void *memcpy(void *dest, const void *src, size_t n);
void *memmove(void *dest, const void *src, size_t n);
void *memset(void *s, int c, size_t n);
int memcmp(const void *s1, const void *s2, size_t n);
void *memchr(const void *s, int c, size_t n);

char *strcpy(char *dest, const char *src);
char *strncpy(char *dest, const char *src, size_t n);
char *strcat(char *dest, const char *src);
char *strncat(char *dest, const char *src, size_t n);
int strcmp(const char *s1, const char *s2);
int strncmp(const char *s1, const char *s2, size_t n);
int strcoll(const char *s1, const char *s2);
size_t strxfrm(char *dest, const char *src, size_t n);

char *strchr(const char *s, int c);
char *strrchr(const char *s, int c);
size_t strspn(const char *s, const char *accept);
size_t strcspn(const char *s, const char *reject);
char *strpbrk(const char *s, const char *accept);
char *strstr(const char *haystack, const char *needle);
char *strtok(char *str, const char *delim);

size_t strlen(const char *s);
char *strerror(int errnum);

#endif /* _ULISP_STRING_H */
