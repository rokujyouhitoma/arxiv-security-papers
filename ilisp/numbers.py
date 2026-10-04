"""R7RS-small Section 6.2 Numbers and Arithmetic Implementation for ILISP.

Provides comprehensive numerical tower predicates, rounding functions,
exactness conversions, integer division/remainder variants, and radix-aware string conversions.
"""

from __future__ import annotations

import cmath
import math
from fractions import Fraction
from typing import Any, Union

from ilisp.types import Values

Real = Union[int, float, Fraction]
Number = Union[int, float, complex, Fraction]


# --- 1. Numerical Predicates ---


def number_p(x: Any) -> bool:
    """Return True if x is a number (int, float, complex, or Fraction)."""
    return isinstance(x, (int, float, complex, Fraction)) and not isinstance(x, bool)


def complex_p(x: Any) -> bool:
    """Return True if x is a complex number (in Scheme, all numbers are complex)."""
    return number_p(x)


def real_p(x: Any) -> bool:
    """Return True if x is a real number (including Fraction and complex with exact zero imag)."""
    if isinstance(x, bool):
        return False
    if isinstance(x, (int, float, Fraction)):
        return True
    if isinstance(x, complex):
        return x.imag == 0.0 and getattr(x, "exact_imag", False)
    return False


def rational_p(x: Any) -> bool:
    """Return True if x is a rational number (all finite real numbers in ILISP)."""
    if not real_p(x):
        return False
    if isinstance(x, Fraction):
        return True
    if isinstance(x, complex):
        return math.isfinite(x.real)
    return math.isfinite(x)


def integer_p(x: Any) -> bool:
    """Return True if x is an integer or a float with integral value."""
    if isinstance(x, bool):
        return False
    if isinstance(x, int):
        return True
    if isinstance(x, float):
        return math.isfinite(x) and x.is_integer()
    if isinstance(x, complex):
        if getattr(x, "exact_imag", False):
            return integer_p(x.real)
        return False
    return False


def exact_p(x: Any) -> bool:
    """Return True if x is an exact number (int or Fraction)."""
    if isinstance(x, bool):
        return False
    if isinstance(x, (int, Fraction)):
        return True
    if (
        isinstance(x, complex)
        and getattr(x, "exact_real", False)
        and getattr(x, "exact_imag", False)
    ):
        return True
    return False


def inexact_p(x: Any) -> bool:
    """Return True if x is an inexact number (float or complex)."""
    return isinstance(x, (float, complex))


def exact_integer_p(x: Any) -> bool:
    """Return True if x is an exact integer."""
    return isinstance(x, int) and not isinstance(x, bool)


def finite_p(x: Any) -> bool:
    """Return True if x is a finite number."""
    if not number_p(x):
        raise TypeError(f"finite?: expected number, got {x!r}")
    if isinstance(x, complex):
        return math.isfinite(x.real) and math.isfinite(x.imag)
    return math.isfinite(x)


def infinite_p(x: Any) -> bool:
    """Return True if x is positive or negative infinity."""
    if not number_p(x):
        raise TypeError(f"infinite?: expected number, got {x!r}")
    if isinstance(x, complex):
        return math.isinf(x.real) or math.isinf(x.imag)
    return math.isinf(x)


def nan_p(x: Any) -> bool:
    """Return True if x is NaN (Not a Number)."""
    if not number_p(x):
        raise TypeError(f"nan?: expected number, got {x!r}")
    if isinstance(x, complex):
        return math.isnan(x.real) or math.isnan(x.imag)
    return math.isnan(x)


def zero_p(x: Any) -> bool:
    """Return True if x is zero."""
    if not number_p(x):
        raise TypeError(f"zero?: expected number, got {x!r}")
    return bool(x == 0)


def positive_p(x: Any) -> bool:
    """Return True if x is strictly positive."""
    if not number_p(x):
        raise TypeError(f"positive?: expected number, got {x!r}")
    return bool(x > 0)


def negative_p(x: Any) -> bool:
    """Return True if x is strictly negative."""
    if not number_p(x):
        raise TypeError(f"negative?: expected number, got {x!r}")
    return bool(x < 0)


def odd_p(n: Any) -> bool:
    """Return True if n is an odd integer."""
    if not integer_p(n):
        raise TypeError(f"odd?: expected integer, got {n!r}")
    return int(n) % 2 != 0


