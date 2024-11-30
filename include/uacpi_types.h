//
// Created by robot on 2024-11-28.
//

#ifndef UACPI_TYPES_H
#define UACPI_TYPES_H

// BEGIN C NONSENSE

#if defined __x86_64__ && !defined __ILP32__
# define __WORDSIZE        64
#else
# define __WORDSIZE        32
#define __WORDSIZE32_SIZE_ULONG                0
#define __WORDSIZE32_PTRDIFF_LONG        0
#endif
#ifdef __x86_64__
# define __WORDSIZE_TIME64_COMPAT32        1
/* Both x86-64 and x32 use the 64-bit system call interface.  */
# define __SYSCALL_WORDSIZE                64
#else
# define __WORDSIZE_TIME64_COMPAT32        0
#endif

typedef signed char int8_t;
typedef unsigned char uint8_t;
typedef signed short int int16_t;
typedef unsigned short int uint16_t;
typedef signed int int32_t;
typedef unsigned int uint32_t;
#if __WORDSIZE == 64
typedef signed long int int64_t;
typedef unsigned long int uint64_t;
#else
__extension__ typedef signed long long int int64_t;
__extension__ typedef unsigned long long int uint64_t;
#endif

#define __SIZE_TYPE__ long unsigned int
typedef __SIZE_TYPE__ size_t;
typedef long ssize_t;

#define NULL ((void *)0)

#define bool  _Bool
#define false 0
#define true  1

#if __WORDSIZE == 64
# ifndef __intptr_t_defined
typedef long int                intptr_t;
#  define __intptr_t_defined
# endif
typedef unsigned long int        uintptr_t;
#else
# ifndef __intptr_t_defined
typedef int                        intptr_t;
#  define __intptr_t_defined
# endif
typedef unsigned int                uintptr_t;
#endif

#if defined __STDC_VERSION__ && __STDC_VERSION__ > 201710L
#define va_start(v, ...)	__builtin_va_start(v, 0)
#else
#define va_start(v,l)	__builtin_va_start(v,l)
#endif
#define va_end(v)	__builtin_va_end(v)
#define va_arg(v,l)	__builtin_va_arg(v,l)
#if !defined(__STRICT_ANSI__) || __STDC_VERSION__ + 0 >= 199900L \
|| __cplusplus + 0 >= 201103L
#define va_copy(d,s)	__builtin_va_copy(d,s)
#endif
#define __va_copy(d,s)	__builtin_va_copy(d,s)
typedef __builtin_va_list va_list;

// BEGIN UACPI ALIASES

typedef uint8_t uacpi_u8;
typedef uint16_t uacpi_u16;
typedef uint32_t uacpi_u32;
typedef uint64_t uacpi_u64;

typedef int8_t uacpi_i8;
typedef int16_t uacpi_i16;
typedef int32_t uacpi_i32;
typedef int64_t uacpi_i64;

#define UACPI_TRUE true
#define UACPI_FALSE false
typedef bool uacpi_bool;

#define UACPI_NULL NULL

typedef uintptr_t uacpi_uintptr;
typedef uacpi_uintptr uacpi_virt_addr;
typedef size_t uacpi_size;

typedef va_list uacpi_va_list;
#define uacpi_va_start va_start
#define uacpi_va_end va_end
#define uacpi_va_arg va_arg

typedef char uacpi_char;

#include <uacpi/helpers.h>

/*
 * We use unsignd long long for 64-bit number formatting because 64-bit types
 * don't have a standard way to format them. The inttypes.h header is not
 * freestanding therefore it's not practical to force the user to define the
 * corresponding PRI macros. Moreover, unsignd long long  is required to be
 * at least 64-bits as per C99.
 */
UACPI_BUILD_BUG_ON_WITH_MSG(
    sizeof(unsigned long long) < 8,
    "unsigned long long must be at least 64 bits large as per C99"
);
#define UACPI_FMT64(val) ((unsigned long long)(val))

#endif //UACPI_TYPES_H
