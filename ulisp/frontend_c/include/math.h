/* ULisp C99 Built-in <math.h> (ISO C99 §7.12 & System V AMD64 libm ABI) */
#ifndef _ULISP_MATH_H
#define _ULISP_MATH_H

#define M_E        2.7182818284590452354
#define M_LOG2E    1.4426950408889634074
#define M_LOG10E   0.43429448190325182765
#define M_LN2      0.69314718055994530942
#define M_LN10     2.30258509299404568402
#define M_PI       3.14159265358979323846
#define M_PI_2     1.57079632679489661923
#define M_PI_4     0.78539816339744830962
#define M_1_PI     0.31830988618379067154
#define M_2_PI     0.63661977236758134308
#define M_2_SQRTPI 1.12837916709551257390
#define M_SQRT2    1.41421356237309504880
#define M_SQRT1_2  0.70710678118654752440

#define HUGE_VAL   (1.0 / 0.0)
#define HUGE_VALF  (1.0f / 0.0f)
#define INFINITY   (1.0f / 0.0f)
#define NAN        (0.0f / 0.0f)

typedef float float_t;
typedef double double_t;

double acos(double x);
double asin(double x);
double atan(double x);
double atan2(double y, double x);
double cos(double x);
double sin(double x);
double tan(double x);
double cosh(double x);
double sinh(double x);
double tanh(double x);
double exp(double x);
double frexp(double x, int *exp);
double ldexp(double x, int exp);
double log(double x);
double log10(double x);
double log2(double x);
double modf(double x, double *iptr);
double pow(double x, double y);
double sqrt(double x);
double ceil(double x);
double fabs(double x);
double floor(double x);
double fmod(double x, double y);
double trunc(double x);
double round(double x);
double hypot(double x, double y);
double copysign(double x, double y);

float acosf(float x);
float asinf(float x);
float atanf(float x);
float atan2f(float y, float x);
float cosf(float x);
float sinf(float x);
float tanf(float x);
float coshf(float x);
float sinhf(float x);
float tanhf(float x);
float expf(float x);
float frexpf(float x, int *exp);
float ldexpf(float x, int exp);
float logf(float x);
float log10f(float x);
float log2f(float x);
float modff(float x, float *iptr);
float powf(float x, float y);
float sqrtf(float x);
float ceilf(float x);
float fabsf(float x);
float floorf(float x);
float fmodf(float x, float y);
float truncf(float x);
float roundf(float x);
float hypotf(float x, float y);
float copysignf(float x, float y);

#endif /* _ULISP_MATH_H */