def even_p(n: Any) -> bool:
    """Return True if n is an even integer."""
    if not integer_p(n):
        raise TypeError(f"even?: expected integer, got {n!r}")
    return int(n) % 2 == 0


# --- 2. Numerical Comparison (Multi-argument) ---


def num_eq(*nums: Any) -> bool:
    """Return True if all arguments are numerically equal (= z1 z2 ...)."""
    if not nums:
        return True
    first = nums[0]
    for n in nums[1:]:
        if not (first == n):
            return False
    return True


def num_lt(*nums: Any) -> bool:
    """Return True if arguments are monotonically increasing (< x1 x2 ...)."""
    if len(nums) <= 1:
        return True
    for i in range(len(nums) - 1):
        if not (nums[i] < nums[i + 1]):
            return False
    return True


def num_gt(*nums: Any) -> bool:
    """Return True if arguments are monotonically decreasing (> x1 x2 ...)."""
    if len(nums) <= 1:
        return True
    for i in range(len(nums) - 1):
        if not (nums[i] > nums[i + 1]):
            return False
    return True


def num_le(*nums: Any) -> bool:
    """Return True if arguments are monotonically non-decreasing (<= x1 x2 ...)."""
    if len(nums) <= 1:
        return True
    for i in range(len(nums) - 1):
        if not (nums[i] <= nums[i + 1]):
            return False
    return True


def num_ge(*nums: Any) -> bool:
    """Return True if arguments are monotonically non-increasing (>= x1 x2 ...)."""
    if len(nums) <= 1:
        return True
    for i in range(len(nums) - 1):
        if not (nums[i] >= nums[i + 1]):
            return False
    return True


# --- 3. Arithmetic Operations ---


def num_div(first: Number, *rest: Number) -> Number:
    """Perform division (/ z) or (/ z1 z2 ...)."""
    from fractions import Fraction

    if not rest:
        if isinstance(first, (int, Fraction)):
            if first == 0:
                raise ZeroDivisionError("division by zero")
            frac = Fraction(1, first)
            return frac.numerator if frac.denominator == 1 else frac
        if first == 0:
            if isinstance(first, float):
                return float("inf")
            raise ZeroDivisionError("division by zero")
        return 1.0 / first
    res: Number = first
    for n in rest:
        if isinstance(res, (int, Fraction)) and isinstance(n, (int, Fraction)):
            if n == 0:
                raise ZeroDivisionError("division by zero")
            frac = Fraction(res, n)
            res = frac.numerator if frac.denominator == 1 else frac
        else:
            if n == 0:
                if isinstance(res, (int, float)) and isinstance(n, (int, float)):
                    if res > 0:
                        res = float("inf")
                    elif res < 0:
                        res = float("-inf")
                    else:
                        res = float("nan")
                else:
                    raise ZeroDivisionError("division by zero")
            else:
                res = res / n
    return res


def num_max(*nums: Real) -> Real:
    """Return maximum of arguments, preserving inexactness."""
    if not nums:
        raise TypeError("max: requires at least one argument")
    m = max(nums)
    if any(isinstance(n, float) for n in nums):
        return float(m)
    return m


def num_min(*nums: Real) -> Real:
    """Return minimum of arguments, preserving inexactness."""
    if not nums:
        raise TypeError("min: requires at least one argument")
    m = min(nums)
    if any(isinstance(n, float) for n in nums):
        return float(m)
    return m


def num_abs(x: Number) -> Number:
    """Return absolute value."""
    if isinstance(x, complex):
        return float(abs(x))
    if isinstance(x, Fraction):
        return abs(x)
    if isinstance(x, float):
        return abs(x)
    return abs(int(x))


def num_gcd(*nums: int) -> int:
    """Return greatest common divisor of integer arguments."""
    if not nums:
        return 0
    res = abs(int(nums[0]))
    for n in nums[1:]:
        res = math.gcd(res, abs(int(n)))
    return res


def num_lcm(*nums: int) -> int:
    """Return least common multiple of integer arguments."""
    if not nums:
        return 1
    res = abs(int(nums[0]))
    for n in nums[1:]:
        val = abs(int(n))
        if res == 0 or val == 0:
            return 0
        res = (res * val) // math.gcd(res, val)
    return res


