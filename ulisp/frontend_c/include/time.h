/* ULisp C99 Built-in <time.h> (ISO C99 §7.23 & Linux x86-64 glibc 2.39 ABI) */
#ifndef _ULISP_TIME_H
#define _ULISP_TIME_H

#include <stddef.h>

#define CLOCKS_PER_SEC 1000000L

typedef long clock_t;
typedef long time_t;

struct tm {
  int tm_sec;
  int tm_min;
  int tm_hour;
  int tm_mday;
  int tm_mon;
  int tm_year;
  int tm_wday;
  int tm_yday;
  int tm_isdst;
  long tm_gmtoff;
  const char *tm_zone;
};

clock_t clock(void);
double difftime(time_t time1, time_t time0);
time_t mktime(struct tm *timeptr);
time_t time(time_t *timer);
char *asctime(const struct tm *timeptr);
char *ctime(const time_t *timer);
struct tm *gmtime(const time_t *timer);
struct tm *localtime(const time_t *timer);
size_t strftime(char *s, size_t maxsize, const char *format, const struct tm *timeptr);

/* POSIX.1 reentrant extensions */
struct tm *gmtime_r(const time_t *timer, struct tm *result);
struct tm *localtime_r(const time_t *timer, struct tm *result);

#endif /* _ULISP_TIME_H */
