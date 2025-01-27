#ifndef UACPI_ARCH_HELPERS_H
#define UACPI_ARCH_HELPERS_H

#include <uacpi/platform/atomic.h>
#include <uacpi_types.h>

#ifndef UACPI_ARCH_FLUSH_CPU_CACHE
#define UACPI_ARCH_FLUSH_CPU_CACHE() do {} while (0)
#endif

typedef uint8_t uacpi_cpu_flags;
typedef uint64_t uacpi_thread_id;

#ifndef UACPI_ATOMIC_LOAD_THREAD_ID
#define UACPI_ATOMIC_LOAD_THREAD_ID(ptr) ((uacpi_thread_id)uacpi_atomic_load64(ptr))
#endif
#ifndef UACPI_ATOMIC_STORE_THREAD_ID
#define UACPI_ATOMIC_STORE_THREAD_ID(ptr, value) uacpi_atomic_store64(ptr, value)
#endif

#ifndef UACPI_THREAD_ID_NONE
#define UACPI_THREAD_ID_NONE ((uacpi_thread_id)-1)
#endif

#endif //UACPI_ARCH_HELPERS_H