# --- 4. Rounding and Truncation ---


def num_floor(x: Real) -> Real:
    """Return largest integer <= x."""
    res = math.floor(x)
    return float(res) if isinstance(x, float) else res


def num_ceiling(x: Real) -> Real:
    """Return smallest integer >= x."""
    res = math.ceil(x)
    return float(res) if isinstance(x, float) else res


def num_truncate(x: Real) -> Real:
    """Truncate towards zero."""
    res = math.trunc(x)
    return float(res) if isinstance(x, float) else res


def num_round(x: Real) -> Real:
    """Round to nearest even integer."""
    res = round(x)
    return float(res) if isinstance(x, float) else res


# --- 5. Integer Division (floor and truncate variants) ---


def floor_quotient(n1: int, n2: int) -> int:
    """Floor quotient: floor(n1 / n2)."""
    return n1 // n2


def floor_remainder(n1: int, n2: int) -> int:
    """Floor remainder: n1 - n2 * floor(n1 / n2)."""
    return n1 % n2


def floor_div(n1: int, n2: int) -> Values:
    """Floor division returning (values quotient remainder)."""
    q = n1 // n2
    r = n1 % n2
    return Values(q, r)


def truncate_quotient(n1: int, n2: int) -> int:
    """Truncate quotient: int(n1 / n2)."""
    return int(n1 / n2)


def truncate_remainder(n1: int, n2: int) -> int:
    """Truncate remainder: n1 - n2 * truncate(n1 / n2)."""
    q = int(n1 / n2)
    return n1 - n2 * q


def truncate_div(n1: int, n2: int) -> Values:
    """Truncate division returning (values quotient remainder)."""
    q = int(n1 / n2)
    r = n1 - n2 * q
    return Values(q, r)


def num_modulo(n1: int, n2: int) -> int:
    """R7RS modulo (floor-remainder)."""
    return n1 % n2


# --- 6. Exactness and Exponentiation ---


def num_exact(z: Number) -> Any:
    """Convert number to exact representation (integer or Fraction)."""
    if isinstance(z, int):
        return z
    from fractions import Fraction

    if isinstance(z, Fraction):
        return z
    if isinstance(z, float):
        if math.isinf(z) or math.isnan(z):
            raise ValueError(f"exact: cannot convert {z} to exact number")
        if z.is_integer():
            return int(z)
        frac = Fraction(z).limit_denominator()
        return frac.numerator if frac.denominator == 1 else frac
    raise TypeError(f"exact: expected number, got {z!r}")


def num_inexact(z: Any) -> Any:
    """Convert number to inexact representation (R7RS 6.2.6)."""
    if isinstance(z, complex):
        return complex(float(z.real), float(z.imag))
    return float(z)


def num_square(z: Number) -> Number:
    """Return square of z."""
    return z * z


def num_sqrt(z: Number) -> Number:
    """Return square root of z (R7RS 6.2.6).

    For non-negative real numbers, returns real (or int if exact square).
    For negative real numbers or complex numbers, returns complex.
    """
    if isinstance(z, complex):
        if z.imag == 0 and z.real < 0:
            return complex(0.0, math.sqrt(-z.real))
        return cmath.sqrt(z)
    if isinstance(z, (int, float)):
        if z < 0:
            return complex(0.0, math.sqrt(-z))
        res = math.sqrt(z)
        if isinstance(z, int) and res.is_integer() and int(res) * int(res) == z:
            return int(res)
        return res
    raise TypeError(f"sqrt: expected number, got {z!r}")


def num_exp(z: Number) -> Number:
    """Return the natural exponential of z."""
    if isinstance(z, complex):
        return cmath.exp(z)
    if isinstance(z, (int, float)):
        return math.exp(z)
    raise TypeError(f"exp: expected number, got {z!r}")


def num_log(z: Number, *base: Number) -> Number:
    """Return the logarithm of z.

    (log z) computes natural log ln(z).
    (log z b) computes log_b(z) = ln(z) / ln(b).
    """
    if len(base) > 1:
        raise TypeError(f"log: expected 1 or 2 arguments, got {len(base) + 1}")

    def _single_log(val: Number) -> Number:
        if isinstance(val, complex):
            return cmath.log(val)
        if isinstance(val, (int, float)):
            if val > 0:
                return math.log(val)
            return cmath.log(val)
        raise TypeError(f"log: expected number, got {val!r}")

    res_z = _single_log(z)
    if not base:
        return res_z
    res_b = _single_log(base[0])
    return res_z / res_b


