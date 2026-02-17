#ifndef CSafeMemory_h
#define CSafeMemory_h

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

/// Safely read `size` bytes from `source` into `dest`.
/// Returns true if the read succeeded, false if a SIGSEGV/SIGBUS occurred.
bool safe_memory_read(const void *source, void *dest, size_t size);

#endif /* CSafeMemory_h */
