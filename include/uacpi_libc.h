#pragma once
#include <stdint.h>

#define UACPI_PRIx64 "lx"
#define UACPI_PRIX64 "lX"
#define UACPI_PRIu64 "lu"

#define PRIx64 UACPI_PRIx64
#define PRIX64 UACPI_PRIX64
#define PRIu64 UACPI_PRIu64

//int _strncmp(const char *src1, const char *src2, size_t size);
//int _strcmp(const char *src1, const char *src2);
size_t _strnlen(const char *src, size_t size);
size_t _strlen(const char *src);

#define uacpi_memcpy __builtin_memcpy
#define uacpi_memset __builtin_memset
#define uacpi_memcmp __builtin_memcmp
#define uacpi_memmove __builtin_memmove

//#define uacpi_strncmp _strncmp
//#define uacpi_strcmp _strcmp
#define uacpi_strnlen _strnlen
#define uacpi_strlen _strlen

#define uacpi_offsetof(t, m) ((uintptr_t)(&((t*)0)->m))