def num_sin(z: Number) -> Number:
    """Return the sine of z."""
    if isinstance(z, complex):
        return cmath.sin(z)
    if isinstance(z, (int, float)):
        return math.sin(z)
    raise TypeError(f"sin: expected number, got {z!r}")


def num_cos(z: Number) -> Number:
    """Return the cosine of z."""
    if isinstance(z, complex):
        return cmath.cos(z)
    if isinstance(z, (int, float)):
        return math.cos(z)
    raise TypeError(f"cos: expected number, got {z!r}")


def num_tan(z: Number) -> Number:
    """Return the tangent of z."""
    if isinstance(z, complex):
        return cmath.tan(z)
    if isinstance(z, (int, float)):
        return math.tan(z)
    raise TypeError(f"tan: expected number, got {z!r}")


def num_asin(z: Number) -> Number:
    """Return the arcsine of z."""
    if isinstance(z, complex):
        return cmath.asin(z)
    if isinstance(z, (int, float)):
        if -1.0 <= z <= 1.0:
            return math.asin(z)
        return cmath.asin(z)
    raise TypeError(f"asin: expected number, got {z!r}")


def num_acos(z: Number) -> Number:
    """Return the arccosine of z."""
    if isinstance(z, complex):
        return cmath.acos(z)
    if isinstance(z, (int, float)):
        if -1.0 <= z <= 1.0:
            return math.acos(z)
        return cmath.acos(z)
    raise TypeError(f"acos: expected number, got {z!r}")


def num_atan(*args: Number) -> Number:
    """Return the arctangent of z (1 arg) or atan2(y, x) (2 args)."""
    if len(args) == 1:
        z = args[0]
        if isinstance(z, complex):
            return cmath.atan(z)
        if isinstance(z, (int, float)):
            return math.atan(z)
        raise TypeError(f"atan: expected number, got {z!r}")
    elif len(args) == 2:
        y, x = args
        if isinstance(y, (int, float)) and isinstance(x, (int, float)):
            return math.atan2(y, x)
        raise TypeError("atan (2 arguments): expected real numbers")
    else:
        raise TypeError(f"atan: expected 1 or 2 arguments, got {len(args)}")


def num_expt(z1: Number, z2: Number) -> Number:
    """Compute z1 raised to power z2."""
    res = z1**z2
    if isinstance(res, (int, float, complex)):
        return res
    return float(res)


# --- 6b. Extended Roots and Complex Numbers (R7RS 6.2 & (scheme complex)) ---


def exact_integer_sqrt(k: Any) -> Values:
    """Return two non-negative exact integers s and r where k = s^2 + r and k < (s+1)^2."""
    if not exact_integer_p(k):
        raise TypeError(f"exact-integer-sqrt: expected exact integer, got {k!r}")
    n = int(k)
    if n < 0:
        raise ValueError(f"exact-integer-sqrt: expected non-negative integer, got {n}")
    s = math.isqrt(n)
    r = n - s * s
    return Values(s, r)


def make_rectangular(x1: Any, x2: Any) -> complex:
    """Construct a complex number from real and imaginary parts."""
    if not real_p(x1) or not real_p(x2):
        raise TypeError(
            f"make-rectangular: expected real numbers, got ({x1!r}, {x2!r})"
        )
    r = float(x1.real if isinstance(x1, complex) else x1)
    i = float(x2.real if isinstance(x2, complex) else x2)
    exact_r = exact_p(x1)
    exact_i = exact_p(x2)
    from ilisp.types import SchemeComplex

    return SchemeComplex(
        r, i, exact_real=exact_r, exact_imag=exact_i, real_val=x1, imag_val=x2
    )


def make_polar(x3: Any, x4: Any) -> complex:
    """Construct a complex number from magnitude and angle (in radians)."""
    if not real_p(x3) or not real_p(x4):
        raise TypeError(f"make-polar: expected real numbers, got ({x3!r}, {x4!r})")
    mag = float(x3.real if isinstance(x3, complex) else x3)
    ang = float(x4.real if isinstance(x4, complex) else x4)
    return cmath.rect(mag, ang)


