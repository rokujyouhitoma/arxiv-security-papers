/* ULisp C99 Built-in <signal.h> (ISO C99 §7.14 & Linux x86-64 glibc 2.39 ABI) */
#ifndef _ULISP_SIGNAL_H
#define _ULISP_SIGNAL_H

typedef int sig_atomic_t;
typedef void (*__sighandler_t)(int);

#define SIGHUP  1
#define SIGINT  2
#define SIGQUIT 3
#define SIGILL  4
#define SIGABRT 6
#define SIGFPE  8
#define SIGKILL 9
#define SIGSEGV 11
#define SIGPIPE 13
#define SIGALRM 14
#define SIGTERM 15

#define SIG_ERR ((void (*)(int))-1)
#define SIG_DFL ((void (*)(int))0)
#define SIG_IGN ((void (*)(int))1)

#define SA_NOCLDSTOP 0x1
#define SA_RESETHAND 0x80000000
#define SA_RESTART   0x10000000

typedef struct {
  unsigned long __val[16];
} sigset_t;

struct sigaction {
  __sighandler_t sa_handler;
  sigset_t sa_mask;
  int sa_flags;
  void (*sa_restorer)(void);
};

__sighandler_t signal(int sig, __sighandler_t func);
int raise(int sig);
int sigemptyset(sigset_t *set);
int sigfillset(sigset_t *set);
int sigaddset(sigset_t *set, int signum);
int sigaction(int sig, const struct sigaction *act, struct sigaction *oldact);

#endif /* _ULISP_SIGNAL_H */