def real_part(z: Any) -> Any:
    """Return the real part of number z."""
    from ilisp.types import SchemeComplex

    if isinstance(z, SchemeComplex):
        if z.real_val is not None:
            return z.real_val
        if z.exact_real:
            return int(z.real) if z.real.is_integer() else z.real
        return float(z.real)
    if isinstance(z, complex):
        return float(z.real)
    if isinstance(z, (int, float, Fraction)) and not isinstance(z, bool):
        return z
    raise TypeError(f"real-part: expected number, got {z!r}")


def imag_part(z: Any) -> Any:
    """Return the imaginary part of number z."""
    from ilisp.types import SchemeComplex

    if isinstance(z, SchemeComplex):
        if z.imag_val is not None:
            return z.imag_val
        if z.exact_imag:
            return int(z.imag) if z.imag.is_integer() else z.imag
        return float(z.imag)
    if isinstance(z, complex):
        return float(z.imag)
    if isinstance(z, (int, float, Fraction)) and not isinstance(z, bool):
        return 0
    raise TypeError(f"imag-part: expected number, got {z!r}")


def num_magnitude(z: Any) -> Union[int, float]:
    """Return the magnitude (modulus / absolute value) of number z."""
    if isinstance(z, complex):
        return float(abs(z))
    if isinstance(z, (int, float)) and not isinstance(z, bool):
        return abs(z)
    raise TypeError(f"magnitude: expected number, got {z!r}")


def num_angle(z: Any) -> float:
    """Return the angle (phase) of number z in radians."""
    if not number_p(z):
        raise TypeError(f"angle: expected number, got {z!r}")
    return cmath.phase(z)


# --- 7. Radix and String Conversions ---


def number_to_string(z: Real, radix: int = 10) -> str:
    """Convert number z to a string in base radix (2, 8, 10, or 16)."""
    if radix not in (2, 8, 10, 16):
        raise ValueError(
            f"number->string: unsupported radix {radix} (must be 2, 8, 10, or 16)"
        )
    from fractions import Fraction

    if isinstance(z, Fraction):
        if radix != 10:
            raise ValueError(
                "number->string: non-decimal radix only supported for integers"
            )
        return f"{z.numerator}/{z.denominator}"
    if isinstance(z, float):
        if radix != 10:
            raise ValueError(
                "number->string: non-decimal radix only supported for integers"
            )
        s = str(z)
        if "e" in s and "." not in s.split("e")[0]:
            parts = s.split("e")
            s = f"{parts[0]}.0e{parts[1]}"
        return s

    n = int(z)
    is_neg = n < 0
    abs_n = abs(n)

    if radix == 10:
        s = str(abs_n)
    elif radix == 16:
        s = hex(abs_n)[2:].lower()
    elif radix == 8:
        s = oct(abs_n)[2:]
    elif radix == 2:
        s = bin(abs_n)[2:]
    else:
        raise ValueError(f"unsupported radix {radix}")

    return f"-{s}" if is_neg else s


def string_to_number(s: str, radix: int = 10) -> Any:
    """Parse string as a number in base radix (2, 8, 10, or 16), or return False on failure."""
    if not isinstance(s, str):
        raise TypeError(f"string->number: expected string, got {s!r}")
    if radix not in (2, 8, 10, 16):
        raise ValueError(f"string->number: unsupported radix {radix}")

    stripped = s.strip()
    if not stripped:
        return False

    # Check for prefix radix syntax (#b, #o, #d, #x)
    actual_radix = radix
    clean_s = stripped
    if clean_s.startswith("#b") or clean_s.startswith("#B"):
        actual_radix = 2
        clean_s = clean_s[2:]
    elif clean_s.startswith("#o") or clean_s.startswith("#O"):
        actual_radix = 8
        clean_s = clean_s[2:]
    elif clean_s.startswith("#d") or clean_s.startswith("#D"):
        actual_radix = 10
        clean_s = clean_s[2:]
    elif clean_s.startswith("#x") or clean_s.startswith("#X"):
        actual_radix = 16
        clean_s = clean_s[2:]

    try:
        return int(clean_s, actual_radix)
    except ValueError:
        if actual_radix == 10:
            try:
                return float(clean_s)
            except ValueError:
                return False
        return False
